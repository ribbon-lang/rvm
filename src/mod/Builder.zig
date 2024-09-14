const std = @import("std");

const Support = @import("Support");
const Bytecode = @import("Bytecode");
const IO = @import("IO");


const Builder = @This();

allocator: std.mem.Allocator,
types: TypeMap,
globals: GlobalList,
functions: FunctionList,


pub const Error = std.mem.Allocator.Error || error {
    TooManyTypes,
    TooManyGlobals,
    TooManyFunctions,
    TypeError,
};

pub const void_t: Bytecode.TypeIndex = 0;
pub const bool_t: Bytecode.TypeIndex = 1;
pub const u8_t: Bytecode.TypeIndex   = 2;
pub const u16_t: Bytecode.TypeIndex  = 3;
pub const u32_t: Bytecode.TypeIndex  = 4;
pub const u64_t: Bytecode.TypeIndex  = 5;
pub const s8_t: Bytecode.TypeIndex   = 6;
pub const s16_t: Bytecode.TypeIndex  = 7;
pub const s32_t: Bytecode.TypeIndex  = 8;
pub const s64_t: Bytecode.TypeIndex  = 9;
pub const f32_t: Bytecode.TypeIndex  = 10;
pub const f64_t: Bytecode.TypeIndex  = 11;

const basic_types = [_]Bytecode.Type {
    .void,
    .bool,
    .{ .int = Bytecode.Type.Int { .bit_width = .i8,  .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i16, .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i32, .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i64, .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i8,  .is_signed = true } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i16, .is_signed = true } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i32, .is_signed = true } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i64, .is_signed = true } },
    .{ .float = Bytecode.Type.Float { .bit_width = .f32 } },
    .{ .float = Bytecode.Type.Float { .bit_width = .f64 } },
};

const TypeMap = std.ArrayHashMapUnmanaged(Bytecode.Type, void, TypeMapContext, true);
const GlobalList = std.ArrayListUnmanaged(Global);
const FunctionList = std.ArrayListUnmanaged(Function);

const TypeMapContext = struct {
    pub fn hash(_: TypeMapContext, key: Bytecode.Type) u32 {
        return Support.fnv1a_32(key);
    }

    pub fn eql(_: TypeMapContext, a: Bytecode.Type, b: Bytecode.Type, _: usize) bool {
        return Support.equal(a, b);
    }
};

pub const Global = struct {
    type: Bytecode.TypeIndex,
    initial: []u8,
};

pub const Function = union(enum) {
    bytecode: BytecodeBuilder,
    foreign: Foreign,

    pub const Foreign = struct {
        type: Bytecode.TypeIndex,
    };
};

pub const BytecodeBuilder = struct {
    blocks: std.ArrayListUnmanaged(Bytecode.Block),
    encoder: IO.Encoder,
};


pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Builder {
    var types = TypeMap {};
    try types.ensureTotalCapacity(allocator, 256);
    errdefer types.deinit(allocator);

    for (basic_types) |t| {
        try types.put(allocator, t, {});
    }

    std.debug.assert(Support.equal(types.keys()[void_t], basic_types[void_t]));
    std.debug.assert(Support.equal(types.keys()[u8_t], basic_types[u8_t]));
    std.debug.assert(Support.equal(types.keys()[f64_t], basic_types[f64_t]));

    var globals = GlobalList {};
    try globals.ensureTotalCapacity(allocator, 256);
    errdefer globals.deinit(allocator);

    var functions = FunctionList {};
    try functions.ensureTotalCapacity(allocator, 256);
    errdefer functions.deinit(allocator);

    return Builder{
        .allocator = allocator,
        .types = types,
        .globals = globals,
        .functions = functions,
    };
}

pub fn typeId(self: *Builder, t: Bytecode.Type) Error!Bytecode.TypeIndex {
    const existing = self.types.getIndex(t);
    if (existing) |ex| {
        return @truncate(ex);
    }

    const index = self.types.keys().len;
    if (index >= std.math.maxInt(Bytecode.TypeIndex)) {
        return Error.TooManyTypes;
    }

    try self.types.put(self.allocator, t, {});

    return @truncate(index);
}

pub fn typeIdFromNative(self: *Builder, comptime T: type) Error!Bytecode.TypeIndex {
    switch (@typeInfo(T)) {
        .void => return self.typeId(.void),
        .bool => return self.typeId(.bool),
        .int => |info| {
            const is_signed = info.signedness == .signed;
            const bit_width = switch (info.bits) {
                8 => .i8,
                16 => .i16,
                32 => .i32,
                64 => .i64,
                else => return Error.TypeError,
            };
            return self.typeId(.{ .int = .{ .bit_width = bit_width, .is_signed = is_signed } });
        },
        .float => |info| {
            const bit_width = switch (info.bits) {
                32 => .f32,
                64 => .f64,
                else => return Error.TypeError,
            };
            return self.typeId(.{ .float = .{ .bit_width = bit_width } });
        },
        .@"enum" => |info| return self.typeIdFromNative(info.tag_type),
        .@"struct" => |info| {
            const fields = try self.allocator.alloc(Bytecode.TypeId, info.fields.len);
            errdefer self.allocator.free(fields);

            inline for (info.fields, 0..) |field, i| {
                const fieldType = try self.typeIdFromNative(field.type);
                fields[i] = fieldType;
            }

            return self.typeId(.{ .product = .{ .types = fields } });
        },
        .@"union" => |info| {
            const fields = try self.allocator.alloc(Bytecode.TypeId, info.fields.len);
            errdefer self.allocator.free(fields);

            inline for (info.fields, 0..) |field, i| {
                const fieldType = try self.typeIdFromNative(field.type);
                fields[i] = fieldType;
            }

            if (info.tag_type) |TT| {
                const tagType = try self.typeIdFromNative(TT);
                return self.typeId(.{ .sum = .{ .discriminator = tagType, .types = fields } });
            } else {
                return self.typeId(.{ .raw_sum = .{ .types = fields } });
            }
        },
        .@"array" => |info| return self.typeId(.{ .array = .{ .element = try self.typeIdFromNative(info.element_type), .length = info.len } }),
        .@"fn" => |info| {
            const params = try self.allocator.alloc(Bytecode.TypeId, info.params.len);
            inline for (info.param_types, 0..) |param, i| {
                const paramType = try self.typeIdFromNative(param);
                params[i] = paramType;
            }
            const returnType = try self.typeIdFromNative(info.return_type.?);
            return self.typeId(.{ .function = .{ .params = params, .result = returnType } });
        },
        else => return Error.TypeError,
    }
}

pub fn globalBytes(self: *Builder, t: Bytecode.TypeIndex, initial: []u8) Error!Bytecode.GlobalIndex {
    const index = self.globals.items.len;
    if (index >= std.math.maxInt(Bytecode.GlobalIndex)) {
        return Error.TooManyGlobals;
    }

    try self.globals.append(self.allocator, .{
        .type = t,
        .initial = initial,
    });

    return @truncate(index);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
