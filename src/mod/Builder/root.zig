const std = @import("std");

const Support = @import("Support");
const Bytecode = @import("Bytecode");
const IO = @import("IO");


const Builder = @This();
pub const BlockBuilder = @import("./BlockBuilder.zig");
pub const FunctionBuilder = @import("./FunctionBuilder.zig");
pub const EvidenceBuilder = @import("./EvidenceBuilder.zig");
pub const HandlerSetBuilder = @import("./HandlerSetBuilder.zig");


allocator: std.mem.Allocator,
types: TypeMap,
globals: GlobalList,
functions: FunctionList,
handler_sets: HandlerSetList,
evidences: EvidenceMap(*EvidenceBuilder),


pub const Error = std.mem.Allocator.Error || error {
    TooManyTypes,
    TooManyGlobals,
    TooManyFunctions,
    TooManyBlocks,
    TooManyRegisters,
    TooManyHandlerSets,
    TooManyEvidences,
    TypeError,
    LayoutFailed,
    TooManyArguments,
    EvidenceOverlap,
    MissingEvidence,
    NotEnoughArguments,
    InstructionsAfterExit,
    MultipleExits,
    InvalidIndex,
    InvalidOffset,
    InvalidOperand,
    UnregisteredOperand,
};

pub const void_t: Bytecode.TypeIndex = 0;
pub const bool_t: Bytecode.TypeIndex = 1;
pub const i8_t: Bytecode.TypeIndex   = 2;
pub const i16_t: Bytecode.TypeIndex  = 3;
pub const i32_t: Bytecode.TypeIndex  = 4;
pub const i64_t: Bytecode.TypeIndex  = 5;
pub const f32_t: Bytecode.TypeIndex  = 6;
pub const f64_t: Bytecode.TypeIndex  = 7;

const basic_types = [_]Bytecode.Type {
    .void,
    .bool,
    .{ .int = Bytecode.Type.Int { .bit_width = .i8  } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i16 } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i32 } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i64 } },
    .{ .float = Bytecode.Type.Float { .bit_width = .f32 } },
    .{ .float = Bytecode.Type.Float { .bit_width = .f64 } },
};

pub const TypeMap = std.ArrayHashMapUnmanaged(Bytecode.Type, void, TypeMapContext, true);
pub const TypeList = std.ArrayListUnmanaged(Bytecode.TypeIndex);
pub const GlobalList = std.ArrayListUnmanaged(Global);
pub const FunctionList = std.ArrayListUnmanaged(*Function);
pub const BlockList = std.ArrayListUnmanaged(*BlockBuilder);
pub const HandlerSetList = std.ArrayListUnmanaged(*HandlerSetBuilder);
pub const HandlerMap = EvidenceMap(Bytecode.FunctionIndex);
pub const OpList = std.ArrayListUnmanaged(Bytecode.Op);

fn EvidenceMap(comptime T: type) type {
    return std.ArrayHashMapUnmanaged(Bytecode.EvidenceIndex, T, EvidenceMapContext, false);
}

const TypeMapContext = struct {
    pub fn hash(_: TypeMapContext, key: Bytecode.Type) u32 {
        return Support.fnv1a_32(key);
    }

    pub fn eql(_: TypeMapContext, a: Bytecode.Type, b: Bytecode.Type, _: usize) bool {
        return Support.equal(a, b);
    }
};

const EvidenceMapContext = struct {
    pub fn hash(_: EvidenceMapContext, key: Bytecode.EvidenceIndex) u32 {
        return Support.fnv1a_32(key);
    }

    pub fn eql(_: EvidenceMapContext, a: Bytecode.EvidenceIndex, b: Bytecode.EvidenceIndex, _: usize) bool {
        return a == b;
    }
};

pub const Global = struct {
    type: Bytecode.TypeIndex,
    initial: []u8,
};

pub const Function = union(enum) {
    bytecode: *FunctionBuilder,
    foreign: Foreign,

    pub const Foreign = struct {
        parent: *Builder,
        type: Bytecode.TypeIndex,
        evidence: ?Bytecode.EvidenceIndex,
        index: Bytecode.FunctionIndex,
    };
};


/// The allocator passed in should be an arena or a similar allocator that doesn't care about freeing individual allocations
pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Builder {
    var types = TypeMap {};
    try types.ensureTotalCapacity(allocator, 256);

    for (basic_types) |t| {
        try types.put(allocator, t, {});
    }

    std.debug.assert(Support.equal(types.keys()[void_t], basic_types[void_t]));
    std.debug.assert(Support.equal(types.keys()[i8_t], basic_types[i8_t]));
    std.debug.assert(Support.equal(types.keys()[f64_t], basic_types[f64_t]));

    var globals = GlobalList {};
    try globals.ensureTotalCapacity(allocator, 256);

    var functions = FunctionList {};
    try functions.ensureTotalCapacity(allocator, 256);

    var handler_sets = HandlerSetList {};
    try handler_sets.ensureTotalCapacity(allocator, 256);

    var evidences = EvidenceMap(*EvidenceBuilder) {};
    try evidences.ensureTotalCapacity(allocator, 256);

    return Builder {
        .allocator = allocator,
        .types = types,
        .globals = globals,
        .functions = functions,
        .handler_sets = handler_sets,
        .evidences = evidences,
    };
}

pub fn getType(self: *const Builder, index: Bytecode.TypeIndex) Error!Bytecode.Type {
    if (index >= self.types.keys().len) {
        return Error.InvalidIndex;
    }

    return self.types.keys()[index];
}

pub fn getOffsetType(self: *const Builder, t: Bytecode.TypeIndex, offset: Bytecode.RegisterLocalOffset) Error!Bytecode.TypeIndex {
    if (t >= self.types.keys().len) {
        return Error.InvalidIndex;
    }

    return Bytecode.offsetType(self.types.keys(), t, offset) orelse Error.InvalidOffset;
}

pub fn getTypeLayout(self: *const Builder, t: Bytecode.TypeIndex) Error!Bytecode.Layout {
    return Bytecode.typeLayout(self.types.keys(), t) orelse Error.LayoutFailed;
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

    try self.types.put(self.allocator, try t.clone(self.allocator), {});

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

pub fn getGlobal(self: *const Builder, index: Bytecode.GlobalIndex) Error!Global {
    if (index >= self.globals.items.len) {
        return Error.InvalidIndex;
    }

    return self.globals.items[index];
}

pub fn getGlobalType(self: *const Builder, operand: Bytecode.GlobalOperand) Error!Bytecode.TypeIndex {
    const global = try self.getGlobal(operand.index);
    return self.getOffsetType(global.type, operand.offset);
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

pub fn globalNative(self: *Builder, value: anytype) Error!Bytecode.GlobalIndex {
    const T = @TypeOf(value);
    const tId = try self.typeIdFromNative(T);
    const initial = try self.allocator.create(T);
    initial.* = value;
    return self.globalBytes(tId, @as([*]u8, @ptrCast(initial))[0..@sizeOf(T)]);
}

pub fn getFunction(self: *const Builder, index: Bytecode.FunctionIndex) Error!*Function {
    if (index >= self.functions.items.len) {
        return Error.InvalidIndex;
    }

    return self.functions.items[index];
}

pub fn getFunctionType(self: *const Builder, index: Bytecode.FunctionIndex) Error!Bytecode.TypeIndex {
    return switch ((try self.getFunction(index)).*) {
        .bytecode => |builder| builder.type,
        .foreign => |forn| forn.type,
    };
}

pub fn getFunctionEvidence(self: *const Builder, index: Bytecode.FunctionIndex) Error!?Bytecode.EvidenceIndex {
    return switch ((try self.getFunction(index)).*) {
        .bytecode => |builder| builder.evidence,
        .foreign => |forn| forn.evidence,
    };
}

pub fn function(self: *Builder, t: Bytecode.TypeIndex) Error!*FunctionBuilder {
    const index = self.functions.items.len;
    if (index >= std.math.maxInt(Bytecode.FunctionIndex)) {
        return Error.TooManyFunctions;
    }

    const func = try self.allocator.create(Function);
    func.bytecode = try FunctionBuilder.init(self, t, @truncate(index));

    try self.functions.append(self.allocator, func);

    return func.bytecode;
}

pub fn foreign(self: *Builder, t: Bytecode.TypeIndex) Error!*Function.Foreign {
    const index = self.functions.items.len;
    if (index >= std.math.maxInt(Bytecode.FunctionIndex)) {
        return Error.TooManyFunctions;
    }

    const ty = try self.getType(t);
    if (ty != .function) {
        return Error.TypeError;
    }

    const func = try self.allocator.create(Function);
    func.foreign = .{ .parent = self, .type = t, .evidence = null, .index = @truncate(index) };

    try self.functions.append(self.allocator, func);

    return &func.foreign;
}

pub fn foreignNative(self: *Builder, comptime T: type) Error!Function.Foreign {
    const tId = try self.typeIdFromNative(T);

    return self.foreign(tId);
}

pub fn getEvidence(self: *const Builder, e: Bytecode.EvidenceIndex) Error!*EvidenceBuilder {
    return self.evidences.get(e) orelse Error.InvalidIndex;
}

pub fn getEvidenceType(self: *const Builder, e: Bytecode.EvidenceIndex) Error!Bytecode.TypeIndex {
    return (try self.getEvidence(e)).type;
}

pub fn evidence(self: *Builder, t: Bytecode.TypeIndex, tt: Bytecode.TypeIndex) Error!*EvidenceBuilder {
    const index = self.evidences.keys().len;
    if (index >= std.math.maxInt(Bytecode.EvidenceIndex)) {
        return Error.TooManyEvidences;
    }

    const builder = try EvidenceBuilder.init(self, t, tt, @truncate(index));

    try self.evidences.put(self.allocator, @truncate(index), builder);

    return builder;
}


pub fn getHandlerSet(self: *const Builder, index: Bytecode.HandlerSetIndex) Error!*HandlerSetBuilder {
    if (index >= self.handler_sets.items.len) {
        return Error.InvalidIndex;
    }

    return self.handler_sets.items[index];
}

pub fn handlerSet(self: *Builder) Error!*HandlerSetBuilder {
    const index = self.handler_sets.items.len;
    if (index >= std.math.maxInt(Bytecode.HandlerSetIndex)) {
        return Error.TooManyHandlerSets;
    }

    const handler_set = try HandlerSetBuilder.init(self, @truncate(index));

    try self.handler_sets.append(self.allocator, handler_set);

    return handler_set;
}

pub fn typecheck(self: *const Builder, a: Bytecode.TypeIndex, b: Bytecode.TypeIndex) Error!void {
    const aTy = try self.getType(b);
    const bTy = try self.getType(a);
    if (Support.equal(aTy, bTy)) {
        return;
    }

    return Error.TypeError;
}


pub fn extractFunctionIndex(self: *const Builder, f: anytype) Error!Bytecode.FunctionIndex {
    switch (@TypeOf(f)) {
        *Bytecode.FunctionIndex => return extractFunctionIndex(self, f.*),
        Bytecode.FunctionIndex => {
            if (f >= self.functions.items.len) {
                return Error.InvalidIndex;
            }
            return f;
        },

        Function => return extractFunctionIndex(self, &f),
        *Function => return extractFunctionIndex(self, @as(*const Function, f)),
        *const Function => switch(f.value) {
            .bytecode => |builder| return extractFunctionIndex(self, builder),
            .foreign => |forn| {
                if (forn.parent != self) {
                    return Error.InvalidIndex;
                }
                return forn.index;
            },
        },

        FunctionBuilder => return extractFunctionIndex(self, &f),
        *FunctionBuilder => return extractFunctionIndex(self, @as(*const FunctionBuilder, f)),
        *const FunctionBuilder => {
            if (f.parent != self) {
                return Error.InvalidIndex;
            }
            return f.index;
        },

        else => @compileError(std.fmt.comptimePrint(
            "invalid block index parameter, expected either `Bytecode.FunctionIndex`, `*Builder.FunctionBuilder` or `Builder.Function`, got `{s}`",
            .{@typeName(@TypeOf(f))}
        )),
    }
}

pub fn extractHandlerSetIndex(self: *const Builder, h: anytype) Error!Bytecode.HandlerSetIndex {
    switch (@TypeOf(h)) {
        *Bytecode.HandlerSetIndex => return extractHandlerSetIndex(self, h.*),
        Bytecode.HandlerSetIndex => {
            if (h >= self.handler_sets.items.len) {
                return Error.InvalidIndex;
            }
            return h;
        },

        HandlerSetBuilder => return extractHandlerSetIndex(self, &h),
        *HandlerSetBuilder => return extractHandlerSetIndex(self, @as(*const HandlerSetBuilder, h)),
        *const HandlerSetBuilder => {
            if (h.parent != self) {
                return Error.InvalidIndex;
            }
            return h.index;
        },

        else => @compileError(std.fmt.comptimePrint(
            "invalid handler set index parameter, expected either `Bytecode.HandlerSetIndex` or `*Builder.HandlerSetBuilder`, got `{s}`",
            .{@typeName(@TypeOf(h))}
        )),
    }
}

pub fn extractEvidenceIndex(self: *const Builder, e: anytype) Error!Bytecode.EvidenceIndex {
    switch (@TypeOf(e)) {
        *Bytecode.EvidenceIndex => return extractEvidenceIndex(self, e.*),
        Bytecode.EvidenceIndex => {
            if (e >= self.evidences.keys().len) {
                return Error.InvalidIndex;
            }

            return e;
        },

        EvidenceBuilder => return extractEvidenceIndex(self, &e),
        *EvidenceBuilder => return extractEvidenceIndex(self, @as(*const EvidenceBuilder, e)),
        *const EvidenceBuilder => {
            if (e.parent != self) {
                return Error.InvalidIndex;
            }

            return e.index;
        },

        *Bytecode.FunctionIndex,
        Bytecode.FunctionIndex,
        Function,
        *Function,
        *const Function,
        FunctionBuilder,
        *FunctionBuilder,
        *const FunctionBuilder,
        => {
            const functionIndex = try self.extractFunctionIndex(e);

            return try self.getFunctionEvidence(functionIndex) orelse Error.MissingEvidence;
        },

        else => @compileError(std.fmt.comptimePrint(
            "invalid evidence index parameter, expected either `Bytecode.EvidenceIndex`, `*Builder.EvidenceBuilder` or a function that is evidence, got `{s}`",
            .{@typeName(@TypeOf(e))}
        )),
    }
}


test {
    std.testing.refAllDecls(@This());
}
