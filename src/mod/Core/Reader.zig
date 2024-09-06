pub const std = @import("std");

const Core = @import("root.zig");
const ISA = Core.ISA;
const Endian = Core.Endian;

const Reader = @This();

inner: std.io.AnyReader,
endian: std.builtin.Endian = ISA.ENDIANNESS,

pub fn init(inner: std.io.AnyReader) Reader {
    return .{
        .inner = inner,
    };
}

pub fn initEndian(inner: std.io.AnyReader, endian: std.builtin.Endian) Reader {
    return .{
        .inner = inner,
        .endian = endian,
    };
}

pub fn readByte(self: Reader, value: u8) !void {
    try self.inner.readByte(value);
}

pub fn readBytes(self: Reader, values: []u8) !void {
    try self.inner.readAll(values);
}

pub fn readRaw(self: Reader, comptime T: type) !T {
    const size = @sizeOf(T);

    var value: T = undefined;
    const buffer = @as([*]u8, @ptrCast(&value))[0..size];

    try self.inner.readAll(buffer);

    return value;
}

pub fn read(self: Reader, comptime T: type, allocator: std.mem.Allocator) !T {
    if (T == void) return {};

    if (comptime std.meta.hasFn(T, "read")) {
        return T.read(self, allocator);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = try self.inner.readInt(I, self.endian);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.readStructure(T, allocator);
    }
}

fn readStructure(self: Reader, comptime T: type, allocator: std.mem.Allocator) !T {
    switch (@typeInfo(T)) {
        // handled by read:
        // .void

        // handled by Endian.IntType:
        // .int => T,
        // .vector => std.meta.Int(.unsigned, @sizeOf(T) * 8),

        // .float => |info| std.meta.Int(.unsigned, info.bits),

        // .@"struct" => |info|
        //     if (info.backing_integer) |i| i
        //     else null,

        // .@"enum" => |info| IntType(info.tag_type),

        .@"struct" => |info| {
            var value: T = undefined;

            inline for (info.fields) |field| {
                @field(value, field.name) = try self.read(field.type, allocator);
            }

            return value;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = try self.read(TT, allocator);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    return @unionInit(T, field.name, try self.read(field.type, allocator));
                }
            }
        } else
            @compileError(std.fmt.comptimePrint("cannot read union `{s}` without tag type", .{
                @typeName(T),
            })),

        .array => |info| {
            var value: T = undefined;

            for (0..info.len) |i| {
                value[i] = try self.read(info.child, allocator);
            }

            return value;
        },

        .pointer => |info| switch (info.size) {
            .One => {
                const value = try allocator.create(info.child);
                errdefer allocator.free(value);

                value.* = try self.read(info.child, allocator);

                return value;
            },
            .Many => if (info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                var buffer = std.ArrayListUnmanaged(info.child) {};
                defer buffer.deinit(allocator);

                while (true) {
                    const value = try self.read(info.child, allocator);
                    if (value == sentinel) break;
                    try buffer.append(value);
                }

                return buffer.toOwnedSliceSentinel(allocator, sentinel);
            } else
                @compileError(std.fmt.comptimePrint("cannot read pointer `{s}` with kind Many, requires sentinel", .{
                    @typeName(T),
                })),
            .Slice => {
                const len = try self.read(usize, allocator);

                const sentinel = if (info.sentinel) |sPtr| @as(*const info.child, @ptrCast(sPtr)).* else null;

                var buffer = try allocator.alloc(info.child, if (sentinel != null) len + 1 else len);
                errdefer allocator.free(buffer);

                for (0..len) |i| {
                    buffer[i] = try self.read(info.child, allocator);
                }

                if (sentinel) |s| {
                    if (try self.read(info.child, allocator) != s) {
                        return error.BadEncoding;
                    }

                    buffer[len] = s;
                }

                return buffer.ptr[0..len];
            },
            else =>
                @compileError(std.fmt.comptimePrint("cannot read pointer `{s}` with kind {s}", .{
                    @typeName(T),
                    info.size,
                }))
        },

        else =>
            @compileError(std.fmt.comptimePrint("cannot read type `{s}` with type info: {}", .{
                @typeName(T),
                @typeInfo(T),
            }))
    }

    unreachable;
}
