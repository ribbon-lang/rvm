const std = @import("std");

const Support = @import("Support");
const TextUtils = @import("ZigTextUtils");
const TypeUtils = @import("ZigTypeUtils");

const IO = @import("IO");


const Bytecode = @This();


pub const ISA = @import("ISA.zig");
pub const Info = @import("Info.zig");
pub const Print = @import("Print.zig");


blocks: []const [*]const Instruction,
instructions: []const Instruction,


pub const Register = u64;
pub const RegisterIndex = u8;
pub const RegisterLocalOffset = u16;
pub const RegisterBaseOffset = u32;
pub const UpvalueIndex = u8;
pub const UpvalueLocalOffset = u16;
pub const UpvalueBaseOffset = u32;
pub const GlobalIndex = u16;
pub const GlobalLocalOffset = u16;
pub const GlobalBaseOffset = u32;
pub const BlockIndex = u16;
pub const LayoutTableSize = RegisterBaseOffset;
pub const FunctionIndex = u16;
pub const HandlerSetIndex = u16;
pub const EvidenceIndex = u16;
pub const MemorySize = u48;
pub const ForeignId = u48;

pub const MAX_BLOCKS: BlockIndex = 1024;
pub const MAX_EVIDENCE: EvidenceIndex = 1024;
pub const MAX_REGISTERS: RegisterIndex = 255;

pub const EVIDENCE_SENTINEL = std.math.maxInt(EvidenceIndex);
pub const HANDLER_SET_SENTINEL = std.math.maxInt(HandlerSetIndex);
pub const FUNCTION_SENTINEL = std.math.maxInt(FunctionIndex);

pub const Instruction = packed struct {
    opcode: OpCode,
    data: OpData,
};

pub const OpCode = op_code: {
    var fields: []const std.builtin.Type.EnumField = &[0]std.builtin.Type.EnumField{};

    var i: u8 = 0;
    for (ISA.Instructions) |category| {
        for (category.kinds) |kind| {
            var j: u8 = 1;

            for (kind.instructions) |instr| {
                fields = fields ++ [1]std.builtin.Type.EnumField { .{
                    .name = (if (instr.prefix.len > 0) instr.prefix ++ "_" else "") ++ kind.base_name ++ (if (instr.suffix.len > 0) "_" ++ instr.suffix else ""),
                    .value = (@as(u16, i) << 8) | @as(u16, j),
                } };

                j += 1;
            }

            i += 1;
        }
    }

    break :op_code @Type(.{ .@"enum" = .{
        .tag_type = u16,
        .fields = fields,
        .decls = &[0]std.builtin.Type.Declaration {},
        .is_exhaustive = true,
    } });
};

pub const OpData = op_data: {
    const opCodeFields = @typeInfo(OpCode).@"enum".fields;
    var fields: []const std.builtin.Type.UnionField = &[0]std.builtin.Type.UnionField{};

    var i = 0;

    for (ISA.Instructions) |category| {
        for (category.kinds) |kind| {
            for (kind.instructions) |instr| {
                var operands: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

                if (instr.operands.len > 0) {
                    var size = 0;
                    for (instr.operands, 0..) |operand, o| {
                        const opType = switch (operand) {
                            .register => RegisterIndex,
                            .byte => u8,
                            .short => u16,
                            .immediate => u32,
                            .handler_set_index => HandlerSetIndex,
                            .evidence_index => EvidenceIndex,
                            .global_index => GlobalIndex,
                            .upvalue_index => UpvalueIndex,
                            .function_index => FunctionIndex,
                            .block_index => BlockIndex,
                        };

                        size += @bitSizeOf(opType);

                        operands = operands ++ [1]std.builtin.Type.StructField { .{
                            .name = std.fmt.comptimePrint("{}", .{o}),
                            .type = opType,
                            .is_comptime = false,
                            .default_value = null,
                            .alignment = 0,
                        } };
                    }

                    if (size > 48) {
                        @compileError("Operand set size too large in instruction `"
                            ++ opCodeFields[i].name ++ "`");
                    }

                    const backingType = std.meta.Int(.unsigned, size);
                    fields = fields ++ [1]std.builtin.Type.UnionField { .{
                        .name = opCodeFields[i].name,
                        .type = @Type(.{ .@"struct" = .{
                            .layout = .@"packed",
                            .backing_integer = backingType,
                            .fields = operands,
                            .decls = &[0]std.builtin.Type.Declaration {},
                            .is_tuple = false,
                        } }),
                        .alignment = @alignOf(backingType),
                    } };
                } else {
                    fields = fields ++ [1]std.builtin.Type.UnionField { .{
                        .name = opCodeFields[i].name,
                        .type = void,
                        .alignment = 0,
                    } };
                }

                i += 1;
            }
        }
    }

    break :op_data @Type(.{ .@"union" = .{
        .layout = .@"packed",
        .tag_type = null,
        .fields = fields,
        .decls = &[0]std.builtin.Type.Declaration {},
    } });
};


pub const Function = struct {
    num_arguments: RegisterIndex,
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


pub const Program = struct {
    globals: []const [*]u8,
    global_memory: []u8,
    functions: []const Function,
    handler_sets: []const HandlerSet,
    main: FunctionIndex,

    pub fn deinit(self: Program, allocator: std.mem.Allocator) void {
        allocator.free(self.globals);

        allocator.free(self.global_memory);

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

pub fn deinit(self: Bytecode, allocator: std.mem.Allocator) void {
    allocator.free(self.blocks);
    allocator.free(self.instructions);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
