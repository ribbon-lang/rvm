const std = @import("std");

const Config = @import("Config");


pub fn Stack(comptime T: type, comptime A: type, comptime alignment: ?u29) type {
    return struct {
        memory: []T,
        ptr: Ptr,

        const Self = @This();

        pub const Ptr = A;

        pub const Error = error { Overflow, Underflow, OutOfBounds };

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const mem = try allocator.allocWithOptions(T, size, alignment, null);
            return Self{ .memory = mem, .ptr = 0 };
        }

        pub fn initPreallocated(memory: []T) Self {
            return Self{ .memory = memory, .ptr = 0 };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.memory);
        }

        pub fn top(self: *const Self) callconv(Config.INLINING_CALL_CONV) Error!T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            return self.memory[self.ptr - 1];
        }

        pub fn topPtr(self: *const Self) callconv(Config.INLINING_CALL_CONV) Error!*T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            return &self.memory[self.ptr - 1];
        }

        pub fn topPtrUnchecked(self: *const Self) callconv(Config.INLINING_CALL_CONV) *T {
            return &self.memory[self.ptr - 1];
        }

        pub fn topSlice(self: *const Self, n: Ptr) callconv(Config.INLINING_CALL_CONV) Error![]T {
            if (self.ptr < n) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            return self.memory[self.ptr - n..self.ptr];
        }

        pub fn get(self: *const Self, i: Ptr) callconv(Config.INLINING_CALL_CONV) Error!T {
            if (i >= self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return self.memory[i];
        }

        pub fn getPtr(self: *const Self, i: Ptr) callconv(Config.INLINING_CALL_CONV) Error!*T {
            if (i > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return &self.memory[i];
        }

        pub fn getPtrUnchecked(self: *const Self, i: Ptr) callconv(Config.INLINING_CALL_CONV) *T {
            return &self.memory[i];
        }

        pub fn getSlice(self: *const Self, i: Ptr, n: usize) callconv(Config.INLINING_CALL_CONV) Error![]T {
            if (i + n > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return self.memory[i..i + n];
        }

        pub fn checkSlice(self: *const Self, i: Ptr, n: usize) callconv(Config.INLINING_CALL_CONV) Error![*]T {
            if (i + n > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return @ptrCast(&self.memory[i]);
        }

        pub fn set(self: *Self, i: Ptr, value: T) callconv(Config.INLINING_CALL_CONV) Error!void {
            if (i >= self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            self.memory[i] = value;
        }

        pub fn setSlice(self: *Self, i: Ptr, slice: []const T) callconv(Config.INLINING_CALL_CONV) Error!void {
            if (i + slice.len > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            @memcpy(self.memory[i..i + slice.len], slice);
        }

        pub fn push(self: *Self, value: T) callconv(Config.INLINING_CALL_CONV) Error!void {
            if (self.ptr >= self.memory.len) {
                @branchHint(.cold);
                return Error.Overflow;
            }

            self.memory[self.ptr] = value;
            self.ptr += 1;
        }

        pub fn pushUnchecked(self: *Self, value: T) callconv(Config.INLINING_CALL_CONV) void {
            // if (self.ptr >= self.memory.len) {
            //     @branchHint(.cold);
            //     return Error.Overflow;
            // }

            self.memory[self.ptr] = value;
            self.ptr += 1;
        }

        pub fn pushSlice(self: *Self, slice: []const T) callconv(Config.INLINING_CALL_CONV) Error!void {
            if (self.ptr + slice.len > self.memory.len) {
                @branchHint(.cold);
                return Error.Overflow;
            }

            for (slice) |value| {
                self.memory[self.ptr] = value;
                self.ptr += 1;
            }
        }

        pub fn pushUninit(self: *Self, size: Ptr) callconv(Config.INLINING_CALL_CONV) Error!void {
            if (self.ptr + size > self.memory.len) {
                @branchHint(.cold);
                return Error.Overflow;
            }

            self.ptr += size;
        }

        pub fn pushUninitSlice(self: *Self, size: Ptr) callconv(Config.INLINING_CALL_CONV) Error![]T {
            if (self.ptr + size > self.memory.len) {
                @branchHint(.cold);
                return Error.Overflow;
            }

            const slice = self.memory[self.ptr..self.ptr + size];
            self.ptr += size;
            return slice;
        }

        pub fn pop(self: *Self) callconv(Config.INLINING_CALL_CONV) Error!T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            self.ptr -= 1;
            return self.memory[self.ptr];
        }

        pub fn popUnchecked(self: *Self) callconv(Config.INLINING_CALL_CONV) T {
            // if (self.ptr == 0) {
            //     @branchHint(.cold);
            //     return Error.Underflow;
            // }

            self.ptr -= 1;
            return self.memory[self.ptr];
        }

        pub fn popPtr(self: *Self) callconv(Config.INLINING_CALL_CONV) Error!*T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            self.ptr -= 1;
            return &self.memory[self.ptr];
        }

        pub fn popSlice(self: *Self, n: Ptr) callconv(Config.INLINING_CALL_CONV) Error![]T {
            if (self.ptr < n) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            self.ptr -= n;
            return self.memory[self.ptr..self.ptr + n];
        }
    };
}

test {
    var mem = [1]u8 {0} ** 4;
    var stack = Stack(u8, u8, 256).initPreallocated(&mem);

    try std.testing.expectError(error.Underflow, stack.pop());

    try stack.push(1);

    try std.testing.expectEqual(try stack.top(), 1);
    try std.testing.expectEqual(stack.ptr, 1);

    try std.testing.expectEqual(try stack.pop(), 1);

    try stack.pushSlice(&[_]u8 {1, 2, 3, 4});
    try std.testing.expectEqualSlices(u8, &[_]u8{3, 4}, try stack.topSlice(2));

    try std.testing.expectError(error.Overflow, stack.push(1));

    try std.testing.expectEqual(3, try stack.get(2));

    try stack.set(2, 5);

    try std.testing.expectEqualSlices(u8, &[_]u8{2, 5}, try stack.getSlice(1, 2));

    try stack.setSlice(2, &[_]u8{9, 6});

    try std.testing.expectError(error.OutOfBounds, stack.set(5, 0));
    try std.testing.expectError(error.OutOfBounds, stack.setSlice(3, &[_]u8{0, 0}));

    try std.testing.expectEqualSlices(u8, &[_]u8{1, 2, 9, 6}, try stack.popSlice(4));

    try std.testing.expectError(error.Underflow, stack.pop());
}
