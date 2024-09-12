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

const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Core = @import("root.zig");
const Context = Core.Context;
const Stack = Core.Stack;


const Fiber = @This();


context: *Context,
program: *Bytecode.Program,
stack: StackSet,
evidence: []Evidence,


pub const Trap = error {
    Unreachable,
    Underflow,
    Overflow,
    OutOfBounds,
    MissingEvidence,
    OutValueMismatch,
    BadEncoding,
    ArgCountMismatch,
    MissingOutputValue,
    BadAlignment,
    InvalidBlockRestart,
};


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


pub const DATA_STACK_SIZE: usize
    = (1024 * 1024 * 8)
    // take a little bit off to account for the other stacks,
    // making a nice even number of mb for the total fiber size  (16mb, currently)
    - OVERFLOW_META_SIZE
     ;
pub const CALL_STACK_SIZE: usize = 4096;
pub const BLOCK_STACK_SIZE: usize = CALL_STACK_SIZE * 256;
pub const EVIDENCE_VECTOR_SIZE: usize = 1024;
const TOTAL_META_SIZE: usize
    = CALL_STACK_SIZE * @sizeOf(CallFrame)
    + BLOCK_STACK_SIZE * @sizeOf(BlockFrame)
    + EVIDENCE_VECTOR_SIZE * @sizeOf(Evidence);
const OVERFLOW_META_SIZE: usize
    = @rem(TOTAL_META_SIZE, 1024 * 1024);

comptime {
    std.testing.expect(DATA_STACK_SIZE >= 7 * 1024 * 1024) catch unreachable;
    std.testing.expectEqual(
        16 * 1024 * 1024,
        DATA_STACK_SIZE + TOTAL_META_SIZE
    ) catch unreachable;
}

pub const DataStack = Stack(u8, u24);
pub const CallStack = Stack(CallFrame, u16);
pub const BlockStack = Stack(BlockFrame, u16);

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

    pub inline fn noOutput(index: Bytecode.BlockIndex) BlockFrame {
        return .{ .index = index, .ip_offset = 0, .out = undefined };
    }

    pub inline fn entryPoint(operand: ?Bytecode.Operand) BlockFrame {
        return
            if (operand) |op| .{ .index = 0, .ip_offset = 0, .out = op }
            else .{ .index = 0, .ip_offset = 0, .out = undefined };
    }

    pub inline fn value(index: Bytecode.BlockIndex, operand: Bytecode.Operand) BlockFrame {
        return .{ .index = index, .ip_offset = 0, .out = operand };
    }
};

pub const CallFrame = struct {
    function: Bytecode.FunctionIndex,
    evidence: Bytecode.EvidenceIndex,
    block: BlockStack.Ptr,
    stack: StackRef,

    pub const StackRef = packed struct {
        base: DataStack.Ptr,
        origin: DataStack.Ptr,
    };
};


pub fn init(context: *Context, program: *Bytecode.Program) !*Fiber {
    const ptr = try context.allocator.create(Fiber);
    errdefer context.allocator.destroy(ptr);

    const stack = try StackSet.init(context.allocator);
    errdefer stack.deinit(context.allocator);

    const evidence = try context.allocator.alloc(Evidence, EVIDENCE_VECTOR_SIZE);
    errdefer context.allocator.free(evidence);

    ptr.* = Fiber {
        .program = program,
        .context = context,
        .stack = stack,
        .evidence = evidence,
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
