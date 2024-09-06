const std = @import("std");

const Core = @import("root.zig");

pub const u16Le = Little(u16);
pub const u24Le = Little(u24);
pub const u32Le = Little(u32);
pub const u64Le = Little(u64);
pub const u128Le = Little(u128);
pub const u256Le = Little(u256);

pub const i16Le = Little(i16);
pub const i24Le = Little(i24);
pub const i32Le = Little(i32);
pub const i64Le = Little(i64);
pub const i128Le = Little(i128);
pub const i256Le = Little(i256);

pub const f32Le = Little(f32);
pub const f64Le = Little(f64);

pub const u16Be = Big(u16);
pub const u24Be = Big(u24);
pub const u32Be = Big(u32);
pub const u64Be = Big(u64);
pub const u128Be = Big(u128);
pub const u256Be = Big(u256);

pub const i16Be = Big(i16);
pub const i24Be = Big(i24);
pub const i32Be = Big(i32);
pub const i64Be = Big(i64);
pub const i128Be = Big(i128);
pub const i256Be = Big(i256);

pub const f32Be = Big(f32);
pub const f64Be = Big(f64);

pub fn ISA(comptime T: type) type {
    return Endian(Core.ISA.ENDIANNESS, T);
}

pub fn Little(comptime T: type) type {
    return Endian(.little, T);
}

pub fn Big(comptime T: type) type {
    return Endian(.big, T);
}

fn Endian(comptime endian: std.builtin.Endian, comptime T: type) type {
    const native_endian = @import("builtin").target.cpu.arch.endian();

    if (native_endian == endian) {
        return packed struct {
            _encoded_value: BackingType,

            const Self = @This();

            pub const BackingType = T;

            pub inline fn init(value: T) Self {
                return Self { ._encoded_value = value };
            }

            pub inline fn set(self: *Self, value: T) void {
                self._encoded_value = value;
            }

            pub inline fn get(self: Self) T {
                return self._encoded_value;
            }
        };
    } else {
        return packed struct {
            _encoded_value: BackingType,

            const Self = @This();

            pub const BackingType = GetBackingType(T)
                orelse @compileError("Type `" ++ @typeName(T) ++ "` is not supported for automatic endian conversion");

            pub inline fn init(value: T) Self {
                return Self { ._encoded_value = @byteSwap(@as(BackingType, @bitCast(value))) };
            }

            pub inline fn set(self: *Self, value: T) void {
                self._encoded_value = @byteSwap(@as(BackingType, @bitCast(value)));
            }

            pub inline fn get(self: Self) T {
                return @bitCast(@byteSwap(self._encoded_value));
            }
        };
    }
}

pub fn GetBackingType(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .int,
        .vector,
        => T,

        .float => |info| std.meta.Int(.unsigned, info.bits),

        .@"struct" => |info|
            if (info.backing_integer) |i| i
            else null,

        .@"enum" => |info| GetBackingType(info.tag_type),

        else => null,
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

        .@"enum" => |info| IntType(info.tag_type),

        else => null,
    };
}


test {
    {
        const i = 0x12345678;
        var x = Big(u32).init(i);
        const j = x.get();

        try std.testing.expectEqual(i, j);

        const k = 0x12345678 * 10;

        x.set(k);

        const l = x.get();

        try std.testing.expectEqual(k, l);
    }

    {
        const i = 10.10101;
        var x = Big(f32).init(i);
        const j = x.get();

        try std.testing.expectEqual(i, j);

        const k = 10.10101 * 10;

        x.set(k);

        const l = x.get();

        try std.testing.expectEqual(k, l);
    }

    {
        const i = 0x12345678;
        var x = Little(u32).init(i);
        const j = x.get();

        try std.testing.expectEqual(i, j);

        const k = 0x12345678 * 10;

        x.set(k);

        const l = x.get();

        try std.testing.expectEqual(k, l);
    }

    {
        const i = 10.10101;
        var x = Little(f32).init(i);
        const j = x.get();

        try std.testing.expectEqual(i, j);

        const k = 10.10101 * 10;

        x.set(k);

        const l = x.get();

        try std.testing.expectEqual(k, l);
    }

    {
        const Test = packed struct { foo: f32, bar: i128 };

        const i = Test { .foo = 1.0, .bar = 0x1234567890abcdef };
        var x = Big(Test).init(i);
        const j = x.get();

        try std.testing.expectEqual(i, j);

        const k = Test { .foo = 10.0, .bar = 0x1234567890abcdef * 10 };

        x.set(k);

        const l = x.get();

        try std.testing.expectEqual(k, l);
    }
}
