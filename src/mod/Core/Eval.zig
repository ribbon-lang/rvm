const std = @import("std");

const Config = @import("Config");
const Support = @import("Support");

const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Core = @import("root.zig");
const Fiber = Core.Fiber;


const Eval = @This();



const ZeroCheck = enum {
    zero,
    non_zero
};

const CallStyle = union(enum) {
    tail: void,
    tail_v: void,
    no_tail: void,
    no_tail_v: Bytecode.Operand,
};


pub fn step(fiber: *Fiber) Fiber.Trap!void {
    const currentCallFrame = try fiber.stack.call.topPtr();
    const currentFunction = &fiber.program.functions[currentCallFrame.function];

    const registerData = try fiber.getRegisterData(currentCallFrame, currentFunction);

    switch (currentFunction.value) {
        .bytecode => try @call(Config.INLINING_CALL_MOD, stepBytecode, .{fiber, currentCallFrame, currentFunction, registerData}),
        .foreign => try @call(Config.INLINING_CALL_MOD, stepForeign, .{fiber, currentCallFrame, currentFunction, registerData}),
    }
}

pub fn stepBytecode(fiber: *Fiber, currentCallFrame: *Fiber.CallFrame, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet) Fiber.Trap!void {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA);

    const currentBlockFrame = try fiber.stack.block.topPtr();
    const currentBlock = &currentFunction.value.bytecode.blocks[currentBlockFrame.index];

    const decoder = IO.Decoder {
        .memory = currentFunction.value.bytecode.instructions,
        .base = currentBlock.base,
        .offset = &currentBlockFrame.ip_offset,
    };

    const instr = try decoder.decodeInline(Bytecode.Op);

    switch (instr) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => {},

        .tail_call => |operands| try call(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .tail),
        .tail_call_v => |operands| try call(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .tail_v),
        .dyn_tail_call => |operands| try dynCall(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .tail),
        .dyn_tail_call_v => |operands| try dynCall(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .tail_v),
        .tail_prompt => |operands| try prompt(fiber, currentCallFrame, currentFunction, registerData, operands.e, operands.as, .tail),
        .tail_prompt_v => |operands| try prompt(fiber, currentCallFrame, currentFunction, registerData, operands.e, operands.as, .tail_v),

        .call => |operands| try call(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .no_tail),
        .call_v => |operands| try call(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .{ .no_tail_v = operands.y }),
        .dyn_call => |operands| try dynCall(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .no_tail),
        .dyn_call_v => |operands| try dynCall(fiber, currentCallFrame, currentFunction, registerData, operands.f, operands.as, .{ .no_tail_v = operands.y }),
        .prompt => |operands| try prompt(fiber, currentCallFrame, currentFunction, registerData, operands.e, operands.as, .no_tail),
        .prompt_v => |operands| try prompt(fiber, currentCallFrame, currentFunction, registerData, operands.e, operands.as, .{ .no_tail_v = operands.y }),

        .ret => try ret(fiber, currentCallFrame, currentFunction, registerData, null),
        .ret_v => |operands| try ret(fiber, currentCallFrame, currentFunction, registerData, operands.y),
        .term => try term(fiber, currentCallFrame, currentFunction, registerData, null),
        .term_v => |operands| try term(fiber, currentCallFrame, currentFunction, registerData, operands.y),

        .when_z => |operands| try when(fiber, currentFunction, registerData, operands.b, operands.x, .zero),
        .when_nz => |operands| try when(fiber, currentFunction, registerData, operands.b, operands.x, .non_zero),

        .re => |operands| try re(fiber, currentFunction, registerData, operands.b, null, null),
        .re_z => |operands| try re(fiber, currentFunction, registerData, operands.b, operands.x, .zero),
        .re_nz => |operands| try re(fiber, currentFunction, registerData, operands.b, operands.x, .non_zero),

        .br => |operands | try br(fiber, currentFunction, registerData, operands.b, null, null, null),
        .br_z => |operands | try br(fiber, currentFunction, registerData, operands.b, operands.x, null, .zero),
        .br_nz => |operands | try br(fiber, currentFunction, registerData, operands.b, operands.x, null, .non_zero),

        .br_v => |operands| try br(fiber, currentFunction, registerData, operands.b, null, operands.y, null),
        .br_z_v => |operands| try br(fiber, currentFunction, registerData, operands.b, operands.x, operands.y, .zero),
        .br_nz_v => |operands| try br(fiber, currentFunction, registerData, operands.b, operands.x, operands.y, .non_zero),

        .block => |operands| try block(fiber, currentFunction, operands.b, null),
        .block_v => |operands| try block(fiber, currentFunction, operands.b, operands.y),

        .with => |operands| try with(fiber, currentFunction, operands.b, operands.h, null),
        .with_v => |operands| try with(fiber, currentFunction, operands.b, operands.h, operands.y),

        .if_z => |operands| try @"if"(fiber, currentFunction, registerData, operands.t, operands.e, operands.x, null, .zero),
        .if_nz => |operands| try @"if"(fiber, currentFunction, registerData, operands.t, operands.e, operands.x, null, .non_zero),
        .if_z_v => |operands| try @"if"(fiber, currentFunction, registerData, operands.t, operands.e, operands.x, operands.y, .zero),
        .if_nz_v => |operands| try @"if"(fiber, currentFunction, registerData, operands.t, operands.e, operands.x, operands.y, .non_zero),

        .case => |operands| try case(fiber, currentFunction, registerData, operands.bs, operands.x, null),
        .case_v => |operands| try case(fiber, currentFunction, registerData, operands.bs, operands.x, operands.y),

        .addr => |operands| try addr(fiber, registerData, operands.x, operands.y),

        .load8 => |operands| try fiber.load(u8, registerData, operands.x, operands.y),
        .load16 => |operands| try fiber.load(u16, registerData, operands.x, operands.y),
        .load32 => |operands| try fiber.load(u32, registerData, operands.x, operands.y),
        .load64 => |operands| try fiber.load(u64, registerData, operands.x, operands.y),

        .store8 => |operands| try fiber.store(u8, registerData, operands.x, operands.y),
        .store16 => |operands| try fiber.store(u16, registerData, operands.x, operands.y),
        .store32 => |operands| try fiber.store(u32, registerData, operands.x, operands.y),
        .store64 => |operands| try fiber.store(u64, registerData, operands.x, operands.y),

        .clear8 => |operands| try fiber.clear(u8, registerData, operands.x),
        .clear16 => |operands| try fiber.clear(u16, registerData, operands.x),
        .clear32 => |operands| try fiber.clear(u32, registerData, operands.x),
        .clear64 => |operands| try fiber.clear(u64, registerData, operands.x),

        .swap8 => |operands| try fiber.swap(u8, registerData, operands.x, operands.y),
        .swap16 => |operands| try fiber.swap(u16, registerData, operands.x, operands.y),
        .swap32 => |operands| try fiber.swap(u32, registerData, operands.x, operands.y),
        .swap64 => |operands| try fiber.swap(u64, registerData, operands.x, operands.y),

        .copy8 => |operands| try fiber.copy(u8, registerData, operands.x, operands.y),
        .copy16 => |operands| try fiber.copy(u16, registerData, operands.x, operands.y),
        .copy32 => |operands| try fiber.copy(u32, registerData, operands.x, operands.y),
        .copy64 => |operands| try fiber.copy(u64, registerData, operands.x, operands.y),

        .b_not => |operands| try fiber.unary(bool, "not", registerData, operands),
        .b_and => |operands| try fiber.binary(bool, "and", registerData, operands),
        .b_or => |operands| try fiber.binary(bool, "or", registerData, operands),

        .f_add32 => |operands| try fiber.binary(f32, "add", registerData, operands),
        .f_add64 => |operands| try fiber.binary(f64, "add", registerData, operands),
        .f_sub32 => |operands| try fiber.binary(f32, "sub", registerData, operands),
        .f_sub64 => |operands| try fiber.binary(f64, "sub", registerData, operands),
        .f_mul32 => |operands| try fiber.binary(f32, "mul", registerData, operands),
        .f_mul64 => |operands| try fiber.binary(f64, "mul", registerData, operands),
        .f_div32 => |operands| try fiber.binary(f32, "div", registerData, operands),
        .f_div64 => |operands| try fiber.binary(f64, "div", registerData, operands),
        .f_rem32 => |operands| try fiber.binary(f32, "rem", registerData, operands),
        .f_rem64 => |operands| try fiber.binary(f64, "rem", registerData, operands),
        .f_neg32 => |operands| try fiber.unary(f32, "neg", registerData, operands),
        .f_neg64 => |operands| try fiber.unary(f64, "neg", registerData, operands),

        .f_eq32 => |operands| try fiber.binary(f32, "eq", registerData, operands),
        .f_eq64 => |operands| try fiber.binary(f64, "eq", registerData, operands),
        .f_ne32 => |operands| try fiber.binary(f32, "ne", registerData, operands),
        .f_ne64 => |operands| try fiber.binary(f64, "ne", registerData, operands),
        .f_lt32 => |operands| try fiber.binary(f32, "lt", registerData, operands),
        .f_lt64 => |operands| try fiber.binary(f64, "lt", registerData, operands),
        .f_gt32 => |operands| try fiber.binary(f32, "gt", registerData, operands),
        .f_gt64 => |operands| try fiber.binary(f64, "gt", registerData, operands),
        .f_le32 => |operands| try fiber.binary(f32, "le", registerData, operands),
        .f_le64 => |operands| try fiber.binary(f64, "le", registerData, operands),
        .f_ge32 => |operands| try fiber.binary(f32, "ge", registerData, operands),
        .f_ge64 => |operands| try fiber.binary(f64, "ge", registerData, operands),

        .i_add8 => |operands| try fiber.binary(u8, "add", registerData, operands),
        .i_add16 => |operands| try fiber.binary(u16, "add", registerData, operands),
        .i_add32 => |operands| try fiber.binary(u32, "add", registerData, operands),
        .i_add64 => |operands| try fiber.binary(u64, "add", registerData, operands),
        .i_sub8 => |operands| try fiber.binary(u8, "sub", registerData, operands),
        .i_sub16 => |operands| try fiber.binary(u16, "sub", registerData, operands),
        .i_sub32 => |operands| try fiber.binary(u32, "sub", registerData, operands),
        .i_sub64 => |operands| try fiber.binary(u64, "sub", registerData, operands),
        .i_mul8 => |operands| try fiber.binary(u8, "mul", registerData, operands),
        .i_mul16 => |operands| try fiber.binary(u16, "mul", registerData, operands),
        .i_mul32 => |operands| try fiber.binary(u32, "mul", registerData, operands),
        .i_mul64 => |operands| try fiber.binary(u64, "mul", registerData, operands),
        .s_div8 => |operands| try fiber.binary(i8, "divFloor", registerData, operands),
        .s_div16 => |operands| try fiber.binary(i16, "divFloor", registerData, operands),
        .s_div32 => |operands| try fiber.binary(i32, "divFloor", registerData, operands),
        .s_div64 => |operands| try fiber.binary(i64, "divFloor", registerData, operands),
        .u_div8 => |operands| try fiber.binary(u8, "div", registerData, operands),
        .u_div16 => |operands| try fiber.binary(u16, "div", registerData, operands),
        .u_div32 => |operands| try fiber.binary(u32, "div", registerData, operands),
        .u_div64 => |operands| try fiber.binary(u64, "div", registerData, operands),
        .s_rem8 => |operands| try fiber.binary(i8, "rem", registerData, operands),
        .s_rem16 => |operands| try fiber.binary(i16, "rem", registerData, operands),
        .s_rem32 => |operands| try fiber.binary(i32, "rem", registerData, operands),
        .s_rem64 => |operands| try fiber.binary(i64, "rem", registerData, operands),
        .u_rem8 => |operands| try fiber.binary(u8, "rem", registerData, operands),
        .u_rem16 => |operands| try fiber.binary(u16, "rem", registerData, operands),
        .u_rem32 => |operands| try fiber.binary(u32, "rem", registerData, operands),
        .u_rem64 => |operands| try fiber.binary(u64, "rem", registerData, operands),
        .s_neg8 => |operands| try fiber.unary(i8, "neg", registerData, operands),
        .s_neg16 => |operands| try fiber.unary(i16, "neg", registerData, operands),
        .s_neg32 => |operands| try fiber.unary(i32, "neg", registerData, operands),
        .s_neg64 => |operands| try fiber.unary(i64, "neg", registerData, operands),

        .i_bitnot8 => |operands| try fiber.unary(u8, "bitnot", registerData, operands),
        .i_bitnot16 => |operands| try fiber.unary(u16, "bitnot", registerData, operands),
        .i_bitnot32 => |operands| try fiber.unary(u32, "bitnot", registerData, operands),
        .i_bitnot64 => |operands| try fiber.unary(u64, "bitnot", registerData, operands),
        .i_bitand8 => |operands| try fiber.binary(u8, "bitand", registerData, operands),
        .i_bitand16 => |operands| try fiber.binary(u16, "bitand", registerData, operands),
        .i_bitand32 => |operands| try fiber.binary(u32, "bitand", registerData, operands),
        .i_bitand64 => |operands| try fiber.binary(u64, "bitand", registerData, operands),
        .i_bitor8 => |operands| try fiber.binary(u8, "bitor", registerData, operands),
        .i_bitor16 => |operands| try fiber.binary(u16, "bitor", registerData, operands),
        .i_bitor32 => |operands| try fiber.binary(u32, "bitor", registerData, operands),
        .i_bitor64 => |operands| try fiber.binary(u64, "bitor", registerData, operands),
        .i_bitxor8 => |operands| try fiber.binary(u8, "bitxor", registerData, operands),
        .i_bitxor16 => |operands| try fiber.binary(u16, "bitxor", registerData, operands),
        .i_bitxor32 => |operands| try fiber.binary(u32, "bitxor", registerData, operands),
        .i_bitxor64 => |operands| try fiber.binary(u64, "bitxor", registerData, operands),
        .i_shiftl8 => |operands| try fiber.binary(u8, "shiftl", registerData, operands),
        .i_shiftl16 => |operands| try fiber.binary(u16, "shiftl", registerData, operands),
        .i_shiftl32 => |operands| try fiber.binary(u32, "shiftl", registerData, operands),
        .i_shiftl64 => |operands| try fiber.binary(u64, "shiftl", registerData, operands),
        .u_shiftr8 => |operands| try fiber.binary(u8, "shiftr", registerData, operands),
        .u_shiftr16 => |operands| try fiber.binary(u16, "shiftr", registerData, operands),
        .u_shiftr32 => |operands| try fiber.binary(u32, "shiftr", registerData, operands),
        .u_shiftr64 => |operands| try fiber.binary(u64, "shiftr", registerData, operands),
        .s_shiftr8 => |operands| try fiber.binary(i8, "shiftr", registerData, operands),
        .s_shiftr16 => |operands| try fiber.binary(i16, "shiftr", registerData, operands),
        .s_shiftr32 => |operands| try fiber.binary(i32, "shiftr", registerData, operands),
        .s_shiftr64 => |operands| try fiber.binary(i64, "shiftr", registerData, operands),

        .i_eq8 => |operands| try fiber.binary(u8, "eq", registerData, operands),
        .i_eq16 => |operands| try fiber.binary(u16, "eq", registerData, operands),
        .i_eq32 => |operands| try fiber.binary(u32, "eq", registerData, operands),
        .i_eq64 => |operands| try fiber.binary(u64, "eq", registerData, operands),
        .i_ne8 => |operands| try fiber.binary(u8, "ne", registerData, operands),
        .i_ne16 => |operands| try fiber.binary(u16, "ne", registerData, operands),
        .i_ne32 => |operands| try fiber.binary(u32, "ne", registerData, operands),
        .i_ne64 => |operands| try fiber.binary(u64, "ne", registerData, operands),
        .u_lt8 => |operands| try fiber.binary(u8, "lt", registerData, operands),
        .u_lt16 => |operands| try fiber.binary(u16, "lt", registerData, operands),
        .u_lt32 => |operands| try fiber.binary(u32, "lt", registerData, operands),
        .u_lt64 => |operands| try fiber.binary(u64, "lt", registerData, operands),
        .s_lt8 => |operands| try fiber.binary(i8, "lt", registerData, operands),
        .s_lt16 => |operands| try fiber.binary(i16, "lt", registerData, operands),
        .s_lt32 => |operands| try fiber.binary(i32, "lt", registerData, operands),
        .s_lt64 => |operands| try fiber.binary(i64, "lt", registerData, operands),
        .u_gt8 => |operands| try fiber.binary(u8, "gt", registerData, operands),
        .u_gt16 => |operands| try fiber.binary(u16, "gt", registerData, operands),
        .u_gt32 => |operands| try fiber.binary(u32, "gt", registerData, operands),
        .u_gt64 => |operands| try fiber.binary(u64, "gt", registerData, operands),
        .s_gt8 => |operands| try fiber.binary(i8, "gt", registerData, operands),
        .s_gt16 => |operands| try fiber.binary(i16, "gt", registerData, operands),
        .s_gt32 => |operands| try fiber.binary(i32, "gt", registerData, operands),
        .s_gt64 => |operands| try fiber.binary(i64, "gt", registerData, operands),
        .u_le8 => |operands| try fiber.binary(u8, "le", registerData, operands),
        .u_le16 => |operands| try fiber.binary(u16, "le", registerData, operands),
        .u_le32 => |operands| try fiber.binary(u32, "le", registerData, operands),
        .u_le64 => |operands| try fiber.binary(u64, "le", registerData, operands),
        .s_le8 => |operands| try fiber.binary(i8, "le", registerData, operands),
        .s_le16 => |operands| try fiber.binary(i16, "le", registerData, operands),
        .s_le32 => |operands| try fiber.binary(i32, "le", registerData, operands),
        .s_le64 => |operands| try fiber.binary(i64, "le", registerData, operands),
        .u_ge8 => |operands| try fiber.binary(u8, "ge", registerData, operands),
        .u_ge16 => |operands| try fiber.binary(u16, "ge", registerData, operands),
        .u_ge32 => |operands| try fiber.binary(u32, "ge", registerData, operands),
        .u_ge64 => |operands| try fiber.binary(u64, "ge", registerData, operands),
        .s_ge8 => |operands| try fiber.binary(i8, "ge", registerData, operands),
        .s_ge16 => |operands| try fiber.binary(i16, "ge", registerData, operands),
        .s_ge32 => |operands| try fiber.binary(i32, "ge", registerData, operands),
        .s_ge64 => |operands| try fiber.binary(i64, "ge", registerData, operands),

        .u_ext8x16 => |operands| try fiber.cast(u8, u16, registerData, operands),
        .u_ext8x32 => |operands| try fiber.cast(u8, u32, registerData, operands),
        .u_ext8x64 => |operands| try fiber.cast(u8, u64, registerData, operands),
        .u_ext16x32 => |operands| try fiber.cast(u16, u32, registerData, operands),
        .u_ext16x64 => |operands| try fiber.cast(u16, u64, registerData, operands),
        .u_ext32x64 => |operands| try fiber.cast(u32, u64, registerData, operands),
        .s_ext8x16 => |operands| try fiber.cast(i8, i16, registerData, operands),
        .s_ext8x32 => |operands| try fiber.cast(i8, i32, registerData, operands),
        .s_ext8x64 => |operands| try fiber.cast(i8, i64, registerData, operands),
        .s_ext16x32 => |operands| try fiber.cast(i16, i32, registerData, operands),
        .s_ext16x64 => |operands| try fiber.cast(i16, i64, registerData, operands),
        .s_ext32x64 => |operands| try fiber.cast(i32, i64, registerData, operands),
        .f_ext32x64 => |operands| try fiber.cast(f32, i64, registerData, operands),

        .i_trunc64x32 => |operands| try fiber.cast(u64, u32, registerData, operands),
        .i_trunc64x16 => |operands| try fiber.cast(u64, u16, registerData, operands),
        .i_trunc64x8 => |operands| try fiber.cast(u64, u8, registerData, operands),
        .i_trunc32x16 => |operands| try fiber.cast(u32, u16, registerData, operands),
        .i_trunc32x8 => |operands| try fiber.cast(u32, u8, registerData, operands),
        .i_trunc16x8 => |operands| try fiber.cast(u16, u8, registerData, operands),
        .f_trunc64x32 => |operands| try fiber.cast(f64, f32, registerData, operands),

        .u8_to_f32 => |operands| try fiber.cast(u8, f32, registerData, operands),
        .u8_to_f64 => |operands| try fiber.cast(u8, f64, registerData, operands),
        .u16_to_f32 => |operands| try fiber.cast(u16, f32, registerData, operands),
        .u16_to_f64 => |operands| try fiber.cast(u16, f64, registerData, operands),
        .u32_to_f32 => |operands| try fiber.cast(u32, f32, registerData, operands),
        .u32_to_f64 => |operands| try fiber.cast(u32, f64, registerData, operands),
        .u64_to_f32 => |operands| try fiber.cast(u64, f32, registerData, operands),
        .u64_to_f64 => |operands| try fiber.cast(u64, f64, registerData, operands),
        .s8_to_f32 => |operands| try fiber.cast(i8, f32, registerData, operands),
        .s8_to_f64 => |operands| try fiber.cast(i8, f64, registerData, operands),
        .s16_to_f32 => |operands| try fiber.cast(i16, f32, registerData, operands),
        .s16_to_f64 => |operands| try fiber.cast(i16, f64, registerData, operands),
        .s32_to_f32 => |operands| try fiber.cast(i32, f32, registerData, operands),
        .s32_to_f64 => |operands| try fiber.cast(i32, f64, registerData, operands),
        .s64_to_f32 => |operands| try fiber.cast(i64, f32, registerData, operands),
        .s64_to_f64 => |operands| try fiber.cast(i64, f64, registerData, operands),
        .f32_to_u8 => |operands| try fiber.cast(f32, u8, registerData, operands),
        .f32_to_u16 => |operands| try fiber.cast(f32, u16, registerData, operands),
        .f32_to_u32 => |operands| try fiber.cast(f32, u32, registerData, operands),
        .f32_to_u64 => |operands| try fiber.cast(f32, u64, registerData, operands),
        .f64_to_u8 => |operands| try fiber.cast(f64, u8, registerData, operands),
        .f64_to_u16 => |operands| try fiber.cast(f64, u16, registerData, operands),
        .f64_to_u32 => |operands| try fiber.cast(f64, u32, registerData, operands),
        .f64_to_u64 => |operands| try fiber.cast(f64, u64, registerData, operands),
        .f32_to_s8 => |operands| try fiber.cast(f32, i8, registerData, operands),
        .f32_to_s16 => |operands| try fiber.cast(f32, i16, registerData, operands),
        .f32_to_s32 => |operands| try fiber.cast(f32, i32, registerData, operands),
        .f32_to_s64 => |operands| try fiber.cast(f32, i64, registerData, operands),
        .f64_to_s8 => |operands| try fiber.cast(f64, i8, registerData, operands),
        .f64_to_s16 => |operands| try fiber.cast(f64, i16, registerData, operands),
        .f64_to_s32 => |operands| try fiber.cast(f64, i32, registerData, operands),
        .f64_to_s64 => |operands| try fiber.cast(f64, i64, registerData, operands),
    }
}

pub fn stepForeign(fiber: *Fiber, currentCallFrame: *Fiber.CallFrame, currentFfunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet) Fiber.Trap!void {
    const foreign = try fiber.getForeign(currentFfunction.value.foreign);

    const currentBlockFrame = try fiber.stack.block.getPtr(currentCallFrame.root_block);
    const foreignRegisterData = Fiber.ForeignRegisterDataSet.fromNative(registerData);

    var out: Fiber.ForeignOut = undefined;
    const control = foreign(fiber, currentBlockFrame.index, &foreignRegisterData, &out);

    switch (control) {
        .trap => return Fiber.convertForeignError(out.trap),
        .step => currentBlockFrame.index = out.step,
        .done => try ret(fiber, currentCallFrame, currentFfunction, registerData, out.done),
    }
}


fn when(fiber: *Fiber, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, newBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, comptime zeroCheck: ZeroCheck) Fiber.Trap!void {
    const cond = try fiber.read(u8, registerData, x);

    if (newBlockIndex >= currentFunction.value.bytecode.blocks.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const newBlock = &currentFunction.value.bytecode.blocks[newBlockIndex];

    if (newBlock.kind.hasOutput()) {
        @branchHint(.cold);
        return Fiber.Trap.OutValueMismatch;
    }

    switch (zeroCheck) {
        .zero => if (cond == 0) try fiber.stack.block.push(.noOutput(newBlockIndex, null)),
        .non_zero => if (cond != 0) try fiber.stack.block.push(.noOutput(newBlockIndex, null)),
    }
}

fn br(fiber: *Fiber, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, terminatedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, y: ?Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) Fiber.Trap!void {
    const blockPtr = fiber.stack.block.ptr;

    if (terminatedBlockOffset >= blockPtr) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const terminatedBlockPtr = blockPtr - (terminatedBlockOffset + 1);
    const terminatedBlockFrame = try fiber.stack.block.getPtr(terminatedBlockPtr);
    const terminatedBlock = &currentFunction.value.bytecode.blocks[terminatedBlockFrame.index];

    if (!terminatedBlock.kind.hasOutput()) {
        @branchHint(.cold);
        return Fiber.Trap.OutValueMismatch;
    }

    if (zeroCheck) |zc| {
        const cond = try fiber.read(u8, registerData, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    if (y) |yOp| {
        const desiredSize = terminatedBlock.output_layout.?.size;
        const src = try fiber.addr(registerData, yOp, desiredSize);
        const dest = try fiber.addr(registerData, terminatedBlockFrame.out, desiredSize);
        @memcpy(dest[0..desiredSize], src);
    }

    try fiber.removeAnyHandlerSet(terminatedBlockFrame);

    fiber.stack.block.ptr = terminatedBlockPtr;
}

fn re(fiber: *Fiber, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, restartedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const blockPtr = fiber.stack.block.ptr;

    if (restartedBlockOffset >= blockPtr) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const restartedBlockPtr = blockPtr - (restartedBlockOffset + 1);

    const restartedBlockFrame = try fiber.stack.block.getPtr(restartedBlockPtr);

    const restartedBlock = &currentFunction.value.bytecode.blocks[restartedBlockFrame.index];

    if (restartedBlock.kind != .basic) {
        @branchHint(.cold);
        return Fiber.Trap.InvalidBlockRestart;
    }

    if (zeroCheck) |zc| {
        const cond = try fiber.read(u8, registerData, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    restartedBlockFrame.ip_offset = 0;

    fiber.stack.block.ptr = restartedBlockPtr + 1;
}

fn block(fiber: *Fiber, currentFunction: *Bytecode.Function, newBlockIndex: Bytecode.BlockIndex, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (newBlockIndex >= currentFunction.value.bytecode.blocks.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const newBlock = &currentFunction.value.bytecode.blocks[newBlockIndex];

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            if (!newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :newBlockFrame Fiber.BlockFrame.value(newBlockIndex, yOp, null);
        } else {
            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :newBlockFrame Fiber.BlockFrame.noOutput(newBlockIndex, null);
        }
    };

    try fiber.stack.block.push(newBlockFrame);
}

fn with(fiber: *Fiber, currentFunction: *Bytecode.Function, newBlockIndex: Bytecode.BlockIndex, handlerSetIndex: Bytecode.HandlerSetIndex, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (newBlockIndex >= currentFunction.value.bytecode.blocks.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const newBlock = &currentFunction.value.bytecode.blocks[newBlockIndex];

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

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            if (!newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :newBlockFrame Fiber.BlockFrame.value(newBlockIndex, yOp, handlerSetIndex);
        } else {
            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :newBlockFrame Fiber.BlockFrame.noOutput(newBlockIndex, handlerSetIndex);
        }
    };

    try fiber.stack.block.push(newBlockFrame);
}

fn @"if"(fiber: *Fiber, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, thenBlockIndex: Bytecode.BlockIndex, elseBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, y: ?Bytecode.Operand, comptime zeroCheck: ZeroCheck) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const cond = try fiber.read(u8, registerData, x);

    const thenBlockInBounds = @intFromBool(thenBlockIndex < currentFunction.value.bytecode.blocks.len);
    const elseBlockInBounds = @intFromBool(elseBlockIndex < currentFunction.value.bytecode.blocks.len);
    if (thenBlockInBounds & elseBlockInBounds != 1) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const thenBlock = &currentFunction.value.bytecode.blocks[thenBlockIndex];
    const elseBlock = &currentFunction.value.bytecode.blocks[elseBlockIndex];

    const thenBlockHasOutput = @intFromBool(thenBlock.kind.hasOutput());
    const elseBlockHasOutput = @intFromBool(elseBlock.kind.hasOutput());

    const destBlockIndex = switch (zeroCheck) {
        .zero => if (cond == 0) thenBlockIndex else elseBlockIndex,
        .non_zero => if (cond != 0) thenBlockIndex else elseBlockIndex,
    };

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            if (thenBlockHasOutput & elseBlockHasOutput != 1) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :newBlockFrame Fiber.BlockFrame.value(destBlockIndex, yOp, null);
        } else {
            if (thenBlockHasOutput | elseBlockHasOutput != 0) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            break :newBlockFrame Fiber.BlockFrame.noOutput(destBlockIndex, null);
        }
    };

    try fiber.stack.block.push(newBlockFrame);
}

fn case(fiber: *Fiber, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, blockIndices: []const Bytecode.BlockIndex, x: Bytecode.Operand, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const index = try fiber.read(u8, registerData, x);

    if (index >= blockIndices.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const caseBlockIndex = blockIndices[index];

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            // TODO: find a way to do this more efficiently
            for (blockIndices) |blockIndex| {
                if (blockIndex >= currentFunction.value.bytecode.blocks.len) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutOfBounds;
                }

                const caseBlock = &currentFunction.value.bytecode.blocks[blockIndex];

                if (!caseBlock.kind.hasOutput()) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            }

            break :newBlockFrame Fiber.BlockFrame.value(caseBlockIndex, yOp, null);
        } else {
            // TODO: find a way to do this more efficiently
            for (blockIndices) |blockIndex| {
                if (blockIndex >= currentFunction.value.bytecode.blocks.len) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutOfBounds;
                }

                const caseBlock = &currentFunction.value.bytecode.blocks[blockIndex];

                if (caseBlock.kind.hasOutput()) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            }

            break :newBlockFrame Fiber.BlockFrame.noOutput(caseBlockIndex, null);
        }
    };

    try fiber.stack.block.push(newBlockFrame);
}

fn addr(fiber: *Fiber, registerData: Fiber.RegisterDataSet, x: Bytecode.Operand, y: Bytecode.Operand) Fiber.Trap!void {
    const bytes: [*]const u8 = try fiber.addr(registerData, x, 0);

    try fiber.write(registerData, y, bytes);
}

fn dynCall(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, func: Bytecode.Operand, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const funcIndex = try fiber.read(Bytecode.FunctionIndex, registerData, func);

    return call(fiber, oldCallFrame, oldFunction, registerData, funcIndex, args, style);
}

fn call(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (funcIndex >= fiber.program.functions.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return callImpl(fiber, oldCallFrame, oldFunction, registerData, Bytecode.EVIDENCE_SENTINEL, funcIndex, args, style);
}

fn prompt(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, evIndex: Bytecode.EvidenceIndex, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (evIndex >= fiber.evidence.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const evidence = try fiber.evidence[evIndex].topPtr();

    return callImpl(fiber, oldCallFrame, oldFunction, registerData, evIndex, evidence.handler, args, style);
}

fn callImpl(fiber: *Fiber, oldCallFrame: *Fiber.CallFrame, oldFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    if (args.len != newFunction.layout_table.num_arguments) {
        @branchHint(.cold);
        return Fiber.Trap.ArgCountMismatch;
    }

    const newBlockFrame, const isTail = callStyle: {
        switch (style) {
            .no_tail => if (newFunction.layout_table.return_layout != null) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            } else {
                break :callStyle .{
                    Fiber.BlockFrame.entryPoint(null),
                    false,
                };
            },
            .no_tail_v => |out| if (newFunction.layout_table.return_layout) |returnLayout| {
                _ = try fiber.addr(registerData, out, returnLayout.size);
                break :callStyle .{
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
                break :callStyle .{
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
                    break :callStyle .{
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
        const arg = try fiber.addr(registerData, args[i], desiredSize);
        const offset = newFunction.layout_table.register_offsets[i];
        @memcpy(fiber.stack.data.memory[offset..offset + desiredSize], arg);
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

    try fiber.stack.block.push(newBlockFrame);

}

fn term(fiber: *Fiber, currentCallFrame: *Fiber.CallFrame, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const evRef = if (currentCallFrame.evidence) |e| e else {
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
            const size = currentFunction.layout_table.term_layout.?.size;
            const src: [*]const u8 = try fiber.addr(registerData, outOp, size);

            const rootRegisterData = try fiber.getRegisterData(rootCallFrame, rootFunction);
            const dest: [*]u8 = try fiber.addr(rootRegisterData, rootBlockFrame.out, size);

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

fn ret(fiber: *Fiber, currentCallFrame: *Fiber.CallFrame, currentFunction: *Bytecode.Function, registerData: Fiber.RegisterDataSet, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const rootBlockFrame = try fiber.stack.block.getPtr(currentCallFrame.root_block);
    const rootBlock = &currentFunction.value.bytecode.blocks[rootBlockFrame.index];

    const callerFrame = try fiber.stack.call.getPtr(fiber.stack.call.ptr - 2);
    const callerFunction = &fiber.program.functions[callerFrame.function];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = currentFunction.layout_table.return_layout.?.size;
            const src: [*]const u8 = try fiber.addr(registerData, outOp, size);

            const callerRegisterData = try fiber.getRegisterData(callerFrame, callerFunction);
            const dest: [*]u8 = try fiber.addr(callerRegisterData, rootBlockFrame.out, size);

            @memcpy(dest[0..size], src);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.OutValueMismatch;
        }
    }

    fiber.stack.data.ptr = currentCallFrame.stack.base;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = currentCallFrame.root_block - 1;
}

