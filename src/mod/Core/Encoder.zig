const std = @import("std");

const Support = @import("Support");

const Core = @import("root.zig");
const Bytecode = Core.Bytecode;
const ISA = Core.ISA;

const Encoder = @This();


instructions: InstructionList,


const InstructionList = std.ArrayListUnmanaged(u8);

pub const Error = std.mem.Allocator.Error || error {};


pub fn init() Encoder {
    return .{
        .instructions = .{},
    };
}

pub fn deinit(self: *Encoder, allocator: std.mem.Allocator) void {
    self.instructions.deinit(allocator);
}

pub fn finalize(self: *Encoder, allocator: std.mem.Allocator) ![]const u8 {
    return self.instructions.toOwnedSlice(allocator);
}


pub fn encodeByte(self: *Encoder, allocator: std.mem.Allocator, value: u8) Error!void {
    return self.instructions.append(allocator, value);
}

pub fn encodeBytes(self: *Encoder, allocator: std.mem.Allocator, values: []u8) Error!void {
    return self.instructions.appendSlice(allocator, values);
}

pub fn encodeRaw(self: *Encoder, allocator: std.mem.Allocator, value: anytype) Error!void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);
    const buffer = @as([*]const u8, @ptrCast(&value))[0..size];
    return self.instructions.appendSlice(allocator, buffer);
}

pub fn pad(self: *Encoder, allocator: std.mem.Allocator, alignment: usize) Error!void {
    const addr = @intFromPtr(self.instructions.items.ptr) + self.instructions.items.len;
    const padding = Support.alignmentDelta(addr, alignment);
    for (0..padding) |_| {
        try self.encodeByte(allocator, 0);
    }
}

pub fn len(self: *const Encoder) usize {
    return self.instructions.items.len;
}

pub fn encode(self: *Encoder, allocator: std.mem.Allocator, value: anytype) Error!void {
    const T = @TypeOf(value);

    if (comptime std.meta.hasFn(T, "encode")) {
        return T.encode(self, allocator, value);
    }

    switch (@typeInfo(T)) {
        .void => return,

        .bool, .int, .float, .comptime_int, .comptime_float, .vector, .@"enum"
        => return self.encodeRaw(allocator, value),

        .@"struct" => |info| {
            if (info.backing_integer) |I| {
                return self.encode(allocator, @as(I, @bitCast(value)));
            }

            inline for (comptime std.meta.fieldNames(T)) |fieldName| {
                const field = @field(value, fieldName);
                try self.encode(allocator, field);
            }
        },

        .@"union" => |info| {
            if (info.tag_type) |TT| {
                const tag = @as(TT, value);

                try self.encode(allocator, tag);

                inline for (info.fields) |field| {
                    if (@field(TT, field.name) == tag) {
                        return self.encode(allocator, @field(value, field.name));
                    }
                }

                unreachable;
            }

            try self.pad(allocator, @alignOf(T));
            try self.encodeRaw(allocator, value);
        },

        .array => |info| {
            for (0..value.len) |i| {
                try self.encode(allocator, value[i]);
            }

            if (comptime info.sentinel) |sPtr| {
                const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                try self.encode(allocator, sentinel);
            }
        },

        .pointer => |info| switch(info.size) {
            .One => {
                try self.pad(allocator, @alignOf(info.child));
                return self.encode(allocator, value.*);
            },
            .Many => {
                if (comptime info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    var i: usize = 0;

                    try self.pad(allocator, @alignOf(info.child));

                    while (true) {
                        const item = value[i];
                        try self.encode(allocator, item);
                        if (item == sentinel) {
                            break;
                        }
                        i += 1;
                    }
                } else {
                    @compileError("cannot encode many-pointer `" ++ @typeName(T) ++ "` without sentinel");
                }
            },
            .Slice => {
                try self.encode(allocator, value.len);

                try self.pad(allocator, @alignOf(info.child));

                for (value) |item| {
                    try self.encode(allocator, item);
                }

                if (info.sentinel) |sPtr| {
                    const sentinel = @as(*const info.child, @ptrCast(sPtr)).*;
                    try self.encode(allocator, sentinel);
                }
            },
            else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
        },

        else => @compileError("cannot encode type `" ++ @typeName(T) ++ "` to encoder"),
    }
}


pub fn next(self: *Encoder, allocator: std.mem.Allocator, value: ISA.Op) Error!void {
    const opCode = @as(ISA.OpCode, value);

    try self.encode(allocator, opCode);

    const opInfo = @typeInfo(ISA.Op).@"union";

    inline for (opInfo.fields) |field| {
        const tag = @field(ISA.OpCode, field.name);

        if (opCode == tag) {
            const fieldValue = @field(value, field.name);
            try self.encode(allocator, fieldValue);
            return;
        }
    }

    unreachable;
}
