const std = @import("std");

const TextUtils = @import("ZigTextUtils");
const TypeUtils = @import("ZigTypeUtils");

const Bytecode = @import("root.zig");
const Operand = Bytecode.Operand;
const Register = Bytecode.Register;
const RegisterLocalOffset = Bytecode.RegisterLocalOffset;
const BlockIndex = Bytecode.BlockIndex;
const EvidenceIndex = Bytecode.EvidenceIndex;
const ConstantIndex = Bytecode.ConstantIndex;
const HandlerSetIndex = Bytecode.HandlerSetIndex;

const OpCodeIndex = u8;

const InstructionPrototypes = .{
    .basic = .{
        .{ "trap"
         , \\triggers a trap if execution reaches it
         , void
        },

        .{ "nop"
         , \\no operation, does nothing
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
            arg_regs: []const Register,
           }
        },

        .{ "prompt"
         , \\prompt the given `evidence`,
           \\using the registers `arg_regs` as arguments,
           \\and placing the result in `ret_reg`
         , struct {
            evidence: EvidenceIndex,
            ret_reg: Register,
            arg_regs: []const Register,
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
            imm: ConstantIndex,
           }
        },
        .{ "break_if_imm"
         , \\exit the designated block,
           \\if the condition in `cond` is non-zero
           \\copy the immediate value `imm`,
           \\and place the result in the block's yield register
         , struct {
            block: BlockIndex,
            imm: ConstantIndex,
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
            blocks: []const BlockIndex,
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
            imm: ConstantIndex,
            dst: Operand,
           }
        },

        .{ "store_imm"
         , \\copy the immediate value `imm`
           \\and store the result at the address stored in `addr`
         , struct {
            imm: ConstantIndex,
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

pub const Op = ops: {
    const TagType = OpCodeIndex;
    const max = std.math.maxInt(TagType);

    const FLOAT_SIZE = [2]u8 { 32, 64 };
    const INTEGER_SIZE = [4]u8 { 8, 16, 32, 64 };
    const SIGNEDNESS = [2]TextUtils.Char { 'u', 's' };

    const Tools = struct {
        fn makeFloatFields(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, name: [:0]const u8, comptime operands: type) void {
            for (FLOAT_SIZE) |size| {
                const fieldName = std.fmt.comptimePrint("f_{s}{}", .{name, size});
                enumFields[id.*] = .{
                    .name = fieldName,
                    .value = id.*,
                };
                unionFields[id.*] = .{
                    .name = fieldName,
                    .type = operands,
                    .alignment = @alignOf(operands),
                };
                id.* += 1;
            }
        }

        fn makeIntField(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, fieldName: [:0]const u8, comptime operands: type) void {
            enumFields[id.*] = .{
                .name = fieldName,
                .value = id.*,
            };
            unionFields[id.*] = .{
                .name = fieldName,
                .type = operands,
                .alignment = @alignOf(operands),
            };
            id.* += 1;
        }

        fn makeIntFields(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, name: [:0]const u8, comptime operands: type, signVariance: ArithmeticValueInfo.SignVariance) void {
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
                unionFields[id] = .{
                    .name = name,
                    .type = operands,
                    .alignment = @alignOf(operands),
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
                                unionFields[id] = .{
                                    .name = fieldName,
                                    .type = operands,
                                    .alignment = @alignOf(operands),
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
                                unionFields[id] = .{
                                    .name = fieldName,
                                    .type = operands,
                                    .alignment = @alignOf(operands),
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
                        unionFields[id] = .{
                            .name = fieldNameA,
                            .type = operands,
                            .alignment = @alignOf(operands),
                        };
                        id += 1;

                        const fieldNameB = std.fmt.comptimePrint("{s}_f{}_{u}{}", .{name, float_size, sign, int_size});
                        enumFields[id] = .{
                            .name = fieldNameB,
                            .value = id,
                        };
                        unionFields[id] = .{
                            .name = fieldNameB,
                            .type = operands,
                            .alignment = @alignOf(operands),
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
                unionFields[id] = .{
                    .name = name,
                    .type = operands,
                    .alignment = @alignOf(operands),
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

    break :ops OpUnion;
};

test {

const OpCode = @typeInfo(Op).@"union".tag_type.?;
    const isa_snapshot =
        "{ trap, nop, call, prompt, return, terminate, when, unless, loop, break_imm, break_if_imm, reiter, reiter_if, block, block_v, with, with_v, if_else, if_else_v, case, case_v, break, break_v, break_if, break_if_v, addr_of_upvalue, addr_of, load, store, load_imm, store_imm, i_add8, i_add16, i_add32, i_add64, f_add32, f_add64, i_sub8, i_sub16, i_sub32, i_sub64, f_sub32, f_sub64, i_mul8, i_mul16, i_mul32, i_mul64, f_mul32, f_mul64, u_div8, s_div8, u_div16, s_div16, u_div32, s_div32, u_div64, s_div64, f_div32, f_div64, u_rem8, s_rem8, u_rem16, s_rem16, u_rem32, s_rem32, u_rem64, s_rem64, f_rem32, f_rem64, s_neg8, s_neg16, s_neg32, s_neg64, f_neg32, f_neg64, i_bitnot8, i_bitnot16, i_bitnot32, i_bitnot64, i_bitand8, i_bitand16, i_bitand32, i_bitand64, i_bitor8, i_bitor16, i_bitor32, i_bitor64, i_bitxor8, i_bitxor16, i_bitxor32, i_bitxor64, i_shiftl8, i_shiftl16, i_shiftl32, i_shiftl64, i_shiftar8, i_shiftar16, i_shiftar32, i_shiftar64, i_shiftlr8, i_shiftlr16, i_shiftlr32, i_shiftlr64, i_eq8, i_eq16, i_eq32, i_eq64, f_eq32, f_eq64, i_ne8, i_ne16, i_ne32, i_ne64, f_ne32, f_ne64, i_lt8, i_lt16, i_lt32, i_lt64, f_lt32, f_lt64, i_le8, i_le16, i_le32, i_le64, f_le32, f_le64, i_gt8, i_gt16, i_gt32, i_gt64, f_gt32, f_gt64, i_ge8, i_ge16, i_ge32, i_ge64, f_ge32, f_ge64, b_and, b_or, b_xor, b_not, u_ext8x16, u_ext8x32, u_ext8x64, u_ext16x32, u_ext16x64, u_ext32x64, s_ext8x16, s_ext8x32, s_ext8x64, s_ext16x32, s_ext16x64, s_ext32x64, i_trunc64x32, i_trunc64x16, i_trunc64x8, i_trunc32x16, i_trunc32x8, i_trunc16x8, f_ext32x64, f_trunc64x32, u8_to_f32, to_f32_u8, u8_to_f64, to_f64_u8, u16_to_f32, to_f32_u16, u16_to_f64, to_f64_u16, u32_to_f32, to_f32_u32, u32_to_f64, to_f64_u32, u64_to_f32, to_f32_u64, u64_to_f64, to_f64_u64, s8_to_f32, to_f32_s8, s8_to_f64, to_f64_s8, s16_to_f32, to_f32_s16, s16_to_f64, to_f64_s16, s32_to_f32, to_f32_s32, s32_to_f64, to_f64_s32, s64_to_f32, to_f32_s64, s64_to_f64, to_f64_s64 }";

    try std.testing.expectFmt(
        isa_snapshot,
        "{s}", .{std.meta.fieldNames(OpCode)}
    );

    try std.testing.expectFmt(
        isa_snapshot,
        "{s}", .{std.meta.fieldNames(Op)}
    );

    const op: Op = .{ .break_v = .{ .block = 10, .src = .{ .register = .r245, .offset = 440 } } };
    _ = op;
}
