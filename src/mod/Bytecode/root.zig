//!

const std = @import("std");

const TextUtils = @import("ZigTextUtils");
const TypeUtils = @import("ZigTypeUtils");

const IO = @import("IO");


const Bytecode = @This();


blocks: []const Block,
instructions: []const u8,


pub const Op = @import("ISA.zig").Op;
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
pub const GlobalIndex = u16;
pub const ConstantIndex = u16;
pub const EvidenceIndex = u16;


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
    register: Register,
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
        signed: bool,
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
        names: [][]const u8,
        types: []TypeIndex,
    };

    pub const Sum = struct {
        names: [][]const u8,
        types: []TypeIndex,
    };

    pub const Function = struct {
        params: []TypeIndex,
        result: TypeIndex,
    };
};

pub const LayoutTable = struct {
    type: TypeIndex,
    local_types: []TypeIndex,
    local_layouts: []Layout,
    local_offsets: []RegisterBaseOffset,
    size: LayoutTableSize,
    alignment: ValueAlignment,
    num_params: Register,
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

pub const Data = struct {
    type: TypeIndex,
    layout: Layout,
    value: []u8,
};

pub const Program = struct {
    types: []Type,
    globals: []Data,
    constants: []Data,
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
        try block.write(writer);
    }

    try writeInstructions(self.instructions, writer);
}

pub fn writeInstructions(instructions: []const u8, writer: IO.Writer) !void {
    try writer.write(@as(InstructionPointer, @intCast(instructions.len)));

    var decoder = IO.Decoder.init(instructions);

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
        .fun = Bytecode.Operand {
            .register = .r12,
            .offset = 45,
        },
        .ret = .r33,
        .args = &[_]Bytecode.Register {
            .r1, .r2, .r3, .r44
        },
    }};
    try encoder.encode(allocator, call);

    const br_imm = Op { .br_imm = .{
        .block = 36,
        .imm = 22,
    }};
    try encoder.encode(allocator, br_imm);

    const prompt = Op { .prompt = .{
        .ev = 234,
        .ret = .r55,
        .args = &[_]Bytecode.Register {
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
    const nonNativeEndian: std.builtin.Endian = switch (nativeEndian) { .little => .big, .big => .little };

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

    var decoder = IO.Decoder.init(instructions);

    try std.testing.expectEqualDeep(nop, try decoder.decode(Op));
    try std.testing.expectEqualDeep(trap, try decoder.decode(Op));
    try std.testing.expectEqualDeep(call, try decoder.decode(Op));
    try std.testing.expectEqualDeep(br_imm, try decoder.decode(Op));
    try std.testing.expectEqualDeep(prompt, try decoder.decode(Op));
    try std.testing.expectEqualDeep(nop, try decoder.decode(Op));
    try std.testing.expectEqualDeep(trap, try decoder.decode(Op));
    try std.testing.expect(decoder.isEof());
}
