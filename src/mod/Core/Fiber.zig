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

const Extern = @import("Extern");
const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Core = @import("root.zig");
const Context = Core.Context;
const Stack = Core.Stack;


const Fiber = @This();


context: *Context,
program: *Bytecode.Program,
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
    layout: *Bytecode.LayoutTable,
};

pub const RegisterDataSet = struct {
    local: RegisterData,
    upvalue: ?RegisterData,
};

pub const ForeignFunction = *const fn (*Fiber, Bytecode.BlockIndex, *const ForeignRegisterDataSet, *ForeignOut) callconv(.C) ForeignControl;

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
pub const BLOCK_STACK_SIZE: usize = CALL_STACK_SIZE * 256;
pub const EVIDENCE_VECTOR_SIZE: usize = 1024;
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

pub const DataStack = Stack(u8, u24);
pub const CallStack = Stack(CallFrame, u16);
pub const BlockStack = Stack(BlockFrame, u16);
pub const EvidenceStack = Stack(Evidence, u8);

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
    function: Bytecode.FunctionIndex,
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


pub fn init(context: *Context, program: *Bytecode.Program, foreign: []const ForeignFunction) !*Fiber {
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
        .function = call.function,
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
