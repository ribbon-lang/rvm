const std = @import("std");

const Config = @import("Config");
const Support = @import("Support");

const IO = @import("root.zig");
const Endian = IO.Endian;

const Encoder = @This();


memory: Memory = .{},

const Memory = std.ArrayListUnmanaged(u8);

pub const Error = std.mem.Allocator.Error;


pub fn deinit(self: *Encoder, allocator: std.mem.Allocator) void {
    return @call(.always_inline, Memory.deinit, .{&self.memory, allocator});
}

pub fn finalize(self: *Encoder, allocator: std.mem.Allocator) ![]u8 {
    return @call(.always_inline, Memory.toOwnedSlice, .{&self.memory, allocator});
}

pub fn encodeByte(self: *Encoder, allocator: std.mem.Allocator, value: u8) Error!void {
    return @call(.always_inline, encodeByteInline, .{self, allocator, value});
}

pub fn encodeAll(self: *Encoder, allocator: std.mem.Allocator, values: []const u8) Error!void {
    return @call(.always_inline, encodeAllInline, .{self, allocator, values});
}

pub fn encodeRaw(self: *Encoder, allocator: std.mem.Allocator, value: anytype) Error!void {
    return @call(.always_inline, encodeRawInline, .{self, allocator, value});
}

pub fn pad(self: *Encoder, allocator: std.mem.Allocator, alignment: usize) Error!void {
    return @call(.always_inline, padInline, .{self, allocator, alignment});
}

pub fn len(self: *const Encoder) callconv(Config.INLINING_CALL_CONV) usize {
    return self.memory.items.len;
}

pub fn encode(self: *Encoder, allocator: std.mem.Allocator, value: anytype) Error!void {
    const T = @TypeOf(value);

    return @call(.always_inline, encodeInline, .{self, T, allocator, value});
}


pub fn encodeByteInline(self: *Encoder, allocator: std.mem.Allocator, value: u8) callconv(Config.INLINING_CALL_CONV) Error!void {
    return @call(.always_inline, Memory.append, .{&self.memory, allocator, value});
}

pub fn encodeAllInline(self: *Encoder, allocator: std.mem.Allocator, values: []const u8) callconv(Config.INLINING_CALL_CONV) Error!void {
    return @call(.always_inline, Memory.appendSlice, .{&self.memory, allocator, values});
}

pub fn encodeRawInline(self: *Encoder, allocator: std.mem.Allocator, value: anytype) callconv(Config.INLINING_CALL_CONV) Error!void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);
    const buffer = @as([*]const u8, @ptrCast(&value))[0..size];
    return self.encodeAllInline(allocator, buffer);
}

pub fn padInline(self: *Encoder, allocator: std.mem.Allocator, alignment: usize) callconv(Config.INLINING_CALL_CONV) Error!void {
    const addr = @intFromPtr(self.memory.items.ptr) + self.memory.items.len;
    const padding = Support.alignmentDelta(addr, alignment);
    for (0..padding) |_| {
        try self.encodeByteInline(allocator, 0);
    }
}

pub fn encodeInline(self: *Encoder, comptime T: type, allocator: std.mem.Allocator, value: T) callconv(Config.INLINING_CALL_CONV) Error!void {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA); // lots of inlining going on here

    if (comptime T == void) return;

    if (comptime std.meta.hasFn(T, "encode")) {
        return @call(.always_inline, T.encode, .{value, allocator, self});
    }

    if (comptime Endian.IntType(T)) |_| {
        const int = Endian.bitCastTo(value);
        return self.encodeRawInline(allocator, int);
    } else {
        return self.encodeStructure(T, allocator, value);
    }
}

fn encodeStructure(self: *Encoder, comptime T: type, allocator: std.mem.Allocator, value: T) callconv(Config.INLINING_CALL_CONV) Error!void {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                const fieldValue = @field(value, field.name);
                try self.encodeInline(field.type, allocator, fieldValue);
            }
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = @as(TT, value);

            try self.encodeInline(TT, allocator, tag);

            inline for (info.fields) |field| {
                if (@field(TT, field.name) == tag) {
                    return self.encodeInline(field.type, allocator, @field(value, field.name));
                }
            }

            unreachable;
        } else {
            @compileError("cannot encode union `" ++ @typeName(T) ++ "` without tag or packed layout");
        },

        .array => |info| {
            for (0..value.len) |i| {
                try self.encodeInline(info.child, allocator, value[i]);
            }

            if (comptime info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                try self.encodeInline(info.child, allocator, sentinel);
            }
        },

        .pointer => |info| switch(info.size) {
            .One => {
                try self.padInline(allocator, @alignOf(info.child));
                return self.encodeInline(info.child, allocator, value.*);
            },
            .Many => if (comptime info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                var i: usize = 0;

                try self.padInline(allocator, @alignOf(info.child));

                while (true) {
                    const item = value[i];
                    try self.encodeInline(info.child, allocator, item);
                    if (item == sentinel) {
                        break;
                    }
                    i += 1;
                }
            } else {
                @compileError("cannot encode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
            },
            .Slice => {
                try self.encodeInline(usize, allocator, value.len);

                try self.padInline(allocator, @alignOf(info.child));

                for (value) |item| {
                    try self.encodeInline(info.child, allocator, item);
                }

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    try self.encodeInline(info.child, allocator, sentinel);
                }
            },
            else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
        },

        .optional => |info| {
            if (value) |v| {
                try self.encodeInline(bool, allocator, true);
                try self.encodeInline(info.child, allocator, v);
            } else {
                try self.encodeInline(bool, allocator, false);
            }
        },

        else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
    }
}
