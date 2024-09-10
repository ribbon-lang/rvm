const std = @import("std");


pub fn Stack(comptime T: type, comptime A: type) type {
    return struct {
        mem: []T,
        ptr: Ptr,

        const Self = @This();

        pub const Ptr = A;

        pub const Error = error { Overflow, Underflow, OutOfBounds };

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const mem = try allocator.alloc(T, size);
            return Self{ .mem = mem, .ptr = 0 };
        }

        pub fn initPreallocated(mem: []T) Self {
            return Self{ .mem = mem, .ptr = 0 };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.mem);
        }

        pub inline fn top(self: *const Self) Error!T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            return self.mem[self.ptr - 1];
        }

        pub inline fn topPtr(self: *const Self) Error!*T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            return &self.mem[self.ptr - 1];
        }

        pub inline fn topSlice(self: *const Self, n: Ptr) Error![]T {
            if (self.ptr < n) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            return self.mem[self.ptr - n..self.ptr];
        }

        pub inline fn get(self: *const Self, i: Ptr) Error!T {
            if (i >= self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return self.mem[i];
        }

        pub inline fn getPtr(self: *const Self, i: Ptr) Error!*T {
            if (i > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return @ptrCast(self.mem[i..self.ptr].ptr);
        }

        pub inline fn getSlice(self: *const Self, i: Ptr, n: usize) Error![]T {
            if (i + n > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            return self.mem[i..i + n];
        }

        pub inline fn set(self: *Self, i: Ptr, value: T) Error!void {
            if (i >= self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            self.mem[i] = value;
        }

        pub inline fn setSlice(self: *Self, i: Ptr, slice: []const T) Error!void {
            if (i + slice.len > self.ptr) {
                @branchHint(.cold);
                return Error.OutOfBounds;
            }

            for (slice, i..) |value, j| {
                self.mem[j] = value;
            }
        }

        pub inline fn push(self: *Self, value: T) Error!void {
            if (self.ptr >= self.mem.len) {
                @branchHint(.cold);
                return Error.Overflow;
            }

            self.mem[self.ptr] = value;
            self.ptr += 1;
        }

        pub inline fn pushSlice(self: *Self, slice: []const T) Error!void {
            if (self.ptr + slice.len > self.mem.len) {
                @branchHint(.cold);
                return Error.Overflow;
            }

            for (slice) |value| {
                self.mem[self.ptr] = value;
                self.ptr += 1;
            }
        }

        pub inline fn pop(self: *Self) Error!T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            self.ptr -= 1;
            return self.mem[self.ptr];
        }

        pub inline fn popPtr(self: *Self) Error!*T {
            if (self.ptr == 0) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            self.ptr -= 1;
            return &self.mem[self.ptr];
        }

        pub inline fn popSlice(self: *Self, n: Ptr) Error![]T {
            if (self.ptr < n) {
                @branchHint(.cold);
                return Error.Underflow;
            }

            self.ptr -= n;
            return self.mem[self.ptr..self.ptr + n];
        }
    };
}

test {
    var mem = [1]u8 {0} ** 4;
    var stack = Stack(u8, u8).initPreallocated(&mem);

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
