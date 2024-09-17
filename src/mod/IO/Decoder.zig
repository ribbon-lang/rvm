const std = @import("std");

const Config = @import("Config");
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

pub fn decodeByte(self: *const Decoder) Error!u8 {
    return self.decodeByteInline();
}

pub fn decodeAll(self: *const Decoder, count: usize) Error![]const u8 {
    return self.decodeAllInline(count);
}

pub fn decodeRaw(self: *const Decoder, comptime T: type) Error!T {
    return self.decodeRawInline(T);
}

pub fn pad(self: *const Decoder, alignment: usize) Error!void {
    return self.padInline(alignment);
}

pub fn decode(self: *const Decoder, comptime T: type) Error!T {
    return self.decodeInline(T);
}

pub fn decodeUnchecked(self: *const Decoder, comptime T: type) T {
    return self.decodeInlineUnchecked(T);
}

pub inline fn decodeByteInline(self: *const Decoder) Error!u8 {
    if (self.isEof()) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    const value = self.memory[self.ip()];
    self.offset.* += 1;
    return value;
}

pub inline fn decodeAllInline(self: *const Decoder, count: usize) Error![]const u8 {
    if (!self.inbounds(count)) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    return self.decodeAllInlineUnchecked(count);
}

pub inline fn decodeAllInlineUnchecked(self: *const Decoder, count: usize) []const u8 {
    const start = self.ip();
    self.offset.* += @truncate(count);
    return self.memory[start..self.ip()];
}

pub inline fn decodeRawInline(self: *const Decoder, comptime T: type) Error!T {
    const bytes = try self.decodeAllInline(@sizeOf(T));
    var out: T = undefined;
    @memcpy(@as([*]u8, @ptrCast(&out)), bytes);
    return out;
}

pub inline fn decodeRawInlineUnchecked(self: *const Decoder, comptime T: type) T {
    const bytes = self.decodeAllInlineUnchecked(@sizeOf(T));
    var out: T = undefined;
    @memcpy(@as([*]u8, @ptrCast(&out)), bytes);
    return out;
}

pub inline fn padInline(self: *const Decoder, alignment: usize) Error!void {
    const addr = @intFromPtr(self.memory.ptr) + self.ip();
    const padding = Support.alignmentDelta(addr, alignment);

    if (!self.inbounds(padding)) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    self.offset.* += @truncate(padding);
}

pub inline fn padInlineUnchecked(self: *const Decoder, alignment: usize) void {
    const addr = @intFromPtr(self.memory.ptr) + self.ip();
    const padding = Support.alignmentDelta(addr, alignment);

    self.offset.* += @truncate(padding);
}

pub inline fn decodeInline(self: *const Decoder, comptime T: type) Error!T {
    @setEvalBranchQuota(10_000);

    if (comptime T == void) return {};

    if (comptime std.meta.hasFn(T, "decode")) {
        return T.decode(self);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = try self.decodeRawInline(I);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.decodeStructure(T);
    }
}

pub inline fn decodeInlineUnchecked(self: *const Decoder, comptime T: type) T {
    @setEvalBranchQuota(10_000);

    if (comptime T == void) return {};

    if (comptime std.meta.hasFn(T, "decodeUnchecked")) {
        return T.decodeUnchecked(self);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = self.decodeRawInlineUnchecked(I);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.decodeStructureUnchecked(T);
    }
}

inline fn decodeStructure(self: *const Decoder, comptime T: type) Error!T {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var out: T = undefined;

            inline for (info.fields) |field| {
                @field(out, field.name) = try self.decodeInline(field.type);
            }

            return out;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = try self.decodeInline(TT);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    const fieldValue = try self.decodeInline(field.type);
                    return @unionInit(T, field.name, fieldValue);
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
                out[i] = try self.decodeInline(info.child);
            }

            const lastValue = try self.decodeInline(info.child);
            if (lastValue != sentinel) {
                @branchHint(.cold);
                return Error.BadEncoding;
            }

            @as([*]info.child, &out)[info.len] = sentinel;

            return out;
        } else {
            var out: [info.len]info.child = undefined;

            for (0..info.len) |i| {
                out[i] = try self.decodeInline(info.child);
            }

            return out;
        },

        .pointer => |info| switch(info.size) {
            .One => {
                try self.padInline(@alignOf(info.child));

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

                    try self.padInline(@alignOf(info.child));

                    const ptr: T = @alignCast(@ptrCast(&self.memory[self.ip()]));

                    while (true) {
                        const elemValue = try self.decodeInline(info.child);
                        if (elemValue == sentinel) break;
                    }

                    return ptr;
                } else {
                    @compileError("cannot decode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
                }
            },
            .Slice => {
                const len = try self.decodeInline(u8);

                try self.padInline(@alignOf(info.child));

                const ptr: [*]const info.child = @alignCast(@ptrCast(&self.memory[self.ip()]));

                const size = len * @as(usize, @sizeOf(info.child));

                if (!self.inbounds(size)) {
                    @branchHint(.cold);
                    return Error.BadEncoding;
                }

                const slice = ptr[0..len];

                self.offset.* += @truncate(size);

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    const elemValue = try self.decodeInline(info.child);
                    if (elemValue != sentinel) {
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

        .optional => |info| {
            const discrimValue = try self.decodeInline(bool);
            if (discrimValue) {
                return try self.decodeInline(info.child);
            } else {
                return null;
            }
        },

        else => {
            @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
        },
    }
}



inline fn decodeStructureUnchecked(self: *const Decoder, comptime T: type) T {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var out: T = undefined;

            inline for (info.fields) |field| {
                @field(out, field.name) = self.decodeInlineUnchecked(field.type);
            }

            return out;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = self.decodeInlineUnchecked(TT);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    const fieldValue = self.decodeInlineUnchecked(field.type);
                    return @unionInit(T, field.name, fieldValue);
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
                out[i] = self.decodeInlineUnchecked(info.child);
            }

            _ = self.decodeInlineUnchecked(info.child);

            @as([*]info.child, &out)[info.len] = sentinel;

            return out;
        } else {
            var out: [info.len]info.child = undefined;

            for (0..info.len) |i| {
                out[i] = self.decodeInlineUnchecked(info.child);
            }

            return out;
        },

        .pointer => |info| switch(info.size) {
            .One => {
                self.padInlineUnchecked(@alignOf(info.child));

                const ptr: T = @alignCast(@ptrCast(&self.memory[self.ip()]));

                self.offset.* += @sizeOf(info.child);

                return ptr;
            },
            .Many => {
                if (comptime info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                    self.padInlineUnchecked(@alignOf(info.child));

                    const ptr: T = @alignCast(@ptrCast(&self.memory[self.ip()]));

                    while (true) {
                        const elemValue = self.decodeInlineUnchecked(info.child);
                        if (elemValue == sentinel) break;
                    }

                    return ptr;
                } else {
                    @compileError("cannot decode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
                }
            },
            .Slice => {
                const len = self.decodeInlineUnchecked(u8);

                self.padInlineUnchecked(@alignOf(info.child));

                const ptr: [*]const info.child = @alignCast(@ptrCast(&self.memory[self.ip()]));

                const size = len * @as(usize, @sizeOf(info.child));
                const slice = ptr[0..len];

                self.offset.* += @truncate(size);

                if (info.sentinel != null) {
                    _ = self.decodeInlineUnchecked(info.child);
                }

                return slice;
            },
            else => {
                @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
            },
        },

        .optional => |info| {
            const discrimValue = self.decodeInlineUnchecked(bool);
            if (discrimValue) {
                return self.decodeInlineUnchecked(info.child);
            } else {
                return null;
            }
        },

        else => {
            @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
        },
    }
}
