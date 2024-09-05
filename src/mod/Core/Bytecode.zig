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
pub const ValueSize = u16;
pub const ValueAlignment = u16;
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
    local_types: []Type,
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
         , \\call the function at the address stored in `fun`,
           \\using the registers `arg_regs` as arguments,
           \\and placing the result in `ret_reg`
         , struct {
            fun: Operand,
            ret_reg: Register,
            arg_regs: []Register,
           }
        },

        .{ "prompt"
         , \\prompt the given `evidence`,
           \\using the registers `arg_regs` as arguments,
           \\and placing the result in `ret_reg`
         , struct {
            evidence: EvidenceIndex,
            ret_reg: Register,
            arg_regs: []Register,
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
           \\if the condition in `cond` is non-zero
         , struct {
            block: BlockIndex,
            cond: Operand,
           }
        },
        .{ "unless"
         , \\enter the designated `block`,
           \\if the condition in `cond` is zero
         , struct {
            block: BlockIndex,
            cond: Operand,
           }
        },
        .{ "loop"
         , \\enter the designated `block`, looping
         , struct {
            block: BlockIndex
           }
        },
        .{ "break_imm"
         , \\exit the designated block,
           \\copy the immediate value `imm`,
           \\and place the result in the block's yield register
         , struct {
            block: BlockIndex,
            imm: Bytecode.ConstantIndex,
           }
        },
        .{ "break_if_imm"
         , \\exit the designated block,
           \\if the condition in `cond` is non-zero
           \\copy the immediate value `imm`,
           \\and place the result in the block's yield register
         , struct {
            block: BlockIndex,
            imm: Bytecode.ConstantIndex,
            cond: Operand,
           }
        },
        .{ "reiter"
         , \\restart the designated loop block
         , struct {
            block: BlockIndex,
           }
        },
        .{ "reiter_if"
         , \\restart the designated loop block,
           \\if the condition in `cond` is non-zero
         , struct {
            block: BlockIndex,
            cond: Operand,
           }
        },
    },

    .control_flow_v = .{
        .{ "block"
         , \\enter the designated `block`
         , struct {
            block: BlockIndex
           }
         , \\place the result of the block in `yield`
         , struct {
            yield: Operand,
           }
        },
        .{ "with"
         , \\enter the designated `block`,
           \\using the `handler_set` to handle effects
         , struct {
            handler_set: HandlerSetIndex,
            block: BlockIndex,
           }
         , \\place the result of the block in `yield`
         , struct {
            yield: Operand,
           }
        },
        .{ "if_else"
         , \\enter the `then_block`,
           \\if the condition in `cond` is non-zero
           \\otherwise enter the `else_block`
         , struct {
            then_block: BlockIndex,
            else_block: BlockIndex,
            cond: Operand,
           }
         , \\place the result of the block in `yield`,
         , struct {
            yield: Operand,
           }
        },
        .{ "case"
         , \\enter the indexed `block`,
           \\based on the value in `case_reg`
         , struct {
            case_reg: Register,
            blocks: []BlockIndex,
           }
         , \\place the result of the block in `yield`
         , struct {
            yield: Operand,
           }
        },
        .{ "break"
         , \\exit the designated `block`
         , struct {
            block: BlockIndex
           }
         , \\copy the value in `src`,
           \\placing the result in the block's yield register
         , struct {
            src: Operand
           }
        },
        .{ "break_if"
         , \\exit the designated `block`,
           \\if the condition in `cond` is non-zero
         , struct {
            block: BlockIndex,
            cond: Operand,
           }
         , \\copy the value in `src`,
           \\placing the result in the block's yield register
         , struct {
            src: Operand
           }
        },
    },

    .memory = .{
        .{ "addr_of_upvalue"
         , \\take the address of the upvalue register `src`,
           \\and store the result in `dst`
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
        .{ "addr_of"
         , \\take the address of `src`,
           \\offset it by `offset`,
           \\and store the result in `dst`
         , struct {
            offset: RegisterLocalOffset,
            src: Operand,
            dst: Operand,
           }
        },
        .{ "load"
         , \\copy the value from the address stored in `addr`,
           \\and store the result in `dst`
         , struct {
            addr: Operand,
            dst: Operand,
           }
        },

        .{ "store"
         , \\copy the value from `src`
           \\and store the result at the address stored in `addr`
         , struct {
            src: Operand,
            addr: Operand,
           }
        },

        .{ "load_imm"
         , \\copy the immediate value `imm`
           \\and store the result in `dst`
         , struct {
            imm: Bytecode.ConstantIndex,
            dst: Operand,
           }
        },

        .{ "store_imm"
         , \\copy the immediate value `imm`
           \\and store the result at the address stored in `addr`
         , struct {
            imm: Bytecode.ConstantIndex,
            addr: Operand,
           }
        },
    },

    .arithmetic = .{
        .{ "add"
         , \\load two values from `lhs` and `rhs`,
           \\perform addition,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "sub"
         , \\load two values from `lhs` and `rhs`,
           \\perform subtraction,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "mul"
         , \\load two values from `lhs` and `rhs`,
           \\perform division,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "div"
         , \\load two values from `lhs` and `rhs`,
           \\perform division,
           \\and store the result in `dst`
         , intFloat(.different)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "rem"
         , \\load two values from `lhs` and `rhs`,
           \\perform remainder division,
           \\and store the result in `dst`
         , intFloat(.different)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "neg"
         , \\load a value from `val`,
           \\perform negative,
           \\and store the result in `dst`
         , intFloat(.only_signed)
         , struct {
            val: Operand,
            dst: Operand,
           }
        },

        .{ "bitnot"
         , \\load a value from `val`,
           \\perform bitwise not,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            val: Operand,
            dst: Operand,
           }
        },

        .{ "bitand"
         , \\load two values from `lhs` and `rhs`,
           \\perform bitwise and,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "bitor"
         , \\load two values from `lhs` and `rhs`,
           \\perform bitwise or,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "bitxor"
         , \\load two values from `lhs` and `rhs`,
           \\perform bitwise xor,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "shiftl"
         , \\load two values from `lhs` and `rhs`,
           \\perform bitwise left shift,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "shiftar"
         , \\load two values from `lhs` and `rhs`,
           \\perform bitwise arithmetic right shift,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "shiftlr"
         , \\load two values from `lhs` and `rhs`,
           \\perform bitwise logical right shift,
           \\and store the result in `dst`
         , intOnly(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "eq"
         , \\load two values from `lhs` and `rhs`,
           \\perform equality comparison,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "ne"
         , \\load two values from `lhs` and `rhs`,
           \\perform inequality comparison,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "lt"
         , \\load two values from `lhs` and `rhs`,
           \\perform less than comparison,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "le"
         , \\load two values from `lhs` and `rhs`,
           \\perform less than or equal comparison,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "gt"
         , \\load two values from `lhs` and `rhs`,
           \\perform greater than comparison,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "ge"
         , \\load two values from `lhs` and `rhs`,
           \\perform greater than or equal comparison,
           \\and store the result in `dst`
         , intFloat(.same)
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },
    },

    .boolean = .{
        .{ "b_and"
         , \\load two values from `lhs` and `rhs`,
           \\perform logical and,
           \\and store the result in `dst`
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "b_or"
         , \\load two values from `lhs` and `rhs`,
           \\perform logical or,
           \\and store the result in `dst`
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "b_xor"
         , \\load two values from `lhs` and `rhs`,
           \\perform logical xor,
           \\and store the result in `dst`
         , struct {
            lhs: Operand,
            rhs: Operand,
            dst: Operand,
           }
        },

        .{ "b_not"
         , \\load a value from `val`,
           \\perform logical not,
           \\and store the result in `dst`
         , struct {
            val: Operand,
            dst: Operand,
           }
        },
    },

    .size_cast_int = .{
        .{ "u_ext"
         , \\load a value from `src`,
           \\perform zero extension,
           \\and store the result in `dst`
         , .up
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
        .{ "s_ext"
         , \\load a value from `src`,
           \\perform sign extension,
           \\and store the result in `dst`
         , .up
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
        .{ "i_trunc"
         , \\load a value from `src`,
           \\perform sign extension,
           \\and store the result in `dst`
         , .down
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
    },

    .size_cast_float = .{
        .{ "f_ext"
         , \\load a value from `src`,
           \\perform floating point extension,
           \\and store the result in `dst`
         , .up
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
        .{ "f_trunc"
         , \\load a value from `src`,
           \\perform floating point truncation,
           \\and store the result in `dst`
         , .down
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
    },

    .int_float_cast = .{
        .{ "to"
         , \\load a value from `src`,
           \\perform int/float conversion,
           \\and store the result in `dst`
         , struct {
            src: Operand,
            dst: Operand,
           }
        },
    },
};


const ArithmeticValueInfo = union(enum) {
    none: void,
    float_only: void,
    int_only: SignVariance,
    int_float: SignVariance,
    const SignVariance = enum {
        same,
        different,
        only_unsigned,
        only_signed,
    };
};

fn intOnly(signVariance: ArithmeticValueInfo.SignVariance) ArithmeticValueInfo {
    return .{ .int_only = signVariance };
}

fn floatOnly() ArithmeticValueInfo {
    return .float_only;
}

fn intFloat(signVariance: ArithmeticValueInfo.SignVariance) ArithmeticValueInfo {
    return .{ .int_float = signVariance };
}

const Ops = ops: {
    const TagType = OpCodeIndex;
    const max = std.math.maxInt(TagType);

    const FLOAT_SIZE = [2]u8 { 32, 64 };
    const INTEGER_SIZE = [4]u8 { 8, 16, 32, 64 };
    const SIGNEDNESS = [2]TextUtils.Char { 'u', 's' };

    const Tools = struct {
        fn makeFloatFields(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, name: [:0]const u8, operands: anytype) void {
            for (FLOAT_SIZE) |size| {
                const fieldName = std.fmt.comptimePrint("f_{s}{}", .{name, size});
                enumFields[id.*] = .{
                    .name = fieldName,
                    .value = id.*,
                };
                const T = @TypeOf(operands);
                unionFields[id.*] = .{
                    .name = fieldName,
                    .type = T,
                    .alignment = @alignOf(T),
                };
                id.* += 1;
            }
        }

        fn makeIntField(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, fieldName: [:0]const u8, operands: anytype) void {
            enumFields[id.*] = .{
                .name = fieldName,
                .value = id.*,
            };
            const T = @TypeOf(operands);
            unionFields[id.*] = .{
                .name = fieldName,
                .type = T,
                .alignment = @alignOf(T),
            };
            id.* += 1;
        }

        fn makeIntFields(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, name: [:0]const u8, operands: anytype, signVariance: ArithmeticValueInfo.SignVariance) void {
            for (INTEGER_SIZE) |size| {
                switch (signVariance) {
                    .different => {
                        for (SIGNEDNESS) |sign| {
                            makeIntField(enumFields, unionFields, id, std.fmt.comptimePrint("{u}_{s}{}", .{sign, name, size}), operands);
                        }
                    },
                    .same => {
                        makeIntField(enumFields, unionFields, id, std.fmt.comptimePrint("i_{s}{}", .{name, size}), operands);
                    },
                    .only_unsigned => {
                        makeIntField(enumFields, unionFields, id, std.fmt.comptimePrint("u_{s}{}", .{name, size}), operands);
                    },
                    .only_signed => {
                        makeIntField(enumFields, unionFields, id, std.fmt.comptimePrint("s_{s}{}", .{name, size}), operands);
                    }
                }
            }
        }
    };

    var enumFields = [1]std.builtin.Type.EnumField {undefined} ** max;
    var unionFields = [1]std.builtin.Type.UnionField {undefined} ** max;

    var id: usize = 0;

    for (std.meta.fieldNames(@TypeOf(InstructionPrototypes))) |categoryName| {
        const category = @field(InstructionPrototypes, categoryName);

        if (std.mem.eql(u8, categoryName, "arithmetic")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const multipliers: ArithmeticValueInfo = proto[2];
                const operands = proto[3];

                switch (multipliers) {
                    .none => {
                        enumFields[id] = .{
                            .name = name,
                            .value = id,
                        };
                        id += 1;
                    },
                    .int_only => |signVariance| {
                        Tools.makeIntFields(&enumFields, &unionFields, &id, name, operands, signVariance);
                    },
                    .float_only => {
                        Tools.makeFloatFields(&enumFields, &unionFields, &id, name, operands);
                    },
                    .int_float => |signVariance| {
                        Tools.makeIntFields(&enumFields, &unionFields, &id, name, operands, signVariance);
                        Tools.makeFloatFields(&enumFields, &unionFields, &id, name, operands);
                    }
                }
            }
        } else if (std.mem.endsWith(u8, categoryName, "_v")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const operands = proto[2];
                // const vDoc = proto[3];
                const vOperands = proto[4];

                enumFields[id] = .{
                    .name = name,
                    .value = id,
                };
                const OpT = @TypeOf(operands);
                unionFields[id] = .{
                    .name = name,
                    .type = OpT,
                    .alignment = @alignOf(OpT),
                };
                id += 1;

                const fieldName = std.fmt.comptimePrint("{s}_v", .{name});
                enumFields[id] = .{
                    .name = fieldName,
                    .value = id,
                };
                const VT = TypeUtils.StructConcat(.{operands, vOperands});
                unionFields[id] = .{
                    .name = fieldName,
                    .type = VT,
                    .alignment = @alignOf(VT),
                };
                id += 1;
            }
        } else if (std.mem.startsWith(u8, categoryName, "size_cast")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const order: enum { up, down } = proto[2];
                const operands = proto[3];

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
                                const fieldName = std.fmt.comptimePrint("{s}{}x{}", .{name, xsize, ysize});
                                enumFields[id] = .{
                                    .name = fieldName,
                                    .value = id,
                                };
                                const T = @TypeOf(operands);
                                unionFields[id] = .{
                                    .name = fieldName,
                                    .type = T,
                                    .alignment = @alignOf(T),
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
                                const fieldName = std.fmt.comptimePrint("{s}{}x{}", .{name, xsize, ysize});
                                enumFields[id] = .{
                                    .name = fieldName,
                                    .value = id,
                                };
                                const T = @TypeOf(operands);
                                unionFields[id] = .{
                                    .name = fieldName,
                                    .type = T,
                                    .alignment = @alignOf(T),
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
            const operands = proto[2];

            for (SIGNEDNESS) |sign| {
                for (INTEGER_SIZE) |int_size| {
                    for (FLOAT_SIZE) |float_size| {
                        const fieldNameA = std.fmt.comptimePrint("{u}{}_{s}_f{}", .{sign, int_size, name, float_size});
                        enumFields[id] = .{
                            .name = fieldNameA,
                            .value = id,
                        };
                        const T = @TypeOf(operands);
                        unionFields[id] = .{
                            .name = fieldNameA,
                            .type = T,
                            .alignment = @alignOf(T),
                        };
                        id += 1;

                        const fieldNameB = std.fmt.comptimePrint("{s}_f{}_{u}{}", .{name, float_size, sign, int_size});
                        enumFields[id] = .{
                            .name = fieldNameB,
                            .value = id,
                        };
                        unionFields[id] = .{
                            .name = fieldNameB,
                            .type = T,
                            .alignment = @alignOf(T),
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
                const operands = proto[2];

                enumFields[id] = .{
                    .name = name,
                    .value = id,
                };
                const OpT = @TypeOf(operands);
                unionFields[id] = .{
                    .name = name,
                    .type = OpT,
                    .alignment = @alignOf(OpT),
                };
                id += 1;
            }
        }
    }

    const OpCodeEnum = @Type(.{ .@"enum" = .{
        .tag_type = TagType,
        .fields = enumFields[0..id],
        .decls = &[0]std.builtin.Type.Declaration{},
        .is_exhaustive = true,
    }});

    const OpUnion = @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = OpCodeEnum,
        .fields = unionFields[0..id],
        .decls = &[0]std.builtin.Type.Declaration{},
    }});

    break :ops .{
        .Op = OpUnion,
        .OpCode = OpCodeEnum,
    };
};

pub const OpCode = Ops.OpCode;
pub const Op = Ops.Op;

test {
    for (std.meta.fieldNames(OpCode)) |name| {
        std.debug.print("`{s}`\n", .{name});
    }

    const fields = std.meta.fieldNames(@TypeOf((Op { .break_v = undefined }).break_v));
    for (fields) |name| {
        std.debug.print("`{s}`\n", .{name});
    }

    const op: Op = .{ .break_v = .{ .block = 0, .src = .{ .register = .r0, .offset = 0 } } };

    std.debug.print("{}\n", .{op});
}
