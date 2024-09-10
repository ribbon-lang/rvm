const std = @import("std");

const Support = @import("Support");

const Bytecode = @import("Bytecode");

const IO = @import("root.zig");
const Endian = IO.Endian;


const Decoder = @This();


memory: []const u8,
base: Bytecode.InstructionPointer,
offset: *Bytecode.InstructionPointerOffset,


pub const Error = error {
    OutOfBounds,
    BadEncoding,
};


pub inline fn isEof(self: *const Decoder) bool {
    return self.ip() >= self.memory.len;
}

pub inline fn inbounds(self: *const Decoder, offset: usize) bool {
    return self.relIp(offset) <= self.memory.len;
}

pub inline fn ip(self: *const Decoder) Bytecode.InstructionPointer {
    return self.base + self.offset.*;
}

pub inline fn relIp(self: *const Decoder, offset: usize) usize {
    return self.ip() + offset;
}

pub inline fn decodeByte(self: *const Decoder) Error!u8 {
    if (self.isEof()) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    const value = self.memory[self.ip()];
    self.offset.* += 1;
    return value;
}

pub inline fn decodeAll(self: *const Decoder, count: usize) Error![]const u8 {
    if (!self.inbounds(count)) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    const start = self.ip();
    self.offset.* += @truncate(count);
    return self.memory[start..self.ip()];
}

pub inline fn decodeRaw(self: *const Decoder, comptime T: type) Error!T {
    const bytes = try self.decodeAll(@sizeOf(T));
    var out: T = undefined;
    @memcpy(@as([*]u8, @ptrCast(&out)), bytes);
    return out;
}

pub inline fn pad(self: *const Decoder, alignment: usize) Error!void {
    const addr = @intFromPtr(self.memory.ptr) + self.ip();
    const padding = Support.alignmentDelta(addr, alignment);

    if (!self.inbounds(padding)) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    self.offset.* += @truncate(padding);
}

pub fn decode(self: *const Decoder, comptime T: type) Error!T {
    if (comptime T == void) return {};

    if (comptime std.meta.hasFn(T, "decode")) {
        return T.decode(self);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = try self.decodeRaw(I);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.decodeStructure(T);
    }
}

fn decodeStructure(self: *const Decoder, comptime T: type) Error!T {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var out: T = undefined;

            inline for (info.fields) |field| {
                @field(out, field.name) = try self.decode(field.type);
            }

            return out;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = try self.decode(TT);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    return @unionInit(T, field.name, try self.decode(field.type));
                }
            }

            unreachable;
        } else {
            @compileError("cannot decode union `" ++ @typeName(T) ++ "` without tag or packed layout");
        },

        .array => |info| if (comptime info.sentinel) |sPtr| {
            const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

            var out: [info.len:sentinel]info.child = undefined;

            for (0..info.len) |i| {
                out[i] = try self.decode();
            }

            if (try self.decode(info.child) != sentinel) {
                @branchHint(.cold);
                return Error.BadEncoding;
            }

            @as([*]info.child, &out)[info.len] = sentinel;

            return out;
        } else {
            var out: [info.len]info.child = undefined;

            for (0..info.len) |i| {
                out[i] = try self.decode();
            }

            return out;
        },

        .pointer => |info| switch(info.size) {
            .One => {
                try self.pad(@alignOf(info.child));

                if (!self.inbounds(@sizeOf(info.child))) {
                    @branchHint(.cold);
                    return Error.BadEncoding;
                }

                const ptr: T = @alignCast(@ptrCast(&self.memory[self.ip()]));

                self.offset.* += @sizeOf(info.child);

                return ptr;
            },
            .Many => {
                if (comptime info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                    try self.pad(@alignOf(info.child));

                    const ptr: T = @alignCast(@ptrCast(&self.memory[self.ip()]));

                    while (true) {
                        if (try self.decode(info.child) == sentinel) break;
                    }

                    return ptr;
                } else {
                    @compileError("cannot decode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
                }
            },
            .Slice => {
                const len = try self.decode(usize);

                try self.pad(@alignOf(info.child));

                const ptr: [*]const info.child = @alignCast(@ptrCast(&self.memory[self.ip()]));

                const size = len * @sizeOf(info.child);

                if (!self.inbounds(size)) {
                    @branchHint(.cold);
                    return Error.BadEncoding;
                }

                const slice = ptr[0..len];

                self.offset.* += @truncate(size);

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    if (try self.decode(info.child) != sentinel) {
                        @branchHint(.cold);
                        return Error.BadEncoding;
                    }
                }

                return slice;
            },
            else => {
                @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
            },
        },

        .optional => |info| if (try self.decode(bool)) {
            return try self.decode(info.child);
        } else {
            return null;
        },

        else => {
            @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
        },
    }

}
