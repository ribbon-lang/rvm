const std = @import("std");

const Bytecode = @import("Bytecode");
const IO = @import("IO");


pub fn operand(op: anytype, writer: anytype) !void {
    const OpT = @TypeOf(op);

    switch (OpT) {
        Bytecode.Operand => {
            const offset = switch (op.kind) {
                .global => global: { try writer.print("(global {}", .{op.data.global.index}); break :global op.data.global.offset; },
                .upvalue => upvalue: { try writer.print("(upvalue {s}", .{@tagName(op.data.register.register)}); break :upvalue op.data.register.offset; },
                .local => local: { try writer.print("(local {s}", .{@tagName(op.data.register.register)}); break :local op.data.register.offset; },
            };

            if (offset != 0) {
                try writer.print(" {x:0>4})", .{offset});
            } else {
                try writer.writeAll(")");
            }
        },
        else => switch (@typeInfo(OpT)) {
            .int => try writer.print("{d}", .{op}),
            .float => try writer.print("{d:10.10}", .{op}),
            .pointer => |info| if (info.size == .Slice) {
                try writer.writeAll("(");
                for (op, 0..) |x, i| {
                    try operand(x, writer);
                    if (i < op.len - 1) {
                        try writer.writeAll(" ");
                    }
                }
                try writer.writeAll(")");
            } else unreachable,
            else => unreachable,
        }
    }
}

pub fn instruction(instr: Bytecode.Op, writer: anytype) !void {
    const opCode = @as(Bytecode.OpCode, instr);
    inline for (comptime std.meta.fieldNames(Bytecode.Op)) |fieldName| {
        if (opCode == @field(Bytecode.OpCode, fieldName)) {
            try writer.print("({s}", .{fieldName});
            const operands = @field(instr, fieldName);
            const Operands = @TypeOf(operands);
            if (Operands != void) {
                try writer.writeAll(" ");
                const operandNames = comptime std.meta.fieldNames(Operands);
                inline for (operandNames, 0..) |operandName, i| {
                    const opValue = @field(operands, operandName);
                    try writer.print("({s} ", .{operandName});
                    try operand(opValue, writer);
                    try writer.writeAll(")");
                    if (i < operandNames.len - 1) {
                        try writer.writeAll(" ");
                    }
                }
            }
            try writer.writeAll(")\n");
        }
    }
}

pub fn bytecode(code: Bytecode, writer: anytype) !void {
    @setEvalBranchQuota(10_000);

    for (code.blocks, 0..) |block, i| {
        var offset: Bytecode.InstructionPointerOffset = 0;
        const decoder = IO.Decoder {.memory = code.instructions, .base = block.base, .offset = &offset};

        try writer.print("\t\t{}:\n", .{i});
        while (offset < block.size) {
            try writer.print("\t\t\t{x:0>6}\t", .{decoder.ip()});
            const op = try decoder.decode(Bytecode.Op);
            try instruction(op, writer);
        }
    }
}

pub fn typ(types: []const Bytecode.Type, ty: Bytecode.TypeIndex, writer: anytype) !void {
    return Bytecode.printType(types, ty, writer);
}
