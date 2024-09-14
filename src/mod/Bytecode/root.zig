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
pub const BlockIndex = u16;
pub const RegisterLocalOffset = u16;
pub const RegisterBaseOffset = u24;
pub const LayoutTableSize = RegisterBaseOffset;
pub const ValueSize = u16;
pub const ValueAlignment = u16;
pub const FunctionIndex = u16;
pub const HandlerSetIndex = u16;
pub const TypeIndex = u16;
pub const RegisterIndex = u8;
pub const GlobalIndex = u14;
pub const GlobalOffset = u32;
pub const EvidenceIndex = u16;
pub const MemorySize = u48;
pub const ForeignId = u48;


pub const MAX_REGISTERS = std.math.maxInt(RegisterIndex);

pub const TYPE_SENTINEL = std.math.maxInt(TypeIndex);
pub const EVIDENCE_SENTINEL = std.math.maxInt(EvidenceIndex);
pub const HANDLER_SET_SENTINEL = std.math.maxInt(HandlerSetIndex);

pub const Register = reg: {
    const TagType = RegisterIndex;
    const max = std.math.maxInt(TagType);
    var fields = [1]std.builtin.Type.EnumField {undefined} ** max;

    for(0..max) |i| {
        fields[i] = .{
           .name = std.fmt.comptimePrint("r{}", .{i}),
           .value = i,
        };
    }

    break :reg @Type(.{ .@"enum" = .{
        .tag_type = TagType,
        .fields = &fields,
        .decls = &[0]std.builtin.Type.Declaration{},
        .is_exhaustive = true,
    }});
};

pub const Operand = packed struct {
    kind: Kind,
    data: OperandData,

    pub const Kind = enum(u2) {
        global,
        upvalue,
        local,
    };

    pub fn global(index: GlobalIndex, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .global, .data = .{ .global = .{ .index = index, .offset = offset } } };
    }

    pub fn upvalue(reg: Register, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .upvalue, .data = .{ .register = .{ .register = reg, .offset = offset } } };
    }

    pub fn local(reg: Register, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .local, .data = .{ .register = .{ .register = reg, .offset = offset } } };
    }
};

comptime {
    std.testing.expectEqual(32, @bitSizeOf(Operand)) catch unreachable;
    std.testing.expectEqual(4, @sizeOf(Operand)) catch unreachable;
    // @compileError(std.fmt.comptimePrint(
    //     \\sizeOf(Operand) = {}, bitSizeOf(Operand) = {}
    //     \\sizeOf(OperandData) = {}, bitSizeOf(OperandData) = {}
    //     \\sizeOf(RegisterOperand) = {}, bitSizeOf(RegisterOperand) = {}
    //     \\sizeOf(ImmediateOperand) = {}, bitSizeOf(ImmediateOperand) = {}
    //     , .{
    //         @sizeOf(Operand), @bitSizeOf(Operand),
    //         @sizeOf(OperandData), @bitSizeOf(OperandData),
    //         @sizeOf(RegisterOperand), @bitSizeOf(RegisterOperand),
    //         @sizeOf(ImmediateOperand), @bitSizeOf(ImmediateOperand),
    //     }
    // ));
}


pub const OperandData = packed union {
    register: RegisterOperand,
    global: GlobalOperand,
};

pub const RegisterOperand = packed struct {
    register: Register,
    offset: RegisterLocalOffset,
};

pub const GlobalOperand = packed struct {
    index: GlobalIndex,
    offset: RegisterLocalOffset,
};

pub const Block = struct {
    kind: Kind,
    base: InstructionPointer,
    size: InstructionPointerOffset,
    handlers: HandlerSetIndex,
    output_layout: ?Layout,

    pub const Kind = enum(u8) {
          basic = 0x00, basic_v = 0x10,
          if_nz = 0x01, if_nz_v = 0x11,
           if_z = 0x02,  if_z_v = 0x12,
           case = 0x03,  case_v = 0x13,
           with = 0x04,  with_v = 0x14,
          entry = 0x05, entry_v = 0x15,

           when = 0x06,
         unless = 0x07,

        pub inline fn hasOutput(self: Kind) bool {
            return switch (self) {
                inline
                    .basic_v, .if_nz_v, .if_z_v, .case_v, .with_v, .entry_v
                => true,
                inline else => false,
            };
        }
    };
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
    raw_sum: Sum,
    function: Type.Function,

    pub const Int = struct {
        bit_width: BitWidth,
        is_signed: bool,
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
        types: []TypeIndex,
    };

    pub const Sum = struct {
        discriminator: TypeIndex,
        types: []TypeIndex,
    };

    pub const RawSum = struct {
        types: []TypeIndex,
    };

    pub const Function = struct {
        params: []TypeIndex,
        result: TypeIndex,
    };
};

pub const LayoutTable = struct {
    term_type: TypeIndex,
    return_type: TypeIndex,
    register_types: [*]const TypeIndex,

    term_layout: ?Layout,
    return_layout: ?Layout,
    register_layouts: [*]const Layout,

    register_offsets: [*]const RegisterBaseOffset,

    size: LayoutTableSize,
    alignment: ValueAlignment,

    num_arguments: RegisterIndex,
    num_registers: RegisterIndex,

    pub inline fn getType(self: *const LayoutTable, register: Register) TypeIndex {
        return self.register_types[@as(RegisterIndex, @intFromEnum(register))];
    }

    pub inline fn getLayout(self: *const LayoutTable, register: Register) Layout {
        return self.register_layouts[@as(RegisterIndex, @intFromEnum(register))];
    }

    pub inline fn inbounds(self: *const LayoutTable, operand: RegisterOperand, size: ValueSize) bool {
        return self.getLayout(operand.register).inbounds(operand.offset, size);
    }
};

pub const Function = struct {
    layout_table: LayoutTable,
    value: Value,

    pub const Value = union(Kind) {
        bytecode: Bytecode,
        foreign: ForeignId,
    };

    pub const Kind = enum(u1) {
        bytecode,
        foreign,
    };
};

pub const HandlerSet = []const HandlerBinding;

pub const HandlerBinding = struct {
    id: EvidenceIndex,
    handler: FunctionIndex,
};

pub const Global = struct {
    type: TypeIndex,
    layout: Layout,
    offset: GlobalOffset,

    pub fn read(reader: IO.Reader, context: anytype) !Global {
        const typeIndex = try reader.read(TypeIndex, context);
        const layout = try reader.read(Layout, context);

        const offset: GlobalOffset = @truncate(context.globalMemory.len);

        for (0..layout.size) |_| {
            const byte = try reader.read(u8, context);
            try context.globalMemory.append(byte, context.allocator);
        }

        if (context.globalMemory.items.len > std.math.maxInt(GlobalOffset)) {
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
    handler_sets: []const HandlerSet,
    main: ?FunctionIndex,
};

pub const Location = struct {
    function: FunctionIndex,
    block: BlockIndex,
    offset: InstructionPointerOffset,
};


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



pub fn printType(types: []const Bytecode.Type, ty: Bytecode.TypeIndex, writer: anytype) !void {
    switch (types[ty]) {
        .void => try writer.writeAll("void"),
        .bool => try writer.writeAll("bool"),
        .int => |info| try writer.print("{u}{}", .{ if (info.is_signed) 's' else 'u', info.bit_width.toInt() }),
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
            for (info.fields, 0..) |field, i| {
                try printType(types, field, writer);
                if (i < info.fields.len - 1) {
                    try writer.writeAll(" * ");
                }
            }
            try writer.writeAll(")");
        },
        .sum => |info| {
            try writer.writeAll("(sum ");
            try printType(types, info.discriminator, writer);
            try writer.writeAll(": ");
            for (info.fields, 0..) |field, i| {
                try printType(types, field, writer);
                if (i < info.fields.len - 1) {
                    try writer.writeAll(" + ");
                }
            }
            try writer.writeAll(")");
        },
        .raw_sum => |info| {
            try writer.writeAll("(raw_sum: ");
            for (info.fields, 0..) |field, i| {
                try printType(types, field, writer);
                if (i < info.fields.len - 1) {
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
            try writer.writeAll(")");
        },
    }
}

pub fn printValue(types: []const Bytecode.Type, ty: Bytecode.TypeIndex, bytes: [*]const u8, len: ?usize, writer: anytype) !void {
    switch (types[ty]) {
        .void => if (len) |l| try writer.print("{any}", .{bytes[0..l]}) else try writer.writeAll("[cannot display]"),
        .bool => try writer.print("{}", .{ @as(*align(1) bool, @ptrCast(bytes)).* }),
        .int => |info| {
            if (info.is_signed) {
                switch (info.bit_width) {
                    .i8 => try writer.print("{}", .{ @as(*align(1) i8, @ptrCast(bytes)).* }),
                    .i16 => try writer.print("{}", .{ @as(*align(1) i16, @ptrCast(bytes)).* }),
                    .i32 => try writer.print("{}", .{ @as(*align(1) i32, @ptrCast(bytes)).* }),
                    .i64 => try writer.print("{}", .{ @as(*align(1) i64, @ptrCast(bytes)).* }),
                }
            } else {
                switch (info.bit_width) {
                    .i8 => try writer.print("{}", .{ @as(*align(1) i8, @ptrCast(bytes)).* }),
                    .i16 => try writer.print("{}", .{ @as(*align(1) i16, @ptrCast(bytes)).* }),
                    .i32 => try writer.print("{}", .{ @as(*align(1) i32, @ptrCast(bytes)).* }),
                    .i64 => try writer.print("{}", .{ @as(*align(1) i64, @ptrCast(bytes)).* }),
                }
            }
        },
        .float => |info| switch (info.bit_width) {
            .f32 => try writer.print("{}", .{ @as(*align(1) f32, @ptrCast(bytes)).* }),
            .f64 => try writer.print("{}", .{ @as(*align(1) f64, @ptrCast(bytes)).* }),
        },
        .pointer => |info| {
            const ptr = @as(*align(1) [*]const u8, @ptrCast(bytes)).*;
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
            for (info.fields, 0..) |field, i| {
                if (typeLayout(types, field)) |fieldLayout| {
                    offset += Support.alignmentDelta(offset, fieldLayout.alignment);
                    try printValue(types, field, bytes + offset, fieldLayout.size, writer);
                    if (i < info.fields.len - 1) {
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
                    1 => @as(*align(1) u8, @ptrCast(bytes)).*,
                    2 => @as(*align(1) u16, @ptrCast(bytes)).*,
                    4 => @as(*align(1) u32, @ptrCast(bytes)).*,
                    8 => @as(*align(1) u64, @ptrCast(bytes)).*,
                    else => return writer.writeAll("[cannot display]"),
                };
                break :layout .{discLayout.size, discValue};
            } else {
                return writer.writeAll("[cannot display]");
            };

            const fieldType = info.types[disc.discValue];

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
        .function => try writer.print("(fn {})", .{ @as(*align(1) u64, @ptrCast(bytes)).* }),
    }
}


pub fn typeLayout(types: []const Bytecode.Type, ty: Bytecode.TypeIndex) ?Bytecode.Layout {
    switch (types[ty]) {
        .void => return null,
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



test {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var encoder = IO.Encoder {};
    defer encoder.deinit(allocator);


    const nop = Op { .nop = {} };
    try encoder.encode(allocator, nop);

    const trap = Op { .trap = {} };
    try encoder.encode(allocator, trap);

    const call = Op { .dyn_call_v = .{
        .f = .local(.r12, 45),
        .as = &[_]Bytecode.Operand {
            .local(.r1, 0), .local(.r2, 256), .upvalue(.r3, 13), .local(.r44, 44)
        },
        .y = .local(.r33, 0),
    }};
    try encoder.encode(allocator, call);

    const br_imm = Op { .br_v = .{
        .b = 36,
        .y = .global(12, 34),
    }};
    try encoder.encode(allocator, br_imm);

    const prompt = Op { .prompt = .{
        .e = 234,
        .as = &[_]Bytecode.Operand {
            .local(.r4, 100), .upvalue(.r6, 15), .local(.r9, 11), .local(.r133, 9)
        },
    }};
    try encoder.encode(allocator, prompt);

    try encoder.encode(allocator, nop);

    try encoder.encode(allocator, trap);

    const instructionsNative = try encoder.finalize(allocator);
    defer allocator.free(instructionsNative);

    var instructionsEndian = std.ArrayList(u8).init(allocator);
    defer instructionsEndian.deinit();

    const nativeEndian = @import("builtin").cpu.arch.endian();
    const nonNativeEndian = IO.Endian.flip(nativeEndian);

    const writer = IO.Writer.initEndian(instructionsEndian.writer().any(), nonNativeEndian);

    try Bytecode.writeInstructions(instructionsNative, writer);

    var bufferStream = std.io.fixedBufferStream(instructionsEndian.items);

    const reader = IO.Reader.initEndian(bufferStream.reader().any(), nonNativeEndian);
    const readerContext = .{
        .allocator = allocator,
        .tempAllocator = arena.allocator(),
    };

    const instructions = try Bytecode.readInstructions(reader, readerContext);
    defer allocator.free(instructions);

    try std.testing.expectEqualSlices(u8, instructionsNative, instructions);

    var decodeOffset: InstructionPointerOffset = 0;
    const decoder = IO.Decoder { .memory = instructions, .base = 0, .offset = &decodeOffset };

    try std.testing.expect(Support.equal(nop, try decoder.decode(Op)));
    try std.testing.expect(Support.equal(trap, try decoder.decode(Op)));
    try std.testing.expect(Support.equal(call, try decoder.decode(Op)));
    try std.testing.expect(Support.equal(br_imm, try decoder.decode(Op)));
    try std.testing.expect(Support.equal(prompt, try decoder.decode(Op)));
    try std.testing.expect(Support.equal(nop, try decoder.decode(Op)));
    try std.testing.expect(Support.equal(trap, try decoder.decode(Op)));
    try std.testing.expect(decoder.isEof());
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
