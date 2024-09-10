const std = @import("std");

const IO = @import("root.zig");


pub const ENCODING: std.builtin.Endian = .little;


pub fn flip(value: std.builtin.Endian) std.builtin.Endian {
    return switch (value) {
        .little => .big,
        .big => .little,
    };
}


pub fn bitCastTo(value: anytype) IntType(@TypeOf(value)).? {
    return switch (@typeInfo(@TypeOf(value))) {
        .@"enum" => @bitCast(@intFromEnum(value)),

        else => @bitCast(value),
    };
}

pub fn bitCastFrom(comptime T: type, value: IntType(T).?) T {
    return switch (@typeInfo(T)) {
        .@"enum" => |info| @enumFromInt(@as(info.tag_type, @bitCast(value))),

        else => @bitCast(value),
    };
}

pub fn IntType(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .int => T,
        .vector => std.meta.Int(.unsigned, @sizeOf(T) * 8),

        .float => |info| std.meta.Int(.unsigned, info.bits),

        .@"struct" => |info|
            if (info.backing_integer) |i| i
            else null,

        .@"union" => |info|
            if (info.layout == .@"packed") std.meta.Int(@bitSizeOf(T))
            else null,

        .@"enum" => |info| IntType(info.tag_type),

        else => null,
    };
}
