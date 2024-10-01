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


const Fiber = @This();


context: *const Context,
program: *const Bytecode.Program,
data: DataStack,
calls: CallStack,
blocks: BlockStack,
evidence: []EvidenceStack,
foreign: []const ForeignFunction,


pub const CALL_STACK_SIZE: usize = 1024;
pub const BLOCK_STACK_SIZE: usize = CALL_STACK_SIZE * Bytecode.MAX_BLOCKS;
pub const EVIDENCE_VECTOR_SIZE: usize = Bytecode.MAX_EVIDENCE;
pub const EVIDENCE_STACK_SIZE: usize = 1024;
pub const DATA_STACK_SIZE: usize = CALL_STACK_SIZE * Bytecode.MAX_REGISTERS;


pub const DataStack = Stack(Bytecode.Register, false);
pub const CallStack = Stack(CallFrame, true);
pub const BlockStack = Stack(BlockFrame, true);
pub const EvidenceStack = Stack(Evidence, true);

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



pub fn Stack(comptime T: type, comptime PRE_INCR: bool) type {
    return struct {
        top_ptr: [*]T,

        base_ptr: [*]T,
        max_ptr: [*]T,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const buf = try allocator.alloc(T, size);
            return .{
                .top_ptr =
                    if (comptime PRE_INCR) buf.ptr - 1
                    else buf.ptr,
                .base_ptr = buf.ptr,
                .max_ptr = buf.ptr + size,
            };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.base_ptr[0..(@intFromPtr(self.max_ptr) - @intFromPtr(self.base_ptr)) / @sizeOf(T)]);
        }

        pub inline fn push(self: *Self, value: T) void {
            if (comptime PRE_INCR) {
                self.top_ptr += 1;
                self.top_ptr[0] = value;
            } else {
                self.top_ptr[0] = value;
                self.top_ptr += 1;
            }
        }

        pub inline fn pushGet(self: *Self, value: T) *T {
            if (comptime PRE_INCR) {
                self.top_ptr += 1;
                self.top_ptr[0] = value;
                return @ptrCast(self.top_ptr);
            } else {
                self.top_ptr[0] = value;
                self.top_ptr += 1;
                return @ptrCast(self.top_ptr - 1);
            }
        }

        pub inline fn top(self: *Self) *T {
            return @ptrCast(self.top_ptr);
        }

        pub inline fn incr(self: *Self, count: usize) void {
            self.top_ptr += count;
        }

        pub inline fn incrGet(self: *Self, count: usize) *T {
            return @ptrCast(self.incrGetMulti(count));
        }

        pub inline fn incrGetMulti(self: *Self, count: usize) [*]T {
            if (comptime PRE_INCR) {
                self.top_ptr += count;
                return self.top_ptr;
            } else {
                const out = self.top_ptr;
                self.top_ptr += count;
                return out;
            }
        }

        pub inline fn pop(self: *Self) void {
            self.top_ptr -= 1;
        }

        pub inline fn popGet(self: *Self) *T {
            if (comptime PRE_INCR) {
                const out = self.top_ptr;
                self.top_ptr -= 1;
                return @ptrCast(out);
            } else {
                self.top_ptr -= 1;
                return @ptrCast(self.top_ptr);
            }
        }

        pub inline fn hasSpace(self: *Self, count: usize) bool {
            return @intFromPtr(self.top_ptr + count) < @intFromPtr(self.max_ptr);
        }

        pub inline fn hasSpaceU1(self: *Self, count: usize) u1 {
            return @intFromBool(self.hasSpace(count));
        }
    };
}

pub const Evidence = struct {
    handler: *const Bytecode.Function,
    call: *CallFrame,
    block: *BlockFrame,
    data: [*]Bytecode.Register,
};

pub const BlockFrame = struct {
    base: [*]const Bytecode.Instruction,
    ip: [*]const Bytecode.Instruction,
    out: Bytecode.RegisterIndex,
    handler_set: ?*const Bytecode.HandlerSet,
};

pub const CallFrame = struct {
    function: *const Bytecode.Function,
    evidence: *Evidence,
    block: *BlockFrame,
    data: [*]Bytecode.Register,
};


pub fn init(context: *const Context, program: *const Bytecode.Program, foreign: []const ForeignFunction) !*Fiber {
    const ptr = try context.allocator.create(Fiber);
    errdefer context.allocator.destroy(ptr);

    const data = try DataStack.init(context.allocator, DATA_STACK_SIZE);
    errdefer data.deinit(context.allocator);

    const calls = try CallStack.init(context.allocator, CALL_STACK_SIZE);
    errdefer calls.deinit(context.allocator);

    const blocks = try BlockStack.init(context.allocator, BLOCK_STACK_SIZE);
    errdefer blocks.deinit(context.allocator);

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
        .data = data,
        .calls = calls,
        .blocks = blocks,
        .evidence = evidence,
        .foreign = foreign,
    };

    return ptr;
}

pub fn deinit(self: *Fiber) void {
    self.data.deinit(self.context.allocator);
    self.calls.deinit(self.context.allocator);
    self.blocks.deinit(self.context.allocator);

    for (self.evidence) |ev| {
        ev.deinit(self.context.allocator);
    }
    self.context.allocator.free(self.evidence);

    self.context.allocator.destroy(self);
}

pub fn getLocation(self: *const Fiber) Bytecode.Info.Location {
    const call = &self.calls.top_ptr[0];
    const block = &self.blocks.top_ptr[0];

    return .{
        .function = call.function,
        .block = block.base,
        .ip = block.ip,
    };
}


pub fn getForeign(self: *const Fiber, index: Bytecode.ForeignId) callconv(Config.INLINING_CALL_CONV) ForeignFunction {
    return self.foreign[index];
}

pub fn boundsCheck(self: *Fiber, address: anytype, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{self, address, size});
}

pub inline fn removeAnyHandlerSet(self: *Fiber, blockFrame: *const Fiber.BlockFrame) void {
    if (blockFrame.handler_set) |handlerSet| {
        self.removeHandlerSet(handlerSet);
    }
}

pub inline fn removeHandlerSet(self: *Fiber, handlerSet: *const Bytecode.HandlerSet) void {
    for (handlerSet.*) |binding| {
        const removedEv = self.evidence[binding.id].popGet();
        std.debug.assert(removedEv.handler == &self.program.functions[binding.handler]);
    }
}




pub fn invoke(self: *Core.Fiber, comptime T: type, functionIndex: Bytecode.FunctionIndex, arguments: anytype) Trap!T {
    const function = &self.program.functions[functionIndex];

    if (( self.calls.hasSpaceU1(2)
        & self.data.hasSpaceU1(function.num_registers + 1)
        ) != 1) {
        @branchHint(.cold);
        return Trap.Overflow;
    }

    const wrapperInstructions = [_]Bytecode.Instruction {
        .{ .code = .halt, .data = .{ .halt = {} } },
    };

    const wrapper = Bytecode.Function {
        .num_arguments = 0,
        .num_registers = 1,
        .value = .{.bytecode = .{
            .blocks = &[_][*]const Bytecode.Instruction {
                &wrapperInstructions
            },
            .instructions = &wrapperInstructions
        }},
    };

    var dataBase = self.data.incrGet(1);
    const wrapperBlock = self.blocks.pushGet(BlockFrame {
        .base = &wrapperInstructions,
        .ip = &wrapperInstructions,
        .out = undefined,
        .handler_set = null,
    });

    self.calls.push(CallFrame {
        .function = &wrapper,
        .evidence = undefined,
        .block = wrapperBlock,
        .data = @ptrCast(dataBase),
    });

    dataBase = self.data.incrGet(function.num_registers);

    const block = self.blocks.pushGet(BlockFrame {
        .base = function.value.bytecode.blocks[0],
        .ip = function.value.bytecode.blocks[0],
        .out = 0,
        .handler_set = null,
    });

    self.calls.push(CallFrame {
        .function = function,
        .evidence = undefined,
        .block = block,
        .data = @ptrCast(dataBase),
    });

    inline for (0..arguments.len) |i| {
        self.writeLocal(i, arguments[i]);
    }

    try Core.Eval.run(self);

    const result = self.readLocal(T, 0);

    const frame = self.calls.popGet();
    self.data.top_ptr = frame.data;

    self.blocks.pop();

    return result;
}


pub inline fn readLocal(self: *Fiber, comptime T: type, r: Bytecode.RegisterIndex) T {
    return readReg(T, self.calls.top(), r);
}

pub inline fn writeLocal(self: *Fiber, r: Bytecode.RegisterIndex, value: anytype) void {
    return writeReg(self.calls.top(), r, value);
}

pub inline fn addrLocal(self: *Fiber, r: Bytecode.RegisterIndex) *u64 {
    return addrReg(self.calls.top(), r);
}

pub inline fn readUpvalue(self: *Fiber, comptime T: type, u: Bytecode.UpvalueIndex) T {
    return readReg(T, self.calls.top().evidence.call, u);
}

pub inline fn writeUpvalue(self: *Fiber, u: Bytecode.UpvalueIndex, value: anytype) void {
    return writeReg(self.calls.top().evidence.call, u, value);
}

pub inline fn addrUpvalue(self: *Fiber, u: Bytecode.UpvalueIndex) *u64 {
    return addrReg(self.calls.top().evidence.call, u);
}

pub inline fn addrGlobal(self: *Fiber, g: Bytecode.GlobalIndex) [*]u8 {
    return self.program.globals[g];
}

pub inline fn readGlobal(self: *Fiber, comptime T: type, g: Bytecode.GlobalIndex) T {
    return @as(*T, @ptrCast(@alignCast(self.addrGlobal(g)))).*;
}

pub inline fn writeGlobal(self: *Fiber, g: Bytecode.GlobalIndex, value: anytype) void {
    @as(*@TypeOf(value), @ptrCast(@alignCast(self.addrGlobal(g)))).* = value;
}

pub inline fn addrReg(frame: *const CallFrame, r: Bytecode.RegisterIndex) *u64 {
    return @ptrCast(frame.data + r);
}

pub inline fn readReg(comptime T: type, frame: *const CallFrame, r: Bytecode.RegisterIndex) T {
    return @as(*T, @ptrCast(addrReg(frame, r))).*;
}

pub inline fn writeReg(frame: *const CallFrame, r: Bytecode.RegisterIndex, value: anytype) void {
    @as(*@TypeOf(value), @ptrCast(addrReg(frame, r))).* = value;
}


test {
    std.testing.refAllDeclsRecursive(@This());
}
