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

pub inline fn decodeByte(self: *const Decoder) Error!u8 {
    return @call(.never_inline, decodeByteImpl, .{self, });
}

pub inline fn decodeAll(self: *const Decoder, count: usize) Error![]const u8 {
    return @call(.never_inline, decodeAllImpl, .{self, count});
}

pub inline fn decodeRaw(self: *const Decoder, comptime T: type) Error!T {
    return @call(.never_inline, decodeRawImpl, .{self, T});
}

pub inline fn pad(self: *const Decoder, alignment: usize) Error!void {
    return @call(.never_inline, padImpl, .{self, alignment});
}

pub inline fn decode(self: *const Decoder, comptime T: type) Error!T {
    return @call(.never_inline, decodeImpl, .{self, T});
}

pub inline fn decodeRawUnchecked(self: *const Decoder, comptime T: type) T {
    return @call(.never_inline, decodeRawUncheckedImpl, .{self, T});
}

pub inline fn decodeUnchecked(self: *const Decoder, comptime T: type) T {
    return @call(.never_inline, decodeUncheckedImpl, .{self, T});
}

pub inline fn grabSliceUnchecked(self: *const Decoder, comptime T: type, size: usize) []const align(@alignOf(IO.SizeT)) T {
    return @call(.never_inline, grabSliceUncheckedImpl, .{self, T, size});
}


pub fn decodeByteImpl(self: *const Decoder) Error!u8 {
    if (self.isEof()) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    const value = self.memory[self.ip()];
    self.offset.* += 1;
    return value;
}

pub fn decodeAllImpl(self: *const Decoder, count: usize) Error![]const u8 {
    if (!self.inbounds(count)) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    return @call(.always_inline, decodeAllUncheckedImpl, .{self, count});
}

pub fn decodeAllUncheckedImpl(self: *const Decoder, count: usize) []const u8 {
    const start = self.ip();
    self.offset.* += @truncate(count);
    return self.memory[start..self.ip()];
}

pub fn decodeRawImpl(self: *const Decoder, comptime T: type) Error!T {
    if (!self.inbounds(@sizeOf(T))) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    return @call(.always_inline, decodeRawUncheckedImpl, .{self, T});
}

pub fn decodeRawUncheckedImpl(self: *const Decoder, comptime T: type) T {
    const start = self.ip();

    self.offset.* += @truncate(@sizeOf(T));

    return @as(*const align(@alignOf(IO.SizeT)) T, @alignCast(@ptrCast(&self.memory[start]))).*;
}

pub fn grabSliceUncheckedImpl(self: *const Decoder, comptime T: type, size: usize) []const align(@alignOf(IO.SizeT)) T {
    const start = self.ip();

    self.offset.* += @truncate(@sizeOf(T) * size);

    return @as([*]const align(@alignOf(IO.SizeT)) T, @alignCast(@ptrCast(&self.memory[start])))[0..size];
}

pub fn padImpl(self: *const Decoder, alignment: usize) Error!void {
    const addr = @intFromPtr(self.memory.ptr) + self.ip();
    const padding = Support.alignmentDelta(addr, alignment);

    if (!self.inbounds(padding)) {
        @branchHint(.cold);
        return Error.OutOfBounds;
    }

    self.offset.* += @truncate(padding);
}

pub fn padUncheckedImpl(self: *const Decoder, alignment: usize) void {
    const addr = @intFromPtr(self.memory.ptr) + self.ip();
    const padding = Support.alignmentDelta(addr, alignment);

    self.offset.* += @truncate(padding);
}

pub fn decodeImpl(self: *const Decoder, comptime T: type) Error!T {
    @setEvalBranchQuota(25_000);

    if (comptime T == void) return {};

    if (comptime std.meta.hasFn(T, "decode")) {
        return T.decode(self);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = try self.decodeRawImpl(I);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.decodeStructure(T);
    }
}

pub fn decodeUncheckedImpl(self: *const Decoder, comptime T: type) T {
    @setEvalBranchQuota(25_000);

    if (comptime T == void) return {};

    if (comptime std.meta.hasFn(T, "decodeUnchecked")) {
        return T.decodeUnchecked(self);
    }

    if (comptime Endian.IntType(T)) |I| {
        const int = self.decodeRawUncheckedImpl(I);
        return Endian.bitCastFrom(T, int);
    } else {
        return self.decodeStructureUnchecked(T);
    }
}

fn decodeStructure(self: *const Decoder, comptime T: type) Error!T {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var out: T = undefined;

            inline for (info.fields) |field| {
                @field(out, field.name) = try self.decodeImpl(field.type);
            }

            return out;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = try self.decodeImpl(TT);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    const fieldValue = try self.decodeImpl(field.type);
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

            inline for (0..info.len) |i| {
                out[i] = try self.decodeImpl(info.child);
            }

            const lastValue = try self.decodeImpl(info.child);
            if (lastValue != sentinel) {
                @branchHint(.cold);
                return Error.BadEncoding;
            }

            @as([*]info.child, &out)[info.len] = sentinel;

            return out;
        } else {
            var out: [info.len]info.child = undefined;

            inline for (0..info.len) |i| {
                out[i] = try self.decodeImpl(info.child);
            }

            return out;
        },


        // FIXME: likely to be broken without padding
        .pointer => |info| switch(info.size) {
            .One => {
                // try self.padInline(@alignOf(info.child));

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

                    // try self.padInline(@alignOf(info.child));

                    const ptr: T = @alignCast(@ptrCast(&self.memory[self.ip()]));

                    while (true) {
                        const elemValue = try self.decodeImpl(info.child);
                        if (elemValue == sentinel) break;
                    }

                    return ptr;
                } else {
                    @compileError("cannot decode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
                }
            },
            .Slice => {
                const len = try self.decodeImpl(IO.SizeT);

                // try self.padInline(@alignOf(info.child));

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
                    const elemValue = try self.decodeImpl(info.child);
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
            const discrimValue = try self.decodeImpl(bool);
            if (discrimValue) {
                return try self.decodeImpl(info.child);
            } else {
                return null;
            }
        },

        else => {
            @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
        },
    }
}



fn decodeStructureUnchecked(self: *const Decoder, comptime T: type) T {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            var out: T = undefined;

            inline for (info.fields) |field| {
                @field(out, field.name) = self.decodeUncheckedImpl(field.type);
            }

            return out;
        },

        .@"union" => |info| if (info.tag_type) |TT| {
            const tag = self.decodeUncheckedImpl(TT);

            inline for (info.fields) |field| {
                if (tag == @field(TT, field.name)) {
                    const fieldValue = self.decodeUncheckedImpl(field.type);
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

            inline for (0..info.len) |i| {
                out[i] = self.decodeUncheckedImpl(info.child);
            }

            _ = self.decodeUncheckedImpl(info.child);

            @as([*]info.child, &out)[info.len] = sentinel;

            return out;
        } else {
            var out: [info.len]info.child = undefined;

            inline for (0..info.len) |i| {
                out[i] = self.decodeUncheckedImpl(info.child);
            }

            return out;
        },

        .pointer => @compileError("cannot decode type `" ++ @typeName(T) ++ "`; decode pointers individually"),

        .optional => |info| {
            const discrimValue = self.decodeUncheckedImpl(bool);
            if (discrimValue) {
                return self.decodeUncheckedImpl(info.child);
            } else {
                return null;
            }
        },

        else => {
            @compileError("cannot decode type `" ++ @typeName(T) ++ "`");
        },
    }
}
