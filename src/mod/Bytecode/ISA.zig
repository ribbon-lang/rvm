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
        .{ "when"
         , \\enter the block designated by `b`, if the condition in `x` is non-zero
         , BlockOperand
        },

        .{ "unless"
         , \\enter the block designated by `b`, if the condition in `x` is zero
         , BlockOperand
        },

        .{ "re"
         , \\restart the block designated by `b`
         , Block
        },

        .{ "re_if"
         , \\restart the designated block, if the condition in `x` is non-zero
         , BlockOperand
        },
    },

    .@"Control Flow _v" = .{
        .{ "call"
         , \\call the function at the address stored in `f`
           \\use the registers `as` as arguments
         , Function
         , \\place the result in `y`
         , YieldOperand
        },

        .{ "tail_call"
         , \\call the function at the address stored in `f`
           \\use the registers `as` as arguments
           \\end the current function
         , Function
         , \\place the result in the caller's return register
         , void
        },

        .{ "prompt"
         , \\prompt the evidence given by `e`
           \\use the registers `as` as arguments
         , Prompt
         , \\place the result in `y`
         , YieldOperand
        },

        .{ "tail_prompt"
         , \\prompt the evidence given by `e`
           \\use the registers `as` as arguments
           \\end the current function
         , Prompt
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
         , Block
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "with"
         , \\enter the block designated by `b`
           \\use the effect handler set designated by `h` to handle effects
         , With
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "if_nz"
         , \\if the condition in `x` is non-zero:
           \\then: enter the block designated by `t`
           \\else: enter the block designated by `e`
         , Branch
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "if_z"
         , \\if the condition in `x` is zero:
           \\then: enter the block designated by `t`
           \\else: enter the block designated by `e`
         , Branch
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "case"
         , \\enter one of the blocks designated in `bs`, indexed by the value in `x`
         , Case
         , \\place the result of the block in `y`
         , YieldOperand
        },

        .{ "br"
         , \\exit the block designated by `b`
         , Block
         , \\copy the value in `y` into the block's yield register
         , YieldOperand
        },

        .{ "br_if"
         , \\exit the block designated by `b`, if the condition in `x` is non-zero
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

        .{ "load"
         , \\copy `m` bytes from the address stored in `x` into `y`
           \\the address must be located in the operand stack or global memory
         , MemTwoOperand
        },

        .{ "store"
         , \\copy `m` bytes from `x` to the address stored in `y`
           \\the address must be located in the operand stack or global memory
         , MemTwoOperand
        },

        .{ "clear"
         , \\clear `m` bytes of `x`
         , MemOneOperand
        },

        .{ "swap"
         , \\swap `m` bytes stored in `x` and `y`
         , MemTwoOperand
        },

        .{ "copy"
         , \\copy `m` bytes from `x` into `y`
         , MemTwoOperand
        },
    },

    .@"Arithmetic" = .{
        .{ "add"
         , \\load two values from `x` and `y`
           \\perform addition
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "sub"
         , \\load two values from `x` and `y`
           \\perform subtraction
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "mul"
         , \\load two values from `x` and `y`
           \\perform division
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "div"
         , \\load two values from `x` and `y`
           \\perform division
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "rem"
         , \\load two values from `x` and `y`
           \\perform remainder division
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "neg"
         , \\load a value from `x`
           \\perform negation
           \\store the result in `y`
         , intFloat(.only_signed)
         , TwoOperand
        },

        .{ "bitnot"
         , \\load a value from `x`
           \\perform bitwise not
           \\store the result in `y`
         , intOnly(.same)
         , TwoOperand
        },

        .{ "bitand"
         , \\load two values from `x` and `y`
           \\perform bitwise and
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "bitor"
         , \\load two values from `x` and `y`
           \\perform bitwise or
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "bitxor"
         , \\load two values from `x` and `y`
           \\perform bitwise xor
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "shiftl"
         , \\load two values from `x` and `y`
           \\perform bitwise left shift
           \\store the result in `z`
         , intOnly(.same)
         , ThreeOperand
        },

        .{ "shiftr"
         , \\load two values from `x` and `y`
           \\perform bitwise arithmetic right shift
           \\store the result in `z`
         , intOnly(.different)
         , ThreeOperand
        },

        .{ "eq"
         , \\load two values from `x` and `y`
           \\perform equality comparison
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "ne"
         , \\load two values from `x` and `y`
           \\perform inequality comparison
           \\store the result in `z`
         , intFloat(.same)
         , ThreeOperand
        },

        .{ "lt"
         , \\load two values from `x` and `y`
           \\perform less than comparison
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "le"
         , \\load two values from `x` and `y`
           \\perform less than or equal comparison
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "gt"
         , \\load two values from `x` and `y`
           \\perform greater than comparison
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },

        .{ "ge"
         , \\load two values from `x` and `y`
           \\perform greater than or equal comparison
           \\store the result in `z`
         , intFloat(.different)
         , ThreeOperand
        },
    },

    .@"Boolean" = .{
        .{ "b_and"
         , \\load two values from `x` and `y`
           \\perform logical and
           \\store the result in `z`
         , ThreeOperand
        },

        .{ "b_or"
         , \\load two values from `x` and `y`
           \\perform logical or
           \\store the result in `z`
         , ThreeOperand
        },

        .{ "b_not"
         , \\load a value from `x`
           \\perform logical not
           \\store the result in `y`
         , TwoOperand
        },
    },

    .@"Size Cast Int" = .{
        .{ "u_ext"
         , \\load a value from `x`
           \\perform zero extension
           \\store the result in `y`
         , .up
         , TwoOperand
        },
        .{ "s_ext"
         , \\load a value from `x`
           \\perform sign extension
           \\store the result in `y`
         , .up
         , TwoOperand
        },
        .{ "i_trunc"
         , \\load a value from `x`
           \\perform truncation
           \\store the result in `y`
         , .down
         , TwoOperand
        },
    },

    .@"Size Cast Float" = .{
        .{ "f_ext"
         , \\load a value from `x`
           \\perform floating point extension
           \\store the result in `y`
         , .up
         , TwoOperand
        },
        .{ "f_trunc"
         , \\load a value from `x`
           \\perform floating point truncation
           \\store the result in `y`
         , .down
         , TwoOperand
        },
    },

    .@"Int <-> Float Cast" = .{
        .{ "to"
         , \\load a value from `x`
           \\perform int <-> float conversion
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

pub const Function = struct {
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
