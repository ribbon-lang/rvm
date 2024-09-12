const std = @import("std");

const Config = @import("Config");
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

    const upvalueData = if (callFrame.evidence != Bytecode.EVIDENCE_SENTINEL) ev: {
        const evidence = &fiber.evidence[callFrame.evidence];
        const evFrame = try fiber.stack.call.getPtr(evidence.call);
        const evFunction = &fiber.program.functions[evFrame.function];
        break :ev RegisterData { .call = evFrame, .layout = &evFunction.layout_table };
    } else null;

    switch (function.value) {
        .bytecode => try @call(Config.INLINING_CALL_MOD, stepBytecode, .{fiber, function, callFrame, localData, upvalueData}),
        .native => |nat| try @call(Config.INLINING_CALL_MOD, stepNative, .{fiber, localData, upvalueData, nat}),
    }
}

pub fn stepBytecode(fiber: *Fiber, function: *Bytecode.Function, callFrame: *Fiber.CallFrame, localData: RegisterData, upvalueData: ?RegisterData) Fiber.Trap!void {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA); // tons of inlining going on here

    const blockFrame = try fiber.stack.block.topPtr();
    const block = &function.value.bytecode.blocks[blockFrame.index];
    const globals = &fiber.program.globals;
    const stack = &fiber.stack.data;

    const decoder = IO.Decoder {
        .memory = function.value.bytecode.instructions,
        .base = block.base,
        .offset = &blockFrame.ip_offset,
    };

    const instr = try decoder.decodeInline(Bytecode.Op);

    switch (instr) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => {},

        .call => |operands| try call(fiber, localData, upvalueData, operands.f, operands.as, null),
        .call_v => |operands| try call(fiber, localData, upvalueData, operands.f, operands.as, operands.y),
        .prompt => |operands| try prompt(fiber, localData, upvalueData, operands.e, operands.as, null),
        .prompt_v => |operands| try prompt(fiber, localData, upvalueData, operands.e, operands.as, operands.y),

        .ret => try ret(fiber, function, callFrame, localData, upvalueData, null),
        .ret_v => |operands| try ret(fiber, function, callFrame, localData, upvalueData, operands.y),
        .term => try term(fiber, function, callFrame, localData, upvalueData, null),
        .term_v => |operands| try term(fiber, function, callFrame, localData, upvalueData, operands.y),

        .addr => |operands| {
            const bytes: [*]const u8 = try addr(globals, stack, localData, upvalueData, operands.x, 0);

            try write(globals, stack, localData, upvalueData, operands.y, bytes);
        },

        // TODO: replace these with specific bit-sized operations? ie load8, load16, etc
        .load => |operands| {
            const inAddr: [*]const u8 = try read([*]const u8, globals, stack, localData, upvalueData, operands.x);
            const outAddr: [*]u8 = try addr(globals, stack, localData, upvalueData, operands.y, operands.m);

            try boundsCheck(globals, stack, inAddr, operands.m);

            @memcpy(outAddr[0..operands.m], inAddr);
        },

        .store => |operands| {
            const inAddr: [*]const u8 = try addr(globals, stack, localData, upvalueData, operands.x, operands.m);
            const outAddr: [*]u8 = try read([*]u8, globals, stack, localData, upvalueData, operands.y);

            try boundsCheck(globals, stack, outAddr, operands.m);

            @memcpy(outAddr[0..operands.m], inAddr);
        },

        .clear => |operands| {
            const bytes: [*]u8 = try addr(globals, stack, localData, upvalueData, operands.x, operands.m);

            @memset(bytes[0..operands.m], 0);
        },

        .swap => |operands| {
            const xBytes: [*]u8 = try addr(globals, stack, localData, upvalueData, operands.x, operands.m);
            const yBytes: [*]u8 = try addr(globals, stack, localData, upvalueData, operands.y, operands.m);

            for (0..operands.m) |i| {
                @call(Config.INLINING_CALL_MOD, std.mem.swap, .{u8, &xBytes[i], &yBytes[i]});
            }
        },

        .copy => |operands| {
            const xBytes: [*]const u8 = try addr(globals, stack, localData, upvalueData, operands.x, operands.m);
            const yBytes: [*]u8 = try addr(globals, stack, localData, upvalueData, operands.y, operands.m);

            @call(Config.INLINING_CALL_MOD, std.mem.copyForwards, .{u8, yBytes[0..operands.m], xBytes[0..operands.m]});
        },

        .b_not => |operands| try ops.unary(bool, "not", globals, stack, localData, upvalueData, operands),
        .b_and => |operands| try ops.binary(bool, "and", globals, stack, localData, upvalueData, operands),
        .b_or => |operands| try ops.binary(bool, "or", globals, stack, localData, upvalueData, operands),

        .f_add32 => |operands| try ops.binary(f32, "add", globals, stack, localData, upvalueData, operands),
        .f_add64 => |operands| try ops.binary(f64, "add", globals, stack, localData, upvalueData, operands),
        .f_sub32 => |operands| try ops.binary(f32, "sub", globals, stack, localData, upvalueData, operands),
        .f_sub64 => |operands| try ops.binary(f64, "sub", globals, stack, localData, upvalueData, operands),
        .f_mul32 => |operands| try ops.binary(f32, "mul", globals, stack, localData, upvalueData, operands),
        .f_mul64 => |operands| try ops.binary(f64, "mul", globals, stack, localData, upvalueData, operands),
        .f_div32 => |operands| try ops.binary(f32, "div", globals, stack, localData, upvalueData, operands),
        .f_div64 => |operands| try ops.binary(f64, "div", globals, stack, localData, upvalueData, operands),
        .f_rem32 => |operands| try ops.binary(f32, "rem", globals, stack, localData, upvalueData, operands),
        .f_rem64 => |operands| try ops.binary(f64, "rem", globals, stack, localData, upvalueData, operands),
        .f_neg32 => |operands| try ops.unary(f32, "neg", globals, stack, localData, upvalueData, operands),
        .f_neg64 => |operands| try ops.unary(f64, "neg", globals, stack, localData, upvalueData, operands),

        .f_eq32 => |operands| try ops.binary(f32, "eq", globals, stack, localData, upvalueData, operands),
        .f_eq64 => |operands| try ops.binary(f64, "eq", globals, stack, localData, upvalueData, operands),
        .f_ne32 => |operands| try ops.binary(f32, "ne", globals, stack, localData, upvalueData, operands),
        .f_ne64 => |operands| try ops.binary(f64, "ne", globals, stack, localData, upvalueData, operands),
        .f_lt32 => |operands| try ops.binary(f32, "lt", globals, stack, localData, upvalueData, operands),
        .f_lt64 => |operands| try ops.binary(f64, "lt", globals, stack, localData, upvalueData, operands),
        .f_gt32 => |operands| try ops.binary(f32, "gt", globals, stack, localData, upvalueData, operands),
        .f_gt64 => |operands| try ops.binary(f64, "gt", globals, stack, localData, upvalueData, operands),
        .f_le32 => |operands| try ops.binary(f32, "le", globals, stack, localData, upvalueData, operands),
        .f_le64 => |operands| try ops.binary(f64, "le", globals, stack, localData, upvalueData, operands),
        .f_ge32 => |operands| try ops.binary(f32, "ge", globals, stack, localData, upvalueData, operands),
        .f_ge64 => |operands| try ops.binary(f64, "ge", globals, stack, localData, upvalueData, operands),

        .i_add8 => |operands| try ops.binary(u8, "add", globals, stack, localData, upvalueData, operands),
        .i_add16 => |operands| try ops.binary(u16, "add", globals, stack, localData, upvalueData, operands),
        .i_add32 => |operands| try ops.binary(u32, "add", globals, stack, localData, upvalueData, operands),
        .i_add64 => |operands| try ops.binary(u64, "add", globals, stack, localData, upvalueData, operands),
        .i_sub8 => |operands| try ops.binary(u8, "sub", globals, stack, localData, upvalueData, operands),
        .i_sub16 => |operands| try ops.binary(u16, "sub", globals, stack, localData, upvalueData, operands),
        .i_sub32 => |operands| try ops.binary(u32, "sub", globals, stack, localData, upvalueData, operands),
        .i_sub64 => |operands| try ops.binary(u64, "sub", globals, stack, localData, upvalueData, operands),
        .i_mul8 => |operands| try ops.binary(u8, "mul", globals, stack, localData, upvalueData, operands),
        .i_mul16 => |operands| try ops.binary(u16, "mul", globals, stack, localData, upvalueData, operands),
        .i_mul32 => |operands| try ops.binary(u32, "mul", globals, stack, localData, upvalueData, operands),
        .i_mul64 => |operands| try ops.binary(u64, "mul", globals, stack, localData, upvalueData, operands),
        .s_div8 => |operands| try ops.binary(i8, "divFloor", globals, stack, localData, upvalueData, operands),
        .s_div16 => |operands| try ops.binary(i16, "divFloor", globals, stack, localData, upvalueData, operands),
        .s_div32 => |operands| try ops.binary(i32, "divFloor", globals, stack, localData, upvalueData, operands),
        .s_div64 => |operands| try ops.binary(i64, "divFloor", globals, stack, localData, upvalueData, operands),
        .u_div8 => |operands| try ops.binary(u8, "div", globals, stack, localData, upvalueData, operands),
        .u_div16 => |operands| try ops.binary(u16, "div", globals, stack, localData, upvalueData, operands),
        .u_div32 => |operands| try ops.binary(u32, "div", globals, stack, localData, upvalueData, operands),
        .u_div64 => |operands| try ops.binary(u64, "div", globals, stack, localData, upvalueData, operands),
        .s_rem8 => |operands| try ops.binary(i8, "rem", globals, stack, localData, upvalueData, operands),
        .s_rem16 => |operands| try ops.binary(i16, "rem", globals, stack, localData, upvalueData, operands),
        .s_rem32 => |operands| try ops.binary(i32, "rem", globals, stack, localData, upvalueData, operands),
        .s_rem64 => |operands| try ops.binary(i64, "rem", globals, stack, localData, upvalueData, operands),
        .u_rem8 => |operands| try ops.binary(u8, "rem", globals, stack, localData, upvalueData, operands),
        .u_rem16 => |operands| try ops.binary(u16, "rem", globals, stack, localData, upvalueData, operands),
        .u_rem32 => |operands| try ops.binary(u32, "rem", globals, stack, localData, upvalueData, operands),
        .u_rem64 => |operands| try ops.binary(u64, "rem", globals, stack, localData, upvalueData, operands),
        .s_neg8 => |operands| try ops.unary(i8, "neg", globals, stack, localData, upvalueData, operands),
        .s_neg16 => |operands| try ops.unary(i16, "neg", globals, stack, localData, upvalueData, operands),
        .s_neg32 => |operands| try ops.unary(i32, "neg", globals, stack, localData, upvalueData, operands),
        .s_neg64 => |operands| try ops.unary(i64, "neg", globals, stack, localData, upvalueData, operands),

        .i_bitnot8 => |operands| try ops.unary(u8, "bitnot", globals, stack, localData, upvalueData, operands),
        .i_bitnot16 => |operands| try ops.unary(u16, "bitnot", globals, stack, localData, upvalueData, operands),
        .i_bitnot32 => |operands| try ops.unary(u32, "bitnot", globals, stack, localData, upvalueData, operands),
        .i_bitnot64 => |operands| try ops.unary(u64, "bitnot", globals, stack, localData, upvalueData, operands),
        .i_bitand8 => |operands| try ops.binary(u8, "bitand", globals, stack, localData, upvalueData, operands),
        .i_bitand16 => |operands| try ops.binary(u16, "bitand", globals, stack, localData, upvalueData, operands),
        .i_bitand32 => |operands| try ops.binary(u32, "bitand", globals, stack, localData, upvalueData, operands),
        .i_bitand64 => |operands| try ops.binary(u64, "bitand", globals, stack, localData, upvalueData, operands),
        .i_bitor8 => |operands| try ops.binary(u8, "bitor", globals, stack, localData, upvalueData, operands),
        .i_bitor16 => |operands| try ops.binary(u16, "bitor", globals, stack, localData, upvalueData, operands),
        .i_bitor32 => |operands| try ops.binary(u32, "bitor", globals, stack, localData, upvalueData, operands),
        .i_bitor64 => |operands| try ops.binary(u64, "bitor", globals, stack, localData, upvalueData, operands),
        .i_bitxor8 => |operands| try ops.binary(u8, "bitxor", globals, stack, localData, upvalueData, operands),
        .i_bitxor16 => |operands| try ops.binary(u16, "bitxor", globals, stack, localData, upvalueData, operands),
        .i_bitxor32 => |operands| try ops.binary(u32, "bitxor", globals, stack, localData, upvalueData, operands),
        .i_bitxor64 => |operands| try ops.binary(u64, "bitxor", globals, stack, localData, upvalueData, operands),
        .i_shiftl8 => |operands| try ops.binary(u8, "shiftl", globals, stack, localData, upvalueData, operands),
        .i_shiftl16 => |operands| try ops.binary(u16, "shiftl", globals, stack, localData, upvalueData, operands),
        .i_shiftl32 => |operands| try ops.binary(u32, "shiftl", globals, stack, localData, upvalueData, operands),
        .i_shiftl64 => |operands| try ops.binary(u64, "shiftl", globals, stack, localData, upvalueData, operands),
        .u_shiftr8 => |operands| try ops.binary(u8, "shiftr", globals, stack, localData, upvalueData, operands),
        .u_shiftr16 => |operands| try ops.binary(u16, "shiftr", globals, stack, localData, upvalueData, operands),
        .u_shiftr32 => |operands| try ops.binary(u32, "shiftr", globals, stack, localData, upvalueData, operands),
        .u_shiftr64 => |operands| try ops.binary(u64, "shiftr", globals, stack, localData, upvalueData, operands),
        .s_shiftr8 => |operands| try ops.binary(i8, "shiftr", globals, stack, localData, upvalueData, operands),
        .s_shiftr16 => |operands| try ops.binary(i16, "shiftr", globals, stack, localData, upvalueData, operands),
        .s_shiftr32 => |operands| try ops.binary(i32, "shiftr", globals, stack, localData, upvalueData, operands),
        .s_shiftr64 => |operands| try ops.binary(i64, "shiftr", globals, stack, localData, upvalueData, operands),

        .i_eq8 => |operands| try ops.binary(u8, "eq", globals, stack, localData, upvalueData, operands),
        .i_eq16 => |operands| try ops.binary(u16, "eq", globals, stack, localData, upvalueData, operands),
        .i_eq32 => |operands| try ops.binary(u32, "eq", globals, stack, localData, upvalueData, operands),
        .i_eq64 => |operands| try ops.binary(u64, "eq", globals, stack, localData, upvalueData, operands),
        .i_ne8 => |operands| try ops.binary(u8, "ne", globals, stack, localData, upvalueData, operands),
        .i_ne16 => |operands| try ops.binary(u16, "ne", globals, stack, localData, upvalueData, operands),
        .i_ne32 => |operands| try ops.binary(u32, "ne", globals, stack, localData, upvalueData, operands),
        .i_ne64 => |operands| try ops.binary(u64, "ne", globals, stack, localData, upvalueData, operands),
        .u_lt8 => |operands| try ops.binary(u8, "lt", globals, stack, localData, upvalueData, operands),
        .u_lt16 => |operands| try ops.binary(u16, "lt", globals, stack, localData, upvalueData, operands),
        .u_lt32 => |operands| try ops.binary(u32, "lt", globals, stack, localData, upvalueData, operands),
        .u_lt64 => |operands| try ops.binary(u64, "lt", globals, stack, localData, upvalueData, operands),
        .s_lt8 => |operands| try ops.binary(i8, "lt", globals, stack, localData, upvalueData, operands),
        .s_lt16 => |operands| try ops.binary(i16, "lt", globals, stack, localData, upvalueData, operands),
        .s_lt32 => |operands| try ops.binary(i32, "lt", globals, stack, localData, upvalueData, operands),
        .s_lt64 => |operands| try ops.binary(i64, "lt", globals, stack, localData, upvalueData, operands),
        .u_gt8 => |operands| try ops.binary(u8, "gt", globals, stack, localData, upvalueData, operands),
        .u_gt16 => |operands| try ops.binary(u16, "gt", globals, stack, localData, upvalueData, operands),
        .u_gt32 => |operands| try ops.binary(u32, "gt", globals, stack, localData, upvalueData, operands),
        .u_gt64 => |operands| try ops.binary(u64, "gt", globals, stack, localData, upvalueData, operands),
        .s_gt8 => |operands| try ops.binary(i8, "gt", globals, stack, localData, upvalueData, operands),
        .s_gt16 => |operands| try ops.binary(i16, "gt", globals, stack, localData, upvalueData, operands),
        .s_gt32 => |operands| try ops.binary(i32, "gt", globals, stack, localData, upvalueData, operands),
        .s_gt64 => |operands| try ops.binary(i64, "gt", globals, stack, localData, upvalueData, operands),
        .u_le8 => |operands| try ops.binary(u8, "le", globals, stack, localData, upvalueData, operands),
        .u_le16 => |operands| try ops.binary(u16, "le", globals, stack, localData, upvalueData, operands),
        .u_le32 => |operands| try ops.binary(u32, "le", globals, stack, localData, upvalueData, operands),
        .u_le64 => |operands| try ops.binary(u64, "le", globals, stack, localData, upvalueData, operands),
        .s_le8 => |operands| try ops.binary(i8, "le", globals, stack, localData, upvalueData, operands),
        .s_le16 => |operands| try ops.binary(i16, "le", globals, stack, localData, upvalueData, operands),
        .s_le32 => |operands| try ops.binary(i32, "le", globals, stack, localData, upvalueData, operands),
        .s_le64 => |operands| try ops.binary(i64, "le", globals, stack, localData, upvalueData, operands),
        .u_ge8 => |operands| try ops.binary(u8, "ge", globals, stack, localData, upvalueData, operands),
        .u_ge16 => |operands| try ops.binary(u16, "ge", globals, stack, localData, upvalueData, operands),
        .u_ge32 => |operands| try ops.binary(u32, "ge", globals, stack, localData, upvalueData, operands),
        .u_ge64 => |operands| try ops.binary(u64, "ge", globals, stack, localData, upvalueData, operands),
        .s_ge8 => |operands| try ops.binary(i8, "ge", globals, stack, localData, upvalueData, operands),
        .s_ge16 => |operands| try ops.binary(i16, "ge", globals, stack, localData, upvalueData, operands),
        .s_ge32 => |operands| try ops.binary(i32, "ge", globals, stack, localData, upvalueData, operands),
        .s_ge64 => |operands| try ops.binary(i64, "ge", globals, stack, localData, upvalueData, operands),

        .u_ext8x16 => |operands| try ops.cast(u8, u16, globals, stack, localData, upvalueData, operands),
        .u_ext8x32 => |operands| try ops.cast(u8, u32, globals, stack, localData, upvalueData, operands),
        .u_ext8x64 => |operands| try ops.cast(u8, u64, globals, stack, localData, upvalueData, operands),
        .u_ext16x32 => |operands| try ops.cast(u16, u32, globals, stack, localData, upvalueData, operands),
        .u_ext16x64 => |operands| try ops.cast(u16, u64, globals, stack, localData, upvalueData, operands),
        .u_ext32x64 => |operands| try ops.cast(u32, u64, globals, stack, localData, upvalueData, operands),
        .s_ext8x16 => |operands| try ops.cast(i8, i16, globals, stack, localData, upvalueData, operands),
        .s_ext8x32 => |operands| try ops.cast(i8, i32, globals, stack, localData, upvalueData, operands),
        .s_ext8x64 => |operands| try ops.cast(i8, i64, globals, stack, localData, upvalueData, operands),
        .s_ext16x32 => |operands| try ops.cast(i16, i32, globals, stack, localData, upvalueData, operands),
        .s_ext16x64 => |operands| try ops.cast(i16, i64, globals, stack, localData, upvalueData, operands),
        .s_ext32x64 => |operands| try ops.cast(i32, i64, globals, stack, localData, upvalueData, operands),
        .f_ext32x64 => |operands| try ops.cast(f32, i64, globals, stack, localData, upvalueData, operands),

        .i_trunc64x32 => |operands| try ops.cast(u64, u32, globals, stack, localData, upvalueData, operands),
        .i_trunc64x16 => |operands| try ops.cast(u64, u16, globals, stack, localData, upvalueData, operands),
        .i_trunc64x8 => |operands| try ops.cast(u64, u8, globals, stack, localData, upvalueData, operands),
        .i_trunc32x16 => |operands| try ops.cast(u32, u16, globals, stack, localData, upvalueData, operands),
        .i_trunc32x8 => |operands| try ops.cast(u32, u8, globals, stack, localData, upvalueData, operands),
        .i_trunc16x8 => |operands| try ops.cast(u16, u8, globals, stack, localData, upvalueData, operands),
        .f_trunc64x32 => |operands| try ops.cast(f64, f32, globals, stack, localData, upvalueData, operands),

        .u8_to_f32 => |operands| try ops.cast(u8, f32, globals, stack, localData, upvalueData, operands),
        .u8_to_f64 => |operands| try ops.cast(u8, f64, globals, stack, localData, upvalueData, operands),
        .u16_to_f32 => |operands| try ops.cast(u16, f32, globals, stack, localData, upvalueData, operands),
        .u16_to_f64 => |operands| try ops.cast(u16, f64, globals, stack, localData, upvalueData, operands),
        .u32_to_f32 => |operands| try ops.cast(u32, f32, globals, stack, localData, upvalueData, operands),
        .u32_to_f64 => |operands| try ops.cast(u32, f64, globals, stack, localData, upvalueData, operands),
        .u64_to_f32 => |operands| try ops.cast(u64, f32, globals, stack, localData, upvalueData, operands),
        .u64_to_f64 => |operands| try ops.cast(u64, f64, globals, stack, localData, upvalueData, operands),
        .s8_to_f32 => |operands| try ops.cast(i8, f32, globals, stack, localData, upvalueData, operands),
        .s8_to_f64 => |operands| try ops.cast(i8, f64, globals, stack, localData, upvalueData, operands),
        .s16_to_f32 => |operands| try ops.cast(i16, f32, globals, stack, localData, upvalueData, operands),
        .s16_to_f64 => |operands| try ops.cast(i16, f64, globals, stack, localData, upvalueData, operands),
        .s32_to_f32 => |operands| try ops.cast(i32, f32, globals, stack, localData, upvalueData, operands),
        .s32_to_f64 => |operands| try ops.cast(i32, f64, globals, stack, localData, upvalueData, operands),
        .s64_to_f32 => |operands| try ops.cast(i64, f32, globals, stack, localData, upvalueData, operands),
        .s64_to_f64 => |operands| try ops.cast(i64, f64, globals, stack, localData, upvalueData, operands),
        .f32_to_u8 => |operands| try ops.cast(f32, u8, globals, stack, localData, upvalueData, operands),
        .f32_to_u16 => |operands| try ops.cast(f32, u16, globals, stack, localData, upvalueData, operands),
        .f32_to_u32 => |operands| try ops.cast(f32, u32, globals, stack, localData, upvalueData, operands),
        .f32_to_u64 => |operands| try ops.cast(f32, u64, globals, stack, localData, upvalueData, operands),
        .f64_to_u8 => |operands| try ops.cast(f64, u8, globals, stack, localData, upvalueData, operands),
        .f64_to_u16 => |operands| try ops.cast(f64, u16, globals, stack, localData, upvalueData, operands),
        .f64_to_u32 => |operands| try ops.cast(f64, u32, globals, stack, localData, upvalueData, operands),
        .f64_to_u64 => |operands| try ops.cast(f64, u64, globals, stack, localData, upvalueData, operands),
        .f32_to_s8 => |operands| try ops.cast(f32, i8, globals, stack, localData, upvalueData, operands),
        .f32_to_s16 => |operands| try ops.cast(f32, i16, globals, stack, localData, upvalueData, operands),
        .f32_to_s32 => |operands| try ops.cast(f32, i32, globals, stack, localData, upvalueData, operands),
        .f32_to_s64 => |operands| try ops.cast(f32, i64, globals, stack, localData, upvalueData, operands),
        .f64_to_s8 => |operands| try ops.cast(f64, i8, globals, stack, localData, upvalueData, operands),
        .f64_to_s16 => |operands| try ops.cast(f64, i16, globals, stack, localData, upvalueData, operands),
        .f64_to_s32 => |operands| try ops.cast(f64, i32, globals, stack, localData, upvalueData, operands),
        .f64_to_s64 => |operands| try ops.cast(f64, i64, globals, stack, localData, upvalueData, operands),

        else => Support.todo(noreturn, {})
    }
}

pub fn stepNative(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, native: Bytecode.Function.Native) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, localData, upvalueData, native});
}

fn extractUp(upvalueData: ?RegisterData) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!RegisterData {
    if (upvalueData) |ud| {
        return ud;
    } else {
        @branchHint(.cold);
        return Fiber.Trap.MissingEvidence;
    }
}

pub fn call(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, func: Bytecode.Operand, args: []const Bytecode.Operand, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const funcIndex = try read(Bytecode.FunctionIndex, &fiber.program.globals, &fiber.stack.data, localData, upvalueData, func);

    if (funcIndex >= fiber.program.functions.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return callImpl(fiber, localData, upvalueData, Bytecode.EVIDENCE_SENTINEL, funcIndex, args, out);
}

pub fn prompt(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, evIndex: Bytecode.EvidenceIndex, args: []const Bytecode.Operand, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (evIndex >= fiber.evidence.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const evidence = &fiber.evidence[evIndex];

    return callImpl(fiber, localData, upvalueData, evIndex, evidence.handler, args, out);
}

fn callImpl(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    if (args.len != newFunction.layout_table.num_arguments) {
        @branchHint(.cold);
        return Fiber.Trap.ArgCountMismatch;
    }

    // ensure ret val will fit
    // FIXME: alignment
    if (out) |outOperand| {
        if (newFunction.layout_table.return_layout) |returnLayout| {
            _ = try slice(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, outOperand, returnLayout.size);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.OutValueMismatch;
        }
    }

    const base = fiber.stack.data.ptr;
    // FIXME: alignment
    const origin = base;

    for (0..args.len) |i| {
        const desiredSize = newFunction.layout_table.register_layouts[i].size;
        const arg = try slice(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, args[i], desiredSize);
        // FIXME: alignment
        try fiber.stack.data.pushSlice(arg);
    }

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = funcIndex,
        .evidence = evIndex,
        .block = fiber.stack.block.ptr,
        .stack = .{
            .base = base,
            .origin = origin,
        },
    });

    try fiber.stack.block.push(.entryPoint(out));
}

pub fn term(fiber: *Fiber, function: *Bytecode.Function, callFrame: *Fiber.CallFrame, localData: RegisterData, upvalueData: ?RegisterData, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (callFrame.evidence == Bytecode.EVIDENCE_SENTINEL) {
        @branchHint(.cold);
        return Fiber.Trap.MissingEvidence;
    }

    const evidence = &fiber.evidence[callFrame.evidence];

    const rootFunction = &fiber.program.functions[evidence.handler];
    const rootBlockFrame = try fiber.stack.block.getPtr(evidence.block);
    const rootBlock = &rootFunction.value.bytecode.blocks[rootBlockFrame.index];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = function.layout_table.term_layout.?.size;
            const src: [*]const u8 = try addr(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, outOp, size);
            const dest: [*]u8 = try addr(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, rootBlockFrame.out, size);
            @memcpy(dest[0..size], src);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.MissingOutputValue;
        }
    }

    fiber.stack.data.ptr = evidence.data;
    fiber.stack.call.ptr = evidence.call;
    fiber.stack.block.ptr = evidence.block - 1;
}

pub fn ret(fiber: *Fiber, function: *Bytecode.Function, callFrame: *Fiber.CallFrame, localData: RegisterData, upvalueData: ?RegisterData, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const rootBlockFrame = try fiber.stack.block.getPtr(callFrame.block);

    const rootBlock = &function.value.bytecode.blocks[rootBlockFrame.index];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = function.layout_table.return_layout.?.size;
            const src: [*]const u8 = try addr(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, outOp, size);
            const dest: [*]u8 = try addr(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, rootBlockFrame.out, size);
            @memcpy(dest[0..size], src);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.MissingOutputValue;
        }
    }

    fiber.stack.data.ptr = callFrame.stack.base;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = callFrame.block - 1;
}

pub fn read(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const size = @sizeOf(T);

    switch (operand.kind) {
        .global => {
            const bytes = try getGlobal(globals, operand.data.global, size);

            var value: T = undefined;
            @memcpy(@as([*]u8, @ptrCast(&value)), bytes);

            return value;
        },

        .upvalue => return readImpl(T, stack, try extractUp(upvalueData), operand.data.register),
        .local => return readImpl(T, stack, localData, operand.data.register),
    }
}

pub fn write(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    switch (operand.kind) {
        .global => {
            const mem = try getGlobal(globals, operand.data.global, @sizeOf(@TypeOf(value)));

            @memcpy(mem, @as([*]const u8, @ptrCast(&value)));
        },

        .upvalue => try writeImpl(stack, try extractUp(upvalueData), operand.data.register, value),
        .local => try writeImpl(stack, localData, operand.data.register, value),
    }
}

pub fn addr(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    switch (operand.kind) {
        .global => return (try getGlobal(globals, operand.data.global, size)).ptr,
        .upvalue => return addrImpl(stack, try extractUp(upvalueData), operand.data.register, size),
        .local => return addrImpl(stack, localData, operand.data.register, size),
    }
}

fn addrImpl(stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, @truncate(size))) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(try stack.getPtr(base + operand.offset));
}

fn slice(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![]u8 {
    switch (operand.kind) {
        .global => return getGlobal(globals, operand.data.global, size),
        .upvalue => return sliceImpl(stack, try extractUp(upvalueData), operand.data.register, size),
        .local => return sliceImpl(stack, localData, operand.data.register, size),
    }
}

fn sliceImpl(stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![]u8 {
    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return try stack.getSlice(base + operand.offset, size);
}

fn readImpl(comptime T: type, stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const size = @sizeOf(T);

    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    // FIXME: need to do alignment on stack values so that this memcpy can be replaced with aligned read
    var value: T = undefined;
    const bytes = try stack.getSlice(base + operand.offset, size);

    @memcpy(@as([*]u8, @ptrCast(&value)), bytes);

    return value;
}

fn writeImpl(stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(@TypeOf(value));

    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    // FIXME: need to do alignment on stack values so that this memcpy can be replaced with aligned write
    const bytes = @as([*]const u8, @ptrCast(&value))[0..size];
    try stack.setSlice(base + operand.offset, bytes);
}

pub fn getGlobal(globals: *Bytecode.GlobalSet, operand: Bytecode.GlobalOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![]u8 {
    if (operand.index >= globals.values.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const data = &globals.values[operand.index];

    if (!data.layout.inbounds(operand.offset, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return globals.memory[operand.offset..operand.offset + size];
}

pub fn getOperandOffset(regData: RegisterData, register: Bytecode.Register) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.DataStack.Ptr {
    const regNumber: Bytecode.RegisterIndex = @intFromEnum(register);

    if (regNumber < regData.layout.num_registers) {
        return regData.call.stack.base + regData.layout.register_offsets[regNumber];
    } else {
        @branchHint(.cold);

        return Fiber.Trap.OutOfBounds;
    }
}

pub fn boundsCheck(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, address: [*]const u8, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const validGlobalA = @intFromBool(@intFromPtr(address) >= @intFromPtr(globals.memory.ptr));
    const validGlobalB = @intFromBool(@intFromPtr(address) + size <= @intFromPtr(globals.memory.ptr) + globals.memory.len);

    const validStackA = @intFromBool(@intFromPtr(address) >= @intFromPtr(stack.memory.ptr));
    const validStackB = @intFromBool(@intFromPtr(address) + size <= stack.ptr);

    if ((validGlobalA & validGlobalB) | (validStackA & validStackB) == 0) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }
}


const ops = struct {
    fn cast(comptime A: type, comptime B: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
        const x = try read(A, globals, stack, localData, upvalueData, operands.x);

        const aKind = @as(std.builtin.TypeId, @typeInfo(A));
        const bKind = @as(std.builtin.TypeId, @typeInfo(B));
        const result =
            if (comptime aKind == bKind) (
                if (comptime aKind == .int) @call(Config.INLINING_CALL_MOD, intCast, .{B, x})
                else @call(Config.INLINING_CALL_MOD, floatCast, .{B, x})
            ) else @call(Config.INLINING_CALL_MOD, typeCast, .{B, x});

        try write(globals, stack, localData, upvalueData, operands.y, result);
    }

    fn unary(comptime T: type, comptime op: []const u8, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
        const x = try read(T, globals, stack, localData, upvalueData, operands.x);

        const result = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x});

        try write(globals, stack, localData, upvalueData, operands.y, result);
    }

    fn binary(comptime T: type, comptime op: []const u8, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operands: Bytecode.ISA.ThreeOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
        const x = try read(T, globals, stack, localData, upvalueData, operands.x);
        const y = try read(T, globals, stack, localData, upvalueData, operands.y);

        const result = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x, y});

        try write(globals, stack, localData, upvalueData, operands.z, result);
    }

    fn intCast(comptime T: type, x: anytype) T {
        const U = @TypeOf(x);

        if (comptime @typeInfo(U).int.bits > @typeInfo(T).int.bits) {
            return @truncate(x);
        } else {
            return x;
        }
    }

    fn floatCast(comptime T: type, x: anytype) T {
        return @floatCast(x);
    }

    fn typeCast(comptime T: type, x: anytype) T {
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
