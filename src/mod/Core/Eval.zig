const std = @import("std");

const Config = @import("Config");
const Support = @import("Support");

const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Core = @import("root.zig");
const Fiber = Core.Fiber;


const Eval = @This();



pub fn step(fiber: *Fiber) Fiber.Trap!void {
    const callFrame = try fiber.stack.call.topPtr();
    const function = &fiber.program.functions[callFrame.function];

    const registerData = try getRegisterData(fiber, callFrame, function);

    switch (function.value) {
        .bytecode => try @call(Config.INLINING_CALL_MOD, stepBytecode, .{fiber, callFrame, function, registerData}),
        .foreign => try @call(Config.INLINING_CALL_MOD, stepForeign, .{fiber, callFrame, function, registerData}),
    }
}

pub fn stepBytecode(fiber: *Fiber, callFrame: *Fiber.CallFrame, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet) Fiber.Trap!void {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA);

    const blockFrame = try fiber.stack.block.topPtr();
    const block = &function.value.bytecode.blocks[blockFrame.index];

    const decoder = IO.Decoder {
        .memory = function.value.bytecode.instructions,
        .base = block.base,
        .offset = &blockFrame.ip_offset,
    };

    const instr = try decoder.decodeInline(Bytecode.Op);

    switch (instr) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => {},

        .tail_call => |operands| try call(fiber, callFrame, function, registerData, operands.f, operands.as, .tail),
        .tail_call_v => |operands| try call(fiber, callFrame, function, registerData, operands.f, operands.as, .tail_v),
        .dyn_tail_call => |operands| try dynCall(fiber, callFrame, function, registerData, operands.f, operands.as, .tail),
        .dyn_tail_call_v => |operands| try dynCall(fiber, callFrame, function, registerData, operands.f, operands.as, .tail_v),
        .tail_prompt => |operands| try prompt(fiber, callFrame, function, registerData, operands.e, operands.as, .tail),
        .tail_prompt_v => |operands| try prompt(fiber, callFrame, function, registerData, operands.e, operands.as, .tail_v),

        .call => |operands| try call(fiber, callFrame, function, registerData, operands.f, operands.as, .no_tail),
        .call_v => |operands| try call(fiber, callFrame, function, registerData, operands.f, operands.as, .{ .no_tail_v = operands.y }),
        .dyn_call => |operands| try dynCall(fiber, callFrame, function, registerData, operands.f, operands.as, .no_tail),
        .dyn_call_v => |operands| try dynCall(fiber, callFrame, function, registerData, operands.f, operands.as, .{ .no_tail_v = operands.y }),
        .prompt => |operands| try prompt(fiber, callFrame, function, registerData, operands.e, operands.as, .no_tail),
        .prompt_v => |operands| try prompt(fiber, callFrame, function, registerData, operands.e, operands.as, .{ .no_tail_v = operands.y }),

        .ret => try ret(fiber, callFrame, function, registerData, null),
        .ret_v => |operands| try ret(fiber, callFrame, function, registerData, operands.y),
        .term => try term(fiber, callFrame, function, registerData, null),
        .term_v => |operands| try term(fiber, callFrame, function, registerData, operands.y),

        .when_z => |operands| try when(fiber, function, registerData, operands.b, operands.x, .zero),
        .when_nz => |operands| try when(fiber, function, registerData, operands.b, operands.x, .non_zero),

        .re => |operands| try re(fiber, function, registerData, operands.b, null, null),
        .re_z => |operands| try re(fiber, function, registerData, operands.b, operands.x, .zero),
        .re_nz => |operands| try re(fiber, function, registerData, operands.b, operands.x, .non_zero),

        .br => |operands | try br(fiber, function, registerData, operands.b, null, null),
        .br_z => |operands | try br(fiber, function, registerData, operands.b, operands.x, .zero),
        .br_nz => |operands | try br(fiber, function, registerData, operands.b, operands.x, .non_zero),

        .br_v => |operands| try br_v(fiber, function, registerData, operands.b, null, operands.y, null),
        .br_z_v => |operands| try br_v(fiber, function, registerData, operands.b, operands.x, operands.y, .zero),
        .br_nz_v => |operands| try br_v(fiber, function, registerData, operands.b, operands.x, operands.y, .non_zero),

        .block => |operands| try blockImpl(fiber, function, operands.b, null),
        .block_v => |operands| try blockImpl(fiber, function, operands.b, operands.y),

        .with => |operands| try with(fiber, function, operands.b, operands.h, null),
        .with_v => |operands| try with(fiber, function, operands.b, operands.h, operands.y),

        .if_z => |operands| try ifImpl(fiber, function, registerData, operands.t, operands.e, operands.x, null, .zero),
        .if_nz => |operands| try ifImpl(fiber, function, registerData, operands.t, operands.e, operands.x, null, .non_zero),
        .if_z_v => |operands| try ifImpl(fiber, function, registerData, operands.t, operands.e, operands.x, operands.y, .zero),
        .if_nz_v => |operands| try ifImpl(fiber, function, registerData, operands.t, operands.e, operands.x, operands.y, .non_zero),

        .case => |operands| try case(fiber, function, registerData, operands.bs, operands.x, null),
        .case_v => |operands| try case(fiber, function, registerData, operands.bs, operands.x, operands.y),

        .addr => |operands| try addrImpl(fiber, registerData, operands.x, operands.y),

        .load8 => |operands| try load(u8, fiber, registerData, operands.x, operands.y),
        .load16 => |operands| try load(u16, fiber, registerData, operands.x, operands.y),
        .load32 => |operands| try load(u32, fiber, registerData, operands.x, operands.y),
        .load64 => |operands| try load(u64, fiber, registerData, operands.x, operands.y),

        .store8 => |operands| try store(u8, fiber, registerData, operands.x, operands.y),
        .store16 => |operands| try store(u16, fiber, registerData, operands.x, operands.y),
        .store32 => |operands| try store(u32, fiber, registerData, operands.x, operands.y),
        .store64 => |operands| try store(u64, fiber, registerData, operands.x, operands.y),

        .clear8 => |operands| try clear(u8, fiber, registerData, operands.x),
        .clear16 => |operands| try clear(u16, fiber, registerData, operands.x),
        .clear32 => |operands| try clear(u32, fiber, registerData, operands.x),
        .clear64 => |operands| try clear(u64, fiber, registerData, operands.x),

        .swap8 => |operands| try swap(u8, fiber, registerData, operands.x, operands.y),
        .swap16 => |operands| try swap(u16, fiber, registerData, operands.x, operands.y),
        .swap32 => |operands| try swap(u32, fiber, registerData, operands.x, operands.y),
        .swap64 => |operands| try swap(u64, fiber, registerData, operands.x, operands.y),

        .copy8 => |operands| try copy(u8, fiber, registerData, operands.x, operands.y),
        .copy16 => |operands| try copy(u16, fiber, registerData, operands.x, operands.y),
        .copy32 => |operands| try copy(u32, fiber, registerData, operands.x, operands.y),
        .copy64 => |operands| try copy(u64, fiber, registerData, operands.x, operands.y),

        .b_not => |operands| try ops.unary(bool, "not", fiber, registerData, operands),
        .b_and => |operands| try ops.binary(bool, "and", fiber, registerData, operands),
        .b_or => |operands| try ops.binary(bool, "or", fiber, registerData, operands),

        .f_add32 => |operands| try ops.binary(f32, "add", fiber, registerData, operands),
        .f_add64 => |operands| try ops.binary(f64, "add", fiber, registerData, operands),
        .f_sub32 => |operands| try ops.binary(f32, "sub", fiber, registerData, operands),
        .f_sub64 => |operands| try ops.binary(f64, "sub", fiber, registerData, operands),
        .f_mul32 => |operands| try ops.binary(f32, "mul", fiber, registerData, operands),
        .f_mul64 => |operands| try ops.binary(f64, "mul", fiber, registerData, operands),
        .f_div32 => |operands| try ops.binary(f32, "div", fiber, registerData, operands),
        .f_div64 => |operands| try ops.binary(f64, "div", fiber, registerData, operands),
        .f_rem32 => |operands| try ops.binary(f32, "rem", fiber, registerData, operands),
        .f_rem64 => |operands| try ops.binary(f64, "rem", fiber, registerData, operands),
        .f_neg32 => |operands| try ops.unary(f32, "neg", fiber, registerData, operands),
        .f_neg64 => |operands| try ops.unary(f64, "neg", fiber, registerData, operands),

        .f_eq32 => |operands| try ops.binary(f32, "eq", fiber, registerData, operands),
        .f_eq64 => |operands| try ops.binary(f64, "eq", fiber, registerData, operands),
        .f_ne32 => |operands| try ops.binary(f32, "ne", fiber, registerData, operands),
        .f_ne64 => |operands| try ops.binary(f64, "ne", fiber, registerData, operands),
        .f_lt32 => |operands| try ops.binary(f32, "lt", fiber, registerData, operands),
        .f_lt64 => |operands| try ops.binary(f64, "lt", fiber, registerData, operands),
        .f_gt32 => |operands| try ops.binary(f32, "gt", fiber, registerData, operands),
        .f_gt64 => |operands| try ops.binary(f64, "gt", fiber, registerData, operands),
        .f_le32 => |operands| try ops.binary(f32, "le", fiber, registerData, operands),
        .f_le64 => |operands| try ops.binary(f64, "le", fiber, registerData, operands),
        .f_ge32 => |operands| try ops.binary(f32, "ge", fiber, registerData, operands),
        .f_ge64 => |operands| try ops.binary(f64, "ge", fiber, registerData, operands),

        .i_add8 => |operands| try ops.binary(u8, "add", fiber, registerData, operands),
        .i_add16 => |operands| try ops.binary(u16, "add", fiber, registerData, operands),
        .i_add32 => |operands| try ops.binary(u32, "add", fiber, registerData, operands),
        .i_add64 => |operands| try ops.binary(u64, "add", fiber, registerData, operands),
        .i_sub8 => |operands| try ops.binary(u8, "sub", fiber, registerData, operands),
        .i_sub16 => |operands| try ops.binary(u16, "sub", fiber, registerData, operands),
        .i_sub32 => |operands| try ops.binary(u32, "sub", fiber, registerData, operands),
        .i_sub64 => |operands| try ops.binary(u64, "sub", fiber, registerData, operands),
        .i_mul8 => |operands| try ops.binary(u8, "mul", fiber, registerData, operands),
        .i_mul16 => |operands| try ops.binary(u16, "mul", fiber, registerData, operands),
        .i_mul32 => |operands| try ops.binary(u32, "mul", fiber, registerData, operands),
        .i_mul64 => |operands| try ops.binary(u64, "mul", fiber, registerData, operands),
        .s_div8 => |operands| try ops.binary(i8, "divFloor", fiber, registerData, operands),
        .s_div16 => |operands| try ops.binary(i16, "divFloor", fiber, registerData, operands),
        .s_div32 => |operands| try ops.binary(i32, "divFloor", fiber, registerData, operands),
        .s_div64 => |operands| try ops.binary(i64, "divFloor", fiber, registerData, operands),
        .u_div8 => |operands| try ops.binary(u8, "div", fiber, registerData, operands),
        .u_div16 => |operands| try ops.binary(u16, "div", fiber, registerData, operands),
        .u_div32 => |operands| try ops.binary(u32, "div", fiber, registerData, operands),
        .u_div64 => |operands| try ops.binary(u64, "div", fiber, registerData, operands),
        .s_rem8 => |operands| try ops.binary(i8, "rem", fiber, registerData, operands),
        .s_rem16 => |operands| try ops.binary(i16, "rem", fiber, registerData, operands),
        .s_rem32 => |operands| try ops.binary(i32, "rem", fiber, registerData, operands),
        .s_rem64 => |operands| try ops.binary(i64, "rem", fiber, registerData, operands),
        .u_rem8 => |operands| try ops.binary(u8, "rem", fiber, registerData, operands),
        .u_rem16 => |operands| try ops.binary(u16, "rem", fiber, registerData, operands),
        .u_rem32 => |operands| try ops.binary(u32, "rem", fiber, registerData, operands),
        .u_rem64 => |operands| try ops.binary(u64, "rem", fiber, registerData, operands),
        .s_neg8 => |operands| try ops.unary(i8, "neg", fiber, registerData, operands),
        .s_neg16 => |operands| try ops.unary(i16, "neg", fiber, registerData, operands),
        .s_neg32 => |operands| try ops.unary(i32, "neg", fiber, registerData, operands),
        .s_neg64 => |operands| try ops.unary(i64, "neg", fiber, registerData, operands),

        .i_bitnot8 => |operands| try ops.unary(u8, "bitnot", fiber, registerData, operands),
        .i_bitnot16 => |operands| try ops.unary(u16, "bitnot", fiber, registerData, operands),
        .i_bitnot32 => |operands| try ops.unary(u32, "bitnot", fiber, registerData, operands),
        .i_bitnot64 => |operands| try ops.unary(u64, "bitnot", fiber, registerData, operands),
        .i_bitand8 => |operands| try ops.binary(u8, "bitand", fiber, registerData, operands),
        .i_bitand16 => |operands| try ops.binary(u16, "bitand", fiber, registerData, operands),
        .i_bitand32 => |operands| try ops.binary(u32, "bitand", fiber, registerData, operands),
        .i_bitand64 => |operands| try ops.binary(u64, "bitand", fiber, registerData, operands),
        .i_bitor8 => |operands| try ops.binary(u8, "bitor", fiber, registerData, operands),
        .i_bitor16 => |operands| try ops.binary(u16, "bitor", fiber, registerData, operands),
        .i_bitor32 => |operands| try ops.binary(u32, "bitor", fiber, registerData, operands),
        .i_bitor64 => |operands| try ops.binary(u64, "bitor", fiber, registerData, operands),
        .i_bitxor8 => |operands| try ops.binary(u8, "bitxor", fiber, registerData, operands),
        .i_bitxor16 => |operands| try ops.binary(u16, "bitxor", fiber, registerData, operands),
        .i_bitxor32 => |operands| try ops.binary(u32, "bitxor", fiber, registerData, operands),
        .i_bitxor64 => |operands| try ops.binary(u64, "bitxor", fiber, registerData, operands),
        .i_shiftl8 => |operands| try ops.binary(u8, "shiftl", fiber, registerData, operands),
        .i_shiftl16 => |operands| try ops.binary(u16, "shiftl", fiber, registerData, operands),
        .i_shiftl32 => |operands| try ops.binary(u32, "shiftl", fiber, registerData, operands),
        .i_shiftl64 => |operands| try ops.binary(u64, "shiftl", fiber, registerData, operands),
        .u_shiftr8 => |operands| try ops.binary(u8, "shiftr", fiber, registerData, operands),
        .u_shiftr16 => |operands| try ops.binary(u16, "shiftr", fiber, registerData, operands),
        .u_shiftr32 => |operands| try ops.binary(u32, "shiftr", fiber, registerData, operands),
        .u_shiftr64 => |operands| try ops.binary(u64, "shiftr", fiber, registerData, operands),
        .s_shiftr8 => |operands| try ops.binary(i8, "shiftr", fiber, registerData, operands),
        .s_shiftr16 => |operands| try ops.binary(i16, "shiftr", fiber, registerData, operands),
        .s_shiftr32 => |operands| try ops.binary(i32, "shiftr", fiber, registerData, operands),
        .s_shiftr64 => |operands| try ops.binary(i64, "shiftr", fiber, registerData, operands),

        .i_eq8 => |operands| try ops.binary(u8, "eq", fiber, registerData, operands),
        .i_eq16 => |operands| try ops.binary(u16, "eq", fiber, registerData, operands),
        .i_eq32 => |operands| try ops.binary(u32, "eq", fiber, registerData, operands),
        .i_eq64 => |operands| try ops.binary(u64, "eq", fiber, registerData, operands),
        .i_ne8 => |operands| try ops.binary(u8, "ne", fiber, registerData, operands),
        .i_ne16 => |operands| try ops.binary(u16, "ne", fiber, registerData, operands),
        .i_ne32 => |operands| try ops.binary(u32, "ne", fiber, registerData, operands),
        .i_ne64 => |operands| try ops.binary(u64, "ne", fiber, registerData, operands),
        .u_lt8 => |operands| try ops.binary(u8, "lt", fiber, registerData, operands),
        .u_lt16 => |operands| try ops.binary(u16, "lt", fiber, registerData, operands),
        .u_lt32 => |operands| try ops.binary(u32, "lt", fiber, registerData, operands),
        .u_lt64 => |operands| try ops.binary(u64, "lt", fiber, registerData, operands),
        .s_lt8 => |operands| try ops.binary(i8, "lt", fiber, registerData, operands),
        .s_lt16 => |operands| try ops.binary(i16, "lt", fiber, registerData, operands),
        .s_lt32 => |operands| try ops.binary(i32, "lt", fiber, registerData, operands),
        .s_lt64 => |operands| try ops.binary(i64, "lt", fiber, registerData, operands),
        .u_gt8 => |operands| try ops.binary(u8, "gt", fiber, registerData, operands),
        .u_gt16 => |operands| try ops.binary(u16, "gt", fiber, registerData, operands),
        .u_gt32 => |operands| try ops.binary(u32, "gt", fiber, registerData, operands),
        .u_gt64 => |operands| try ops.binary(u64, "gt", fiber, registerData, operands),
        .s_gt8 => |operands| try ops.binary(i8, "gt", fiber, registerData, operands),
        .s_gt16 => |operands| try ops.binary(i16, "gt", fiber, registerData, operands),
        .s_gt32 => |operands| try ops.binary(i32, "gt", fiber, registerData, operands),
        .s_gt64 => |operands| try ops.binary(i64, "gt", fiber, registerData, operands),
        .u_le8 => |operands| try ops.binary(u8, "le", fiber, registerData, operands),
        .u_le16 => |operands| try ops.binary(u16, "le", fiber, registerData, operands),
        .u_le32 => |operands| try ops.binary(u32, "le", fiber, registerData, operands),
        .u_le64 => |operands| try ops.binary(u64, "le", fiber, registerData, operands),
        .s_le8 => |operands| try ops.binary(i8, "le", fiber, registerData, operands),
        .s_le16 => |operands| try ops.binary(i16, "le", fiber, registerData, operands),
        .s_le32 => |operands| try ops.binary(i32, "le", fiber, registerData, operands),
        .s_le64 => |operands| try ops.binary(i64, "le", fiber, registerData, operands),
        .u_ge8 => |operands| try ops.binary(u8, "ge", fiber, registerData, operands),
        .u_ge16 => |operands| try ops.binary(u16, "ge", fiber, registerData, operands),
        .u_ge32 => |operands| try ops.binary(u32, "ge", fiber, registerData, operands),
        .u_ge64 => |operands| try ops.binary(u64, "ge", fiber, registerData, operands),
        .s_ge8 => |operands| try ops.binary(i8, "ge", fiber, registerData, operands),
        .s_ge16 => |operands| try ops.binary(i16, "ge", fiber, registerData, operands),
        .s_ge32 => |operands| try ops.binary(i32, "ge", fiber, registerData, operands),
        .s_ge64 => |operands| try ops.binary(i64, "ge", fiber, registerData, operands),

        .u_ext8x16 => |operands| try ops.cast(u8, u16, fiber, registerData, operands),
        .u_ext8x32 => |operands| try ops.cast(u8, u32, fiber, registerData, operands),
        .u_ext8x64 => |operands| try ops.cast(u8, u64, fiber, registerData, operands),
        .u_ext16x32 => |operands| try ops.cast(u16, u32, fiber, registerData, operands),
        .u_ext16x64 => |operands| try ops.cast(u16, u64, fiber, registerData, operands),
        .u_ext32x64 => |operands| try ops.cast(u32, u64, fiber, registerData, operands),
        .s_ext8x16 => |operands| try ops.cast(i8, i16, fiber, registerData, operands),
        .s_ext8x32 => |operands| try ops.cast(i8, i32, fiber, registerData, operands),
        .s_ext8x64 => |operands| try ops.cast(i8, i64, fiber, registerData, operands),
        .s_ext16x32 => |operands| try ops.cast(i16, i32, fiber, registerData, operands),
        .s_ext16x64 => |operands| try ops.cast(i16, i64, fiber, registerData, operands),
        .s_ext32x64 => |operands| try ops.cast(i32, i64, fiber, registerData, operands),
        .f_ext32x64 => |operands| try ops.cast(f32, i64, fiber, registerData, operands),

        .i_trunc64x32 => |operands| try ops.cast(u64, u32, fiber, registerData, operands),
        .i_trunc64x16 => |operands| try ops.cast(u64, u16, fiber, registerData, operands),
        .i_trunc64x8 => |operands| try ops.cast(u64, u8, fiber, registerData, operands),
        .i_trunc32x16 => |operands| try ops.cast(u32, u16, fiber, registerData, operands),
        .i_trunc32x8 => |operands| try ops.cast(u32, u8, fiber, registerData, operands),
        .i_trunc16x8 => |operands| try ops.cast(u16, u8, fiber, registerData, operands),
        .f_trunc64x32 => |operands| try ops.cast(f64, f32, fiber, registerData, operands),

        .u8_to_f32 => |operands| try ops.cast(u8, f32, fiber, registerData, operands),
        .u8_to_f64 => |operands| try ops.cast(u8, f64, fiber, registerData, operands),
        .u16_to_f32 => |operands| try ops.cast(u16, f32, fiber, registerData, operands),
        .u16_to_f64 => |operands| try ops.cast(u16, f64, fiber, registerData, operands),
        .u32_to_f32 => |operands| try ops.cast(u32, f32, fiber, registerData, operands),
        .u32_to_f64 => |operands| try ops.cast(u32, f64, fiber, registerData, operands),
        .u64_to_f32 => |operands| try ops.cast(u64, f32, fiber, registerData, operands),
        .u64_to_f64 => |operands| try ops.cast(u64, f64, fiber, registerData, operands),
        .s8_to_f32 => |operands| try ops.cast(i8, f32, fiber, registerData, operands),
        .s8_to_f64 => |operands| try ops.cast(i8, f64, fiber, registerData, operands),
        .s16_to_f32 => |operands| try ops.cast(i16, f32, fiber, registerData, operands),
        .s16_to_f64 => |operands| try ops.cast(i16, f64, fiber, registerData, operands),
        .s32_to_f32 => |operands| try ops.cast(i32, f32, fiber, registerData, operands),
        .s32_to_f64 => |operands| try ops.cast(i32, f64, fiber, registerData, operands),
        .s64_to_f32 => |operands| try ops.cast(i64, f32, fiber, registerData, operands),
        .s64_to_f64 => |operands| try ops.cast(i64, f64, fiber, registerData, operands),
        .f32_to_u8 => |operands| try ops.cast(f32, u8, fiber, registerData, operands),
        .f32_to_u16 => |operands| try ops.cast(f32, u16, fiber, registerData, operands),
        .f32_to_u32 => |operands| try ops.cast(f32, u32, fiber, registerData, operands),
        .f32_to_u64 => |operands| try ops.cast(f32, u64, fiber, registerData, operands),
        .f64_to_u8 => |operands| try ops.cast(f64, u8, fiber, registerData, operands),
        .f64_to_u16 => |operands| try ops.cast(f64, u16, fiber, registerData, operands),
        .f64_to_u32 => |operands| try ops.cast(f64, u32, fiber, registerData, operands),
        .f64_to_u64 => |operands| try ops.cast(f64, u64, fiber, registerData, operands),
        .f32_to_s8 => |operands| try ops.cast(f32, i8, fiber, registerData, operands),
        .f32_to_s16 => |operands| try ops.cast(f32, i16, fiber, registerData, operands),
        .f32_to_s32 => |operands| try ops.cast(f32, i32, fiber, registerData, operands),
        .f32_to_s64 => |operands| try ops.cast(f32, i64, fiber, registerData, operands),
        .f64_to_s8 => |operands| try ops.cast(f64, i8, fiber, registerData, operands),
        .f64_to_s16 => |operands| try ops.cast(f64, i16, fiber, registerData, operands),
        .f64_to_s32 => |operands| try ops.cast(f64, i32, fiber, registerData, operands),
        .f64_to_s64 => |operands| try ops.cast(f64, i64, fiber, registerData, operands),
    }
}

pub fn stepForeign(fiber: *Fiber, callFrame: *Fiber.CallFrame, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet) Fiber.Trap!void {
    const foreign = try fiber.getForeign(function.value.foreign);

    const blockFrame = try fiber.stack.block.getPtr(callFrame.root_block);
    const foreignRegisterData = Fiber.ForeignRegisterDataSet.fromNative(registerData);

    var out: Fiber.ForeignOut = undefined;
    const control = foreign(fiber, blockFrame.index, &foreignRegisterData, &out);

    switch (control) {
        .trap => return Fiber.convertForeignError(out.trap),
        .step => blockFrame.index = out.step,
        .done => try ret(fiber, callFrame, function, registerData, out.done),
    }
}

fn extractUp(registerData: Fiber.RegisterDataSet) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.RegisterData {
    if (registerData.upvalue) |ud| {
        return ud;
    } else {
        @branchHint(.cold);
        return Fiber.Trap.MissingEvidence;
    }
}

fn getRegisterData(fiber: *Fiber, callFrame: *Fiber.CallFrame, function: *Bytecode.Function) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.RegisterDataSet {
    return .{
        .local = .{
            .call = callFrame,
            .layout = &function.layout_table,
        },
        .upvalue = if (callFrame.evidence) |evRef| ev: {
            const evidence = try fiber.evidence[evRef.index].getPtr(evRef.offset);
            const evFrame = try fiber.stack.call.getPtr(evidence.call);
            const evFunction = &fiber.program.functions[evFrame.function];
            break :ev .{
                .call = evFrame,
                .layout = &evFunction.layout_table
            };
        } else null,
    };
}

const ZeroCheck = enum {zero, non_zero};

fn when(fiber: *Fiber, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, newBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, comptime zeroCheck: ZeroCheck) Fiber.Trap!void {
    const cond = try read(u8, fiber, registerData, x);

    if (newBlockIndex >= function.value.bytecode.blocks.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const newBlock = &function.value.bytecode.blocks[newBlockIndex];

    if (newBlock.kind.hasOutput()) {
        @branchHint(.cold);
        return Fiber.Trap.OutValueMismatch;
    }

    switch (zeroCheck) {
        .zero => if (cond == 0) try fiber.stack.block.push(.noOutput(newBlockIndex, null)),
        .non_zero => if (cond != 0) try fiber.stack.block.push(.noOutput(newBlockIndex, null)),
    }
}

fn br(fiber: *Fiber, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, terminatedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) Fiber.Trap!void {
    const blockPtr = fiber.stack.block.ptr;

    if (terminatedBlockOffset >= blockPtr) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const terminatedBlockPtr = blockPtr - (terminatedBlockOffset + 1);
    const terminatedBlockFrame = try fiber.stack.block.getPtr(terminatedBlockPtr);
    const terminatedBlock = &function.value.bytecode.blocks[terminatedBlockFrame.index];

    if (terminatedBlock.kind.hasOutput()) {
        @branchHint(.cold);
        return Fiber.Trap.OutValueMismatch;
    }

    if (zeroCheck) |zc| {
        const cond = try read(u8, fiber, registerData, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    try removeAnyHandlerSet(fiber, terminatedBlockFrame);

    fiber.stack.block.ptr = terminatedBlockPtr;
}

fn br_v(fiber: *Fiber, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, terminatedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, y: Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) Fiber.Trap!void {
    const blockPtr = fiber.stack.block.ptr;

    if (terminatedBlockOffset >= blockPtr) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const terminatedBlockPtr = blockPtr - (terminatedBlockOffset + 1);
    const terminatedBlockFrame = try fiber.stack.block.getPtr(terminatedBlockPtr);
    const terminatedBlock = &function.value.bytecode.blocks[terminatedBlockFrame.index];

    if (!terminatedBlock.kind.hasOutput()) {
        @branchHint(.cold);
        return Fiber.Trap.OutValueMismatch;
    }

    if (zeroCheck) |zc| {
        const cond = try read(u8, fiber, registerData, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    const desiredSize = terminatedBlock.output_layout.?.size;
    const src = try addr(fiber, registerData, y, desiredSize);
    const dest = try addr(fiber, registerData, terminatedBlockFrame.out, desiredSize);
    @memcpy(dest[0..desiredSize], src);

    try removeAnyHandlerSet(fiber, terminatedBlockFrame);

    fiber.stack.block.ptr = terminatedBlockPtr;
}

fn re(fiber: *Fiber, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, restartedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const blockPtr = fiber.stack.block.ptr;

    if (restartedBlockOffset >= blockPtr) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const restartedBlockPtr = blockPtr - (restartedBlockOffset + 1);

    const restartedBlockFrame = try fiber.stack.block.getPtr(restartedBlockPtr);

    const restartedBlock = &function.value.bytecode.blocks[restartedBlockFrame.index];

    if (restartedBlock.kind != .basic) {
        @branchHint(.cold);
        return Fiber.Trap.InvalidBlockRestart;
    }

    if (zeroCheck) |zc| {
        const cond = try read(u8, fiber, registerData, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    restartedBlockFrame.ip_offset = 0;

    fiber.stack.block.ptr = restartedBlockPtr + 1;
}

fn blockImpl(fiber: *Fiber, function: *Bytecode.Function, newBlockIndex: Bytecode.BlockIndex, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (newBlockIndex >= function.value.bytecode.blocks.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const newBlock = &function.value.bytecode.blocks[newBlockIndex];

    const block = block: {
        if (y) |yOp| {
            if (!newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :block Fiber.BlockFrame.value(newBlockIndex, yOp, null);
        } else {
            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :block Fiber.BlockFrame.noOutput(newBlockIndex, null);
        }
    };

    try fiber.stack.block.push(block);
}

fn with(fiber: *Fiber, function: *Bytecode.Function, newBlockIndex: Bytecode.BlockIndex, handlerSetIndex: Bytecode.HandlerSetIndex, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (newBlockIndex >= function.value.bytecode.blocks.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const newBlock = &function.value.bytecode.blocks[newBlockIndex];

    if (handlerSetIndex >= fiber.program.handler_sets.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const handlerSet = fiber.program.handler_sets[handlerSetIndex];

    for (handlerSet) |binding| {
        if (binding.id >= fiber.evidence.len) {
            @branchHint(.cold);
            return Fiber.Trap.OutOfBounds;
        }

        try fiber.evidence[binding.id].push(Fiber.Evidence {
            .handler = binding.handler,
            .data = fiber.stack.data.ptr,
            .call = fiber.stack.call.ptr,
            .block = fiber.stack.block.ptr,
        });
    }

    const block = block: {
        if (y) |yOp| {
            if (!newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :block Fiber.BlockFrame.value(newBlockIndex, yOp, handlerSetIndex);
        } else {
            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :block Fiber.BlockFrame.noOutput(newBlockIndex, handlerSetIndex);
        }
    };

    try fiber.stack.block.push(block);
}

fn ifImpl(fiber: *Fiber, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, thenBlockIndex: Bytecode.BlockIndex, elseBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, y: ?Bytecode.Operand, comptime zeroCheck: ZeroCheck) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const cond = try read(u8, fiber, registerData, x);

    const thenBlockInBounds = @intFromBool(thenBlockIndex < function.value.bytecode.blocks.len);
    const elseBlockInBounds = @intFromBool(elseBlockIndex < function.value.bytecode.blocks.len);
    if (thenBlockInBounds & elseBlockInBounds != 1) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const thenBlock = &function.value.bytecode.blocks[thenBlockIndex];
    const elseBlock = &function.value.bytecode.blocks[elseBlockIndex];

    const thenBlockHasOutput = @intFromBool(thenBlock.kind.hasOutput());
    const elseBlockHasOutput = @intFromBool(elseBlock.kind.hasOutput());

    const destBlockIndex = switch (zeroCheck) {
        .zero => if (cond == 0) thenBlockIndex else elseBlockIndex,
        .non_zero => if (cond != 0) thenBlockIndex else elseBlockIndex,
    };

    const block = block: {
        if (y) |yOp| {
            if (thenBlockHasOutput & elseBlockHasOutput != 1) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :block Fiber.BlockFrame.value(destBlockIndex, yOp, null);
        } else {
            if (thenBlockHasOutput | elseBlockHasOutput != 0) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :block Fiber.BlockFrame.noOutput(destBlockIndex, null);
        }
    };

    try fiber.stack.block.push(block);
}

fn case(fiber: *Fiber, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, blockIndices: []const Bytecode.BlockIndex, x: Bytecode.Operand, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const index = try read(u8, fiber, registerData, x);

    if (index >= blockIndices.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const caseBlockIndex = blockIndices[index];

    const block = block: {
        if (y) |yOp| {
            // TODO: find a way to do this more efficiently
            for (blockIndices) |blockIndex| {
                if (blockIndex >= function.value.bytecode.blocks.len) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutOfBounds;
                }

                const caseBlock = &function.value.bytecode.blocks[blockIndex];

                if (!caseBlock.kind.hasOutput()) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            }

            break :block Fiber.BlockFrame.value(caseBlockIndex, yOp, null);
        } else {
            // TODO: find a way to do this more efficiently
            for (blockIndices) |blockIndex| {
                if (blockIndex >= function.value.bytecode.blocks.len) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutOfBounds;
                }

                const caseBlock = &function.value.bytecode.blocks[blockIndex];

                if (caseBlock.kind.hasOutput()) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            }

            break :block Fiber.BlockFrame.noOutput(caseBlockIndex, null);
        }
    };

    try fiber.stack.block.push(block);
}

fn addrImpl(fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) Fiber.Trap!void {
    const bytes: [*]const u8 = try addr(fiber, registerData, x, 0);

    try write(fiber, registerData, y, bytes);
}

fn load(comptime T: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = try read([*]const u8, fiber, registerData, x);
    const outAddr: [*]u8 = try addr(fiber, registerData, y, size);

    try boundsCheck(fiber, inAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

fn store(comptime T: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = try addr(fiber, registerData, x, size);
    const outAddr: [*]u8 = try read([*]u8, fiber, registerData, y);

    try boundsCheck(fiber, outAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

fn clear(comptime T: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const bytes: [*]u8 = try addr(fiber, registerData, x, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), alignment) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(bytes))).* = 0;
}

fn swap(comptime T: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const xBytes: [*]u8 = try addr(fiber, registerData, x, size);
    const yBytes: [*]u8 = try addr(fiber, registerData, y, size);

    const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    if (xAligned & yAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    const temp: T = @as(*T, @ptrCast(@alignCast(xBytes))).*;
    @as(*T, @ptrCast(@alignCast(xBytes))).* = @as(*T, @ptrCast(@alignCast(yBytes))).*;
    @as(*T, @ptrCast(@alignCast(yBytes))).* = temp;
}

fn copy(comptime T: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const xBytes: [*]const u8 = try addr(fiber, registerData, x, size);
    const yBytes: [*]u8 = try addr(fiber, registerData, y, size);

    const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    if (xAligned & yAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(yBytes))).* = @as(*const T, @ptrCast(@alignCast(xBytes))).*;
}

fn dynCall(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, func: Bytecode.Operand, args: []const Bytecode.Operand, style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const funcIndex = try read(Bytecode.FunctionIndex, fiber, registerData, func);

    return call(fiber, oldCallFrame, oldFunction, registerData, funcIndex, args, style);
}

fn call(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (funcIndex >= fiber.program.functions.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return callImpl(fiber, oldCallFrame, oldFunction, registerData, Bytecode.EVIDENCE_SENTINEL, funcIndex, args, style);
}

fn prompt(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, evIndex: Bytecode.EvidenceIndex, args: []const Bytecode.Operand, style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (evIndex >= fiber.evidence.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const evidence = try fiber.evidence[evIndex].topPtr();

    return callImpl(fiber, oldCallFrame, oldFunction, registerData, evIndex, evidence.handler, args, style);
}

const ReturnStyle = union(enum) {
    tail: void,
    tail_v: void,
    no_tail: void,
    no_tail_v: Bytecode.Operand,
};

fn callImpl(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    if (args.len != newFunction.layout_table.num_arguments) {
        @branchHint(.cold);
        return Fiber.Trap.ArgCountMismatch;
    }

    const newBlock, const isTail = returnData: {
        switch (style) {
            .no_tail => if (newFunction.layout_table.return_layout != null) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            } else {
                break :returnData .{
                    Fiber.BlockFrame.entryPoint(null),
                    false,
                };
            },
            .no_tail_v => |out| if (newFunction.layout_table.return_layout) |returnLayout| {
                _ = try addr(fiber, registerData, out, returnLayout.size);
                break :returnData .{
                    Fiber.BlockFrame.entryPoint(out),
                    false,
                };
            } else {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            },
            .tail => if (oldFunction.layout_table.return_layout != null) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            } else {
                break :returnData .{
                    Fiber.BlockFrame.entryPoint(null),
                    true,
                };
            },
            .tail_v => if (oldFunction.layout_table.return_layout) |oldLayout| {
                if (newFunction.layout_table.return_layout) |newLayout| {
                    const sameSize = @intFromBool(oldLayout.size == newLayout.size);
                    const sameAlign = @intFromBool(oldLayout.alignment == newLayout.alignment);
                    if (sameSize & sameAlign != 1) {
                        @branchHint(.cold);
                        return Fiber.Trap.OutValueMismatch;
                    }
                    const oldFunctionRootBlockFrame = try fiber.stack.block.getPtr(oldCallFrame.root_block);
                    const oldFunctionOutput = oldFunctionRootBlockFrame.out;
                    break :returnData .{
                        Fiber.BlockFrame.entryPoint(oldFunctionOutput),
                        true,
                    };
                } else {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            } else {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            },
        }
    };

    if (isTail) {
        fiber.stack.data.ptr = oldCallFrame.stack.base;
        fiber.stack.call.ptr -= 1;
        fiber.stack.block.ptr = oldCallFrame.root_block - 1;
    }

    const origin = fiber.stack.data.ptr;
    const padding = Support.alignmentDelta(origin, newFunction.layout_table.alignment);
    const base = origin + padding;

    try fiber.stack.data.pushUninit(newFunction.layout_table.size + padding);

    for (0..args.len) |i| {
        const desiredSize = newFunction.layout_table.register_layouts[i].size;
        const arg = try slice(fiber, registerData, args[i], desiredSize);
        @memcpy(fiber.stack.data.memory[newFunction.layout_table.register_offsets[i]..].ptr, arg);
    }

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = funcIndex,
        .evidence = if (evIndex != Bytecode.EVIDENCE_SENTINEL) ev: {
            if (evIndex >= fiber.evidence.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            if (fiber.evidence[evIndex].ptr == 0) {
                @branchHint(.cold);
                return Fiber.Trap.MissingEvidence;
            }

            break :ev .{
                .index = evIndex,
                .offset = fiber.evidence[evIndex].ptr - 1,
            };
        } else null,
        .root_block = fiber.stack.block.ptr,
        .stack = .{
            .base = base,
            .origin = origin,
        },
    });

    try fiber.stack.block.push(newBlock);

}

fn term(fiber: *Fiber, callFrame: *Fiber.CallFrame, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const evRef = if (callFrame.evidence) |e| e else {
        @branchHint(.cold);
        return Fiber.Trap.MissingEvidence;
    };

    const evidence = try fiber.evidence[evRef.index].getPtr(evRef.offset);

    const rootFunction = &fiber.program.functions[evidence.handler];
    const rootCallFrame = try fiber.stack.call.getPtr(evidence.call);
    const rootBlockFrame = try fiber.stack.block.getPtr(evidence.block);
    const rootBlock = &rootFunction.value.bytecode.blocks[rootBlockFrame.index];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = function.layout_table.term_layout.?.size;
            const src: [*]const u8 = try addr(fiber, registerData, outOp, size);

            const rootRegisterData = try getRegisterData(fiber, rootCallFrame, rootFunction);
            const dest: [*]u8 = try addr(fiber, rootRegisterData, rootBlockFrame.out, size);

            @memcpy(dest[0..size], src);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.OutValueMismatch;
        }
    }

    fiber.stack.data.ptr = evidence.data;
    fiber.stack.call.ptr = evidence.call;
    fiber.stack.block.ptr = evidence.block - 1;
}

fn ret(fiber: *Fiber, callFrame: *Fiber.CallFrame, function: *Bytecode.Function, registerData: Fiber.RegisterDataSet, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const rootBlockFrame = try fiber.stack.block.getPtr(callFrame.root_block);
    const rootBlock = &function.value.bytecode.blocks[rootBlockFrame.index];

    const callerFrame = try fiber.stack.call.getPtr(fiber.stack.call.ptr - 2);
    const callerFunction = &fiber.program.functions[callerFrame.function];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = function.layout_table.return_layout.?.size;
            const src: [*]const u8 = try addr(fiber, registerData, outOp, size);

            const callerRegisterData = try getRegisterData(fiber, callerFrame, callerFunction);
            const dest: [*]u8 = try addr(fiber, callerRegisterData, rootBlockFrame.out, size);

            @memcpy(dest[0..size], src);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.OutValueMismatch;
        }
    }

    fiber.stack.data.ptr = callFrame.stack.base;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = callFrame.root_block - 1;
}

inline fn read(comptime T: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand) Fiber.Trap!T {
    switch (operand.kind) {
        .global => return readGlobal(T, fiber, operand.data.global),
        .upvalue => return readReg(T, fiber, try extractUp(registerData), operand.data.register),
        .local => return readReg(T, fiber, registerData.local, operand.data.register),
    }
}

inline fn write(fiber: *Fiber, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand, value: anytype) Fiber.Trap!void {
    switch (operand.kind) {
        .global => return writeGlobal(fiber, operand.data.global, value),
        .upvalue => return writeReg(fiber, try extractUp(registerData), operand.data.register, value),
        .local => return writeReg(fiber, registerData.local, operand.data.register, value),
    }
}

inline fn addr(fiber: *Fiber, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) Fiber.Trap![*]u8 {
    switch (operand.kind) {
        .global => return addrGlobal(fiber, operand.data.global, size),
        .upvalue => return addrReg(fiber, try extractUp(registerData), operand.data.register, size),
        .local => return addrReg(fiber, registerData.local, operand.data.register, size),
    }
}

fn addrReg(fiber: *Fiber, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, @truncate(size))) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(try fiber.stack.data.getPtr(base + operand.offset));
}

inline fn slice(fiber: *Fiber, registerData: Fiber.RegisterDataSet, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) Fiber.Trap![]u8 {
    return (try addr(fiber, registerData, operand, size))[0..size];
}

fn readGlobal(comptime T: type, fiber: *Fiber, operand: Bytecode.GlobalOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const bytes = try addrGlobal(fiber, operand, @sizeOf(T));

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

fn readReg(comptime T: type, fiber: *Fiber, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const size = @sizeOf(T);

    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = try fiber.stack.data.checkSlice(base + operand.offset, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

fn writeGlobal(fiber: *Fiber, operand: Bytecode.GlobalOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const T = @TypeOf(value);
    const mem = try addrGlobal(fiber, operand, @sizeOf(T));

    if (Support.alignmentDelta(@intFromPtr(mem), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(mem))).* = value;
}

fn writeReg(fiber: *Fiber, regData: Fiber.RegisterData, operand: Bytecode.RegisterOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);

    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = try fiber.stack.data.checkSlice(base, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(bytes))).* = value;
}

fn addrGlobal(fiber: *Fiber, operand: Bytecode.GlobalOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    if (operand.index >= fiber.program.globals.values.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const data = &fiber.program.globals.values[operand.index];

    if (!data.layout.inbounds(operand.offset, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(&fiber.program.globals.memory[operand.offset]);
}

fn getOperandOffset(regData: Fiber.RegisterData, register: Bytecode.Register) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.DataStack.Ptr {
    const regNumber: Bytecode.RegisterIndex = @intFromEnum(register);

    if (regNumber < regData.layout.num_registers) {
        return regData.call.stack.base + regData.layout.register_offsets[regNumber];
    } else {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }
}

fn boundsCheck(fiber: *Fiber, address: [*]const u8, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const validGlobalA = @intFromBool(@intFromPtr(address) >= @intFromPtr(fiber.program.globals.memory.ptr));
    const validGlobalB = @intFromBool(@intFromPtr(address) + size <= @intFromPtr(fiber.program.globals.memory.ptr) + fiber.program.globals.memory.len);

    const validStackA = @intFromBool(@intFromPtr(address) >= @intFromPtr(fiber.stack.data.memory.ptr));
    const validStackB = @intFromBool(@intFromPtr(address) + size <= fiber.stack.data.ptr);

    if ((validGlobalA & validGlobalB) | (validStackA & validStackB) == 0) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }
}

fn removeAnyHandlerSet(fiber: *Fiber, blockFrame: *Fiber.BlockFrame) Fiber.Trap!void {
    if (blockFrame.handler_set == Bytecode.HANDLER_SET_SENTINEL) return;

    const handlerSet = fiber.program.handler_sets[blockFrame.handler_set];

    for (handlerSet) |binding| {
        const removedEv = try fiber.evidence[binding.id].pop();

        std.debug.assert(removedEv.handler == binding.handler);
    }
}


const ops = struct {
    fn cast(comptime A: type, comptime B: type, fiber: *Fiber, registerData: Fiber.RegisterDataSet, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
        const x = try read(A, fiber, registerData, operands.x);

        const aKind = @as(std.builtin.TypeId, @typeInfo(A));
        const bKind = @as(std.builtin.TypeId, @typeInfo(B));
        const result =
            if (comptime aKind == bKind) (
                if (comptime aKind == .int) @call(Config.INLINING_CALL_MOD, intCast, .{B, x})
                else @call(Config.INLINING_CALL_MOD, floatCast, .{B, x})
            ) else @call(Config.INLINING_CALL_MOD, typeCast, .{B, x});

        try write(fiber, registerData, operands.y, result);
    }

    fn unary(comptime T: type, comptime op: []const u8, fiber: *Fiber, registerData: Fiber.RegisterDataSet, operands: Bytecode.ISA.TwoOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
        const x = try read(T, fiber, registerData, operands.x);

        const result = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x});

        try write(fiber, registerData, operands.y, result);
    }

    fn binary(comptime T: type, comptime op: []const u8, fiber: *Fiber, registerData: Fiber.RegisterDataSet, operands: Bytecode.ISA.ThreeOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
        const x = try read(T, fiber, registerData, operands.x);
        const y = try read(T, fiber, registerData, operands.y);

        const result = @call(Config.INLINING_CALL_MOD, @field(ops, op), .{x, y});

        try write(fiber, registerData, operands.z, result);
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
