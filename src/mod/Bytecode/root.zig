//!

const std = @import("std");

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
pub const HandlerIndex = u8;
pub const TypeIndex = u16;
pub const RegisterIndex = u8;
pub const GlobalIndex = u13;
pub const GlobalOffset = u32;
pub const EvidenceIndex = u16;
pub const MemorySize = u48;


pub const MAX_REGISTERS = std.math.maxInt(RegisterIndex);

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

    pub const Kind = enum(u3) {
        global,
        local_var,
        local_arg,
        upvalue_var,
        upvalue_arg,
    };

    pub fn global(index: GlobalIndex, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .global, .data = .{ .global = .{ .index = index, .offset = offset } } };
    }

    pub fn local_var(reg: Register, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .local_var, .data = .{ .register = .{ .register = reg, .offset = offset } } };
    }

    pub fn local_arg(reg: Register, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .local_arg, .data = .{ .register = .{ .register = reg, .offset = offset } } };
    }

    pub fn upvalue_var(reg: Register, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .upvalue_var, .data = .{ .register = .{ .register = reg, .offset = offset } } };
    }

    pub fn upvalue_arg(reg: Register, offset: RegisterLocalOffset) Operand {
        return .{ .kind = .upvalue_arg, .data = .{ .register = .{ .register = reg, .offset = offset } } };
    }
};

comptime {
    std.debug.assert(@sizeOf(Operand) == 4);
    std.debug.assert(@bitSizeOf(Operand) == 32);
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

    pub const Kind = enum(u8) {
          basic = 0x00,   basic_v = 0x10,
        if_else = 0x01, if_else_v = 0x11,
           case = 0x02,    case_v = 0x12,
           with = 0x03,    with_v = 0x13,

           when = 0x04,
         unless = 0x05,
           loop = 0x06,
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
    function: Type.Function,

    pub const Int = struct {
        bit_width: u8,
    };

    pub const Float = struct {
        bit_width: u8,
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
        types: []TypeIndex,
    };

    pub const Function = struct {
        params: []TypeIndex,
        result: TypeIndex,
    };
};

pub const LayoutTable = struct {
    types: []TypeIndex,
    layouts: []Layout,
    local_offsets: []RegisterBaseOffset,
    size: LayoutTableSize,
    alignment: ValueAlignment,
    num_params: RegisterIndex,

    pub inline fn getType(self: *const LayoutTable, register: Register) TypeIndex {
        return self.types[@as(RegisterIndex, @intFromEnum(register))];
    }

    pub inline fn getLayout(self: *const LayoutTable, register: Register) Layout {
        return self.layouts[@as(RegisterIndex, @intFromEnum(register))];
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
        native: Native,
    };

    pub const Kind = enum(u1) {
        bytecode,
        native,
    };

    pub const Native = *const fn (fiber: *anyopaque) callconv(.C) NativeControl;

    pub const NativeControl = enum(u8) {
        returning,
        continuing,
        prompting,
        stepping,
        trapping,
    };
};

pub const HandlerSet = struct {
    handlers: []FunctionIndex,
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
    values: []Global,

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
    types: []Type,
    globals: GlobalSet,
    global_memory: []u8,
    functions: []Function,
    handlerSets: []HandlerSet,
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


test {
    const Support = @import("Support");

    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var encoder = IO.Encoder {};
    defer encoder.deinit(allocator);


    const nop = Op { .nop = {} };
    try encoder.encode(allocator, nop);

    const trap = Op { .trap = {} };
    try encoder.encode(allocator, trap);

    const call = Op { .call = .{
        .f = .local_var(.r12, 45),
        .r = .r33,
        .as = &[_]Bytecode.Register {
            .r1, .r2, .r3, .r44
        },
    }};
    try encoder.encode(allocator, call);

    const br_imm = Op { .br_v = .{
        .b = 36,
        .y = .global(12, 34),
    }};
    try encoder.encode(allocator, br_imm);

    const prompt = Op { .prompt = .{
        .e = 234,
        .r = .r55,
        .as = &[_]Bytecode.Register {
            .r4, .r6, .r9, .r133
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
