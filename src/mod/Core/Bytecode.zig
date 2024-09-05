//!

const std = @import("std");

const TextUtils = @import("ZigTextUtils");
const TypeUtils = @import("ZigTypeUtils");

const Core = @import("root.zig");
const Fiber = Core.Fiber;

const Bytecode = @This();

instructions: []u8,
blocks: []Block,


pub const InstructionPointer = u24;
pub const InstructionPointerOffset = u16;
pub const BlockIndex = u16;
pub const RegisterLocalOffset = u16;
pub const RegisterBaseOffset = u24;
pub const LayoutTableSize = RegisterBaseOffset;
pub const OperandSize = u16;
pub const OperandAlignment = u16;
pub const FunctionIndex = u16;
pub const HandlerSetIndex = u16;
pub const HandlerIndex = u8;
pub const TypeIndex = u16;
pub const RegisterIndex = u8;
pub const OpCodeIndex = u8;
pub const GlobalIndex = u16;
pub const ConstantIndex = u16;
pub const EvidenceIndex = u16;


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
           case = 0x02,    case_v = 0x12,
           with = 0x03,    with_v = 0x13,

           when = 0x04,
         unless = 0x05,
           loop = 0x06,
    };
};

pub const Layout = struct {
    size: OperandSize,
    alignment: OperandAlignment,
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
    local_types: []Type,
    local_layouts: []Layout,
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

const ArithmeticOperandInfo = union(enum) {
    none: void,
    float_only: void,
    int_only: SignVariance,
    int_float: SignVariance,
    pub const SignVariance = enum {
        same,
        different,
        only_unsigned,
        only_signed,
    };
};

fn intOnly(signVariance: ArithmeticOperandInfo.SignVariance) ArithmeticOperandInfo {
    return .{ .int_only = signVariance };
}

fn floatOnly() ArithmeticOperandInfo {
    return .float_only;
}

fn intFloat(signVariance: ArithmeticOperandInfo.SignVariance) ArithmeticOperandInfo {
    return .{ .int_float = signVariance };
}

const InstructionPrototypes = .{
    .basic = .{
        .{ "unreachable"
         , \\triggers a trap if execution reaches it
         , void
        },

        .{ "nop"
         , \\no-op, does nothing
         , void
        },
    },

    .functional = .{
        .{ "call"
         , \\call the function at the address stored in `fun_reg`,
           \\using the registers `arg_regs` as arguments,
           \\and placing the result in `ret_reg`
         , .{ .fun_reg = Register, .ret_reg = Register
            , .arg_regs = []Register
            }
        },

        .{ "prompt"
         , \\prompt the given `evidence`,
           \\using the registers `arg_regs` as arguments,
           \\and placing the result in `ret_reg`
         , .{ .evidence = EvidenceIndex
            , .ret_reg = Register
            , .arg_regs = []Register
            }
        },

        .{ "return"
         , \\return control from the current function
         , void
        },

        .{ "terminate"
         , \\terminate the current handler's with block
         , void
        },
    },

    .control_flow = .{
        .{ "when"
         , \\enter the designated `block`,
           \\if the condition in `cond_reg` is non-zero
         , .{ .block = BlockIndex
            , .cond_reg = Register
            }
        },
        .{ "unless"
         , \\enter the designated `block`,
           \\if the condition in `cond_reg` is zero
         , .{ .block = BlockIndex
            , .cond_reg = Register
            }
        },
        .{ "loop"
         , \\enter the designated `block`, looping
         , .{ .block = BlockIndex }
        },
        .{ "break_imm"
         , \\exit the designated block,
           \\copy the immediate value `imm`,
           \\and place the result in the block's yield register
         , .{ .block = BlockIndex
            , .imm = Bytecode.ConstantIndex
            }
        },
        .{ "break_if_imm"
         , \\exit the designated block,
           \\if the condition in `cond_reg` is non-zero
           \\copy the immediate value `imm`,
           \\and place the result in the block's yield register
         , .{ .block = BlockIndex
            , .imm = Bytecode.ConstantIndex
            , .cond_reg = Register
            }
        },
        .{ "reiter"
         , \\restart the designated loop block
         , .{ .block = BlockIndex
            }
        },
        .{ "reiter_if"
         , \\restart the designated loop block,
           \\if the condition in `cond_reg` is non-zero
         , .{ .block = BlockIndex
            , .cond_reg = Register
            }
        },
    },

    .control_flow_v = .{
        .{ "block"
         , \\enter the designated `block`
         , .{ .block = BlockIndex }
         , \\place the result of the block in `yield_reg`,
         , .{ .yield_reg = Register
            }
        },
        .{ "with"
         , \\enter the designated `block`,
           \\using the `handler_set` to handle effects
         , .{ .handler_set = HandlerSetIndex
            , .block = BlockIndex
            }
         , \\place the result of the block in `yield_reg`
         , .{ .yield_reg = Register
            }
        },
        .{ "if_else"
         , \\enter the `then_block`,
           \\if the condition in `cond_reg` is non-zero
           \\otherwise enter the `else_block`
         , .{ .then_block = BlockIndex
            , .else_block = BlockIndex
            , .cond_reg = Register
            }
         , \\place the result of the block in `yield_reg`,
         , .{ .yield_reg = Register
            }
        },
        .{ "case"
         , \\enter the indexed `block`,
           \\based on the value in `case_reg`
         , .{ .case_reg = Register
            , .blocks = []BlockIndex
            }
         , \\place the result of the block in `yield_reg`
         , .{ .yield_reg = Register
            }
        },
        .{ "break"
         , \\exit the designated `block`
         , .{ .block = BlockIndex }
         , \\copy the value in `src_reg`,
           \\placing the result in the block's yield register
         , .{ .src_reg = Register }
        },
        .{ "break_if"
         , \\exit the designated `block`,
           \\if the condition in `cond_reg` is non-zero
         , .{ .block = BlockIndex
            , .cond_reg = Register
            }
         , \\copy the value in `src_reg`,
           \\placing the result in the block's yield register
         , .{ .src_reg = Register }
        },
    },

    .memory = .{
        .{ "addr_of_upvalue"
         , \\take the address of the upvalue register `src_reg`,
           \\and store the result in `dst_reg`
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
        },
        .{ "addr_of"
         , \\take the address of `src_reg`,
           \\offset it by `offset`,
           \\and store the result in `dst_reg`
         , .{ .offset = RegisterLocalOffset
            , .src_reg = Register
            , .dst_reg = Register
            }
        },
        .{ "load"
         , \\copy the value from the address stored in `addr_reg`,
           \\and store the result in `dst_reg`
         , .{ .addr_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "store"
         , \\copy the value from `src_reg`
           \\and store the result at the address stored in `addr_reg`
         , .{ .src_reg = Register
            , .addr_reg = Register
            }
        },

        .{ "load_imm"
         , \\copy the immediate value `imm`
           \\and store the result in `dst_reg`
         , .{ .imm = Bytecode.ConstantIndex
            , .dst_reg = Register
            }
        },

        .{ "store_imm"
         , \\copy the immediate value `imm`
           \\and store the result at the address stored in `addr_reg`
         , .{ .imm = Bytecode.ConstantIndex
            , .addr_reg = Register
            }
         }
    },

    .arithmetic = .{
        .{ "add"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform addition,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "sub"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform subtraction,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "mul"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform division,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "div"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform division,
           \\and store the result in `dst_reg`
         , intFloat(.different)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "rem"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform remainder division,
           \\and store the result in `dst_reg`
         , intFloat(.different)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "neg"
         , \\load a value from `lhs_reg`,
           \\perform negative,
           \\and store the result in `dst_reg`
         , intFloat(.only_signed)
         , .{ .val_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "bitnot"
         , \\load a value from `lhs_reg`,
           \\perform bitwise not,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .val_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "bitand"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform bitwise and,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "bitor"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform bitwise or,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "bitxor"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform bitwise xor,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "shiftl"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform bitwise left shift,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "shiftar"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform bitwise arithmetic right shift,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "shiftlr"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform bitwise logical right shift,
           \\and store the result in `dst_reg`
         , intOnly(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "eq"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform equality comparison,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "ne"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform inequality comparison,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "lt"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform less than comparison,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "le"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform less than or equal comparison,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "gt"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform greater than comparison,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "ge"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform greater than or equal comparison,
           \\and store the result in `dst_reg`
         , intFloat(.same)
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },
    },

    .boolean = .{
        .{ "b_and"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform logical and,
           \\and store the result in `dst_reg`
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "b_or"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform logical or,
           \\and store the result in `dst_reg`
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "b_xor"
         , \\load two values from `lhs_reg` and `rhs_reg`,
           \\perform logical xor,
           \\and store the result in `dst_reg`
         , .{ .lhs_reg = Register, .rhs_reg = Register
            , .dst_reg = Register
            }
        },

        .{ "b_not"
         , \\load a value from `lhs_reg`,
           \\perform logical not,
           \\and store the result in `dst_reg`
         , .{ .val_reg = Register
            , .dst_reg = Register
            }
        },
    },

    .size_cast_int = .{
        .{ "u_ext"
         , \\load a value from `src_reg`,
           \\perform zero extension,
           \\and store the result in `dst_reg`
         , .up
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
        },
        .{ "s_ext"
         , \\load a value from `src_reg`,
           \\perform sign extension,
           \\and store the result in `dst_reg`
         , .up
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
        },
        .{ "i_trunc"
         , \\load a value from `src_reg`,
           \\perform sign extension,
           \\and store the result in `dst_reg`
         , .down
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
        },
    },

    .size_cast_float = .{
        .{ "f_ext"
         , \\load a value from `src_reg`,
           \\perform floating point extension,
           \\and store the result in `dst_reg`
         , .up
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
        },
        .{ "f_trunc"
         , \\load a value from `src_reg`,
           \\perform floating point truncation,
           \\and store the result in `dst_reg`
         , .down
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
        },
    },

    .int_float_cast = .{
        .{ "to"
         , \\load a value from `src_reg`,
           \\perform int/float conversion,
           \\and store the result in `dst_reg`
         , .{ .src_reg = Register
            , .dst_reg = Register
            }
         }
    },
};


const OpCode = op: {
    const TagType = OpCodeIndex;
    const max = std.math.maxInt(TagType);

    const FLOAT_SIZE = [2]u8 { 32, 64 };
    const INTEGER_SIZE = [4]u8 { 8, 16, 32, 64 };
    const SIGNEDNESS = [2]TextUtils.Char { 'u', 's' };

    const Tools = struct {
        fn makeFloatFields(fields: []std.builtin.Type.EnumField, id: *usize, name: []const u8) void {
            for (FLOAT_SIZE) |size| {
                fields[id.*] = .{
                    .name = std.fmt.comptimePrint("f_{s}{}", .{name, size}),
                    .value = id.*,
                };
                id.* += 1;
            }
        }

        fn makeIntFields(fields: []std.builtin.Type.EnumField, id: *usize, name: []const u8, signVariance: ArithmeticOperandInfo.SignVariance) void {
            for (INTEGER_SIZE) |size| {
                switch (signVariance) {
                    .different => {
                        for (SIGNEDNESS) |sign| {
                            fields[id.*] = .{
                                .name = std.fmt.comptimePrint("{u}_{s}{}", .{sign, name, size}),
                                .value = id.*,
                            };
                            id.* += 1;
                        }
                    },
                    .same => {
                        fields[id.*] = .{
                            .name = std.fmt.comptimePrint("i_{s}{}", .{name, size}),
                            .value = id.*,
                        };
                        id.* += 1;
                    },
                    .only_unsigned => {
                        fields[id.*] = .{
                            .name = std.fmt.comptimePrint("u_{s}{}", .{name, size}),
                            .value = id.*,
                        };
                        id.* += 1;
                    },
                    .only_signed => {
                        fields[id.*] = .{
                            .name = std.fmt.comptimePrint("s_{s}{}", .{name, size}),
                            .value = id.*,
                        };
                        id.* += 1;
                    }
                }
            }
        }
    };

    var fields = [1]std.builtin.Type.EnumField {undefined} ** max;

    var id: usize = 0;

    for (std.meta.fieldNames(@TypeOf(InstructionPrototypes))) |categoryName| {
        const category = @field(InstructionPrototypes, categoryName);

        if (std.mem.eql(u8, categoryName, "arithmetic")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const multipliers: ArithmeticOperandInfo = proto[2];
                // const operands = proto[3];

                switch (multipliers) {
                    .none => {
                        fields[id] = .{
                            .name = name,
                            .value = id,
                        };
                        id += 1;
                    },
                    .int_only => |signVariance| {
                        Tools.makeIntFields(&fields, &id, name, signVariance);
                    },
                    .float_only => {
                        Tools.makeFloatFields(&fields, &id, name);
                    },
                    .int_float => |signVariance| {
                        Tools.makeIntFields(&fields, &id, name, signVariance);
                        Tools.makeFloatFields(&fields, &id, name);
                    }
                }
            }
        } else if (std.mem.startsWith(u8, categoryName, "size_cast")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const order: enum { up, down } = proto[2];
                // const operands = proto[3];

                const SIZE =
                    if (std.mem.endsWith(u8, categoryName, "int")) INTEGER_SIZE
                    else if (std.mem.endsWith(u8, categoryName, "float")) FLOAT_SIZE
                    else {
                        @compileError("unknown size cast type");
                    };

                switch (order) {
                    .up => {
                        for (0..SIZE.len) |x| {
                            const xsize = SIZE[x];
                            for (x + 1..SIZE.len) |y| {
                                const ysize = SIZE[y];
                                fields[id] = .{
                                    .name = std.fmt.comptimePrint("{s}{}x{}", .{name, xsize, ysize}),
                                    .value = id,
                                };
                                id += 1;
                            }
                        }
                    },
                    .down => {
                        var x: usize = SIZE.len;
                        while (x > 0) : (x -= 1) {
                            const xsize = SIZE[x - 1];
                            var y: usize = x - 1;
                            while (y > 0) : (y -= 1) {
                                const ysize = SIZE[y - 1];
                                fields[id] = .{
                                    .name = std.fmt.comptimePrint("{s}{}x{}", .{name, xsize, ysize}),
                                    .value = id,
                                };
                                id += 1;
                            }
                        }
                    },
                }
            }
        } else if (std.mem.eql(u8, categoryName, "int_float_cast")) {
            const proto = category[0];

            const name = proto[0];
            // const doc = proto[1];
            // const operands = proto[2];

            for (SIGNEDNESS) |sign| {
                for (INTEGER_SIZE) |int_size| {
                    for (FLOAT_SIZE) |float_size| {
                        fields[id] = .{
                            .name = std.fmt.comptimePrint("{u}{}_{s}_f{}", .{sign, int_size, name, float_size}),
                            .value = id,
                        };
                        id += 1;

                        fields[id] = .{
                            .name = std.fmt.comptimePrint("f{}_{s}_{u}{}", .{float_size, name, sign, int_size}),
                            .value = id,
                        };
                        id += 1;
                    }
                }
            }
        } else {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                // const operands = proto[2];

                fields[id] = .{
                    .name = name,
                    .value = id,
                };
                id += 1;
            }
        }
    }

    break :op @Type(.{ .@"enum" = .{
        .tag_type = TagType,
        .fields = fields[0..id],
        .decls = &[0]std.builtin.Type.Declaration{},
        .is_exhaustive = true,
    }});
};

test {
    for (std.meta.fieldNames(OpCode)) |name| {
        std.debug.print("`{s}`\n", .{name});
    }
}
