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

const Core = @import("root.zig");
const Context = Core.Context;
const Stack = Core.Stack;


const Fiber = @This();


context: *Context,
stack: StackSet,
evidence: []Evidence,
diagnostic: ?*?Diagnostic,


pub const StackSet = struct {
    data: DataStack,
    call: CallStack,
    block: BlockStack,

    pub fn init(allocator: std.mem.Allocator) !StackSet {
        const data_stack = try DataStack.init(allocator, DATA_STACK_SIZE);
        errdefer data_stack.deinit(allocator);

        const call_stack = try CallStack.init(allocator, CALL_STACK_SIZE);
        errdefer call_stack.deinit(allocator);

        const block_stack = try BlockStack.init(allocator, BLOCK_STACK_SIZE);
        errdefer block_stack.deinit(allocator);

        return StackSet {
            .data_stack = data_stack,
            .call_stack = call_stack,
            .block_stack = block_stack,
        };
    }

    pub fn deinit(self: StackSet, allocator: std.mem.Allocator) void {
        self.data_stack.deinit(allocator);
        self.call_stack.deinit(allocator);
        self.block_stack.deinit(allocator);
    }
};

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
    out: Bytecode.Operand,
};

pub const CallFrame = struct {
    function: Bytecode.FunctionIndex,
    evidence: ?Bytecode.EvidenceIndex,
    stack: StackRef,

    pub const StackRef = struct {
        base: DataStack.Ptr,
        origin: DataStack.Ptr,
    };
};


pub fn init(context: *Context) !*Fiber {
    const ptr = try context.allocator.create(Fiber);
    errdefer context.allocator.destroy(ptr);

    const stack = try StackSet.init(context.allocator);
    errdefer stack.deinit(context.allocator);

    const evidence = try context.allocator.alloc(EVIDENCE_VECTOR_SIZE);
    errdefer context.allocator.free(evidence);

    ptr.* = Fiber {
        .context = context,
        .stack = stack,
        .evidence = evidence,
        .trap = null,
    };

    return ptr;
}

pub fn deinit(self: *Fiber) void {
    self.stack.deinit(self.context.allocator);
    self.context.allocator.free(self.evidence);
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
