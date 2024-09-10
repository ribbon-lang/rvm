const std = @import("std");

const IO = @import("./root.zig");
const Endian = IO.Endian;


const Writer = @This();


inner: std.io.AnyWriter,
endian: std.builtin.Endian = Endian.ENCODING,


pub fn init(inner: std.io.AnyWriter) Writer {
    return .{
        .inner = inner,
    };
}

pub fn initEndian(inner: std.io.AnyWriter, endian: std.builtin.Endian) Writer {
    return .{
        .inner = inner,
        .endian = endian,
    };
}

pub fn writeByte(self: Writer, value: u8) !void {
    try self.inner.writeByte(value);
}

pub fn writeAll(self: Writer, values: []u8) !void {
    try self.inner.writeAll(values);
}

pub fn writeRaw(self: Writer, value: anytype) !void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);

    const buffer = @as([*]u8, @ptrCast(&value))[0..size];

    try self.inner.writeAll(buffer);
}

pub fn write(self: Writer, value: anytype) !void {
    const T = @TypeOf(value);

    if (T == void) return;

    if (comptime std.meta.hasFn(T, "write")) {
        return T.write(value, self);
    }

    if (comptime Endian.IntType(T)) |I| {
        return self.inner.writeInt(I, Endian.bitCastTo(value), self.endian);
    } else {
        return self.writeStructure(value);
    }
}

fn writeStructure(self: Writer, value: anytype) !void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                const fieldValue = @field(value, field.name);
                try self.write(fieldValue);
            }

            return;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = @as(TT, value);

            try self.write(tag);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    const fieldValue = @field(value, field.name);
                    try self.write(fieldValue);
                    return;
                }
            }

            unreachable;
        } else {
            @compileError(std.fmt.comptimePrint("cannot read union `{s}` without tag or packed layout", .{
                @typeName(T),
            }));
        },

        .array => |info| {
            for (0..info.len) |i| {
                const element = @field(value, i);
                try self.write(element);
            }

            return;
        },

        .pointer => |info| switch (info.size) {
            .One => {
                return self.write(value.*);
            },
            .Many => if (info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                for (value) |element| {
                    try self.write(element);
                }

                return self.write(sentinel);
            } else
                @compileError(std.fmt.comptimePrint("cannot write pointer `{s}` with kind Many, requires sentinel", .{
                    @typeName(T),
                })),
            .Slice => {
                const len = value.len;
                try self.write(len);

                for (value) |element| {
                    try self.write(element);
                }

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    try self.write(sentinel);
                }

                return;
            },
            else => {
                @compileError(std.fmt.comptimePrint("cannot write pointer `{s}` with kind {s}", .{
                    @typeName(T),
                    info.size,
                }));
            }
        },

        .optional => if (value) |v| {
            try self.write(true);
            try self.write(v);
        } else {
            try self.write(false);
        },

        else => {
            @compileError(std.fmt.comptimePrint("cannot write type `{s}` with type info: {}", .{
                @typeName(T),
                @typeInfo(T),
            }));
        }
    }

    unreachable;
}
