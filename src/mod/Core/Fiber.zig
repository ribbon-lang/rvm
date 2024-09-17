//! The Fiber contains everything needed to execute a single thread.
//! This includes:
//! - context pointer
//!     > The shared global state for all Fibers
//! - data stack
//!     > The backing storage for virtual registers
//! - call stack
//!     > stack of CallFrame, which contains the necessary state of a function call
//! - block stack
//!     > stack of BlockFrame, which contains information about a bytecode basic block
//! - evidence vector
//!     > vector of evidence, which is used to store effect handler pointers
//! - trap
//!     > Stores diagnostics about the last trap that occurred

const std = @import("std");

const Config = @import("Config");
const Support = @import("Support");
const Extern = @import("Extern");
const Bytecode = @import("Bytecode");
const Disassembler = @import("Disassembler");
const IO = @import("IO");

const Core = @import("root.zig");
const Context = Core.Context;
const Stack = Core.Stack;


const Fiber = @This();


context: *const Context,
program: *const Bytecode.Program,
stack: StackSet,
evidence: []EvidenceStack,
foreign: []const ForeignFunction,


pub const Trap = error {
    ForeignUnknown,
    Unreachable,
    Underflow,
    Overflow,
    OutOfBounds,
    MissingEvidence,
    OutValueMismatch,
    BadEncoding,
    ArgCountMismatch,
    BadAlignment,
    InvalidBlockRestart,
};

pub const RegisterData = extern struct {
    call: *Fiber.CallFrame,
    layout: *const Bytecode.LayoutTable,
};

pub const RegisterDataSet = struct {
    local: RegisterData,
    upvalue: ?RegisterData,

    pub fn extractUp(self: Fiber.RegisterDataSet) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.RegisterData {
        if (self.upvalue) |ud| {
            return ud;
        } else {
            @branchHint(.cold);
            return Fiber.Trap.MissingEvidence;
        }
    }
};

pub const ForeignFunction = *const fn (*anyopaque, Bytecode.BlockIndex, *ForeignOut) callconv(.C) ForeignControl;

pub const ForeignControl = enum(u32) {
    step,
    done,
    done_v,
    trap,
};

pub const ForeignOut = extern union {
    step: Bytecode.BlockIndex,
    done: void,
    done_v: Bytecode.Operand,
    trap: Extern.Error,
};

pub const ForeignRegisterDataSet = extern struct {
    local: RegisterData,
    upvalue: Extern.Option(RegisterData),

    pub fn fromNative(data: RegisterDataSet) ForeignRegisterDataSet {
        return .{
            .local = data.local,
            .upvalue = .fromNative(data.upvalue),
        };
    }

    pub fn toNative(self: ForeignRegisterDataSet) RegisterDataSet {
        return .{
            .local = self.local,
            .upvalue = self.upvalue.toNative(),
        };
    }
};

pub fn convertForeignError(e: Extern.Error) Trap {
    const i = @intFromError(e.toNative());

    inline for (comptime std.meta.fieldNames(Trap)) |trapName| {
        if (i == @intFromError(@field(Trap, trapName))) {
            return @field(Trap, trapName);
        }
    }

    return Trap.ForeignUnknown;
}

pub const StackSet = struct {
    data: DataStack,
    call: CallStack,
    block: BlockStack,

    pub fn init(allocator: std.mem.Allocator) !StackSet {
        const data = try DataStack.init(allocator, DATA_STACK_SIZE);
        errdefer data.deinit(allocator);

        const call = try CallStack.init(allocator, CALL_STACK_SIZE);
        errdefer call.deinit(allocator);

        const block = try BlockStack.init(allocator, BLOCK_STACK_SIZE);
        errdefer block.deinit(allocator);

        return StackSet {
            .data = data,
            .call = call,
            .block = block,
        };
    }

    pub fn deinit(self: StackSet, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.call.deinit(allocator);
        self.block.deinit(allocator);
    }
};


pub const CALL_STACK_SIZE: usize = 1024;
pub const BLOCK_STACK_SIZE: usize = CALL_STACK_SIZE * Bytecode.MAX_BLOCKS;
pub const EVIDENCE_VECTOR_SIZE: usize = Bytecode.MAX_EVIDENCE;
pub const EVIDENCE_STACK_SIZE: usize = std.math.maxInt(EvidenceStack.Ptr);
pub const DATA_STACK_SIZE: usize
    = (1024 * 1024 * 1)
    // - @rem(TOTAL_META_SIZE, 1024 * 1024)
    ;

const TOTAL_META_SIZE: usize
    = CALL_STACK_SIZE * @sizeOf(CallFrame)
    + BLOCK_STACK_SIZE * @sizeOf(BlockFrame)
    + EVIDENCE_VECTOR_SIZE * (@sizeOf(Evidence) * EVIDENCE_STACK_SIZE + @sizeOf(EvidenceStack))
    + @sizeOf(Fiber)
    ;

// comptime {
//     const TOTAL_SIZE: usize
//         = DATA_STACK_SIZE
//         + TOTAL_META_SIZE
//         ;
//
//     @compileError(std.fmt.comptimePrint(
//         \\DATA_STACK_SIZE: {} ({d:10.10} mb)
//         \\TOTAL_SIZE: {} ({d:10.10} mb)
//         \\TOTAL_META_SIZE: {} ({d:10.10} mb)
//         \\
//         , .{
//             DATA_STACK_SIZE,
//             @as(f64, @floatFromInt(DATA_STACK_SIZE)) / 1024.0 / 1024.0,
//             TOTAL_SIZE,
//             @as(f64, @floatFromInt(TOTAL_SIZE)) / 1024.0 / 1024.0,
//             TOTAL_META_SIZE,
//             @as(f64, @floatFromInt(TOTAL_META_SIZE)) / 1024.0 / 1024.0,
//         }
//     ));
// }

pub const DataStack = Stack(u8, u24, std.mem.page_size);
pub const CallStack = Stack(CallFrame, u16, null);
pub const BlockStack = Stack(BlockFrame, u16, null);
pub const EvidenceStack = Stack(Evidence, u8, null);

pub const Evidence = packed struct {
    handler: Bytecode.FunctionIndex,
    data: DataStack.Ptr,
    call: CallStack.Ptr,
    block: BlockStack.Ptr,
};

pub const BlockFrame = packed struct {
    index: Bytecode.BlockIndex,
    ip_offset: Bytecode.InstructionPointerOffset,
    out: Bytecode.Operand,
    handler_set: Bytecode.HandlerSetIndex,

    pub inline fn noOutput(index: Bytecode.BlockIndex, handler_set: ?Bytecode.HandlerSetIndex) BlockFrame {
        return .{ .index = index, .ip_offset = 0, .out = undefined, .handler_set = handler_set orelse Bytecode.HANDLER_SET_SENTINEL };
    }

    pub inline fn entryPoint(operand: ?Bytecode.Operand) BlockFrame {
        return
            if (operand) |op| .{ .index = 0, .ip_offset = 0, .out = op, .handler_set = Bytecode.HANDLER_SET_SENTINEL }
            else .{ .index = 0, .ip_offset = 0, .out = undefined, .handler_set = Bytecode.HANDLER_SET_SENTINEL };
    }

    pub inline fn value(index: Bytecode.BlockIndex, operand: Bytecode.Operand, handler_set: ?Bytecode.HandlerSetIndex) BlockFrame {
        return .{ .index = index, .ip_offset = 0, .out = operand, .handler_set = handler_set orelse Bytecode.HANDLER_SET_SENTINEL };
    }
};

pub const CallFrame = struct {
    function: *const Bytecode.Function,
    evidence: EvidenceRef,
    root_block: BlockStack.Ptr,
    stack: StackRef,

    pub const StackRef = packed struct {
        base: DataStack.Ptr,
        origin: DataStack.Ptr,
    };

    pub const EvidenceRef = packed struct {
        index: Bytecode.EvidenceIndex,
        offset: EvidenceStack.Ptr,
        const INT_T: type = std.meta.Int(.unsigned, @bitSizeOf(EvidenceRef));
        pub const SENTINEL: EvidenceRef = @bitCast(@as(INT_T, std.math.maxInt(INT_T)));

        pub fn isSentinel(self: EvidenceRef) bool {
            return @as(INT_T, @bitCast(self)) == @as(INT_T, @bitCast(SENTINEL));
        }
    };
};


pub fn init(context: *const Context, program: *const Bytecode.Program, foreign: []const ForeignFunction) !*Fiber {
    const ptr = try context.allocator.create(Fiber);
    errdefer context.allocator.destroy(ptr);

    const stack = try StackSet.init(context.allocator);
    errdefer stack.deinit(context.allocator);

    const evidence = try context.allocator.alloc(EvidenceStack, EVIDENCE_VECTOR_SIZE);
    errdefer context.allocator.free(evidence);

    var i: usize = 0;
    errdefer {
        var j: usize = 0;
        while (j < i) : (j += 1) {
            evidence[j].deinit(context.allocator);
        }
    }

    while (i < EVIDENCE_VECTOR_SIZE) : (i += 1) {
        evidence[i] = try EvidenceStack.init(context.allocator, EVIDENCE_STACK_SIZE);
    }

    ptr.* = Fiber {
        .program = program,
        .context = context,
        .stack = stack,
        .evidence = evidence,
        .foreign = foreign,
    };

    return ptr;
}

pub fn deinit(self: *Fiber) void {
    self.stack.deinit(self.context.allocator);
    self.context.allocator.free(self.evidence);
    self.context.allocator.destroy(self);
}

pub fn getLocation(self: *const Fiber) Trap!Bytecode.Location {
    const call = try self.stack.call.top();
    const block = try self.stack.block.top();

    return .{
        .function = call.function.index,
        .block = block.index,
        .offset = block.ip_offset,
    };
}

pub fn getForeign(self: *const Fiber, index: Bytecode.ForeignId) !ForeignFunction {
    if (index >= self.foreign.len) {
        return Trap.OutOfBounds;
    }

    return self.getForeignUnchecked(index);
}

pub fn getForeignUnchecked(self: *const Fiber, index: Bytecode.ForeignId) ForeignFunction {
    return self.foreign[index];
}

pub fn boundsCheck(fiber: *Fiber, address: [*]const u8, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const validGlobalA = @intFromBool(@intFromPtr(address) >= @intFromPtr(fiber.program.globals.memory.ptr));
    const validGlobalB = @intFromBool(@intFromPtr(address) + size <= @intFromPtr(fiber.program.globals.memory.ptr) + fiber.program.globals.memory.len);

    const validStackA = @intFromBool(@intFromPtr(address) >= @intFromPtr(fiber.stack.data.memory.ptr));
    const validStackB = @intFromBool(@intFromPtr(address) + size <= fiber.stack.data.ptr);

    if ((validGlobalA & validGlobalB) | (validStackA & validStackB) == 0) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }
}

pub fn removeAnyHandlerSet(fiber: *Fiber, blockFrame: *Fiber.BlockFrame) callconv(Config.INLINING_CALL_CONV) void {
    if (blockFrame.handler_set == Bytecode.HANDLER_SET_SENTINEL) return;

    const handlerSet = fiber.program.handler_sets[blockFrame.handler_set];

    removeHandlerSet(fiber, handlerSet);
}

pub fn removeHandlerSet(fiber: *Fiber, handlerSet: Bytecode.HandlerSet) callconv(Config.INLINING_CALL_CONV) void {
    for (handlerSet) |binding| {
        const removedEv = fiber.evidence[binding.id].popUnchecked();

        std.debug.assert(removedEv.handler == binding.handler);
    }
}

pub fn getRegisterDataSet(fiber: *Fiber, framePtr: CallStack.Ptr) callconv(Config.INLINING_CALL_CONV) Fiber.RegisterDataSet {
    const callFrame = fiber.stack.call.getPtrUnchecked(framePtr);

    return .{
        .local = .{
            .call = callFrame,
            .layout = &callFrame.function.layout_table,
        },
        .upvalue = if (!callFrame.evidence.isSentinel()) ev: {
            const evidence = fiber.evidence[callFrame.evidence.index].getPtrUnchecked(callFrame.evidence.offset);
            const evFrame = fiber.stack.call.getPtrUnchecked(evidence.call);
            const evFunction = evFrame.function;
            break :ev .{
                .call = evFrame,
                .layout = &evFunction.layout_table
            };
        } else null,
    };
}


pub const RegisterDataLocation = enum {upvalue, local};

pub fn getRegisterData(fiber: *Fiber, comptime location: RegisterDataLocation, framePtr: CallStack.Ptr) Fiber.Trap!Fiber.RegisterData {
    const callFrame = try fiber.stack.call.getPtr(framePtr);

    return switch (location) {
        .upvalue => if (callFrame.evidence) |evRef| ev: {
            const evidence = try fiber.evidence[evRef.index].getPtr(evRef.offset);
            const evFrame = try fiber.stack.call.getPtr(evidence.call);
            const evFunction = evFrame.function;
            break :ev .{
                .call = evFrame,
                .layout = &evFunction.layout_table
            };
        } else Trap.MissingEvidence,

        .local => .{
            .call = callFrame,
            .layout = &callFrame.function.layout_table,
        },
    };
}

pub fn getRegisterDataUnchecked(fiber: *Fiber, comptime location: RegisterDataLocation, framePtr: CallStack.Ptr) Fiber.RegisterData {
    const callFrame = fiber.stack.call.getPtrUnchecked(framePtr);

    return switch (location) {
        .upvalue => ev: {
            const evidence = fiber.evidence[callFrame.evidence.index].getPtrUnchecked(callFrame.evidence.offset);
            const evFrame = fiber.stack.call.getPtrUnchecked(evidence.call);
            const evFunction = evFrame.function;
            break :ev .{
                .call = evFrame,
                .layout = &evFunction.layout_table
            };
        },

        .local => .{
            .call = callFrame,
            .layout = &callFrame.function.layout_table,
        },
    };
}

pub fn decodeNext(fiber: *Core.Fiber) callconv(Config.INLINING_CALL_CONV) Trap!Bytecode.Op {
    const currentCallFrame = try fiber.stack.call.topPtr();
    const currentBlockFrame = try fiber.stack.block.topPtr();
    const currentBlock = &currentCallFrame.function.value.bytecode.blocks[currentBlockFrame.index];

    const decoder = IO.Decoder {
        .memory = currentCallFrame.function.value.bytecode.instructions,
        .base = currentBlock.base,
        .offset = &currentBlockFrame.ip_offset,
    };

    return try decoder.decodeInline(Bytecode.Op);
}

pub fn decodeNextUnchecked(fiber: *Core.Fiber) callconv(Config.INLINING_CALL_CONV) Bytecode.Op {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const currentBlockFrame = fiber.stack.block.topPtrUnchecked();
    const currentBlock = &currentCallFrame.function.value.bytecode.blocks[currentBlockFrame.index];

    const decoder = IO.Decoder {
        .memory = currentCallFrame.function.value.bytecode.instructions,
        .base = currentBlock.base,
        .offset = &currentBlockFrame.ip_offset,
    };

    return decoder.decodeInlineUnchecked(Bytecode.Op);
}

// TODO:
// 1. handle type checking
// 2. handle type conversion for structural types
pub fn invoke(fiber: *Core.Fiber, comptime T: type, functionIndex: Bytecode.FunctionIndex, arguments: anytype) Trap!T {
    const function = &fiber.program.functions[functionIndex];

    const wrapper = Bytecode.Function {
        .index = Bytecode.FUNCTION_SENTINEL,
        .layout_table = Bytecode.LayoutTable {
            .term_type = Bytecode.Type.void_t,
            .return_type = Bytecode.Type.void_t,
            .register_types = &[_]Bytecode.TypeIndex {function.layout_table.return_type},

            .term_layout = null,
            .return_layout = null,
            .register_layouts = &[_]Bytecode.Layout {
                .{
                    .size = @sizeOf(T),
                    .alignment = @alignOf(T),
                },
            },

            .register_offsets = &[_]Bytecode.RegisterBaseOffset {0},

            .size = @sizeOf(T),
            .alignment = @alignOf(T),

            .num_arguments = 0,
            .num_registers = 1,
        },
        .value = undefined,
    };

    const dataReset = fiber.stack.data.ptr;
    var dataOrigin = fiber.stack.data.ptr;
    try fiber.stack.data.pushUninit(Support.alignmentDelta(fiber.stack.data.ptr, @alignOf(T)));

    var dataBase = fiber.stack.data.ptr;
    try fiber.stack.data.pushUninit(@sizeOf(T));

    try fiber.stack.call.push(CallFrame {
        .function = &wrapper,
        .evidence = CallFrame.EvidenceRef.SENTINEL,
        .root_block = fiber.stack.block.ptr,
        .stack = .{
            .base = dataBase,
            .origin = dataOrigin,
        }
    });
    // const callOrigin = fiber.stack.call.ptr;

    dataOrigin = fiber.stack.data.ptr;
    try fiber.stack.data.pushUninit(Support.alignmentDelta(fiber.stack.data.ptr, function.layout_table.alignment));
    dataBase = fiber.stack.data.ptr;

    try fiber.stack.block.push(BlockFrame {
        .index = 0,
        .ip_offset = 0,
        .out = undefined,
        .handler_set = Bytecode.HANDLER_SET_SENTINEL,
    });

    dataBase = fiber.stack.data.ptr;
    try fiber.stack.data.pushUninit(function.layout_table.size);
    try fiber.stack.call.push(CallFrame {
        .function = function,
        .evidence = CallFrame.EvidenceRef.SENTINEL,
        .root_block = fiber.stack.block.ptr,
        .stack = .{
            .base = dataBase,
            .origin = dataOrigin,
        },
    });
    try fiber.stack.block.push(BlockFrame {
        .index = 0,
        .ip_offset = 0,
        .out = .local(.r0, 0),
        .handler_set = Bytecode.HANDLER_SET_SENTINEL,
    });

    inline for (0..arguments.len) |i| {
        fiber.write(.local(@enumFromInt(i), 0), arguments[i]);
    }

    // while (fiber.stack.call.ptr > callOrigin) {
        // const stderr = std.io.getStdErr().writer();
        // var callFrame = try fiber.stack.call.topPtr();

        // switch (callFrame.function.value) {
        //     .bytecode => |bc| {
        //         const blockFrame = try fiber.stack.block.topPtr();
        //         const currentBlock = bc.blocks[blockFrame.index];
        //         var ip = blockFrame.ip_offset;
        //         const decoder = IO.Decoder { .memory = bc.instructions, .base = currentBlock.base, .offset = &ip };
        //         std.debug.print("stepping {x:0>6}\n\t", .{decoder.ip()});
        //         const op = try decoder.decode(Bytecode.Op);
        //         Disassembler.instruction(op, stderr) catch unreachable;
        //     },
        //     .foreign => |foreignId| {
        //         std.debug.print("stepping foreign function {}", .{foreignId});
        //     }
        // }

        // var currentRegisters = try fiber.getRegisterData(callFrame);
        // fiber.dumpRegisters(currentRegisters.local, stderr) catch unreachable;
        // fiber.dumpGlobals(stderr) catch unreachable;

        // try Core.Eval.step(fiber);
        // std.debug.print("step complete\n", .{});

        // callFrame = try fiber.stack.call.topPtr();
        // currentRegisters = try fiber.getRegisterData(callFrame);
        // fiber.dumpRegisters(currentRegisters.local, stderr) catch unreachable;
        // fiber.dumpGlobals(stderr) catch unreachable;
    // }

    try Core.Eval.stepCall(fiber);

    const result = fiber.read(T, .local(.r0, 0));

    fiber.stack.data.ptr = dataReset;
    _ = try fiber.stack.call.pop();
    _ = try fiber.stack.block.pop();

    return result;
}

pub fn load(fiber: *Fiber, comptime T: type, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = fiber.read([*]const u8, x);
    const outAddr: [*]u8 = fiber.addr(y);

    try fiber.boundsCheck(inAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

pub fn store(fiber: *Fiber, comptime T: type, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = fiber.addr(x);
    const outAddr: [*]u8 = fiber.read([*]u8, y);

    try fiber.boundsCheck(outAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

pub fn clear(fiber: *Fiber, comptime T: type, x: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    // const size = @sizeOf(T);
    // const alignment = @alignOf(T);

    const bytes: [*]u8 = fiber.addr(x);

    // if (Support.alignmentDelta(@intFromPtr(bytes), alignment) != 0) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    @as(*T, @ptrCast(@alignCast(bytes))).* = 0;
}

pub fn swap(fiber: *Fiber, comptime T: type, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    // const size = @sizeOf(T);
    // const alignment = @alignOf(T);

    const xBytes: [*]u8 = fiber.addr(x);
    const yBytes: [*]u8 = fiber.addr(y);

    // const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    // const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    // if (xAligned & yAligned != 1) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    const temp: T = @as(*T, @ptrCast(@alignCast(xBytes))).*;
    @as(*T, @ptrCast(@alignCast(xBytes))).* = @as(*T, @ptrCast(@alignCast(yBytes))).*;
    @as(*T, @ptrCast(@alignCast(yBytes))).* = temp;
}

pub fn copy(fiber: *Fiber, comptime T: type, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    // const size = @sizeOf(T);
    // const alignment = @alignOf(T);

    const xBytes: [*]const u8 = fiber.addr(x);
    const yBytes: [*]u8 = fiber.addr(y);

    // const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    // const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    // if (xAligned & yAligned != 1) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    @as(*T, @ptrCast(@alignCast(yBytes))).* = @as(*const T, @ptrCast(@alignCast(xBytes))).*;
}

pub inline fn read(fiber: *Fiber, comptime T: type, operand: Bytecode.Operand) T {
    return fiber.readImpl(T, fiber.stack.call.ptr -| 1, operand);
}

pub inline fn write(fiber: *Fiber, operand: Bytecode.Operand, value: anytype) void {
    return fiber.writeImpl(fiber.stack.call.ptr -| 1, operand, value);
}

pub inline fn addr(fiber: *Fiber, operand: Bytecode.Operand) [*]u8 {
    return fiber.addrImpl(fiber.stack.call.ptr -| 1, operand);
}

pub inline fn readImpl(fiber: *Fiber, comptime T: type, framePtr: CallStack.Ptr, operand: Bytecode.Operand) T {
    switch (operand.kind) {
        .global => return fiber.readGlobal(T, operand.data.global),
        .upvalue => return fiber.readReg(T, fiber.getRegisterDataUnchecked(.upvalue, framePtr), operand.data.register),
        .local => return fiber.readReg(T, fiber.getRegisterDataUnchecked(.local, framePtr), operand.data.register),
    }
}

pub inline fn writeImpl(fiber: *Fiber, framePtr: CallStack.Ptr, operand: Bytecode.Operand, value: anytype) void {
    switch (operand.kind) {
        .global => return fiber.writeGlobal(operand.data.global, value),
        .upvalue => return fiber.writeReg(fiber.getRegisterDataUnchecked(.upvalue, framePtr), operand.data.register, value),
        .local => return fiber.writeReg(fiber.getRegisterDataUnchecked(.local, framePtr), operand.data.register, value),
    }
}

pub inline fn addrImpl(fiber: *Fiber, framePtr: CallStack.Ptr, operand: Bytecode.Operand) [*]u8 {
    switch (operand.kind) {
        .global => return fiber.addrGlobal(operand.data.global),
        .upvalue => return fiber.addrReg(fiber.getRegisterDataUnchecked(.upvalue, framePtr), operand.data.register),
        .local => return fiber.addrReg(fiber.getRegisterDataUnchecked(.local, framePtr), operand.data.register),
    }
}

pub fn addrReg(fiber: *Fiber, regData: RegisterData, operand: Bytecode.RegisterOperand) callconv(Config.INLINING_CALL_CONV) [*]u8 {
    const base = getRegisterOffsetUnchecked(regData, operand.register);

    // if (!regData.layout.inbounds(operand, @truncate(size))) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    return @ptrCast(fiber.stack.data.getPtrUnchecked(base + operand.offset));
}

pub fn readGlobal(fiber: *Fiber, comptime T: type, operand: Bytecode.GlobalOperand) callconv(Config.INLINING_CALL_CONV) T {
    const bytes = addrGlobal(fiber, operand);

    // TODO: flags to enable safety checks
    // if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

pub fn readReg(fiber: *Fiber, comptime T: type, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand) callconv(Config.INLINING_CALL_CONV) T {
    // const size = @sizeOf(T);

    const base = getRegisterOffsetUnchecked(regData, operand.register);

    // TODO: flags to enable safety checks
    // if (!regData.layout.inbounds(operand, size)) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const bytes = fiber.stack.data.getPtrUnchecked(base + operand.offset);

    // if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

pub fn writeGlobal(fiber: *Fiber, operand: Bytecode.GlobalOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) void {
    const T = @TypeOf(value);
    const mem = addrGlobal(fiber, operand);

    // TODO: flags to enable safety checks
    // if (Support.alignmentDelta(@intFromPtr(mem), @alignOf(T)) != 0) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    @as(*T, @ptrCast(@alignCast(mem))).* = value;
}

pub fn writeReg(fiber: *Fiber, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) void {
    const T = @TypeOf(value);
    // const size = @sizeOf(T);

    const base = getRegisterOffsetUnchecked(regData, operand.register);

    // if (!regData.layout.inbounds(operand, size)) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const bytes = fiber.stack.data.getPtrUnchecked(base + operand.offset);

    // if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.BadAlignment;
    // }

    @as(*T, @ptrCast(@alignCast(bytes))).* = value;
}

pub fn addrGlobal(fiber: *Fiber, operand: Bytecode.GlobalOperand) callconv(Config.INLINING_CALL_CONV) [*]u8 {
    // if (operand.index >= fiber.program.globals.values.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const global = &fiber.program.globals.values[operand.index];

    // if (!global.layout.inbounds(operand.offset, size)) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    return @ptrCast(&fiber.program.globals.memory[global.offset + operand.offset]);
}

pub fn getRegisterOffset(regData: Fiber.RegisterData, register: Bytecode.Register) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.DataStack.Ptr {
    const regNumber: Bytecode.RegisterIndex = @intFromEnum(register);

    if (regNumber < regData.layout.num_registers) {
        return regData.call.stack.base + regData.layout.register_offsets[regNumber];
    } else {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }
}

pub fn getRegisterOffsetUnchecked(regData: Fiber.RegisterData, register: Bytecode.Register) callconv(Config.INLINING_CALL_CONV) Fiber.DataStack.Ptr {
    const regNumber: Bytecode.RegisterIndex = @intFromEnum(register);
    return regData.call.stack.base + regData.layout.register_offsets[regNumber];
}

pub fn cast(fiber: *Fiber, comptime X: type, comptime Y: type, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) void {
    const x = fiber.read(X, operands.x);

    const xKind = @as(std.builtin.TypeId, @typeInfo(X));
    const yKind = @as(std.builtin.TypeId, @typeInfo(Y));

    const y =
        if (comptime xKind == yKind) (
            if (comptime xKind == .int) @call(Config.INLINING_CALL_MOD, ops.intCast, .{Y, x})
            else @call(Config.INLINING_CALL_MOD, ops.floatCast, .{Y, x})
        ) else @call(Config.INLINING_CALL_MOD, ops.typeCast, .{Y, x});

    fiber.write(operands.y, y);
}

pub fn unary(fiber: *Fiber, comptime T: type, comptime op: []const u8, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) void {
    const x = fiber.read(T, operands.x);

    const y = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x});

    fiber.write(operands.y, y);
}

pub fn binary(fiber: *Fiber, comptime T: type, comptime op: []const u8, operands: Bytecode.ISA.ThreeOperand) callconv(Config.INLINING_CALL_CONV) void {
    const x = fiber.read(T, operands.x);
    const y = fiber.read(T, operands.y);

    const z = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x, y});

    fiber.write(operands.z, z);
}

const ops = struct {
    fn intCast(comptime T: type, x: anytype) T {
        const U = @TypeOf(x);

        if (comptime @typeInfo(U).int.bits > @typeInfo(T).int.bits) {
            return @truncate(x);
        } else {
            return x;
        }
    }

    fn floatCast(comptime T: type, x: anytype) T {
        return @floatCast(x);
    }

    fn typeCast(comptime T: type, x: anytype) T {
        const U = @TypeOf(x);

        const tagT = @as(std.builtin.TypeId, @typeInfo(T));
        const tagU = @as(std.builtin.TypeId, @typeInfo(U));

        if (comptime tagT == .int and tagU == .float) {
            return @intFromFloat(x);
        } else if (comptime tagT == .float and tagU == .int) {
            return @floatFromInt(x);
        } else unreachable;
    }

    fn neg(a: anytype) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return -% a,
            else => return -a,
        }
    }

    fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return a +% b,
            else => return a + b,
        }
    }

    fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return a -% b,
            else => return a - b,
        }
    }

    fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return a *% b,
            else => return a * b,
        }
    }

    fn div(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return @divTrunc(a, b),
            else => return a / b,
        }
    }

    fn rem(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return @rem(a, b);
    }

    fn bitnot(a: anytype) @TypeOf(a) {
        return ~a;
    }

    fn not(a: anytype) @TypeOf(a) {
        return !a;
    }

    fn bitand(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a & b;
    }

    fn @"and"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a and b;
    }

    fn bitor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a | b;
    }

    fn @"or"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a or b;
    }

    fn bitxor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a ^ b;
    }

    fn shiftl(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        const bits = @bitSizeOf(T);
        const S = std.meta.Int(.unsigned, std.math.log2(bits));
        const U = std.meta.Int(.unsigned, bits);
        const bu: U = @bitCast(b);
        const bs: U = @rem(std.math.maxInt(S), bu);
        return a << @truncate(bs);
    }

    fn shiftr(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        const bits = @bitSizeOf(T);
        const S = std.meta.Int(.unsigned, std.math.log2(bits));
        const U = std.meta.Int(.unsigned, bits);
        const bu: U = @bitCast(b);
        const bs: U = @rem(std.math.maxInt(S), bu);
        return a >> @truncate(bs);
    }

    fn eq(a: anytype, b: @TypeOf(a)) bool {
        return a == b;
    }

    fn ne(a: anytype, b: @TypeOf(a)) bool {
        return a != b;
    }

    fn lt(a: anytype, b: @TypeOf(a)) bool {
        return a < b;
    }

    fn gt(a: anytype, b: @TypeOf(a)) bool {
        return a > b;
    }

    fn le(a: anytype, b: @TypeOf(a)) bool {
        return a <= b;
    }

    fn ge(a: anytype, b: @TypeOf(a)) bool {
        return a >= b;
    }
};


pub fn dumpGlobals(fiber: *Fiber, writer: anytype) !void {
    try writer.writeAll("Globals:\n");

    for (fiber.program.globals.values, 0..) |global, i| {
        const typeId = global.type;
        const layout = global.layout;
        const valueBase = &fiber.program.globals.memory[global.offset];

        try writer.print("\t{} (", .{ i });
        try Bytecode.printType(fiber.program.types, typeId, writer);
        try writer.print(") at {x:0>8}:\n\t\t", .{ global.offset });
        try Bytecode.printValue(fiber.program.types, typeId, @ptrCast(valueBase), layout.size, writer);
        try writer.writeAll("\n");
    }
}

pub fn dumpRegisters(fiber: *Fiber, registerData: Fiber.RegisterData, writer: anytype) !void {
    try writer.writeAll("Registers:\n");

    for (0..registerData.layout.num_registers) |i| {
        const typeId = registerData.layout.register_types[i];
        const layout = registerData.layout.register_layouts[i];
        const reg: Bytecode.Register = @enumFromInt(i);
        try writer.print("\t{s} (", .{ @tagName(reg) });
        try Bytecode.printType(fiber.program.types, typeId, writer);
        const offset = try getRegisterOffset(registerData, reg);
        try writer.print(") at {x:0>6}:\n\t\t", .{ offset });

        const valueBase = try fiber.stack.data.getPtr(offset);

        try Bytecode.printValue(fiber.program.types, typeId, @ptrCast(valueBase), layout.size, writer);
        try writer.writeAll("\n");
    }
}
