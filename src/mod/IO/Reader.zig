pub const std = @import("std");

const IO = @import("root.zig");
const Endian = IO.Endian;


const Reader = @This();


inner: std.io.AnyReader,
endian: std.builtin.Endian = Endian.ENCODING,


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

pub fn readAll(self: Reader, values: []u8) !void {
    try self.inner.readAll(values);
}

pub fn readRaw(self: Reader, comptime T: type) !T {
    const size = @sizeOf(T);

    var value: T = undefined;
    const buffer = @as([*]u8, @ptrCast(&value))[0..size];

    try self.inner.readAll(buffer);

    return value;
}

/// `context` must be a struct or a pointer to a struct,
/// with at least one field: `tempAllocator: std.mem.Allocator`.
///
/// `context` is passed to the `read` method of custom types
pub fn read(self: Reader, comptime T: type, context: anytype) !T {
    if (T == void) return {};

    if (comptime std.meta.hasFn(T, "read")) {
        return T.read(self, context);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = try self.inner.readInt(I, self.endian);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.readStructure(T, context);
    }
}

fn readStructure(self: Reader, comptime T: type, context: anytype) !T {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var value: T = undefined;

            inline for (info.fields) |field| {
                @field(value, field.name) = try self.read(field.type, context);
            }

            return value;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = try self.read(TT, context);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    return @unionInit(T, field.name, try self.read(field.type, context));
                }
            }
        } else {
            @compileError(std.fmt.comptimePrint("cannot read union `{s}` without tag type", .{
                @typeName(T),
            }));
        },

        .array => |info| {
            var value: T = undefined;

            for (0..info.len) |i| {
                value[i] = try self.read(info.child, context);
            }

            return value;
        },

        .pointer => |info| switch (info.size) {
            .One => {
                const value = try context.tempAllocator.create(info.child);
                errdefer context.tempAllocator.free(value);

                value.* = try self.read(info.child, context);

                return value;
            },
            .Many => if (info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                var buffer = std.ArrayListUnmanaged(info.child) {};
                defer buffer.deinit(context.tempAllocator);

                while (true) {
                    const value = try self.read(info.child, context.tempAllocator);
                    if (value == sentinel) break;
                    try buffer.append(value);
                }

                return buffer.toOwnedSliceSentinel(context.tempAllocator, sentinel);
            } else {
                @compileError(std.fmt.comptimePrint("cannot read pointer `{s}` with kind Many, requires sentinel", .{
                    @typeName(T),
                }));
            },
            .Slice => {
                const len = try self.read(usize, context);

                const sentinel = if (info.sentinel) |sPtr| @as(*const info.child, @ptrCast(sPtr)).* else null;

                var buffer = try context.tempAllocator.alloc(info.child, if (sentinel != null) len + 1 else len);
                errdefer context.tempAllocator.free(buffer);

                for (0..len) |i| {
                    buffer[i] = try self.read(info.child, context);
                }

                if (sentinel) |s| {
                    if (try self.read(info.child, context) != s) {
                        return error.BadEncoding;
                    }

                    buffer[len] = s;
                }

                return buffer.ptr[0..len];
            },
            else => {
                @compileError(std.fmt.comptimePrint("cannot read pointer `{s}` with kind {s}", .{
                    @typeName(T),
                    info.size,
                }));
            }
        },

        .optional => |info| {
            if (try self.read(bool, context)) {
                return try self.read(info.child, context);
            } else {
                return null;
            }
        },

        else => {
            @compileError(std.fmt.comptimePrint("cannot read type `{s}` with type info: {}", .{
                @typeName(T),
                @typeInfo(T),
            }));
        }
    }

    unreachable;
}
