const std = @import("std");

const Support = @import("Support");

const Encoder = @This();


memory: std.ArrayListUnmanaged(u8) = .{},


pub const Error = std.mem.Allocator.Error;


pub fn deinit(self: *Encoder, allocator: std.mem.Allocator) void {
    self.memory.deinit(allocator);
}

pub fn finalize(self: *Encoder, allocator: std.mem.Allocator) ![]const u8 {
    return self.memory.toOwnedSlice(allocator);
}


pub fn encodeByte(self: *Encoder, allocator: std.mem.Allocator, value: u8) Error!void {
    return self.memory.append(allocator, value);
}

pub fn encodeAll(self: *Encoder, allocator: std.mem.Allocator, values: []u8) Error!void {
    return self.memory.appendSlice(allocator, values);
}

pub fn encodeRaw(self: *Encoder, allocator: std.mem.Allocator, value: anytype) Error!void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);
    const buffer = @as([*]const u8, @ptrCast(&value))[0..size];
    return self.memory.appendSlice(allocator, buffer);
}

pub fn pad(self: *Encoder, allocator: std.mem.Allocator, alignment: usize) Error!void {
    const addr = @intFromPtr(self.memory.items.ptr) + self.memory.items.len;
    const padding = Support.alignmentDelta(addr, alignment);
    for (0..padding) |_| {
        try self.encodeByte(allocator, 0);
    }
}

pub fn len(self: *const Encoder) usize {
    return self.memory.items.len;
}

pub fn encode(self: *Encoder, allocator: std.mem.Allocator, value: anytype) Error!void {
    const T = @TypeOf(value);

    if (comptime std.meta.hasFn(T, "encode")) {
        return T.encode(self, allocator, value);
    }

    switch (@typeInfo(T)) {
        .void => return,

        .bool, .int, .float, .vector, .@"enum"
        => return self.encodeRaw(allocator, value),

        .@"struct" => |info| {
            if (info.backing_integer) |I| {
                return self.encode(allocator, @as(I, @bitCast(value)));
            }

            inline for (comptime std.meta.fieldNames(T)) |fieldName| {
                const field = @field(value, fieldName);
                try self.encode(allocator, field);
            }
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = @as(TT, value);

            try self.encode(allocator, tag);

            inline for (info.fields) |field| {
                if (@field(TT, field.name) == tag) {
                    return self.encode(allocator, @field(value, field.name));
                }
            }

            unreachable;
        } else {
            @compileError("cannot encode union `" ++ @typeName(T) ++ "` without tag");
        },

        .array => |info| {
            for (0..value.len) |i| {
                try self.encode(allocator, value[i]);
            }

            if (comptime info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                try self.encode(allocator, sentinel);
            }
        },

        .pointer => |info| switch(info.size) {
            .One => {
                try self.pad(allocator, @alignOf(info.child));
                return self.encode(allocator, value.*);
            },
            .Many => if (comptime info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                var i: usize = 0;

                try self.pad(allocator, @alignOf(info.child));

                while (true) {
                    const item = value[i];
                    try self.encode(allocator, item);
                    if (item == sentinel) {
                        break;
                    }
                    i += 1;
                }
            } else {
                @compileError("cannot encode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
            },
            .Slice => {
                try self.encode(allocator, value.len);

                try self.pad(allocator, @alignOf(info.child));

                for (value) |item| {
                    try self.encode(allocator, item);
                }

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    try self.encode(allocator, sentinel);
                }
            },
            else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
        },

        .optional => {
            if (value) |v| {
                try self.encode(allocator, true);
                try self.encode(allocator, v);
            } else {
                try self.encode(allocator, false);
            }
        },

        else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
    }
}

