const std = @import("std");

const Bytecode = @import("./root.zig");

pub const ValueSize = u16;
pub const ValueAlignment = u16;
pub const TypeIndex = u16;

pub const TYPE_SENTINEL = std.math.maxInt(TypeIndex);

pub const Layout = struct {
    size: ValueSize,
    alignment: ValueAlignment,

    pub fn inbounds(self: Layout, offset: Bytecode.RegisterLocalOffset, size: ValueSize) bool {
        return @as(usize, offset) + @as(usize, size) <= @as(usize, self.size);
    }
};

pub const RegisterWidth = enum(u2) {
    i8, i16, i32, i64,

    pub fn toInt(self: RegisterWidth) u8 {
        switch (self) {
            .i8 => return 8,
            .i16 => return 16,
            .i32 => return 32,
            .i64 => return 64,
        }
    }

    pub fn byteSize(self: RegisterWidth) u8 {
        return self.toInt() / 8;
    }
};

pub const Type = union(enum) {
    void: void,
    bool: void,
    int: Int,
    float: Float,
    pointer: Pointer,
    array: Array,
    product: Product,
    sum: Sum,
    raw_sum: RawSum,
    function: Type.Function,

    pub const Int = struct {
        bit_width: RegisterWidth,
    };

    pub const Float = struct {
        bit_width: BitWidth,
        pub const BitWidth = enum (u1) {
            f32, f64,

            pub fn toInt(self: BitWidth) u8 {
                switch (self) {
                    .f32 => return 32,
                    .f64 => return 64,
                }
            }

            pub fn byteSize(self: BitWidth) u8 {
                return self.toInt() / 8;
            }
        };
    };

    pub const Pointer = struct {
        target: TypeIndex,
    };

    pub const Array = struct {
        element: TypeIndex,
        length: u64,
    };

    pub const Product = struct {
        types: []const TypeIndex,
    };

    pub const Sum = struct {
        discriminator: TypeIndex,
        types: []const TypeIndex,
    };

    pub const RawSum = struct {
        types: []const TypeIndex,
    };

    pub const Function = struct {
        params: []const TypeIndex,
        term: TypeIndex,
        result: TypeIndex,
        evidence: []const Bytecode.EvidenceIndex,
    };

    pub fn deinit(self: Type, allocator: std.mem.Allocator) void {
        switch (self) {
            .void => {},
            .bool => {},
            .int => {},
            .float => {},
            .pointer => {},
            .array => {},
            .product => |info| allocator.free(info.types),
            .sum => |info| allocator.free(info.types),
            .raw_sum => |info| allocator.free(info.types),
            .function => |info| {
                allocator.free(info.params);
                allocator.free(info.evidence);
            },
        }
    }

    pub fn clone(self: Type, allocator: std.mem.Allocator) std.mem.Allocator.Error!Type {
        switch (self) {
            .void => return self,
            .bool => return self,
            .int => return self,
            .float => return self,
            .pointer => return self,
            .array => return self,
            .product => |info| {
                const types = try allocator.alloc(TypeIndex, info.types.len);
                @memcpy(types, info.types);

                return .{ .product = .{ .types = types } };
            },
            .sum => |info| {
                const types = try allocator.alloc(TypeIndex, info.types.len);
                @memcpy(types, info.types);

                return .{ .sum = .{ .discriminator = info.discriminator, .types = types } };
            },
            .raw_sum => |info| {
                const types = try allocator.alloc(TypeIndex, info.types.len);
                @memcpy(types, info.types);

                return .{ .raw_sum = .{ .types = types } };
            },
            .function => |info| {
                const params = try allocator.alloc(TypeIndex, info.params.len);
                errdefer allocator.free(params);

                const evidence = try allocator.alloc(Bytecode.EvidenceIndex, info.evidence.len);
                errdefer allocator.free(evidence);

                @memcpy(params, info.params);
                @memcpy(evidence, info.evidence);

                return .{ .function = .{ .params = params, .term = info.term, .result = info.result, .evidence = evidence } };
            },
        }
    }

    pub const void_t: TypeIndex = 0;
    pub const bool_t: TypeIndex = 1;
    pub const i8_t: TypeIndex   = 2;
    pub const i16_t: TypeIndex  = 3;
    pub const i32_t: TypeIndex  = 4;
    pub const i64_t: TypeIndex  = 5;
    pub const f32_t: TypeIndex  = 6;
    pub const f64_t: TypeIndex  = 7;

    pub const BASIC_TYPES = [_]Type {
        .void,
        .bool,
        .{ .int = Int { .bit_width = .i8  } },
        .{ .int = Int { .bit_width = .i16 } },
        .{ .int = Int { .bit_width = .i32 } },
        .{ .int = Int { .bit_width = .i64 } },
        .{ .float = Float { .bit_width = .f32 } },
        .{ .float = Float { .bit_width = .f64 } },
    };
};
pub const Location = struct {
    function: *const Bytecode.Function,
    block: [*]const Bytecode.Instruction,
    ip: [*]const Bytecode.Instruction,
};
