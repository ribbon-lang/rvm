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
const FunctionIndex = Bytecode.FunctionIndex;
const HandlerSetIndex = Bytecode.HandlerSetIndex;

const OpCodeIndex = u8;

pub const InstructionPrototypes = .{
    .@"Basic" = .{
        .{ "trap"
         , \\triggers a trap if execution reaches it
         , void
        },

        .{ "nop"
         , \\no operation, does nothing
         , void
        },
    },

    .@"Control Flow" = .{
        .{ "when_nz"
         , \\if the 8-bit condition in `x` is non-zero:
           \\enter the block designated by `b`
           \\
           \\`b` is an absolute block index
         , BlockOperand
        },

        .{ "when_z"
         , \\if the 8-bit condition in `x` is zero:
           \\enter the block designated by `b`
           \\
           \\`b` is an absolute block index
         , BlockOperand
        },

        .{ "re"
         , \\restart the block designated by `b`
           \\
           \\`b` is a relative block index
           \\the designated block may not produce a value
         , Block
        },

        .{ "re_nz"
         , \\if the 8-bit condition in `x` is non-zero:
           \\restart the block designated by `b`
           \\
           \\`b` is a relative block index
           \\
           \\the designated block may not produce a value
         , BlockOperand
        },

        .{ "re_z"
         , \\if the 8-bit condition in `x` is zero:
           \\restart the block designated by `b`
           \\
           \\`b` is a relative block index
           \\
           \\the designated block may not produce a value
         , BlockOperand
        },
    },

    .@"Control Flow _v" = .{
        .{ "call"
         , \\call the function statically designated by `f`
           \\use the values designated by `as` as arguments
         , StaticFunction
         , \\place the result in `y`
         , YieldOperand
        },

        .{ "tail_call"
         , \\call the function statically designated by `f`
           \\use the values designated by `as` as arguments
           \\end the current function
         , StaticFunction
         , \\place the result in the caller's return register
         , void
        },

        .{ "prompt"
         , \\prompt the evidence designated by `e`
           \\use the values designated by `as` as arguments
         , Prompt
         , \\place the result in `y`
         , YieldOperand
        },

        .{ "tail_prompt"
         , \\prompt the evidence designated by `e`
           \\use the values designated by `as` as arguments
           \\end the current function
         , Prompt
         , \\place the result in the caller's return register
         , void
        },

        .{ "dyn_call"
         , \\call the function at the index stored in `f`
           \\use the values designated by `as` as arguments
         , DynFunction
         , \\place the result in `y`
         , YieldOperand
        },

        .{ "dyn_tail_call"
         , \\call the function at the index stored in `f`
           \\use the values designated by `as` as arguments
           \\end the current function
         , DynFunction
         , \\place the result in the caller's return register
         , void
        },

        .{ "ret"
         , \\return control from the current function
         , void
         , \\place the result designated by `y` into the call's return register
         , YieldOperand
        },

        .{ "term"
         , \\terminate the current handler's with block
         , void
         , \\ place the result designated by `y` into the handler's return register
         , YieldOperand
        },

        .{ "block"
         , \\enter the block designated by `b`
           \\
           \\`b` is an absolute block index
         , Block
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "with"
         , \\enter the block designated by `b`
           \\use the effect handler set designated by `h` to handle effects
           \\
           \\`b` is an absolute block index
         , With
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "if_nz"
         , \\if the 8-bit condition in `x` is non-zero:
           \\then: enter the block designated by `t`
           \\else: enter the block designated by `e`
           \\
           \\`t` and `e` are absolute block indices
         , Branch
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "if_z"
         , \\if the 8-bit condition in `x` is zero:
           \\then: enter the block designated by `t`
           \\else: enter the block designated by `e`
           \\
           \\`t` and `e` are absolute block indices
         , Branch
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "case"
         , \\indexed by the 8-bit value in `x`:
           \\enter one of the blocks designated in `bs`
           \\
           \\each value of `bs` is an absolute block index
         , Case
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "br"
         , \\exit the block designated by `b`
           \\
           \\`b` is a relative block index
         , Block
         , \\copy the value in `y` into the block's yield register
         , YieldOperand
        },

        .{ "br_nz"
         , \\if the 8-bit condition in `x` is non-zero:
           \\exit the block designated by `b`
           \\
           \\`b` is a relative block index
         , BlockOperand
         , \\copy the value in `y` into the block's yield register
         , YieldOperand
        },

        .{ "br_z"
         , \\if the 8-bit condition in `x` is zero:
           \\exit the block designated by `b`
           \\
           \\`b` is a relative block index
         , BlockOperand
         , \\copy the value in `y` into the block's yield register
         , YieldOperand
        },
    },

    .@"Memory" = .{
        .{ "addr"
         , \\copy the address of `x` into `y`
         , TwoOperand
        },
    },

    .@"Memory _bits" = .{
        .{ "load"
         , \\copy *n* aligned bits from the address stored in `x` into `y`
           \\the address must be located in the operand stack or global memory
         , TwoOperand
        },

        .{ "store"
         , \\copy *n* aligned bits from `x` to the address stored in `y`
           \\the address must be located in the operand stack or global memory
         , TwoOperand
        },

        .{ "clear"
         , \\clear *n* aligned bits of `x`
         , OneOperand
        },

        .{ "swap"
         , \\swap *n* aligned bits stored in `x` and `y`
         , TwoOperand
        },

        .{ "copy"
         , \\copy *n* aligned bits from `x` into `y`
         , TwoOperand
        },
    },

    .@"Arithmetic" = .{
        .{ "add"
         , \\perform *addition* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "sub"
         , \\perform *subtraction* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "mul"
         , \\perform *multiplication* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "div"
         , \\perform *division* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "rem"
         , \\perform *remainder division* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "neg"
         , \\perform *negation* on the value designated by `x`
           \\store the result in `y`
         , intFloat(.only_signed)
         , TwoOperand
        },

        .{ "bitnot"
         , \\perform *bitwise not* on the value designated by `x`
           \\store the result in `y`
         , intOnly(.same)
         , TwoOperand
        },

        .{ "bitand"
         , \\perform *bitwise and* on the values designated by `x` and `y`
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "bitor"
         , \\perform *bitwise or* on the values designated by `x` and `y`
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "bitxor"
         , \\perform *bitwise xor* on the values designated by `x` and `y`
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "shiftl"
         , \\perform *bitwise left shift* on the values designated by `x` and `y`
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "shiftr"
         , \\perform *bitwise right shift* on the values designated by `x` and `y`
           \\store the result in `z`
         , intOnly(.different)
         , ThreeOperand
        },

        .{ "eq"
         , \\perform *equality comparison* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "ne"
         , \\perform *inequality comparison* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "lt"
         , \\perform *less than comparison* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "le"
         , \\perform *less than or equal comparison* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "gt"
         , \\perform *greater than comparison* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "ge"
         , \\perform *greater than or equal comparison* on the values designated by `x` and `y`
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },
    },

    .@"Boolean" = .{
        .{ "b_and"
         , \\perform *logical and* on the values designated by `x` and `y`
           \\store the result in `z`
         , ThreeOperand
        },

        .{ "b_or"
         , \\perform *logical or* on the values designated by `x` and `y`
           \\store the result in `z`
         , ThreeOperand
        },

        .{ "b_not"
         , \\perform *logical not* on the value designated by `x`
           \\store the result in `y`
         , TwoOperand
        },
    },

    .@"Size Cast Int" = .{
        .{ "u_ext"
         , \\perform *integer zero-extension* on the value designated by `x`
           \\store the result in `y`
         , .up
         , TwoOperand
        },
        .{ "s_ext"
         , \\perform *integer sign-extension* on the value designated by `x`
           \\store the result in `y`
         , .up
         , TwoOperand
        },
        .{ "i_trunc"
         , \\perform *integer truncation* on the value designated by `x`
           \\store the result in `y`
         , .down
         , TwoOperand
        },
    },

    .@"Size Cast Float" = .{
        .{ "f_ext"
         , \\perform *floating point extension* on the value designated by `x`
           \\store the result in `y`
         , .up
         , TwoOperand
        },
        .{ "f_trunc"
         , \\perform *floating point truncation* on the value designated by `x`
           \\store the result in `y`
         , .down
         , TwoOperand
        },
    },

    .@"Int <-> Float Cast" = .{
        .{ "to"
         , \\perform *int <-> float conversion* on the value designated by `x`
           \\store the result in `y`
         , TwoOperand
        },
    },
};

pub const OneOperand = struct {
    x: Operand,
};

pub const YieldOperand = struct {
    y: Operand,
};

pub const TwoOperand = struct {
    x: Operand,
    y: Operand,
};

pub const MemOneOperand = struct {
    m: RegisterLocalOffset,
    x: Operand,
};

pub const MemTwoOperand = struct {
    m: RegisterLocalOffset,
    x: Operand,
    y: Operand,
};

pub const ThreeOperand = struct {
    x: Operand,
    y: Operand,
    z: Operand,
};

pub const Block = struct {
    b: BlockIndex,
};

pub const BlockOperand = struct {
    b: BlockIndex,
    x: Operand,
};

pub const StaticFunction = struct {
    f: FunctionIndex,
    as: []const Operand,
};

pub const DynFunction = struct {
    f: Operand,
    as: []const Operand,
};

pub const Prompt = struct {
    e: EvidenceIndex,
    as: []const Operand,
};

pub const With = struct {
    b: BlockIndex,
    h: HandlerSetIndex,
};

pub const Branch = struct {
    t: BlockIndex,
    e: BlockIndex,
    x: Operand,
};

pub const Case = struct {
    x: Operand,
    bs: []const BlockIndex,
};



fn intOnly(signVariance: AVI.SignVariance) ArithmeticValueInfo {
    return .{ .int_only = signVariance };
}

fn floatOnly() ArithmeticValueInfo {
    return .float_only;
}

fn intFloat(signVariance: AVI.SignVariance) ArithmeticValueInfo {
    return .{ .int_float = signVariance };
}


pub const ArithmeticValueInfo = union(enum) {
    none: void,
    float_only: void,
    int_only: SignVariance,
    int_float: SignVariance,
    pub const FLOAT_SIZE = [2]u8 { 32, 64 };
    pub const INTEGER_SIZE = [4]u8 { 8, 16, 32, 64 };
    pub const SIGNEDNESS = [2]std.builtin.Signedness { .unsigned, .signed };
    pub fn signChar(sign: std.builtin.Signedness) u8 {
        return switch (sign) {
            .unsigned => 'u',
            .signed => 's',
        };
    }
    pub fn signFlip(sign: std.builtin.Signedness) std.builtin.Signedness {
        return switch (sign) {
            .unsigned => .signed,
            .signed => .unsigned,
        };
    }
    pub const SignVariance = enum {
        same,
        different,
        only_unsigned,
        only_signed,
    };
    pub const SizeCast = enum {
        up,
        down,
    };
};

const AVI = ArithmeticValueInfo;

fn makeFloatFields(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, name: [:0]const u8, comptime operands: type) void {
    for (AVI.FLOAT_SIZE) |size| {
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

fn makeIntFields(enumFields: []std.builtin.Type.EnumField, unionFields: []std.builtin.Type.UnionField, id: *usize, name: [:0]const u8, comptime operands: type, signVariance: AVI.SignVariance) void {
    for (AVI.INTEGER_SIZE) |size| {
        switch (signVariance) {
            .different => {
                for (AVI.SIGNEDNESS) |sign| {
                    makeIntField(enumFields, unionFields, id, std.fmt.comptimePrint("{u}_{s}{}", .{AVI.signChar(sign), name, size}), operands);
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

pub const Op = ops: {
    const TagType = OpCodeIndex;
    const max = std.math.maxInt(TagType);

    var enumFields = [1]std.builtin.Type.EnumField {undefined} ** max;
    var unionFields = [1]std.builtin.Type.UnionField {undefined} ** max;

    var id: usize = 0;

    for (std.meta.fieldNames(@TypeOf(InstructionPrototypes))) |categoryName| {
        const category = @field(InstructionPrototypes, categoryName);

        if (std.mem.eql(u8, categoryName, "Arithmetic")) {
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
                        makeIntFields(&enumFields, &unionFields, &id, name, operands, signVariance);
                    },
                    .float_only => {
                        makeFloatFields(&enumFields, &unionFields, &id, name, operands);
                    },
                    .int_float => |signVariance| {
                        makeIntFields(&enumFields, &unionFields, &id, name, operands, signVariance);
                        makeFloatFields(&enumFields, &unionFields, &id, name, operands);
                    }
                }
            }
        } else if (std.mem.endsWith(u8, categoryName, "_bits")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const operands = proto[2];

                for (AVI.INTEGER_SIZE) |size| {
                    const fieldName = std.fmt.comptimePrint("{s}{}", .{name, size});
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
                const VT =
                    if (operands == void) vOperands
                    else if (vOperands == void) operands
                    else TypeUtils.StructConcat(.{operands, vOperands});
                unionFields[id] = .{
                    .name = fieldName,
                    .type = VT,
                    .alignment = @alignOf(VT),
                };
                id += 1;
            }
        } else if (std.mem.startsWith(u8, categoryName, "Size Cast")) {
            for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                // const doc = proto[1];
                const order: AVI.SizeCast = proto[2];
                const operands = proto[3];

                const SIZE =
                    if (std.mem.endsWith(u8, categoryName, "Int")) AVI.INTEGER_SIZE
                    else if (std.mem.endsWith(u8, categoryName, "Float")) AVI.FLOAT_SIZE
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
        } else if (std.mem.eql(u8, categoryName, "Int <-> Float Cast")) {
            const proto = category[0];

            const name = proto[0];
            // const doc = proto[1];
            const operands = proto[2];

            for (AVI.SIGNEDNESS) |sign| {
                for (AVI.INTEGER_SIZE) |int_size| {
                    for (AVI.FLOAT_SIZE) |float_size| {
                        const fieldNameA = std.fmt.comptimePrint("{u}{}_{s}_f{}", .{AVI.signChar(sign), int_size, name, float_size});
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

                        const fieldNameB = std.fmt.comptimePrint("f{}_{s}_{u}{}", .{float_size, name, AVI.signChar(sign), int_size});
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
