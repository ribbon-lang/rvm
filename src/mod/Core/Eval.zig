const std = @import("std");

const Support = @import("Support");

const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Core = @import("root.zig");
const Fiber = Core.Fiber;


const Eval = @This();

pub const RegisterData = struct {
    call: *Fiber.CallFrame,
    layout: *Bytecode.LayoutTable,
};

pub fn step(fiber: *Fiber) Fiber.Trap!void {
    const callFrame = try fiber.stack.call.topPtr();
    const function = &fiber.program.functions[callFrame.function];

    const localData = RegisterData {
        .call = callFrame,
        .layout = &function.layout_table,
    };

    const upvalueData = if (callFrame.evidence) |evIndex| ev: {
        const evidence = &fiber.evidence[evIndex];
        const evFrame = try fiber.stack.call.getPtr(evidence.call);
        const evFunction = &fiber.program.functions[evFrame.function];
        break :ev RegisterData { .call = evFrame, .layout = &evFunction.layout_table };
    } else null;

    switch (function.value) {
        .bytecode => |bc| try @call(.always_inline, stepBytecode, .{fiber, localData, upvalueData, bc}),
        .native => |nat| try @call(.always_inline, stepNative, .{fiber, localData, upvalueData, nat}),
    }
}

pub fn stepBytecode(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, bytecode: Bytecode) Fiber.Trap!void {
    @setEvalBranchQuota(25000); // tons of inlining going on here

    const blockFrame = try fiber.stack.block.topPtr();
    const block = &bytecode.blocks[blockFrame.index];
    const constants = fiber.program.constants;
    const stack = &fiber.stack.data;

    const decoder = IO.Decoder {
        .memory = bytecode.instructions,
        .base = block.base,
        .offset = &blockFrame.ip_offset,
    };

    const instr = try decoder.decode(Bytecode.Op);

    switch (instr) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => {},

        .addr_of => |operands| {
            const addr: [*]const u8 = try addrOf(.unknown, 0, constants, stack, localData, upvalueData, operands.x);

            try write(stack, localData, upvalueData, operands.y, addr);
        },

        .load => |operands| {
            const inAddr: [*]const u8 = try read([*]const u8, constants, stack, localData, upvalueData, operands.x);

            const outAddr: [*]u8 = try addrOf(.write, operands.m, constants, stack, localData, upvalueData, operands.y);

            // TODO: bounds check address
            @memcpy(outAddr[0..operands.m], inAddr);
        },

        .store => |operands| {
            const inAddr: [*]const u8 = try addrOf(.read, operands.m, constants, stack, localData, upvalueData, operands.x);
            const outAddr: [*]u8 = try read([*]u8, constants, stack, localData, upvalueData, operands.y);

            // TODO: bounds check address
            @memcpy(outAddr[0..operands.m], inAddr);
        },

        .clear => |operands| {
            const addr: [*]u8 = try addrOf(.write, operands.m, constants, stack, localData, upvalueData, operands.x);

            // TODO: bounds check address
            @memset(addr[0..operands.m], 0);
        },

        .swap => |operands| {
            const a: [*]u8 = try addrOf(.write, operands.m, constants, stack, localData, upvalueData, operands.x);
            const b: [*]u8 = try addrOf(.write, operands.m, constants, stack, localData, upvalueData, operands.y);

            // TODO: bounds check addresses
            for (0..operands.m) |i| {
                @call(.always_inline, std.mem.swap, .{u8, &a[i], &b[i]});
            }
        },

        .copy => |operands| {
            const inAddr: [*]const u8 = try addrOf(.read, operands.m, constants, stack, localData, upvalueData, operands.x);
            const outAddr: [*]u8 = try addrOf(.write, operands.m, constants, stack, localData, upvalueData, operands.y);

            // TODO: bounds check addresses
            @call(.always_inline, std.mem.copyForwards, .{u8, outAddr[0..operands.m], inAddr[0..operands.m]});
        },

        .b_not => |operands| try ops.unary(bool, "not", constants, stack, localData, upvalueData, operands),
        .b_and => |operands| try ops.binary(bool, "and", constants, stack, localData, upvalueData, operands),
        .b_or => |operands| try ops.binary(bool, "or", constants, stack, localData, upvalueData, operands),

        .f_add32 => |operands| try ops.binary(f32, "add", constants, stack, localData, upvalueData, operands),
        .f_add64 => |operands| try ops.binary(f64, "add", constants, stack, localData, upvalueData, operands),
        .f_sub32 => |operands| try ops.binary(f32, "sub", constants, stack, localData, upvalueData, operands),
        .f_sub64 => |operands| try ops.binary(f64, "sub", constants, stack, localData, upvalueData, operands),
        .f_mul32 => |operands| try ops.binary(f32, "mul", constants, stack, localData, upvalueData, operands),
        .f_mul64 => |operands| try ops.binary(f64, "mul", constants, stack, localData, upvalueData, operands),
        .f_div32 => |operands| try ops.binary(f32, "div", constants, stack, localData, upvalueData, operands),
        .f_div64 => |operands| try ops.binary(f64, "div", constants, stack, localData, upvalueData, operands),
        .f_rem32 => |operands| try ops.binary(f32, "rem", constants, stack, localData, upvalueData, operands),
        .f_rem64 => |operands| try ops.binary(f64, "rem", constants, stack, localData, upvalueData, operands),
        .f_neg32 => |operands| try ops.unary(f32, "neg", constants, stack, localData, upvalueData, operands),
        .f_neg64 => |operands| try ops.unary(f64, "neg", constants, stack, localData, upvalueData, operands),
        .f_eq32 => |operands| try ops.binary(f32, "eq", constants, stack, localData, upvalueData, operands),
        .f_eq64 => |operands| try ops.binary(f64, "eq", constants, stack, localData, upvalueData, operands),
        .f_ne32 => |operands| try ops.binary(f32, "ne", constants, stack, localData, upvalueData, operands),
        .f_ne64 => |operands| try ops.binary(f64, "ne", constants, stack, localData, upvalueData, operands),
        .f_lt32 => |operands| try ops.binary(f32, "lt", constants, stack, localData, upvalueData, operands),
        .f_lt64 => |operands| try ops.binary(f64, "lt", constants, stack, localData, upvalueData, operands),
        .f_gt32 => |operands| try ops.binary(f32, "gt", constants, stack, localData, upvalueData, operands),
        .f_gt64 => |operands| try ops.binary(f64, "gt", constants, stack, localData, upvalueData, operands),
        .f_le32 => |operands| try ops.binary(f32, "le", constants, stack, localData, upvalueData, operands),
        .f_le64 => |operands| try ops.binary(f64, "le", constants, stack, localData, upvalueData, operands),
        .f_ge32 => |operands| try ops.binary(f32, "ge", constants, stack, localData, upvalueData, operands),
        .f_ge64 => |operands| try ops.binary(f64, "ge", constants, stack, localData, upvalueData, operands),

        .i_add8 => |operands| try ops.binary(u8, "add", constants, stack, localData, upvalueData, operands),
        .i_add16 => |operands| try ops.binary(u16, "add", constants, stack, localData, upvalueData, operands),
        .i_add32 => |operands| try ops.binary(u32, "add", constants, stack, localData, upvalueData, operands),
        .i_add64 => |operands| try ops.binary(u64, "add", constants, stack, localData, upvalueData, operands),
        .i_sub8 => |operands| try ops.binary(u8, "sub", constants, stack, localData, upvalueData, operands),
        .i_sub16 => |operands| try ops.binary(u16, "sub", constants, stack, localData, upvalueData, operands),
        .i_sub32 => |operands| try ops.binary(u32, "sub", constants, stack, localData, upvalueData, operands),
        .i_sub64 => |operands| try ops.binary(u64, "sub", constants, stack, localData, upvalueData, operands),
        .i_mul8 => |operands| try ops.binary(u8, "mul", constants, stack, localData, upvalueData, operands),
        .i_mul16 => |operands| try ops.binary(u16, "mul", constants, stack, localData, upvalueData, operands),
        .i_mul32 => |operands| try ops.binary(u32, "mul", constants, stack, localData, upvalueData, operands),
        .i_mul64 => |operands| try ops.binary(u64, "mul", constants, stack, localData, upvalueData, operands),
        .s_div8 => |operands| try ops.binary(i8, "divFloor", constants, stack, localData, upvalueData, operands),
        .s_div16 => |operands| try ops.binary(i16, "divFloor", constants, stack, localData, upvalueData, operands),
        .s_div32 => |operands| try ops.binary(i32, "divFloor", constants, stack, localData, upvalueData, operands),
        .s_div64 => |operands| try ops.binary(i64, "divFloor", constants, stack, localData, upvalueData, operands),
        .u_div8 => |operands| try ops.binary(u8, "div", constants, stack, localData, upvalueData, operands),
        .u_div16 => |operands| try ops.binary(u16, "div", constants, stack, localData, upvalueData, operands),
        .u_div32 => |operands| try ops.binary(u32, "div", constants, stack, localData, upvalueData, operands),
        .u_div64 => |operands| try ops.binary(u64, "div", constants, stack, localData, upvalueData, operands),
        .s_rem8 => |operands| try ops.binary(i8, "rem", constants, stack, localData, upvalueData, operands),
        .s_rem16 => |operands| try ops.binary(i16, "rem", constants, stack, localData, upvalueData, operands),
        .s_rem32 => |operands| try ops.binary(i32, "rem", constants, stack, localData, upvalueData, operands),
        .s_rem64 => |operands| try ops.binary(i64, "rem", constants, stack, localData, upvalueData, operands),
        .u_rem8 => |operands| try ops.binary(u8, "rem", constants, stack, localData, upvalueData, operands),
        .u_rem16 => |operands| try ops.binary(u16, "rem", constants, stack, localData, upvalueData, operands),
        .u_rem32 => |operands| try ops.binary(u32, "rem", constants, stack, localData, upvalueData, operands),
        .u_rem64 => |operands| try ops.binary(u64, "rem", constants, stack, localData, upvalueData, operands),
        .i_bitnot8 => |operands| try ops.unary(u8, "bitnot", constants, stack, localData, upvalueData, operands),
        .i_bitnot16 => |operands| try ops.unary(u16, "bitnot", constants, stack, localData, upvalueData, operands),
        .i_bitnot32 => |operands| try ops.unary(u32, "bitnot", constants, stack, localData, upvalueData, operands),
        .i_bitnot64 => |operands| try ops.unary(u64, "bitnot", constants, stack, localData, upvalueData, operands),
        .i_bitand8 => |operands| try ops.binary(u8, "bitand", constants, stack, localData, upvalueData, operands),
        .i_bitand16 => |operands| try ops.binary(u16, "bitand", constants, stack, localData, upvalueData, operands),
        .i_bitand32 => |operands| try ops.binary(u32, "bitand", constants, stack, localData, upvalueData, operands),
        .i_bitand64 => |operands| try ops.binary(u64, "bitand", constants, stack, localData, upvalueData, operands),
        .i_bitor8 => |operands| try ops.binary(u8, "bitor", constants, stack, localData, upvalueData, operands),
        .i_bitor16 => |operands| try ops.binary(u16, "bitor", constants, stack, localData, upvalueData, operands),
        .i_bitor32 => |operands| try ops.binary(u32, "bitor", constants, stack, localData, upvalueData, operands),
        .i_bitor64 => |operands| try ops.binary(u64, "bitor", constants, stack, localData, upvalueData, operands),
        .i_bitxor8 => |operands| try ops.binary(u8, "bitxor", constants, stack, localData, upvalueData, operands),
        .i_bitxor16 => |operands| try ops.binary(u16, "bitxor", constants, stack, localData, upvalueData, operands),
        .i_bitxor32 => |operands| try ops.binary(u32, "bitxor", constants, stack, localData, upvalueData, operands),
        .i_bitxor64 => |operands| try ops.binary(u64, "bitxor", constants, stack, localData, upvalueData, operands),
        .i_shiftl8 => |operands| try ops.binary(u8, "shiftl", constants, stack, localData, upvalueData, operands),
        .i_shiftl16 => |operands| try ops.binary(u16, "shiftl", constants, stack, localData, upvalueData, operands),
        .i_shiftl32 => |operands| try ops.binary(u32, "shiftl", constants, stack, localData, upvalueData, operands),
        .i_shiftl64 => |operands| try ops.binary(u64, "shiftl", constants, stack, localData, upvalueData, operands),
        .u_shiftr8 => |operands| try ops.binary(u8, "shiftr", constants, stack, localData, upvalueData, operands),
        .u_shiftr16 => |operands| try ops.binary(u16, "shiftr", constants, stack, localData, upvalueData, operands),
        .u_shiftr32 => |operands| try ops.binary(u32, "shiftr", constants, stack, localData, upvalueData, operands),
        .u_shiftr64 => |operands| try ops.binary(u64, "shiftr", constants, stack, localData, upvalueData, operands),
        .s_shiftr8 => |operands| try ops.binary(i8, "shiftr", constants, stack, localData, upvalueData, operands),
        .s_shiftr16 => |operands| try ops.binary(i16, "shiftr", constants, stack, localData, upvalueData, operands),
        .s_shiftr32 => |operands| try ops.binary(i32, "shiftr", constants, stack, localData, upvalueData, operands),
        .s_shiftr64 => |operands| try ops.binary(i64, "shiftr", constants, stack, localData, upvalueData, operands),
        .s_neg8 => |operands| try ops.unary(i8, "neg", constants, stack, localData, upvalueData, operands),
        .s_neg16 => |operands| try ops.unary(i16, "neg", constants, stack, localData, upvalueData, operands),
        .s_neg32 => |operands| try ops.unary(i32, "neg", constants, stack, localData, upvalueData, operands),
        .s_neg64 => |operands| try ops.unary(i64, "neg", constants, stack, localData, upvalueData, operands),
        .i_eq8 => |operands| try ops.binary(u8, "eq", constants, stack, localData, upvalueData, operands),
        .i_eq16 => |operands| try ops.binary(u16, "eq", constants, stack, localData, upvalueData, operands),
        .i_eq32 => |operands| try ops.binary(u32, "eq", constants, stack, localData, upvalueData, operands),
        .i_eq64 => |operands| try ops.binary(u64, "eq", constants, stack, localData, upvalueData, operands),
        .i_ne8 => |operands| try ops.binary(u8, "ne", constants, stack, localData, upvalueData, operands),
        .i_ne16 => |operands| try ops.binary(u16, "ne", constants, stack, localData, upvalueData, operands),
        .i_ne32 => |operands| try ops.binary(u32, "ne", constants, stack, localData, upvalueData, operands),
        .i_ne64 => |operands| try ops.binary(u64, "ne", constants, stack, localData, upvalueData, operands),
        .u_lt8 => |operands| try ops.binary(u8, "lt", constants, stack, localData, upvalueData, operands),
        .u_lt16 => |operands| try ops.binary(u16, "lt", constants, stack, localData, upvalueData, operands),
        .u_lt32 => |operands| try ops.binary(u32, "lt", constants, stack, localData, upvalueData, operands),
        .u_lt64 => |operands| try ops.binary(u64, "lt", constants, stack, localData, upvalueData, operands),
        .s_lt8 => |operands| try ops.binary(i8, "lt", constants, stack, localData, upvalueData, operands),
        .s_lt16 => |operands| try ops.binary(i16, "lt", constants, stack, localData, upvalueData, operands),
        .s_lt32 => |operands| try ops.binary(i32, "lt", constants, stack, localData, upvalueData, operands),
        .s_lt64 => |operands| try ops.binary(i64, "lt", constants, stack, localData, upvalueData, operands),
        .u_gt8 => |operands| try ops.binary(u8, "gt", constants, stack, localData, upvalueData, operands),
        .u_gt16 => |operands| try ops.binary(u16, "gt", constants, stack, localData, upvalueData, operands),
        .u_gt32 => |operands| try ops.binary(u32, "gt", constants, stack, localData, upvalueData, operands),
        .u_gt64 => |operands| try ops.binary(u64, "gt", constants, stack, localData, upvalueData, operands),
        .s_gt8 => |operands| try ops.binary(i8, "gt", constants, stack, localData, upvalueData, operands),
        .s_gt16 => |operands| try ops.binary(i16, "gt", constants, stack, localData, upvalueData, operands),
        .s_gt32 => |operands| try ops.binary(i32, "gt", constants, stack, localData, upvalueData, operands),
        .s_gt64 => |operands| try ops.binary(i64, "gt", constants, stack, localData, upvalueData, operands),
        .u_le8 => |operands| try ops.binary(u8, "le", constants, stack, localData, upvalueData, operands),
        .u_le16 => |operands| try ops.binary(u16, "le", constants, stack, localData, upvalueData, operands),
        .u_le32 => |operands| try ops.binary(u32, "le", constants, stack, localData, upvalueData, operands),
        .u_le64 => |operands| try ops.binary(u64, "le", constants, stack, localData, upvalueData, operands),
        .s_le8 => |operands| try ops.binary(i8, "le", constants, stack, localData, upvalueData, operands),
        .s_le16 => |operands| try ops.binary(i16, "le", constants, stack, localData, upvalueData, operands),
        .s_le32 => |operands| try ops.binary(i32, "le", constants, stack, localData, upvalueData, operands),
        .s_le64 => |operands| try ops.binary(i64, "le", constants, stack, localData, upvalueData, operands),
        .u_ge8 => |operands| try ops.binary(u8, "ge", constants, stack, localData, upvalueData, operands),
        .u_ge16 => |operands| try ops.binary(u16, "ge", constants, stack, localData, upvalueData, operands),
        .u_ge32 => |operands| try ops.binary(u32, "ge", constants, stack, localData, upvalueData, operands),
        .u_ge64 => |operands| try ops.binary(u64, "ge", constants, stack, localData, upvalueData, operands),
        .s_ge8 => |operands| try ops.binary(i8, "ge", constants, stack, localData, upvalueData, operands),
        .s_ge16 => |operands| try ops.binary(i16, "ge", constants, stack, localData, upvalueData, operands),
        .s_ge32 => |operands| try ops.binary(i32, "ge", constants, stack, localData, upvalueData, operands),
        .s_ge64 => |operands| try ops.binary(i64, "ge", constants, stack, localData, upvalueData, operands),

        .u_ext8x16 => |operands| try ops.cast(u8, u16, constants, stack, localData, upvalueData, operands),
        .u_ext8x32 => |operands| try ops.cast(u8, u32, constants, stack, localData, upvalueData, operands),
        .u_ext8x64 => |operands| try ops.cast(u8, u64, constants, stack, localData, upvalueData, operands),
        .u_ext16x32 => |operands| try ops.cast(u16, u32, constants, stack, localData, upvalueData, operands),
        .u_ext16x64 => |operands| try ops.cast(u16, u64, constants, stack, localData, upvalueData, operands),
        .u_ext32x64 => |operands| try ops.cast(u32, u64, constants, stack, localData, upvalueData, operands),
        .s_ext8x16 => |operands| try ops.cast(i8, i16, constants, stack, localData, upvalueData, operands),
        .s_ext8x32 => |operands| try ops.cast(i8, i32, constants, stack, localData, upvalueData, operands),
        .s_ext8x64 => |operands| try ops.cast(i8, i64, constants, stack, localData, upvalueData, operands),
        .s_ext16x32 => |operands| try ops.cast(i16, i32, constants, stack, localData, upvalueData, operands),
        .s_ext16x64 => |operands| try ops.cast(i16, i64, constants, stack, localData, upvalueData, operands),
        .s_ext32x64 => |operands| try ops.cast(i32, i64, constants, stack, localData, upvalueData, operands),
        .f_ext32x64 => |operands| try ops.cast(f32, i64, constants, stack, localData, upvalueData, operands),

        .i_trunc64x32 => |operands| try ops.cast(u64, u32, constants, stack, localData, upvalueData, operands),
        .i_trunc64x16 => |operands| try ops.cast(u64, u16, constants, stack, localData, upvalueData, operands),
        .i_trunc64x8 => |operands| try ops.cast(u64, u8, constants, stack, localData, upvalueData, operands),
        .i_trunc32x16 => |operands| try ops.cast(u32, u16, constants, stack, localData, upvalueData, operands),
        .i_trunc32x8 => |operands| try ops.cast(u32, u8, constants, stack, localData, upvalueData, operands),
        .i_trunc16x8 => |operands| try ops.cast(u16, u8, constants, stack, localData, upvalueData, operands),
        .f_trunc64x32 => |operands| try ops.cast(f64, f32, constants, stack, localData, upvalueData, operands),

        .u8_to_f32 => |operands| try ops.cast(u8, f32, constants, stack, localData, upvalueData, operands),
        .u8_to_f64 => |operands| try ops.cast(u8, f64, constants, stack, localData, upvalueData, operands),
        .u16_to_f32 => |operands| try ops.cast(u16, f32, constants, stack, localData, upvalueData, operands),
        .u16_to_f64 => |operands| try ops.cast(u16, f64, constants, stack, localData, upvalueData, operands),
        .u32_to_f32 => |operands| try ops.cast(u32, f32, constants, stack, localData, upvalueData, operands),
        .u32_to_f64 => |operands| try ops.cast(u32, f64, constants, stack, localData, upvalueData, operands),
        .u64_to_f32 => |operands| try ops.cast(u64, f32, constants, stack, localData, upvalueData, operands),
        .u64_to_f64 => |operands| try ops.cast(u64, f64, constants, stack, localData, upvalueData, operands),
        .s8_to_f32 => |operands| try ops.cast(i8, f32, constants, stack, localData, upvalueData, operands),
        .s8_to_f64 => |operands| try ops.cast(i8, f64, constants, stack, localData, upvalueData, operands),
        .s16_to_f32 => |operands| try ops.cast(i16, f32, constants, stack, localData, upvalueData, operands),
        .s16_to_f64 => |operands| try ops.cast(i16, f64, constants, stack, localData, upvalueData, operands),
        .s32_to_f32 => |operands| try ops.cast(i32, f32, constants, stack, localData, upvalueData, operands),
        .s32_to_f64 => |operands| try ops.cast(i32, f64, constants, stack, localData, upvalueData, operands),
        .s64_to_f32 => |operands| try ops.cast(i64, f32, constants, stack, localData, upvalueData, operands),
        .s64_to_f64 => |operands| try ops.cast(i64, f64, constants, stack, localData, upvalueData, operands),
        .f32_to_u8 => |operands| try ops.cast(f32, u8, constants, stack, localData, upvalueData, operands),
        .f32_to_u16 => |operands| try ops.cast(f32, u16, constants, stack, localData, upvalueData, operands),
        .f32_to_u32 => |operands| try ops.cast(f32, u32, constants, stack, localData, upvalueData, operands),
        .f32_to_u64 => |operands| try ops.cast(f32, u64, constants, stack, localData, upvalueData, operands),
        .f64_to_u8 => |operands| try ops.cast(f64, u8, constants, stack, localData, upvalueData, operands),
        .f64_to_u16 => |operands| try ops.cast(f64, u16, constants, stack, localData, upvalueData, operands),
        .f64_to_u32 => |operands| try ops.cast(f64, u32, constants, stack, localData, upvalueData, operands),
        .f64_to_u64 => |operands| try ops.cast(f64, u64, constants, stack, localData, upvalueData, operands),
        .f32_to_s8 => |operands| try ops.cast(f32, i8, constants, stack, localData, upvalueData, operands),
        .f32_to_s16 => |operands| try ops.cast(f32, i16, constants, stack, localData, upvalueData, operands),
        .f32_to_s32 => |operands| try ops.cast(f32, i32, constants, stack, localData, upvalueData, operands),
        .f32_to_s64 => |operands| try ops.cast(f32, i64, constants, stack, localData, upvalueData, operands),
        .f64_to_s8 => |operands| try ops.cast(f64, i8, constants, stack, localData, upvalueData, operands),
        .f64_to_s16 => |operands| try ops.cast(f64, i16, constants, stack, localData, upvalueData, operands),
        .f64_to_s32 => |operands| try ops.cast(f64, i32, constants, stack, localData, upvalueData, operands),
        .f64_to_s64 => |operands| try ops.cast(f64, i64, constants, stack, localData, upvalueData, operands),

        else => Support.todo(noreturn, {})
    }
}

pub fn stepNative(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, native: Bytecode.Function.Native) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, localData, upvalueData, native});
}

inline fn extractUp(upvalueData: ?RegisterData) Fiber.Trap!RegisterData {
    if (upvalueData) |ud| {
        return ud;
    } else {
        @branchHint(.cold);
        return Fiber.Trap.MissingUpvalueContext;
    }
}

pub inline fn read(comptime T: type, constants: []Bytecode.Data, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand) !T {
    const size = @sizeOf(T);

    switch (operand.kind) {
        .immediate => {
            const data = operand.data.immediate;

            const bytes = try getConstant(constants, data, size);

            var value: T = undefined;
            @memcpy(@as([*]u8, @ptrCast(&value)), bytes);

            return value;
        },

        .upvalue_arg => return readImpl(T, .argument, stack, try extractUp(upvalueData), operand.data.register),
        .upvalue_var => return readImpl(T, .variable, stack, try extractUp(upvalueData), operand.data.register),

        .local_arg => return readImpl(T, .argument, stack, localData, operand.data.register),
        .local_var => return readImpl(T, .variable, stack, localData, operand.data.register),
    }
}

pub inline fn write(stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, value: anytype) Fiber.Trap!void {
    switch (operand.kind) {
        .immediate => {
            @branchHint(.cold);
            return Fiber.Trap.ImmediateWrite;
        },

        .upvalue_arg => try writeImpl(.argument, stack, try extractUp(upvalueData), operand.data.register, value),
        .upvalue_var => try writeImpl(.variable, stack, try extractUp(upvalueData), operand.data.register, value),

        .local_arg => try writeImpl(.argument, stack, localData, operand.data.register, value),
        .local_var => try writeImpl(.variable, stack, localData, operand.data.register, value),
    }
}

pub inline fn addrOf(comptime addrKind: enum {unknown, read, write}, size: Bytecode.RegisterLocalOffset, constants: []Bytecode.Data, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand) Fiber.Trap!switch(addrKind) { .read => [*]const u8, else => [*]u8 } {
    switch (operand.kind) {
        .immediate => {
            if (comptime addrKind == .write) {
                @branchHint(.cold);
                return Fiber.Trap.ImmediateWrite;
            } else {
                const data = operand.data.immediate;

                const bytes = try getConstant(constants, data, size);

                return @constCast(bytes.ptr);
            }
        },

        .upvalue_arg => return addrOfImpl(.argument, size, stack, try extractUp(upvalueData), operand.data.register),
        .upvalue_var => return addrOfImpl(.variable, size, stack, try extractUp(upvalueData), operand.data.register),

        .local_arg => return addrOfImpl(.argument, size, stack, localData, operand.data.register),
        .local_var => return addrOfImpl(.variable, size, stack, localData, operand.data.register),
    }
}

inline fn addrOfImpl(comptime kind: OperandKind, size: Bytecode.RegisterLocalOffset, stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand) Fiber.Trap![*]u8 {
    const base = try getOperandOffset(kind, regData, operand.register);

    if (!regData.layout.inbounds(operand, @truncate(size))) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(try stack.getPtr(base + operand.offset));
}

inline fn readImpl(comptime T: type, comptime kind: OperandKind, stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand) Fiber.Trap!T {
    const size = @sizeOf(T);

    const base = try getOperandOffset(kind, regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    var value: T = undefined;
    const bytes = try stack.getSlice(base + operand.offset, size);

    @memcpy(@as([*]u8, @ptrCast(&value)), bytes);

    return value;
}

inline fn writeImpl(comptime kind: OperandKind, stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand, value: anytype) Fiber.Trap!void {
    const size = @sizeOf(@TypeOf(value));

    const base = try getOperandOffset(kind, regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = @as([*]const u8, @ptrCast(&value))[0..size];

    try stack.setSlice(base + operand.offset, bytes);
}

pub inline fn getConstant(constants: []Bytecode.Data, imm: Bytecode.ImmediateOperand, size: Bytecode.RegisterLocalOffset) Fiber.Trap![]const u8 {
    if (imm.index >= constants.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const data = &constants[imm.index];

    if (!data.layout.inbounds(imm.offset, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return data.memory[imm.offset..imm.offset + size];
}

pub const OperandKind = enum { variable, argument };

pub inline fn getOperandOffset(comptime kind: OperandKind, regData: RegisterData, register: Bytecode.Register) Fiber.Trap!Fiber.DataStack.Ptr {
    const regNumber: Bytecode.RegisterIndex = @intFromEnum(register);

    switch (kind) {
        .argument => if (regNumber < regData.call.argument_offsets.len) {
            return regData.call.stack.origin + regData.call.argument_offsets[regNumber];
        } else {
            @branchHint(.cold);

            return Fiber.Trap.OutOfBounds;
        },

        .variable => if (regNumber < regData.layout.local_offsets.len) {
            return regData.call.stack.base + regData.layout.local_offsets[regNumber];
        } else {
            @branchHint(.cold);

            return Fiber.Trap.OutOfBounds;
        },
    }
}


const ops = struct {
    inline fn cast(comptime A: type, comptime B: type, constants: []Bytecode.Data, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operands: Bytecode.ISA.TwoOperand) Fiber.Trap!void {
        const x = try read(A, constants, stack, localData, upvalueData, operands.x);

        const aKind = @as(std.builtin.TypeId, @typeInfo(A));
        const bKind = @as(std.builtin.TypeId, @typeInfo(B));
        const result =
            if (comptime aKind == bKind) (
                if (comptime aKind == .int) intCast(B, x)
                else floatCast(B, x)
            ) else typeCast(B, x);

        try write(stack, localData, upvalueData, operands.y, result);
    }

    inline fn unary(comptime T: type, comptime op: []const u8, constants: []Bytecode.Data, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operands: Bytecode.ISA.TwoOperand) Fiber.Trap!void {
        const x = try read(T, constants, stack, localData, upvalueData, operands.x);

        const result = @call(.always_inline, @field(ops, op), .{x});

        try write(stack, localData, upvalueData, operands.y, result);
    }

    inline fn binary(comptime T: type, comptime op: []const u8, constants: []Bytecode.Data, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operands: Bytecode.ISA.ThreeOperand) Fiber.Trap!void {
        const x = try read(T, constants, stack, localData, upvalueData, operands.x);
        const y = try read(T, constants, stack, localData, upvalueData, operands.y);

        const result = @call(.always_inline, @field(ops, op), .{x, y});

        try write(stack, localData, upvalueData, operands.z, result);
    }

    inline fn intCast(comptime T: type, x: anytype) T {
        const U = @TypeOf(x);

        if (comptime @typeInfo(U).int.bits > @typeInfo(T).int.bits) {
            return @truncate(x);
        } else {
            return x;
        }
    }

    inline fn floatCast(comptime T: type, x: anytype) T {
        return @floatCast(x);
    }

    inline fn typeCast(comptime T: type, x: anytype) T {
        const U = @TypeOf(x);

        const tagT = @as(std.builtin.TypeId, @typeInfo(T));
        const tagU = @as(std.builtin.TypeId, @typeInfo(U));

        if (comptime tagT == .int and tagU == .float) {
            return @intFromFloat(x);
        } else if (comptime tagT == .float and tagU == .int) {
            return @floatFromInt(x);
        } else unreachable;
    }

    fn neg(a: anytype) @TypeOf(a) {
        return -a;
    }

    fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a + b;
    }

    fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a - b;
    }

    fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a * b;
    }

    fn div(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a / b;
    }

    fn divFloor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return @divFloor(a, b);
    }

    fn rem(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return @rem(a, b);
    }

    fn bitnot(a: anytype) @TypeOf(a) {
        return ~a;
    }

    fn not(a: anytype) @TypeOf(a) {
        return !a;
    }

    fn bitand(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a & b;
    }

    fn @"and"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a and b;
    }

    fn bitor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a | b;
    }

    fn @"or"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a or b;
    }

    fn bitxor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a ^ b;
    }

    fn shiftl(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        const bits = @bitSizeOf(T);
        const S = std.meta.Int(.unsigned, std.math.log2(bits));
        const U = std.meta.Int(.unsigned, bits);
        const bu: U = @bitCast(b);
        const bs: U = @rem(std.math.maxInt(S), bu);
        return a << @truncate(bs);
    }

    fn shiftr(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        const bits = @bitSizeOf(T);
        const S = std.meta.Int(.unsigned, std.math.log2(bits));
        const U = std.meta.Int(.unsigned, bits);
        const bu: U = @bitCast(b);
        const bs: U = @rem(std.math.maxInt(S), bu);
        return a >> @truncate(bs);
    }

    fn eq(a: anytype, b: @TypeOf(a)) bool {
        return a == b;
    }

    fn ne(a: anytype, b: @TypeOf(a)) bool {
        return a != b;
    }

    fn lt(a: anytype, b: @TypeOf(a)) bool {
        return a < b;
    }

    fn gt(a: anytype, b: @TypeOf(a)) bool {
        return a > b;
    }

    fn le(a: anytype, b: @TypeOf(a)) bool {
        return a <= b;
    }

    fn ge(a: anytype, b: @TypeOf(a)) bool {
        return a >= b;
    }
};
