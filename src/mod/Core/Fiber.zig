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

const Core = @import("root.zig");
const Context = Core.Context;
const Stack = Core.Stack;
const Bytecode = Core.Bytecode;

const Fiber = @This();


context: *Context,
data_stack: DataStack,
call_stack: CallStack,
block_stack: BlockStack,
evidence_vector: []Evidence,
diagnostic: ?*?Diagnostic,


pub const DATA_STACK_SIZE: usize = (1024 * 1024 * 8)
    // take a little bit off to account for the other stacks,
    // making a nice even number of mb for the total fiber size  (16mb, currently)
    - @rem(CALL_STACK_SIZE * @sizeOf(CallFrame)
         + BLOCK_STACK_SIZE * @sizeOf(BlockFrame)
         + EVIDENCE_VECTOR_SIZE * @sizeOf(Evidence)
         , 1024 * 1024);
pub const CALL_STACK_SIZE: usize = 4096;
pub const BLOCK_STACK_SIZE: usize = CALL_STACK_SIZE * 256;
pub const EVIDENCE_VECTOR_SIZE: usize = 1024;

comptime {
    std.testing.expect(DATA_STACK_SIZE >= 7 * 1024 * 1024) catch unreachable;
    std.testing.expectEqual(
        16 * 1024 * 1024,
        DATA_STACK_SIZE
         + CALL_STACK_SIZE * @sizeOf(CallFrame)
         + BLOCK_STACK_SIZE * @sizeOf(BlockFrame)
         + EVIDENCE_VECTOR_SIZE * @sizeOf(Evidence)
    ) catch unreachable;
}

pub const EvidenceIndex = u16;
pub const DataStack = Stack(u8, u24);
pub const CallStack = Stack(CallFrame, u16);
pub const BlockStack = Stack(BlockFrame, u16);

pub const Trap = error {
    Unreachable,
    Underflow,
    Overflow,
    OutOfBounds,
};

pub const Error = std.mem.Allocator.Error;

pub const Diagnostic = struct {
    message: []const u8,
    location: ?Bytecode.Location,

    pub const FailedToAllocateMessage: []const u8 = "failed to allocate memory for error message";

    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        if (self.message.ptr != FailedToAllocateMessage.ptr) {
            allocator.free(self.message);
        }
    }
};

pub const Evidence = struct {
    handler: Bytecode.HandlerIndex,
    call: CallStack.Ptr,
    block: BlockStack.Ptr,
};

pub const BlockFrame = struct {
    index: Bytecode.BlockIndex,
    ip_offset: Bytecode.InstructionPointerOffset,
    out: Bytecode.Argument,
};

pub const CallFrame = struct {
    function: Bytecode.FunctionIndex,
    evidence: ?EvidenceIndex,
    stack_base: DataStack.Ptr,
    stack_origin: DataStack.Ptr,
};


pub fn init(context: *Context) !*Fiber {
    const ptr = try context.allocator.create(Fiber);
    errdefer context.allocator.destroy(ptr);

    const data_stack = try DataStack.init(context.allocator, DATA_STACK_SIZE);
    errdefer data_stack.deinit(context.allocator);

    const call_stack = try CallStack.init(context.allocator, CALL_STACK_SIZE);
    errdefer call_stack.deinit(context.allocator);

    const block_stack = try BlockStack.init(context.allocator, BLOCK_STACK_SIZE);
    errdefer block_stack.deinit(context.allocator);

    const evidence_stack = try context.allocator.alloc(EVIDENCE_VECTOR_SIZE);
    errdefer context.allocator.free(evidence_stack);

    ptr.* = Fiber {
        .context = context,
        .data_stack = data_stack,
        .call_stack = call_stack,
        .block_stack = block_stack,
        .evidence_stack = evidence_stack,
        .trap = null,
    };

    return ptr;
}

pub fn deinit(self: *Fiber) void {
    self.data_stack.deinit(self.context.allocator);
    self.call_stack.deinit(self.context.allocator);
    self.block_stack.deinit(self.context.allocator);
    self.context.allocator.free(self.evidence_stack);
    self.context.allocator.destroy(self);
}

pub fn getLocation(self: *const Fiber) Trap!Bytecode.Location {
    const call = try self.call_stack.top();
    const block = try self.block_stack.top();

    return .{
        .function = call.function,
        .block = block.index,
        .offset = block.ip_offset,
    };
}

pub fn abort(self: *const Fiber, trap: Trap, comptime fmt: []const u8, args: anytype) Trap!void {
    @branchHint(.cold);

    if (self.trap) |ptr| {
        const message =
            if (std.fmt.allocPrint(self.context.allocator, fmt, args)) |msg| msg
            else Diagnostic.FailedToAllocateMessage;

        ptr.* = Diagnostic {
            .message = message,
            .location = self.getLocation() catch null,
        };
    }

    return trap;
}
