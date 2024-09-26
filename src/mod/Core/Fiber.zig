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
    done_v: Bytecode.RegisterIndex,
    trap: Extern.Error,
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

pub const Evidence = struct {
    handler: Bytecode.FunctionIndex,
    data: DataStack.Ptr,
    call: CallStack.Ptr,
    block: BlockStack.Ptr,
};

pub const BlockFrame = struct {
    index: Bytecode.BlockIndex,
    ip_offset: Bytecode.InstructionPointerOffset,
    out: Bytecode.RegisterIndex,
    handler_set: Bytecode.HandlerSetIndex,

    pub inline fn noOutput(index: Bytecode.BlockIndex, handler_set: ?Bytecode.HandlerSetIndex) BlockFrame {
        return .{ .index = index, .ip_offset = 0, .out = undefined, .handler_set = handler_set orelse Bytecode.HANDLER_SET_SENTINEL };
    }

    pub inline fn entryPoint(operand: ?Bytecode.RegisterIndex) BlockFrame {
        return
            if (operand) |op| .{ .index = 0, .ip_offset = 0, .out = op, .handler_set = Bytecode.HANDLER_SET_SENTINEL }
            else .{ .index = 0, .ip_offset = 0, .out = undefined, .handler_set = Bytecode.HANDLER_SET_SENTINEL };
    }

    pub inline fn value(index: Bytecode.BlockIndex, r: Bytecode.RegisterIndex, handler_set: ?Bytecode.HandlerSetIndex) BlockFrame {
        return .{ .index = index, .ip_offset = 0, .out = r, .handler_set = handler_set orelse Bytecode.HANDLER_SET_SENTINEL };
    }
};

pub const CallFrame = struct {
    function: *const Bytecode.Function,
    evidence: EvidenceRef,
    root_block: BlockStack.Ptr,
    stack: DataStack.Ptr,

    pub const EvidenceRef = struct {
        index: Bytecode.EvidenceIndex,
        offset: EvidenceStack.Ptr,
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


pub fn getForeign(self: *const Fiber, index: Bytecode.ForeignId) callconv(Config.INLINING_CALL_CONV) ForeignFunction {
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




// TODO:
// 1. handle type checking
// 2. handle type conversion for structural types
pub fn invoke(fiber: *Core.Fiber, comptime T: type, functionIndex: Bytecode.FunctionIndex, arguments: anytype) Trap!T {
    const function = &fiber.program.functions[functionIndex];

    const wrapper = Bytecode.Function {
        .index = Bytecode.FUNCTION_SENTINEL,
        .num_registers = 1,
        .value = .{.bytecode = .{
            .blocks = &[_]Bytecode.Block {
                .{ .base = 0, .size = 1 },
            },
            .instructions = &[_]u8 {
                @intFromEnum(Bytecode.OpCode.halt),
            },
        }},
    };

    const dataReset = fiber.stack.data.ptr;

    var dataBase = fiber.stack.data.ptr;
    try fiber.stack.data.pushUninit(8);
    try fiber.stack.call.push(CallFrame {
        .function = &wrapper,
        .evidence = undefined,
        .root_block = fiber.stack.block.ptr,
        .stack = dataBase,
    });
    try fiber.stack.block.push(BlockFrame {
        .index = 0,
        .ip_offset = 0,
        .out = undefined,
        .handler_set = Bytecode.HANDLER_SET_SENTINEL,
    });

    dataBase = fiber.stack.data.ptr;
    try fiber.stack.data.pushUninit(function.num_registers * 8);
    try fiber.stack.call.push(CallFrame {
        .function = function,
        .evidence = undefined,
        .root_block = fiber.stack.block.ptr,
        .stack = dataBase,
    });
    try fiber.stack.block.push(BlockFrame {
        .index = 0,
        .ip_offset = 0,
        .out = 0,
        .handler_set = Bytecode.HANDLER_SET_SENTINEL,
    });

    inline for (0..arguments.len) |i| {
        fiber.writeLocal(i, arguments[i]);
    }

    try Core.Eval.run(fiber);

    const result = fiber.readLocal(T, 0);

    fiber.stack.data.ptr = dataReset;
    _ = try fiber.stack.call.pop();
    _ = try fiber.stack.block.pop();

    return result;
}


pub inline fn readLocal(fiber: *Fiber, comptime T: type, r: Bytecode.RegisterIndex) T {
    return fiber.readReg(T, fiber.stack.call.ptr - 1, r);
}

pub inline fn writeLocal(fiber: *Fiber, r: Bytecode.RegisterIndex, value: anytype) void {
    return fiber.writeReg(fiber.stack.call.ptr - 1, r, value);
}

pub inline fn addrLocal(fiber: *Fiber, r: Bytecode.RegisterIndex) [*]u8 {
    return fiber.addrReg(fiber.stack.call.ptr - 1, r);
}


pub inline fn readUpvalue(fiber: *Fiber, comptime T: type, u: Bytecode.UpvalueIndex) T {
    const evidence = fiber.getEvidence(fiber.stack.call.ptr - 1);
    return fiber.readReg(T, evidence.call, u);
}

pub inline fn writeUpvalue(fiber: *Fiber, u: Bytecode.UpvalueIndex, value: anytype) void {
    const evidence = fiber.getEvidence(fiber.stack.call.ptr - 1);
    return fiber.writeReg(evidence.call, u, value);
}

pub inline fn addrUpvalue(fiber: *Fiber, u: Bytecode.UpvalueIndex) [*]u8 {
    const evidence = fiber.getEvidence(fiber.stack.call.ptr - 1);
    return fiber.addrReg(evidence.call, u);
}


pub fn addrGlobal(fiber: *Fiber, g: Bytecode.GlobalIndex) callconv(Config.INLINING_CALL_CONV) [*]u8 {
    const global = &fiber.program.globals.values[g];

    return @ptrCast(&fiber.program.globals.memory[global.offset]);
}

pub fn readGlobal(fiber: *Fiber, comptime T: type, g: Bytecode.GlobalIndex) callconv(Config.INLINING_CALL_CONV) T {
    const bytes = fiber.addrGlobal(g);

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

pub fn writeGlobal(fiber: *Fiber, g: Bytecode.GlobalIndex, value: anytype) callconv(Config.INLINING_CALL_CONV) void {
    const T = @TypeOf(value);
    const bytes = fiber.addrGlobal(g);

    @as(*T, @ptrCast(@alignCast(bytes))).* = value;
}


pub fn addrReg(fiber: *Fiber, framePtr: CallStack.Ptr, r: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) [*]u8 {
    const offset = fiber.getRegisterOffset(framePtr, r);

    return @ptrCast(fiber.stack.data.getPtrUnchecked(offset));
}

pub fn readReg(fiber: *Fiber, comptime T: type, framePtr: CallStack.Ptr, r: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) T {
    const offset = fiber.getRegisterOffset(framePtr, r);

    const bytes = fiber.stack.data.getPtrUnchecked(offset);

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

pub fn writeReg(fiber: *Fiber, framePtr: CallStack.Ptr, r: Bytecode.RegisterIndex, value: anytype) callconv(Config.INLINING_CALL_CONV) void {
    const T = @TypeOf(value);

    const offset = fiber.getRegisterOffset(framePtr, r);

    const bytes = fiber.stack.data.getPtrUnchecked(offset);

    @as(*T, @ptrCast(@alignCast(bytes))).* = value;
}


pub inline fn getRegisterOffset(fiber: *Fiber, framePtr: CallStack.Ptr, register: Bytecode.RegisterIndex) Fiber.DataStack.Ptr {
    const callFrame = fiber.stack.call.getPtrUnchecked(framePtr);
    return callFrame.stack + (register * 8);
}

pub inline fn getEvidence(fiber: *Fiber, framePtr: CallStack.Ptr) *Evidence {
    const callFrame = fiber.stack.call.getPtrUnchecked(framePtr);
    return fiber.evidence[callFrame.evidence.index].getPtrUnchecked(callFrame.evidence.offset);
}


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

pub fn dumpRegisters(fiber: *Fiber, framePtr: CallStack.Ptr, writer: anytype) !void {
    try writer.writeAll("Registers:\n");

    const callFrame = fiber.stack.call.getPtrUnchecked(framePtr);
    const details = fiber.program.layout_details[callFrame.function.index];

    for (0..callFrame.function.layout_table.num_registers) |i| {
        const typeId = details.register_types[i];
        const layout = details.register_layouts[i];
        const reg: Bytecode.Register = @enumFromInt(i);
        try writer.print("\t{s} (", .{ @tagName(reg) });
        try Bytecode.printType(fiber.program.types, typeId, writer);
        const offset = try fiber.getRegisterOffset(framePtr, reg);
        try writer.print(") at {x:0>6}:\n\t\t", .{ offset });

        const valueBase = try fiber.stack.data.getPtr(offset);

        try Bytecode.printValue(fiber.program.types, typeId, @ptrCast(valueBase), layout.size, writer);
        try writer.writeAll("\n");
    }
}
