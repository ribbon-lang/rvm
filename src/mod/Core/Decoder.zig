const std = @import("std");

const Support = @import("Support");

const Core = @import("root.zig");
const Bytecode = Core.Bytecode;
const ISA = Core.ISA;

const Decoder = @This();


instructions: []const u8,
ip: *Bytecode.InstructionPointer,

pub const Error = error {
    OutOfBounds,
    BadEncoding,
};


pub fn init(instructions: []const u8, ip: *Bytecode.InstructionPointer) Decoder {
    return .{
        .instructions = instructions,
        .ip = ip,
    };
}


pub fn decodeByte(self: *Decoder) Error!u8 {
    if (self.ip.* >= self.instructions.len) {
        return Error.OutOfBounds;
    }

    const value = self.instructions[self.ip.*];
    self.ip.* += 1;
    return value;
}

pub fn decodeBytes(self: *Decoder, count: usize) Error![]const u8 {
    if (self.ip.* + count > self.instructions.len) {
        return Error.OutOfBounds;
    }

    const start = self.ip.*;
    self.ip.* += @intCast(count);
    return self.instructions[start..self.ip.*];
}

pub fn decodeRaw(self: *Decoder, comptime T: type) Error!T {
    const bytes = try self.decodeBytes(@sizeOf(T));
    var out: T = undefined;
    @memcpy(@as([*]u8, @ptrCast(&out)), bytes);
    return out;
}

pub fn pad(self: *Decoder, alignment: usize) Error!void {
    const addr = @intFromPtr(self.instructions.ptr) + self.ip.*;
    const padding = Support.alignmentDelta(addr, alignment);

    if (self.ip.* + padding > self.instructions.len) {
        return Error.OutOfBounds;
    }

    self.ip.* += @intCast(padding);
}

pub fn decode(self: *Decoder, comptime T: type) Error!T {
    if (comptime std.meta.hasFn(T, "decode")) {
        return T.decode(self);
    }

    switch (@typeInfo(T)) {
        .void => return {},

        .bool, .int, .float, .comptime_int, .comptime_float, .vector, .@"enum"
        => return self.decodeRaw(T),

        .@"struct" => |info| {
            if (info.backing_integer) |I| {
                return @bitCast(try self.decode(I));
            }

            var out: T = undefined;
            inline for (info.fields) |field| {
                @field(out, field.name) = try self.decode(field.type);
            }
            return out;
        },

        .@"union" => |info| {
            if (info.tag_type) |TT| {
                const tag = try self.decode(TT);

                inline for (info.fields) |field| {
                    if (tag == @field(TT, field.name)) {
                        return @unionInit(T, field.name, try self.decode(field.type));
                    }
                }
            } else {
                self.pad(@alignOf(T));
                return self.decodeRaw(T);
            }
        },

        .array => |info| {
            if (comptime info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                var out: [info.len:sentinel]info.child = undefined;

                for (0..info.len) |i| {
                    out[i] = try self.decode();
                }

                if (try self.decode(info.child) != sentinel) {
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
            }
        },

        .pointer => |info| switch(info.size) {
            .One => {
                try self.pad(@alignOf(info.child));
                if (self.ip.* + @sizeOf(info.child) > self.instructions.len) {
                    return Error.OutOfBounds;
                }
                const ptr: T = @alignCast(@ptrCast(&self.instructions[self.ip.*]));
                self.ip.* += @sizeOf(info.child);
                return ptr;
            },
            .Many => {
                if (comptime info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;

                    try self.pad(@alignOf(info.child));

                    const ptr: T = @alignCast(@ptrCast(&self.instructions[self.ip.*]));

                    while (true) {
                        const a = try self.decode(info.child);

                        if (a == sentinel) break;
                    }

                    return ptr;
                } else {
                    @compileError("cannot decode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
                }
            },
            .Slice => {
                const len = try self.decode(usize);

                try self.pad(@alignOf(info.child));

                const ptr: [*]const info.child = @alignCast(@ptrCast(&self.instructions[self.ip.*]));

                if (self.ip.* + len * @sizeOf(info.child) > self.instructions.len) {
                    return Error.OutOfBounds;
                }

                self.ip.* += @intCast(len * @sizeOf(info.child));

                const slice = ptr[0..len];

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    if (try self.decode(info.child) != sentinel) {
                        return Error.BadEncoding;
                    }
                }

                return slice;
            },
            else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
        },

        else => @compileError("cannot write type `" ++ @typeName(T) ++ "` to decoder"),
    }
}


pub fn isEof(self: *const Decoder) bool {
    return self.ip.* >= self.instructions.len;
}

pub fn next(self: *Decoder) Error!?ISA.Op {
    if (self.isEof()) return null;

    const opCode = try self.decode(ISA.OpCode);

    const opInfo = @typeInfo(ISA.Op).@"union";

    inline for (opInfo.fields) |field| {
        const tag = @field(ISA.OpCode, field.name);

        if (opCode == tag) {
            return @unionInit(ISA.Op, field.name, try self.decode(field.type));
        }
    }

    return Error.BadEncoding;
}
