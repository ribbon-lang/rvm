//!

const std = @import("std");

const Support = @import("Support");
const TextUtils = @import("ZigTextUtils");
const TypeUtils = @import("ZigTypeUtils");

const IO = @import("IO");


const Bytecode = @This();


blocks: []const Block,
instructions: []const u8,


pub const ISA = @import("ISA.zig");

pub const Op = ISA.Op;
pub const OpCode = @typeInfo(Op).@"union".tag_type.?;

pub const InstructionPointer = u24;
pub const InstructionPointerOffset = u16;
pub const RegisterIndex = u16;
pub const RegisterLocalOffset = u16;
pub const RegisterBaseOffset = u32;
pub const UpvalueIndex = u16;
pub const UpvalueLocalOffset = u16;
pub const UpvalueBaseOffset = u32;
pub const GlobalIndex = u16;
pub const GlobalLocalOffset = u16;
pub const GlobalBaseOffset = u32;
pub const BlockIndex = u16;
pub const LayoutTableSize = RegisterBaseOffset;
pub const ValueSize = u16;
pub const ValueAlignment = u16;
pub const FunctionIndex = u16;
pub const HandlerSetIndex = u16;
pub const TypeIndex = u16;
pub const EvidenceIndex = u16;
pub const MemorySize = u48;
pub const ForeignId = u48;

pub const MAX_BLOCKS: BlockIndex = 256;
pub const MAX_EVIDENCE: EvidenceIndex = 1024;
pub const MAX_REGISTERS: RegisterIndex = 256;
pub const MAX_INSTRUCTIONS: InstructionPointer = std.math.maxInt(InstructionPointer);
pub const MAX_INSTRUCTION_OFFSET: InstructionPointerOffset = std.math.maxInt(InstructionPointerOffset);

pub const TYPE_SENTINEL = std.math.maxInt(TypeIndex);
pub const EVIDENCE_SENTINEL = std.math.maxInt(EvidenceIndex);
pub const HANDLER_SET_SENTINEL = std.math.maxInt(HandlerSetIndex);
pub const FUNCTION_SENTINEL = std.math.maxInt(FunctionIndex);



pub const Block = struct {
    base: InstructionPointer,
    size: InstructionPointerOffset,
};

pub const Layout = struct {
    size: ValueSize,
    alignment: ValueAlignment,

    pub fn inbounds(self: Layout, offset: RegisterLocalOffset, size: ValueSize) bool {
        return @as(usize, offset) + @as(usize, size) <= @as(usize, self.size);
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
        bit_width: BitWidth,
        pub const BitWidth = enum(u2) {
            i8, i16, i32, i64,

            pub fn toInt(self: BitWidth) u8 {
                switch (self) {
                    .i8 => return 8,
                    .i16 => return 16,
                    .i32 => return 32,
                    .i64 => return 64,
                }
            }

            pub fn byteSize(self: BitWidth) u8 {
                return self.toInt() / 8;
            }
        };
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
        evidence: []const EvidenceIndex,
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

                const evidence = try allocator.alloc(EvidenceIndex, info.evidence.len);
                errdefer allocator.free(evidence);

                @memcpy(params, info.params);
                @memcpy(evidence, info.evidence);

                return .{ .function = .{ .params = params, .term = info.term, .result = info.result, .evidence = evidence } };
            },
        }
    }

    pub const void_t: Bytecode.TypeIndex = 0;
    pub const bool_t: Bytecode.TypeIndex = 1;
    pub const i8_t: Bytecode.TypeIndex   = 2;
    pub const i16_t: Bytecode.TypeIndex  = 3;
    pub const i32_t: Bytecode.TypeIndex  = 4;
    pub const i64_t: Bytecode.TypeIndex  = 5;
    pub const f32_t: Bytecode.TypeIndex  = 6;
    pub const f64_t: Bytecode.TypeIndex  = 7;

    pub const BASIC_TYPES = [_]Bytecode.Type {
        .void,
        .bool,
        .{ .int = Bytecode.Type.Int { .bit_width = .i8  } },
        .{ .int = Bytecode.Type.Int { .bit_width = .i16 } },
        .{ .int = Bytecode.Type.Int { .bit_width = .i32 } },
        .{ .int = Bytecode.Type.Int { .bit_width = .i64 } },
        .{ .float = Bytecode.Type.Float { .bit_width = .f32 } },
        .{ .float = Bytecode.Type.Float { .bit_width = .f64 } },
    };
};

pub const LayoutDetails = struct {
    term_type: TypeIndex,
    return_type: TypeIndex,
    register_types: [*]const TypeIndex,
    block_types: [*]const TypeIndex,

    term_layout: Layout,
    return_layout: Layout,
    register_layouts: [*]const Layout,
    block_layouts: [*]const Layout,

    num_arguments: RegisterIndex,
    num_registers: RegisterIndex,
    num_blocks: BlockIndex,

    pub fn deinit(self: *const LayoutDetails, allocator: std.mem.Allocator) void {
        allocator.free(self.register_types[0..self.num_registers]);
        allocator.free(self.register_layouts[0..self.num_registers]);
        allocator.free(self.block_types[0..self.num_blocks]);
    }
};

pub const LayoutTable = packed struct {
    register_info: u48,

    term_size: ValueSize,
    return_size: ValueSize,

    size: LayoutTableSize,
    alignment: ValueAlignment,

    num_registers: RegisterIndex,

    pub const RegisterInfo = packed struct {
        offset: RegisterBaseOffset,
        size: ValueSize,
    };

    pub inline fn registerInfo(self: LayoutTable) [*]RegisterInfo {
        return @ptrFromInt(self.register_info);
    }

    pub fn deinit(self: LayoutTable, allocator: std.mem.Allocator) void {
        allocator.free(self.registerInfo()[0..self.num_registers]);
    }
};

pub const Function = struct {
    index: FunctionIndex,
    num_registers: RegisterIndex,
    value: Value,

    pub const Value = union(Kind) {
        bytecode: Bytecode,
        foreign: ForeignId,
    };

    pub const Kind = enum(u1) {
        bytecode,
        foreign,
    };

    pub fn deinit(self: Function, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .bytecode => self.value.bytecode.deinit(allocator),
            .foreign => {},
        }
    }
};

pub const HandlerSet = []const HandlerBinding;

pub const HandlerBinding = struct {
    id: EvidenceIndex,
    handler: FunctionIndex,
};

pub const Global = struct {
    type: TypeIndex,
    layout: Layout,
    offset: GlobalBaseOffset,

    pub fn read(reader: IO.Reader, context: anytype) !Global {
        const typeIndex = try reader.read(TypeIndex, context);
        const layout = try reader.read(Layout, context);

        const offset: GlobalBaseOffset = @truncate(context.globalMemory.len);

        for (0..layout.size) |_| {
            const byte = try reader.read(u8, context);
            try context.globalMemory.append(byte, context.allocator);
        }

        if (context.globalMemory.items.len > std.math.maxInt(GlobalBaseOffset)) {
            return error.OutOfMemory;
        }

        return .{
            .type = typeIndex,
            .layout = layout,
            .offset = offset,
        };
    }
};

pub const GlobalSet = struct {
    memory: []u8,
    values: []const Global,

    pub fn deinit(self: GlobalSet, allocator: std.mem.Allocator) void {
        allocator.free(self.memory);
        allocator.free(self.values);
    }

    pub fn read(reader: IO.Reader, context: anytype) !GlobalSet {
        var globalMemory = std.ArrayListUnmanaged(u8){};
        const globalCount: usize = try reader.read(GlobalIndex, context);
        var globals = try context.allocator.alloc(Global, globalCount);
        errdefer context.allocator.free(globals);

        const globalContext = TypeUtils.structConcat(.{context, .{ .globalMemory = &globalMemory }});
        for (0..globalCount) |i| {
            const global = try reader.read(Global, globalContext);
            globals[i] = global;
        }
    }
};

pub const Program = struct {
    types: []const Type,
    globals: GlobalSet,
    functions: []const Function,
    layout_details: []const LayoutDetails,
    handler_sets: []const HandlerSet,
    main: ?FunctionIndex,

    pub fn deinit(self: Program, allocator: std.mem.Allocator) void {
        for (self.types) |ty| {
            ty.deinit(allocator);
        }

        allocator.free(self.types);

        self.globals.deinit(allocator);

        for (self.functions) |fun| {
            fun.deinit(allocator);
        }

        allocator.free(self.functions);

        for (self.handler_sets) |handlerSet| {
            allocator.free(handlerSet);
        }

        allocator.free(self.handler_sets);
    }
};

pub const Location = struct {
    function: FunctionIndex,
    block: BlockIndex,
    offset: InstructionPointerOffset,
};


pub fn deinit(self: Bytecode, allocator: std.mem.Allocator) void {
    allocator.free(self.blocks);
    allocator.free(self.instructions);
}

pub fn write(self: *const Bytecode, writer: IO.Writer) !void {
    try writer.write(@as(BlockIndex, @intCast(self.blocks.len)));

    for (self.blocks) |block| {
        try writer.write(block);
    }

    try writeInstructions(self.instructions, writer);
}

pub fn writeInstructions(instructions: []const u8, writer: IO.Writer) !void {
    try writer.write(@as(InstructionPointer, @intCast(instructions.len)));

    var decoderOffset: InstructionPointerOffset = 0;
    const decoder = IO.Decoder { .memory = instructions, .base = 0, .offset = &decoderOffset };

    while (!decoder.isEof()) {
        const op = try decoder.decode(Op);
        try writer.write(op);
    }
}

pub fn read(reader: IO.Reader, context: anytype) !Bytecode {
    const blockCount: usize = try reader.read(BlockIndex, context);
    var blocks = try context.allocator.alloc(Block, blockCount);
    errdefer context.allocator.free(blocks);

    for (0..blockCount) |i| {
        const block = try reader.read(Block, context);
        blocks[i] = block;
    }

    const instructions = try readInstructions(reader, context);
    errdefer context.allocator.free(instructions);

    return .{
        .blocks = blocks,
        .instructions = instructions,
    };
}

pub fn readInstructions(reader: IO.Reader, context: anytype) ![]const u8 {
    if (comptime @hasField(@TypeOf(context), "tempAllocator")) {
        return readInstructionsImpl(reader, context.allocator, .{ .allocator = context.tempAllocator });
    } else {
        var arena = std.heap.ArenaAllocator.init(context.allocator);
        defer arena.deinit();

        return readInstructionsImpl(reader, context.allocator, .{ .allocator = arena.allocator() });
    }
}

pub fn readInstructionsImpl(reader: IO.Reader, encoderAllocator: std.mem.Allocator, context: anytype) ![]const u8 {
    var encoder = IO.Encoder {};
    defer encoder.deinit(encoderAllocator);

    const instructionBytes: usize = try reader.read(InstructionPointer, context);

    while (encoder.len() < instructionBytes) {
        const op = try reader.read(Op, context);
        try encoder.encode(encoderAllocator, op);
    }

    return try encoder.finalize(encoderAllocator);
}


// TODO: this should be a format method on Type
pub fn printType(types: []const Bytecode.Type, ty: Bytecode.TypeIndex, writer: anytype) !void {
    switch (types[ty]) {
        .void => try writer.writeAll("void"),
        .bool => try writer.writeAll("bool"),
        .int => |info| try writer.print("i{}", .{ info.bit_width.toInt() }),
        .float => |info| try writer.print("f{}", .{ info.bit_width.toInt() }),
        .pointer => |info| {
            try writer.writeAll("*");
            try printType(types, info.target, writer);
        },
        .array => |info| {
            try writer.print("[{}]", .{info.length});
            try printType(types, info.element, writer);
        },
        .product => |info| {
            try writer.writeAll("(prod: ");
            for (info.types, 0..) |field, i| {
                try printType(types, field, writer);
                if (i < info.types.len - 1) {
                    try writer.writeAll(" * ");
                }
            }
            try writer.writeAll(")");
        },
        .sum => |info| {
            try writer.writeAll("(sum ");
            try printType(types, info.discriminator, writer);
            try writer.writeAll(": ");
            for (info.types, 0..) |field, i| {
                try printType(types, field, writer);
                if (i < info.types.len - 1) {
                    try writer.writeAll(" + ");
                }
            }
            try writer.writeAll(")");
        },
        .raw_sum => |info| {
            try writer.writeAll("(raw_sum: ");
            for (info.types, 0..) |field, i| {
                try printType(types, field, writer);
                if (i < info.types.len - 1) {
                    try writer.writeAll(" + ");
                }
            }
            try writer.writeAll(")");
        },
        .function => |info| {
            try writer.writeAll("(fn: ");
            for (info.params, 0..) |arg, i| {
                try printType(types, arg, writer);
                if (i < info.params.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" -> ");
            try printType(types, info.result, writer);
            try writer.writeAll(" / ");
            try printType(types, info.term, writer);
            if (info.evidence.len > 0) {
                try writer.writeAll("(in: ");
                for (info.evidence, 0..) |e, i| {
                    try writer.print("{}", .{e});
                    if (i < info.evidence.len - 1) {
                        try writer.writeAll(", ");
                    }
                }
                try writer.writeAll(")");
            }
            try writer.writeAll(")");
        },
    }
}

pub fn printValue(types: []const Bytecode.Type, ty: Bytecode.TypeIndex, bytes: [*]const u8, len: ?usize, writer: anytype) !void {
    switch (types[ty]) {
        .void => if (len) |l| try writer.print("{any}", .{bytes[0..l]}) else try writer.writeAll("[cannot display]"),
        .bool => try writer.print("{}", .{ @as(*const align(1) bool, @ptrCast(bytes)).* }),
        .int => |info| {
            switch (info.bit_width) {
                .i8 => try writer.print("0x{x:0>2}", .{ @as(*const align(1) u8, @ptrCast(bytes)).* }),
                .i16 => try writer.print("0x{x:0>4}", .{ @as(*const align(1) u16, @ptrCast(bytes)).* }),
                .i32 => try writer.print("0x{x:0>8}", .{ @as(*const align(1) u32, @ptrCast(bytes)).* }),
                .i64 => try writer.print("0x{x:0>16}", .{ @as(*const align(1) u64, @ptrCast(bytes)).* }),
            }
        },
        .float => |info| switch (info.bit_width) {
            .f32 => try writer.print("{}", .{ @as(*const align(1) f32, @ptrCast(bytes)).* }),
            .f64 => try writer.print("{}", .{ @as(*const align(1) f64, @ptrCast(bytes)).* }),
        },
        .pointer => |info| {
            const ptr = @as(*const align(1) [*]const u8, @ptrCast(bytes)).*;
            try writer.print("@{x:0>16} => ", .{ @intFromPtr(ptr) });
            try printValue(types, info.target, ptr, null, writer);
        },
        .array => |info| {
            if (typeLayout(types, info.element)) |layout| {
                try writer.writeAll("[");
                for (0..info.length) |i| {
                    try printValue(types, info.element, bytes + layout.size * i, layout.size, writer);
                    if (i < info.length - 1) {
                        try writer.writeAll(", ");
                    }
                }
                try writer.writeAll("]");
            } else {
                try writer.writeAll("[cannot display]");
            }
        },
        .product => |info| {
            var offset: usize = 0;
            try writer.writeAll("(");
            for (info.types, 0..) |field, i| {
                if (typeLayout(types, field)) |fieldLayout| {
                    offset += Support.alignmentDelta(offset, fieldLayout.alignment);
                    try printValue(types, field, bytes + offset, fieldLayout.size, writer);
                    if (i < info.types.len - 1) {
                        try writer.writeAll(" * ");
                    }
                    offset += fieldLayout.size;
                } else {
                    try writer.writeAll("... cannot display");
                    break;
                }
            }
            try writer.writeAll(")");
        },
        .sum => |info| {
            var offset: usize, const disc = if (typeLayout(types, info.discriminator)) |discLayout| layout: {
                try printValue(types, info.discriminator, bytes, discLayout.size, writer);
                const discValue: usize = switch (discLayout.size) {
                    1 => @as(*const align(1) u8, @ptrCast(bytes)).*,
                    2 => @as(*const align(1) u16, @ptrCast(bytes)).*,
                    4 => @as(*const align(1) u32, @ptrCast(bytes)).*,
                    8 => @as(*const align(1) u64, @ptrCast(bytes)).*,
                    else => return writer.writeAll("[cannot display]"),
                };
                break :layout .{discLayout.size, discValue};
            } else {
                return writer.writeAll("[cannot display]");
            };

            const fieldType = info.types[disc];

            if (typeLayout(types, fieldType)) |fieldLayout| {
                offset += Support.alignmentDelta(offset, fieldLayout.alignment);
                try printValue(types, fieldType, bytes + offset, fieldLayout.size, writer);
            } else {
                try writer.writeAll("[cannot display]");
            }
        },
        .raw_sum => if (len) |l| {
            try writer.print("{any}", .{bytes[0..l]});
        } else {
            try writer.writeAll("[cannot display]");
        },
        .function => try writer.print("(fn {})", .{ @as(*const align(1) u64, @ptrCast(bytes)).* }),
    }
}


pub fn typeLayout(types: []const Bytecode.Type, ty: Bytecode.TypeIndex) ?Bytecode.Layout {
    switch (types[ty]) {
        .void => return .{ .size = 0, .alignment = 1 },
        .bool => return .{ .size = 1, .alignment = 1 },
        .int => |info| switch (info.bit_width) {
            .i8 => return .{ .size = 1, .alignment = 1 },
            .i16 => return .{ .size = 2, .alignment = 2 },
            .i32 => return .{ .size = 4, .alignment = 4 },
            .i64 => return .{ .size = 8, .alignment = 8 },
        },
        .float => |info| switch (info.bit_width) {
            .f32 => return .{ .size = 4, .alignment = 4 },
            .f64 => return .{ .size = 8, .alignment = 8 },
        },
        .pointer => return .{ .size = 8, .alignment = 8 },
        .array => |info| if (typeLayout(types, info.element)) |elementLayout| {
            return .{
                .size = @intCast(elementLayout.size * info.length),
                .alignment = elementLayout.alignment,
            };
        } else {
            return null;
        },
        .product => |info| {
            var size: u16 = 0;
            var alignment: u16 = 1;

            for (info.types) |field| {
                if (typeLayout(types, field)) |fieldLayout| {
                    alignment = @max(alignment, fieldLayout.alignment);

                    const padding = Support.alignmentDelta(size, alignment);

                    size += padding + fieldLayout.size;
                } else {
                    return null;
                }
            }

            return .{ .size = size, .alignment = alignment };
        },
        .sum => |info| {
            var size: u16 = 0;
            var alignment: u16 = 1;

            if (typeLayout(types, info.discriminator)) |discInfo| {
                size += discInfo.size;
                alignment = @max(alignment, discInfo.alignment);
            } else {
                return null;
            }

            const baseSize = size;

            for (info.types) |field| {
                if (typeLayout(types, field)) |fieldLayout| {
                    size = @max(size, fieldLayout.size);
                    alignment = @max(alignment, fieldLayout.alignment);
                } else {
                    return null;
                }
            }

            const padding = Support.alignmentDelta(baseSize, alignment);
            size += padding;

            return .{ .size = size, .alignment = alignment };
        },
        .raw_sum => |info| {
            var size: u16 = 0;
            var alignment: u16 = 1;

            for (info.types) |field| {
                if (typeLayout(types, field)) |fieldLayout| {
                    size = @max(size, fieldLayout.size);
                    alignment = @max(alignment, fieldLayout.alignment);
                } else {
                    return null;
                }
            }

            return .{ .size = size, .alignment = alignment };
        },
        .function => return .{ .size = 8, .alignment = 8 },
    }
}

/// expects void to be TypeIndex 0
pub fn offsetType(types: []const Bytecode.Type, ty: Bytecode.TypeIndex, offset: Bytecode.RegisterLocalOffset) ?Bytecode.TypeIndex {
    if (offset == 0) return ty;

    switch (types[ty]) {
        .void => return ty,
        .bool => return null,
        .int => |info| {
            if (offset < info.bit_width.byteSize()) {
                return 0;
            }

            return null;
        },
        .float => |info| {
            if (offset < info.bit_width.byteSize()) {
                return 0;
            }

            return null;
        },
        .pointer => {
            if (offset < 8) {
                return 0;
            }

            return null;
        },
        .array => |info| {
            const elemLayout = typeLayout(types, info.element) orelse return null;

            if (offset < elemLayout.size * info.length) {
                return offsetType(types, info.element, offset % elemLayout.size);
            }

            return null;
        },
        .product => |info| {
            var fieldOffset: u16 = 0;

            const prodLayout = typeLayout(types, ty) orelse return null;

            if (offset < prodLayout.size) {
                for (info.types) |field| {
                    if (typeLayout(types, field)) |fieldLayout| {
                        fieldOffset += Support.alignmentDelta(fieldOffset, fieldLayout.alignment);

                        if (fieldOffset == offset) {
                            return field;
                        }

                        if (offset < fieldOffset + fieldLayout.size) {
                            return offsetType(types, field, offset - fieldOffset);
                        }

                        fieldOffset += fieldLayout.size;
                    } else {
                        return 0;
                    }
                }
            }

            return null;
        },
        .sum => |info| {
            const sumLayout = typeLayout(types, ty) orelse return null;

            if (offset < sumLayout.size) {
                if (typeLayout(types, info.discriminator)) |discLayout| {
                    if (offset < discLayout.size) {
                        return offsetType(types, info.discriminator, offset);
                    } else {
                        return 0;
                    }
                }
            }

            return null;
        },
        .raw_sum => {
            const sumLayout = typeLayout(types, ty) orelse return null;

            if (offset < sumLayout.size) {
                return 0;
            }

            return null;
        },
        .function => {
            if (offset < 8) {
                return 0;
            }

            return null;
        },
    }
}


// test {
//     const allocator = std.testing.allocator;
//     var arena = std.heap.ArenaAllocator.init(allocator);
//     defer arena.deinit();

//     var encoder = IO.Encoder {};
//     defer encoder.deinit(allocator);


//     const nop = Op { .nop = {} };
//     try encoder.encode(allocator, nop);

//     const trap = Op { .trap = {} };
//     try encoder.encode(allocator, trap);

//     const call = Op { .dyn_call_v = .{
//         .f = .local(.r12, 45),
//         .as = &[_]Bytecode.Operand {
//             .local(.r1, 0), .local(.r2, 256), .upvalue(.r3, 13), .local(.r44, 44)
//         },
//         .y = .local(.r33, 0),
//     }};
//     try encoder.encode(allocator, call);

//     const br_imm = Op { .br_v = .{
//         .b = 36,
//         .y = .global(12, 34),
//     }};
//     try encoder.encode(allocator, br_imm);

//     const prompt = Op { .prompt = .{
//         .e = 234,
//         .as = &[_]Bytecode.Operand {
//             .local(.r4, 100), .upvalue(.r6, 15), .local(.r9, 11), .local(.r133, 9)
//         },
//     }};
//     try encoder.encode(allocator, prompt);

//     try encoder.encode(allocator, nop);

//     try encoder.encode(allocator, trap);

//     const instructionsNative = try encoder.finalize(allocator);
//     defer allocator.free(instructionsNative);

//     var instructionsEndian = std.ArrayList(u8).init(allocator);
//     defer instructionsEndian.deinit();

//     const nativeEndian = @import("builtin").cpu.arch.endian();
//     const nonNativeEndian = IO.Endian.flip(nativeEndian);

//     const writer = IO.Writer.initEndian(instructionsEndian.writer().any(), nonNativeEndian);

//     try Bytecode.writeInstructions(instructionsNative, writer);

//     var bufferStream = std.io.fixedBufferStream(instructionsEndian.items);

//     const reader = IO.Reader.initEndian(bufferStream.reader().any(), nonNativeEndian);
//     const readerContext = .{
//         .allocator = allocator,
//         .tempAllocator = arena.allocator(),
//     };

//     const instructions = try Bytecode.readInstructions(reader, readerContext);
//     defer allocator.free(instructions);

//     try std.testing.expectEqualSlices(u8, instructionsNative, instructions);

//     var decodeOffset: InstructionPointerOffset = 0;
//     const decoder = IO.Decoder { .memory = instructions, .base = 0, .offset = &decodeOffset };

//     try std.testing.expect(Support.equal(nop, try decoder.decode(Op)));
//     try std.testing.expect(Support.equal(trap, try decoder.decode(Op)));
//     try std.testing.expect(Support.equal(call, try decoder.decode(Op)));
//     try std.testing.expect(Support.equal(br_imm, try decoder.decode(Op)));
//     try std.testing.expect(Support.equal(prompt, try decoder.decode(Op)));
//     try std.testing.expect(Support.equal(nop, try decoder.decode(Op)));
//     try std.testing.expect(Support.equal(trap, try decoder.decode(Op)));
//     try std.testing.expect(decoder.isEof());
// }

test {
    std.testing.refAllDeclsRecursive(@This());
}
