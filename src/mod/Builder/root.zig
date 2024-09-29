const std = @import("std");

const Support = @import("Support");
const Bytecode = @import("Bytecode");
const IO = @import("IO");


const Builder = @This();
pub const BlockBuilder = @import("./BlockBuilder.zig");
pub const EvidenceBuilder = @import("./EvidenceBuilder.zig");
pub const FunctionBuilder = @import("./FunctionBuilder.zig");
pub const HandlerSetBuilder = @import("./HandlerSetBuilder.zig");


allocator: std.mem.Allocator,
globals: GlobalList,
functions: FunctionList,
handler_sets: HandlerSetList,
evidences: EvidenceMap(*EvidenceBuilder),
main_function: ?Bytecode.FunctionIndex,


pub const Error = std.mem.Allocator.Error || error {
    TooManyGlobals,
    TooManyFunctions,
    TooManyBlocks,
    TooManyRegisters,
    TooManyHandlerSets,
    TooManyEvidences,
    TooManyInstructions,
    GlobalMemoryTooLarge,
    LayoutFailed,
    TooManyArguments,
    EvidenceOverlap,
    MissingEvidence,
    MissingHandler,
    NotEnoughArguments,
    InstructionsAfterExit,
    ArgumentAfterLocals,
    MultipleExits,
    MultipleMains,
    InvalidIndex,
    InvalidOffset,
    InvalidOperand,
    UnregisteredOperand,
    UnfinishedBlock,
};


pub const TypeMap = std.ArrayHashMapUnmanaged(Bytecode.Info.Type, void, Support.SimpleHashContext, true);
pub const TypeList = std.ArrayListUnmanaged(Bytecode.Info.TypeIndex);
pub const GlobalList = std.ArrayListUnmanaged(Global);
pub const FunctionList = std.ArrayListUnmanaged(*Function);
pub const BlockList = std.ArrayListUnmanaged(*BlockBuilder);
pub const HandlerSetList = std.ArrayListUnmanaged(*HandlerSetBuilder);
pub const HandlerMap = EvidenceMap(Bytecode.FunctionIndex);
pub const InstrList = std.ArrayListUnmanaged(Bytecode.Instruction);

fn EvidenceMap(comptime T: type) type {
    return std.ArrayHashMapUnmanaged(Bytecode.EvidenceIndex, T, Support.SimpleHashContext, false);
}


pub const Global = struct {
    alignment: Bytecode.Info.ValueAlignment,
    initial: []u8,
};

pub const Function = union(enum) {
    bytecode: *FunctionBuilder,
    foreign: Foreign,

    pub const Foreign = struct {
        parent: *Builder,
        evidence: ?Bytecode.EvidenceIndex,
        index: Bytecode.FunctionIndex,
        num_arguments: Bytecode.RegisterIndex,
        num_registers: Bytecode.RegisterIndex,

        pub fn assemble(self: *const Foreign, foreignId: Bytecode.ForeignId) Error!Bytecode.Function {
            return Bytecode.Function {
                .num_arguments = self.num_arguments,
                .num_registers = self.num_registers,
                .value = .{ .foreign = foreignId },
            };
        }
    };

    pub fn assemble(self: Function, allocator: std.mem.Allocator) Error!Bytecode.Function {
        // TODO: the builder should be handling this
        var foreignId: Bytecode.ForeignId = 0;

        switch (self) {
            .bytecode => |builder| return builder.assemble(allocator),
            .foreign => |forn| {
                const out = forn.assemble(foreignId);
                foreignId += 1;
                return out;
            },
        }
    }
};


/// The allocator passed in should be an arena or a similar allocator that doesn't care about freeing individual allocations
pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Builder {
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
        .globals = globals,
        .functions = functions,
        .handler_sets = handler_sets,
        .evidences = evidences,
        .main_function = null,
    };
}

/// this does not have to be the same allocator as the one passed to `init`,
/// a long-term allocator is preferred. In the event of an error, the builder
/// will clean-up any allocations made by this function
pub fn assemble(self: *const Builder, allocator: std.mem.Allocator) Error!Bytecode.Program {
    const globals = try self.generateGlobalSet(allocator);
    errdefer {
        allocator.free(globals[0]);
        allocator.free(globals[1]);
    }

    const functions = try self.generateFunctionList(allocator);
    errdefer {
        for (functions) |f| f.deinit(allocator);
        allocator.free(functions);
    }

    const handler_sets = try self.generateHandlerSetList(allocator);
    errdefer {
        for (handler_sets) |h| allocator.free(h);
        allocator.free(handler_sets);
    }

    return .{
        .globals = globals[0],
        .global_memory = globals[1],
        .functions = functions,
        .handler_sets = handler_sets,
        .main = self.main_function orelse Bytecode.FUNCTION_SENTINEL,
    };
}

pub fn generateGlobalSet(self: *const Builder, allocator: std.mem.Allocator) Error!struct { []const [*]u8, []u8 } {
    const values = try allocator.alloc([*]u8, self.globals.items.len);
    errdefer allocator.free(values);

    var buf = std.ArrayListAlignedUnmanaged(u8, std.mem.page_size){};
    defer buf.deinit(allocator);

    const memory = try buf.toOwnedSlice(allocator);

    for (self.globals.items) |global| {
        const padding = Support.alignmentDelta(buf.items.len, global.alignment);
        try buf.appendNTimes(allocator, 0, padding);
        try buf.appendSlice(allocator, global.initial);
    }

    var offset: usize = 0;
    for (self.globals.items, 0..) |global, i| {
        const padding = Support.alignmentDelta(offset, global.alignment);
        offset += padding;
        values[i] = memory.ptr + offset;
        offset += global.initial.len;
    }

    return .{ values, memory };
}

pub fn generateFunctionList(self: *const Builder, allocator: std.mem.Allocator) Error![]Bytecode.Function {
    const functions = try allocator.alloc(Bytecode.Function, self.functions.items.len);

    var i: usize = 0;
    errdefer {
        for (0..i) |j| functions[j].deinit(allocator);
        allocator.free(functions);
    }

    while (i < self.functions.items.len) : (i += 1) {
        const func = try self.functions.items[i].assemble(allocator);

        functions[i] = func;
    }

    return functions;
}

pub fn generateHandlerSetList(self: *const Builder, allocator: std.mem.Allocator) Error![]Bytecode.HandlerSet {
    const handlerSets = try allocator.alloc(Bytecode.HandlerSet, self.handler_sets.items.len);

    var i: usize = 0;
    errdefer {
        for (0..i) |j| allocator.free(handlerSets[j]);
        allocator.free(handlerSets);
    }

    while (i < self.handler_sets.items.len) : (i += 1) {
        handlerSets[i] = try self.handler_sets.items[i].assemble(allocator);
    }

    return handlerSets;
}

pub fn getGlobal(self: *const Builder, index: Bytecode.GlobalIndex) Error!Global {
    if (index >= self.globals.items.len) {
        return Error.InvalidIndex;
    }

    return self.globals.items[index];
}

pub fn globalBytes(self: *Builder, alignment: Bytecode.Info.ValueAlignment, initial: []u8) Error!Bytecode.GlobalIndex {
    const index = self.globals.items.len;
    if (index >= std.math.maxInt(Bytecode.GlobalIndex)) {
        return Error.TooManyGlobals;
    }

    try self.globals.append(self.allocator, .{
        .alignment = alignment,
        .initial = try self.allocator.dupe(u8, initial),
    });

    return @truncate(index);
}

pub fn globalNative(self: *Builder, value: anytype) Error!Bytecode.GlobalIndex {
    const T = @TypeOf(value);
    const initial = try self.allocator.create(T);
    initial.* = value;
    return self.globalBytes(@alignOf(T), @as([*]u8, @ptrCast(initial))[0..@sizeOf(T)]);
}

pub fn getFunction(self: *const Builder, index: Bytecode.FunctionIndex) Error!*Function {
    if (index >= self.functions.items.len) {
        return Error.InvalidIndex;
    }

    return self.functions.items[index];
}

pub fn function(self: *Builder) Error!*FunctionBuilder {
    const index = self.functions.items.len;
    if (index >= std.math.maxInt(Bytecode.FunctionIndex)) {
        return Error.TooManyFunctions;
    }

    const func = try self.allocator.create(Function);
    func.* = .{.bytecode = try FunctionBuilder.init(self, @truncate(index))};

    try self.functions.append(self.allocator, func);

    return func.bytecode;
}

pub fn hasMain(self: *const Builder) bool {
    return self.main_function != null;
}

pub fn main(self: *Builder) Error!*FunctionBuilder {
    if (self.hasMain()) return Error.MultipleMains;

    const func = try self.function();

    self.main_function = func.index;

    return func;
}

pub fn foreign(self: *Builder, num_arguments: Bytecode.RegisterIndex, num_registers: Bytecode.RegisterIndex) Error!*Function.Foreign {
    const index = self.functions.items.len;
    if (index >= std.math.maxInt(Bytecode.FunctionIndex)) {
        return Error.TooManyFunctions;
    }

    const func = try self.allocator.create(Function);
    func.* = .{.foreign = .{ .parent = self, .num_arguments = num_arguments, .num_registers = num_registers, .evidence = null, .index = @truncate(index) }};

    try self.functions.append(self.allocator, func);

    return &func.foreign;
}

pub fn getEvidence(self: *const Builder, e: Bytecode.EvidenceIndex) Error!*EvidenceBuilder {
    return self.evidences.get(e) orelse Error.InvalidIndex;
}

pub fn evidence(self: *Builder) Error!*EvidenceBuilder {
    const index = self.evidences.keys().len;
    if (index >= std.math.maxInt(Bytecode.EvidenceIndex)) {
        return Error.TooManyEvidences;
    }

    const builder = try EvidenceBuilder.init(self, @truncate(index));

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
