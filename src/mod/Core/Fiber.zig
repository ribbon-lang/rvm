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

pub const ForeignFunction = *const fn (*anyopaque, Bytecode.BlockIndex, *const ForeignRegisterDataSet, *ForeignOut) callconv(.C) ForeignControl;

pub const ForeignControl = enum(u32) {
    step,
    done,
    trap,
};

pub const ForeignOut = extern union {
    step: Bytecode.BlockIndex,
    done: Bytecode.Operand,
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


pub const CALL_STACK_SIZE: usize = 4096;
pub const BLOCK_STACK_SIZE: usize = CALL_STACK_SIZE * Bytecode.MAX_BLOCKS;
pub const EVIDENCE_VECTOR_SIZE: usize = Bytecode.MAX_EVIDENCE;
pub const EVIDENCE_STACK_SIZE: usize = std.math.maxInt(EvidenceStack.Ptr);
pub const DATA_STACK_SIZE: usize
    = (1024 * 1024 * 8)
    - @rem(TOTAL_META_SIZE, 1024 * 1024)
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
    evidence: ?EvidenceRef,
    root_block: BlockStack.Ptr,
    stack: StackRef,

    pub const StackRef = packed struct {
        base: DataStack.Ptr,
        origin: DataStack.Ptr,
    };

    pub const EvidenceRef = packed struct {
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

pub fn getForeign(self: *const Fiber, index: Bytecode.ForeignId) !ForeignFunction {
    if (index >= self.foreign.len) {
        return Trap.OutOfBounds;
    }

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

pub fn removeAnyHandlerSet(fiber: *Fiber, blockFrame: *Fiber.BlockFrame) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (blockFrame.handler_set == Bytecode.HANDLER_SET_SENTINEL) return;

    const handlerSet = fiber.program.handler_sets[blockFrame.handler_set];

    try removeHandlerSet(fiber, handlerSet);
}

pub fn removeHandlerSet(fiber: *Fiber, handlerSet: Bytecode.HandlerSet) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    for (handlerSet) |binding| {
        const removedEv = try fiber.evidence[binding.id].pop();

        std.debug.assert(removedEv.handler == binding.handler);
    }
}

pub fn getRegisterData(fiber: *Fiber, callFrame: *Fiber.CallFrame) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.RegisterDataSet {
    return .{
        .local = .{
            .call = callFrame,
            .layout = &callFrame.function.layout_table,
        },
        .upvalue = if (callFrame.evidence) |evRef| ev: {
            const evidence = try fiber.evidence[evRef.index].getPtr(evRef.offset);
            const evFrame = try fiber.stack.call.getPtr(evidence.call);
            const evFunction = evFrame.function;
            break :ev .{
                .call = evFrame,
                .layout = &evFunction.layout_table
            };
        } else null,
    };
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
        .evidence = null,
        .root_block = fiber.stack.block.ptr,
        .stack = .{
            .base = dataBase,
            .origin = dataOrigin,
        }
    });
    const callOrigin = fiber.stack.call.ptr;

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
        .evidence = null,
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

    var registerData = try fiber.getRegisterData(try fiber.stack.call.topPtr());

    inline for (0..arguments.len) |i| {
        try fiber.write(registerData, .local(@enumFromInt(i), 0), arguments[i]);
    }

    while (fiber.stack.call.ptr > callOrigin) {
        try Core.Eval.step(fiber);
    }

    registerData = try fiber.getRegisterData(try fiber.stack.call.topPtr());

    const result = try fiber.read(T, registerData, .local(.r0, 0));

    fiber.stack.data.ptr = dataReset;
    _ = try fiber.stack.call.pop();
    _ = try fiber.stack.block.pop();

    return result;
}

pub fn load(fiber: *Fiber, comptime T: type, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = try fiber.read([*]const u8, registerData, x);
    const outAddr: [*]u8 = try fiber.addr(registerData, y, size);

    try fiber.boundsCheck(inAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

pub fn store(fiber: *Fiber, comptime T: type, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = try fiber.addr(registerData, x, size);
    const outAddr: [*]u8 = try fiber.read([*]u8, registerData, y);

    try fiber.boundsCheck(outAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

pub fn clear(fiber: *Fiber, comptime T: type, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const bytes: [*]u8 = try fiber.addr(registerData, x, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), alignment) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(bytes))).* = 0;
}

pub fn swap(fiber: *Fiber, comptime T: type, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const xBytes: [*]u8 = try fiber.addr(registerData, x, size);
    const yBytes: [*]u8 = try fiber.addr(registerData, y, size);

    const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    if (xAligned & yAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    const temp: T = @as(*T, @ptrCast(@alignCast(xBytes))).*;
    @as(*T, @ptrCast(@alignCast(xBytes))).* = @as(*T, @ptrCast(@alignCast(yBytes))).*;
    @as(*T, @ptrCast(@alignCast(yBytes))).* = temp;
}

pub fn copy(fiber: *Fiber, comptime T: type, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const xBytes: [*]const u8 = try fiber.addr(registerData, x, size);
    const yBytes: [*]u8 = try fiber.addr(registerData, y, size);

    const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    if (xAligned & yAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(yBytes))).* = @as(*const T, @ptrCast(@alignCast(xBytes))).*;
}

pub inline fn read(fiber: *Fiber, comptime T: type, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand) Fiber.Trap!T {
    switch (operand.kind) {
        .global => return fiber.readGlobal(T, operand.data.global),
        .upvalue => return fiber.readReg(T, try registerData.extractUp(), operand.data.register),
        .local => return fiber.readReg(T, registerData.local, operand.data.register),
    }
}

pub inline fn write(fiber: *Fiber, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand, value: anytype) Fiber.Trap!void {
    switch (operand.kind) {
        .global => return fiber.writeGlobal(operand.data.global, value),
        .upvalue => return fiber.writeReg(try registerData.extractUp(), operand.data.register, value),
        .local => return fiber.writeReg(registerData.local, operand.data.register, value),
    }
}

pub inline fn addr(fiber: *Fiber, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) Fiber.Trap![*]u8 {
    switch (operand.kind) {
        .global => return fiber.addrGlobal(operand.data.global, size),
        .upvalue => return fiber.addrReg(try registerData.extractUp(), operand.data.register, size),
        .local => return fiber.addrReg(registerData.local, operand.data.register, size),
    }
}

pub fn addrReg(fiber: *Fiber, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    const base = try getRegisterOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, @truncate(size))) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(try fiber.stack.data.getPtr(base + operand.offset));
}

pub fn readGlobal(fiber: *Fiber, comptime T: type, operand: Bytecode.GlobalOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const bytes = try addrGlobal(fiber, operand, @sizeOf(T));

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

pub fn readReg(fiber: *Fiber, comptime T: type, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const size = @sizeOf(T);

    const base = try getRegisterOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = try fiber.stack.data.checkSlice(base + operand.offset, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

pub fn writeGlobal(fiber: *Fiber, operand: Bytecode.GlobalOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const T = @TypeOf(value);
    const mem = try addrGlobal(fiber, operand, @sizeOf(T));

    if (Support.alignmentDelta(@intFromPtr(mem), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(mem))).* = value;
}

pub fn writeReg(fiber: *Fiber, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);

    const base = try getRegisterOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = try fiber.stack.data.checkSlice(base, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(bytes))).* = value;
}

pub fn addrGlobal(fiber: *Fiber, operand: Bytecode.GlobalOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    if (operand.index >= fiber.program.globals.values.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const data = &fiber.program.globals.values[operand.index];

    if (!data.layout.inbounds(operand.offset, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(&fiber.program.globals.memory[operand.offset]);
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

pub fn cast(fiber: *Fiber, comptime A: type, comptime B: type, registerData: Fiber.RegisterDataSet, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const x = try fiber.read(A, registerData, operands.x);

    const aKind = @as(std.builtin.TypeId, @typeInfo(A));
    const bKind = @as(std.builtin.TypeId, @typeInfo(B));
    const result =
        if (comptime aKind == bKind) (
            if (comptime aKind == .int) @call(Config.INLINING_CALL_MOD, ops.intCast, .{B, x})
            else @call(Config.INLINING_CALL_MOD, ops.floatCast, .{B, x})
        ) else @call(Config.INLINING_CALL_MOD, ops.typeCast, .{B, x});

    try fiber.write(registerData, operands.y, result);
}

pub fn unary(fiber: *Fiber, comptime T: type, comptime op: []const u8, registerData: Fiber.RegisterDataSet, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const x = try fiber.read(T, registerData, operands.x);

    const result = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x});

    try fiber.write(registerData, operands.y, result);
}

pub fn binary(fiber: *Fiber, comptime T: type, comptime op: []const u8, registerData: Fiber.RegisterDataSet, operands: Bytecode.ISA.ThreeOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const x = try fiber.read(T, registerData, operands.x);
    const y = try fiber.read(T, registerData, operands.y);

    const result = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x, y});

    try fiber.write(registerData, operands.z, result);
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


pub fn dumpRegisters(fiber: *Fiber, registerData: Fiber.RegisterData, writer: anytype) !void {
    try writer.print("Registers:\n");

    for (0..registerData.layout.num_registers) |i| {
        const typeId = registerData.layout.register_types[i];
        const layout = registerData.layout.register_layouts[i];
        const reg: Bytecode.Register = @enumFromInt(i);
        const offset = try getRegisterOffset(registerData, reg);
        const valueBase = try fiber.stack.data.getPtr(offset);

        try writer.print("    {s} (", .{ @tagName(reg) });
        try Bytecode.printType(fiber.program.types, typeId, writer);
        try writer.print(") at {x:0>16}:\n        ", .{ @intFromPtr(offset) });
        try Bytecode.printValue(fiber.program.types, typeId, valueBase, layout.size, writer);
        try writer.writeAll("\n");
    }
}
