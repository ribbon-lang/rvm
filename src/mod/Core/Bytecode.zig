//!

const std = @import("std");

const Core = @import("root.zig");
const Fiber = Core.Fiber;

const Bytecode = @This();

instructions: []u8,
blocks: []Block,

pub const OpCode = enum(u8) {};

pub const InstructionPointer = u24;
pub const InstructionPointerOffset = u16;
pub const BlockIndex = u16;
pub const Register = u8;
pub const RegisterLocalOffset = u16;
pub const RegisterBaseOffset = u24;
pub const LayoutTableSize = RegisterBaseOffset;
pub const OperandSize = u16;
pub const OperandAlignment = u16;
pub const FunctionIndex = u16;
pub const HandlerSetIndex = u16;
pub const HandlerIndex = u8;

pub const MAX_REGISTERS = std.math.maxInt(Register);

pub const Argument = packed struct {
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
           with = 0x02,    with_v = 0x12,

        loop = 0x03,
    };
};

pub const Layout = struct {
    size: OperandSize,
    alignment: OperandAlignment,
};

pub const LayoutTable = struct {
    layouts: []Layout,
    local_offsets: []RegisterBaseOffset,
    size: LayoutTableSize,
    alignment: OperandAlignment,
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

    pub const Native = *const fn (*Fiber) callconv(.C) NativeControl;

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


pub const Program = struct {
    functions: []Function,
    handlerSets: []HandlerSet,
    main: ?FunctionIndex,
};

pub const Location = struct {
    function: FunctionIndex,
    block: BlockIndex,
    offset: InstructionPointerOffset,
};
