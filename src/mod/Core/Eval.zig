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


pub fn stepCall(fiber: *Fiber) Fiber.Trap!void {
    const start = fiber.stack.call.ptr;

    if (start == 0) {
        @branchHint(.unlikely);
        return;
    }

    while (fiber.stack.call.ptr >= start) {
        try @call(Config.INLINING_CALL_MOD, step, .{fiber});
    }
}

pub fn step(fiber: *Fiber) Fiber.Trap!void {
    return switch (fiber.stack.call.topPtrUnchecked().function.value) {
        .bytecode => @call(Config.INLINING_CALL_MOD, stepBytecode, .{fiber}),
        .foreign => @call(Config.INLINING_CALL_MOD, stepForeign, .{fiber}),
    };
}

fn stepBytecode(fiber: *Fiber) Fiber.Trap!void {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA);

    switch (fiber.decodeNextUnchecked()) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => {},

        .tail_call => |operands| try call(fiber, operands.f, operands.as, .tail),
        .tail_call_v => |operands| try call(fiber, operands.f, operands.as, .tail_v),
        .dyn_tail_call => |operands| try dynCall(fiber, operands.f, operands.as, .tail),
        .dyn_tail_call_v => |operands| try dynCall(fiber, operands.f, operands.as, .tail_v),
        .tail_prompt => |operands| try prompt(fiber, operands.e, operands.as, .tail),
        .tail_prompt_v => |operands| try prompt(fiber, operands.e, operands.as, .tail_v),

        .call => |operands| try call(fiber, operands.f, operands.as, .no_tail),
        .call_v => |operands| try call(fiber, operands.f, operands.as, .{ .no_tail_v = operands.y }),
        .dyn_call => |operands| try dynCall(fiber, operands.f, operands.as, .no_tail),
        .dyn_call_v => |operands| try dynCall(fiber, operands.f, operands.as, .{ .no_tail_v = operands.y }),
        .prompt => |operands| try prompt(fiber, operands.e, operands.as, .no_tail),
        .prompt_v => |operands| try prompt(fiber, operands.e, operands.as, .{ .no_tail_v = operands.y }),

        .ret => ret(fiber, null),
        .ret_v => |operands| ret(fiber, operands.y),
        .term => term(fiber, null),
        .term_v => |operands| term(fiber, operands.y),

        .when_z => |operands| when(fiber, operands.b, operands.x, .zero),
        .when_nz => |operands| when(fiber, operands.b, operands.x, .non_zero),

        .re => |operands| re(fiber, operands.b, null, null),
        .re_z => |operands| re(fiber, operands.b, operands.x, .zero),
        .re_nz => |operands| re(fiber, operands.b, operands.x, .non_zero),

        .br => |operands | br(fiber, operands.b, null, null, null),
        .br_z => |operands | br(fiber, operands.b, operands.x, null, .zero),
        .br_nz => |operands | br(fiber, operands.b, operands.x, null, .non_zero),

        .br_v => |operands| br(fiber, operands.b, null, operands.y, null),
        .br_z_v => |operands| br(fiber, operands.b, operands.x, operands.y, .zero),
        .br_nz_v => |operands| br(fiber, operands.b, operands.x, operands.y, .non_zero),

        .block => |operands| block(fiber, operands.b, null),
        .block_v => |operands| block(fiber, operands.b, operands.y),

        .with => |operands| try with(fiber, operands.b, operands.h, null),
        .with_v => |operands| try with(fiber, operands.b, operands.h, operands.y),

        .if_z => |operands| @"if"(fiber, operands.t, operands.e, operands.x, null, .zero),
        .if_nz => |operands| @"if"(fiber, operands.t, operands.e, operands.x, null, .non_zero),
        .if_z_v => |operands| @"if"(fiber, operands.t, operands.e, operands.x, operands.y, .zero),
        .if_nz_v => |operands| @"if"(fiber, operands.t, operands.e, operands.x, operands.y, .non_zero),

        .addr => |operands| addr(fiber, operands.x, operands.y),

        .load8 => |operands| try fiber.load(u8, operands.x, operands.y),
        .load16 => |operands| try fiber.load(u16, operands.x, operands.y),
        .load32 => |operands| try fiber.load(u32, operands.x, operands.y),
        .load64 => |operands| try fiber.load(u64, operands.x, operands.y),

        .store8 => |operands| try fiber.store(u8, operands.x, operands.y),
        .store16 => |operands| try fiber.store(u16, operands.x, operands.y),
        .store32 => |operands| try fiber.store(u32, operands.x, operands.y),
        .store64 => |operands| try fiber.store(u64, operands.x, operands.y),

        .clear8 => |operands| fiber.clear(u8, operands.x),
        .clear16 => |operands| fiber.clear(u16, operands.x),
        .clear32 => |operands| fiber.clear(u32, operands.x),
        .clear64 => |operands| fiber.clear(u64, operands.x),

        .swap8 => |operands| fiber.swap(u8, operands.x, operands.y),
        .swap16 => |operands| fiber.swap(u16, operands.x, operands.y),
        .swap32 => |operands| fiber.swap(u32, operands.x, operands.y),
        .swap64 => |operands| fiber.swap(u64, operands.x, operands.y),

        .copy8 => |operands| fiber.copy(u8, operands.x, operands.y),
        .copy16 => |operands| fiber.copy(u16, operands.x, operands.y),
        .copy32 => |operands| fiber.copy(u32, operands.x, operands.y),
        .copy64 => |operands| fiber.copy(u64, operands.x, operands.y),

        .b_not => |operands| fiber.unary(bool, "not", operands),
        .b_and => |operands| fiber.binary(bool, "and", operands),
        .b_or => |operands| fiber.binary(bool, "or", operands),

        .f_add32 => |operands| fiber.binary(f32, "add", operands),
        .f_add64 => |operands| fiber.binary(f64, "add", operands),
        .f_sub32 => |operands| fiber.binary(f32, "sub", operands),
        .f_sub64 => |operands| fiber.binary(f64, "sub", operands),
        .f_mul32 => |operands| fiber.binary(f32, "mul", operands),
        .f_mul64 => |operands| fiber.binary(f64, "mul", operands),
        .f_div32 => |operands| fiber.binary(f32, "div", operands),
        .f_div64 => |operands| fiber.binary(f64, "div", operands),
        .f_rem32 => |operands| fiber.binary(f32, "rem", operands),
        .f_rem64 => |operands| fiber.binary(f64, "rem", operands),
        .f_neg32 => |operands| fiber.unary(f32, "neg", operands),
        .f_neg64 => |operands| fiber.unary(f64, "neg", operands),

        .f_eq32 => |operands| fiber.binary(f32, "eq", operands),
        .f_eq64 => |operands| fiber.binary(f64, "eq", operands),
        .f_ne32 => |operands| fiber.binary(f32, "ne", operands),
        .f_ne64 => |operands| fiber.binary(f64, "ne", operands),
        .f_lt32 => |operands| fiber.binary(f32, "lt", operands),
        .f_lt64 => |operands| fiber.binary(f64, "lt", operands),
        .f_gt32 => |operands| fiber.binary(f32, "gt", operands),
        .f_gt64 => |operands| fiber.binary(f64, "gt", operands),
        .f_le32 => |operands| fiber.binary(f32, "le", operands),
        .f_le64 => |operands| fiber.binary(f64, "le", operands),
        .f_ge32 => |operands| fiber.binary(f32, "ge", operands),
        .f_ge64 => |operands| fiber.binary(f64, "ge", operands),

        .i_add8 => |operands| fiber.binary(u8, "add", operands),
        .i_add16 => |operands| fiber.binary(u16, "add", operands),
        .i_add32 => |operands| fiber.binary(u32, "add", operands),
        .i_add64 => |operands| fiber.binary(u64, "add", operands),
        .i_sub8 => |operands| fiber.binary(u8, "sub", operands),
        .i_sub16 => |operands| fiber.binary(u16, "sub", operands),
        .i_sub32 => |operands| fiber.binary(u32, "sub", operands),
        .i_sub64 => |operands| fiber.binary(u64, "sub", operands),
        .i_mul8 => |operands| fiber.binary(u8, "mul", operands),
        .i_mul16 => |operands| fiber.binary(u16, "mul", operands),
        .i_mul32 => |operands| fiber.binary(u32, "mul", operands),
        .i_mul64 => |operands| fiber.binary(u64, "mul", operands),
        .s_div8 => |operands| fiber.binary(i8, "div", operands),
        .s_div16 => |operands| fiber.binary(i16, "div", operands),
        .s_div32 => |operands| fiber.binary(i32, "div", operands),
        .s_div64 => |operands| fiber.binary(i64, "div", operands),
        .u_div8 => |operands| fiber.binary(u8, "div", operands),
        .u_div16 => |operands| fiber.binary(u16, "div", operands),
        .u_div32 => |operands| fiber.binary(u32, "div", operands),
        .u_div64 => |operands| fiber.binary(u64, "div", operands),
        .s_rem8 => |operands| fiber.binary(i8, "rem", operands),
        .s_rem16 => |operands| fiber.binary(i16, "rem", operands),
        .s_rem32 => |operands| fiber.binary(i32, "rem", operands),
        .s_rem64 => |operands| fiber.binary(i64, "rem", operands),
        .u_rem8 => |operands| fiber.binary(u8, "rem", operands),
        .u_rem16 => |operands| fiber.binary(u16, "rem", operands),
        .u_rem32 => |operands| fiber.binary(u32, "rem", operands),
        .u_rem64 => |operands| fiber.binary(u64, "rem", operands),
        .s_neg8 => |operands| fiber.unary(i8, "neg", operands),
        .s_neg16 => |operands| fiber.unary(i16, "neg", operands),
        .s_neg32 => |operands| fiber.unary(i32, "neg", operands),
        .s_neg64 => |operands| fiber.unary(i64, "neg", operands),

        .i_bitnot8 => |operands| fiber.unary(u8, "bitnot", operands),
        .i_bitnot16 => |operands| fiber.unary(u16, "bitnot", operands),
        .i_bitnot32 => |operands| fiber.unary(u32, "bitnot", operands),
        .i_bitnot64 => |operands| fiber.unary(u64, "bitnot", operands),
        .i_bitand8 => |operands| fiber.binary(u8, "bitand", operands),
        .i_bitand16 => |operands| fiber.binary(u16, "bitand", operands),
        .i_bitand32 => |operands| fiber.binary(u32, "bitand", operands),
        .i_bitand64 => |operands| fiber.binary(u64, "bitand", operands),
        .i_bitor8 => |operands| fiber.binary(u8, "bitor", operands),
        .i_bitor16 => |operands| fiber.binary(u16, "bitor", operands),
        .i_bitor32 => |operands| fiber.binary(u32, "bitor", operands),
        .i_bitor64 => |operands| fiber.binary(u64, "bitor", operands),
        .i_bitxor8 => |operands| fiber.binary(u8, "bitxor", operands),
        .i_bitxor16 => |operands| fiber.binary(u16, "bitxor", operands),
        .i_bitxor32 => |operands| fiber.binary(u32, "bitxor", operands),
        .i_bitxor64 => |operands| fiber.binary(u64, "bitxor", operands),
        .i_shiftl8 => |operands| fiber.binary(u8, "shiftl", operands),
        .i_shiftl16 => |operands| fiber.binary(u16, "shiftl", operands),
        .i_shiftl32 => |operands| fiber.binary(u32, "shiftl", operands),
        .i_shiftl64 => |operands| fiber.binary(u64, "shiftl", operands),
        .u_shiftr8 => |operands| fiber.binary(u8, "shiftr", operands),
        .u_shiftr16 => |operands| fiber.binary(u16, "shiftr", operands),
        .u_shiftr32 => |operands| fiber.binary(u32, "shiftr", operands),
        .u_shiftr64 => |operands| fiber.binary(u64, "shiftr", operands),
        .s_shiftr8 => |operands| fiber.binary(i8, "shiftr", operands),
        .s_shiftr16 => |operands| fiber.binary(i16, "shiftr", operands),
        .s_shiftr32 => |operands| fiber.binary(i32, "shiftr", operands),
        .s_shiftr64 => |operands| fiber.binary(i64, "shiftr", operands),

        .i_eq8 => |operands| fiber.binary(u8, "eq", operands),
        .i_eq16 => |operands| fiber.binary(u16, "eq", operands),
        .i_eq32 => |operands| fiber.binary(u32, "eq", operands),
        .i_eq64 => |operands| fiber.binary(u64, "eq", operands),
        .i_ne8 => |operands| fiber.binary(u8, "ne", operands),
        .i_ne16 => |operands| fiber.binary(u16, "ne", operands),
        .i_ne32 => |operands| fiber.binary(u32, "ne", operands),
        .i_ne64 => |operands| fiber.binary(u64, "ne", operands),
        .u_lt8 => |operands| fiber.binary(u8, "lt", operands),
        .u_lt16 => |operands| fiber.binary(u16, "lt", operands),
        .u_lt32 => |operands| fiber.binary(u32, "lt", operands),
        .u_lt64 => |operands| fiber.binary(u64, "lt", operands),
        .s_lt8 => |operands| fiber.binary(i8, "lt", operands),
        .s_lt16 => |operands| fiber.binary(i16, "lt", operands),
        .s_lt32 => |operands| fiber.binary(i32, "lt", operands),
        .s_lt64 => |operands| fiber.binary(i64, "lt", operands),
        .u_gt8 => |operands| fiber.binary(u8, "gt", operands),
        .u_gt16 => |operands| fiber.binary(u16, "gt", operands),
        .u_gt32 => |operands| fiber.binary(u32, "gt", operands),
        .u_gt64 => |operands| fiber.binary(u64, "gt", operands),
        .s_gt8 => |operands| fiber.binary(i8, "gt", operands),
        .s_gt16 => |operands| fiber.binary(i16, "gt", operands),
        .s_gt32 => |operands| fiber.binary(i32, "gt", operands),
        .s_gt64 => |operands| fiber.binary(i64, "gt", operands),
        .u_le8 => |operands| fiber.binary(u8, "le", operands),
        .u_le16 => |operands| fiber.binary(u16, "le", operands),
        .u_le32 => |operands| fiber.binary(u32, "le", operands),
        .u_le64 => |operands| fiber.binary(u64, "le", operands),
        .s_le8 => |operands| fiber.binary(i8, "le", operands),
        .s_le16 => |operands| fiber.binary(i16, "le", operands),
        .s_le32 => |operands| fiber.binary(i32, "le", operands),
        .s_le64 => |operands| fiber.binary(i64, "le", operands),
        .u_ge8 => |operands| fiber.binary(u8, "ge", operands),
        .u_ge16 => |operands| fiber.binary(u16, "ge", operands),
        .u_ge32 => |operands| fiber.binary(u32, "ge", operands),
        .u_ge64 => |operands| fiber.binary(u64, "ge", operands),
        .s_ge8 => |operands| fiber.binary(i8, "ge", operands),
        .s_ge16 => |operands| fiber.binary(i16, "ge", operands),
        .s_ge32 => |operands| fiber.binary(i32, "ge", operands),
        .s_ge64 => |operands| fiber.binary(i64, "ge", operands),

        .u_ext8x16 => |operands| fiber.cast(u8, u16, operands),
        .u_ext8x32 => |operands| fiber.cast(u8, u32, operands),
        .u_ext8x64 => |operands| fiber.cast(u8, u64, operands),
        .u_ext16x32 => |operands| fiber.cast(u16, u32, operands),
        .u_ext16x64 => |operands| fiber.cast(u16, u64, operands),
        .u_ext32x64 => |operands| fiber.cast(u32, u64, operands),
        .s_ext8x16 => |operands| fiber.cast(i8, i16, operands),
        .s_ext8x32 => |operands| fiber.cast(i8, i32, operands),
        .s_ext8x64 => |operands| fiber.cast(i8, i64, operands),
        .s_ext16x32 => |operands| fiber.cast(i16, i32, operands),
        .s_ext16x64 => |operands| fiber.cast(i16, i64, operands),
        .s_ext32x64 => |operands| fiber.cast(i32, i64, operands),
        .f_ext32x64 => |operands| fiber.cast(f32, i64, operands),

        .i_trunc64x32 => |operands| fiber.cast(u64, u32, operands),
        .i_trunc64x16 => |operands| fiber.cast(u64, u16, operands),
        .i_trunc64x8 => |operands| fiber.cast(u64, u8, operands),
        .i_trunc32x16 => |operands| fiber.cast(u32, u16, operands),
        .i_trunc32x8 => |operands| fiber.cast(u32, u8, operands),
        .i_trunc16x8 => |operands| fiber.cast(u16, u8, operands),
        .f_trunc64x32 => |operands| fiber.cast(f64, f32, operands),

        .u8_to_f32 => |operands| fiber.cast(u8, f32, operands),
        .u8_to_f64 => |operands| fiber.cast(u8, f64, operands),
        .u16_to_f32 => |operands| fiber.cast(u16, f32, operands),
        .u16_to_f64 => |operands| fiber.cast(u16, f64, operands),
        .u32_to_f32 => |operands| fiber.cast(u32, f32, operands),
        .u32_to_f64 => |operands| fiber.cast(u32, f64, operands),
        .u64_to_f32 => |operands| fiber.cast(u64, f32, operands),
        .u64_to_f64 => |operands| fiber.cast(u64, f64, operands),
        .s8_to_f32 => |operands| fiber.cast(i8, f32, operands),
        .s8_to_f64 => |operands| fiber.cast(i8, f64, operands),
        .s16_to_f32 => |operands| fiber.cast(i16, f32, operands),
        .s16_to_f64 => |operands| fiber.cast(i16, f64, operands),
        .s32_to_f32 => |operands| fiber.cast(i32, f32, operands),
        .s32_to_f64 => |operands| fiber.cast(i32, f64, operands),
        .s64_to_f32 => |operands| fiber.cast(i64, f32, operands),
        .s64_to_f64 => |operands| fiber.cast(i64, f64, operands),
        .f32_to_u8 => |operands| fiber.cast(f32, u8, operands),
        .f32_to_u16 => |operands| fiber.cast(f32, u16, operands),
        .f32_to_u32 => |operands| fiber.cast(f32, u32, operands),
        .f32_to_u64 => |operands| fiber.cast(f32, u64, operands),
        .f64_to_u8 => |operands| fiber.cast(f64, u8, operands),
        .f64_to_u16 => |operands| fiber.cast(f64, u16, operands),
        .f64_to_u32 => |operands| fiber.cast(f64, u32, operands),
        .f64_to_u64 => |operands| fiber.cast(f64, u64, operands),
        .f32_to_s8 => |operands| fiber.cast(f32, i8, operands),
        .f32_to_s16 => |operands| fiber.cast(f32, i16, operands),
        .f32_to_s32 => |operands| fiber.cast(f32, i32, operands),
        .f32_to_s64 => |operands| fiber.cast(f32, i64, operands),
        .f64_to_s8 => |operands| fiber.cast(f64, i8, operands),
        .f64_to_s16 => |operands| fiber.cast(f64, i16, operands),
        .f64_to_s32 => |operands| fiber.cast(f64, i32, operands),
        .f64_to_s64 => |operands| fiber.cast(f64, i64, operands),
    }
}

fn stepForeign(fiber: *Fiber) Fiber.Trap!void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const registerData = fiber.getRegisterDataSetUnchecked(fiber.stack.call.ptr -| 1);
    const foreign = fiber.getForeignUnchecked(currentCallFrame.function.value.foreign);

    const currentBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);
    const foreignRegisterData = Fiber.ForeignRegisterDataSet.fromNative(registerData);

    var out: Fiber.ForeignOut = undefined;
    const control = foreign(fiber, currentBlockFrame.index, &foreignRegisterData, &out);

    switch (control) {
        .trap => return Fiber.convertForeignError(out.trap),
        .step => currentBlockFrame.index = out.step,
        .done => ret(fiber, out.done),
    }
}


fn when(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, comptime zeroCheck: ZeroCheck) void {
    // const currentCallFrame = try fiber.stack.call.topPtr();
    const cond = fiber.read(u8, x);

    // if (newBlockIndex >= currentCallFrame.function.value.bytecode.blocks.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    // const newBlock = &currentCallFrame.function.value.bytecode.blocks[newBlockIndex];

    // if (newBlock.kind.hasOutput()) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutValueMismatch;
    // }

    switch (zeroCheck) {
        .zero => if (cond == 0) fiber.stack.block.pushUnchecked(.noOutput(newBlockIndex, null)),
        .non_zero => if (cond != 0) fiber.stack.block.pushUnchecked(.noOutput(newBlockIndex, null)),
    }
}

fn br(fiber: *Fiber, terminatedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, y: ?Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const blockPtr = fiber.stack.block.ptr;

    // if (terminatedBlockOffset >= blockPtr) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const terminatedBlockPtr = blockPtr - (terminatedBlockOffset + 1);
    const terminatedBlockFrame = fiber.stack.block.getPtrUnchecked(terminatedBlockPtr);
    const terminatedBlock = &currentCallFrame.function.value.bytecode.blocks[terminatedBlockFrame.index];

    // if (!terminatedBlock.kind.hasOutput()) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutValueMismatch;
    // }

    if (zeroCheck) |zc| {
        const cond = fiber.read(u8, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    if (y) |yOp| {
        const desiredSize = terminatedBlock.output_layout.?.size;
        const src = fiber.addr(yOp);
        const dest = fiber.addr(terminatedBlockFrame.out);
        @memcpy(dest[0..desiredSize], src);
    }

    fiber.removeAnyHandlerSet(terminatedBlockFrame);

    fiber.stack.block.ptr = terminatedBlockPtr;
}

fn re(fiber: *Fiber, restartedBlockOffset: Bytecode.BlockIndex, x: ?Bytecode.Operand, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    // const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const blockPtr = fiber.stack.block.ptr;

    // if (restartedBlockOffset >= blockPtr) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const restartedBlockPtr = blockPtr - (restartedBlockOffset + 1);

    const restartedBlockFrame = fiber.stack.block.getPtrUnchecked(restartedBlockPtr);

    // const restartedBlock = &currentCallFrame.function.value.bytecode.blocks[restartedBlockFrame.index];

    // if (restartedBlock.kind != .basic) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.InvalidBlockRestart;
    // }

    if (zeroCheck) |zc| {
        const cond = fiber.read(u8, x.?);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    restartedBlockFrame.ip_offset = 0;

    fiber.stack.block.ptr = restartedBlockPtr + 1;
}

fn block(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    // const currentCallFrame = try fiber.stack.call.topPtr();

    // if (newBlockIndex >= currentCallFrame.function.value.bytecode.blocks.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    // const newBlock = &currentCallFrame.function.value.bytecode.blocks[newBlockIndex];

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            // if (!newBlock.kind.hasOutput()) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // }

            break :newBlockFrame Fiber.BlockFrame.value(newBlockIndex, yOp, null);
        } else {
            // if (newBlock.kind.hasOutput()) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // }

            break :newBlockFrame Fiber.BlockFrame.noOutput(newBlockIndex, null);
        }
    };

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn with(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, handlerSetIndex: Bytecode.HandlerSetIndex, y: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    // const currentCallFrame = try fiber.stack.call.topPtr();

    // if (newBlockIndex >= currentCallFrame.function.value.bytecode.blocks.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    // const newBlock = &currentCallFrame.function.value.bytecode.blocks[newBlockIndex];

    // if (handlerSetIndex >= fiber.program.handler_sets.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const handlerSet = fiber.program.handler_sets[handlerSetIndex];

    for (handlerSet) |binding| {
        // if (binding.id >= fiber.evidence.len) {
        //     @branchHint(.cold);
        //     return Fiber.Trap.OutOfBounds;
        // }

        try fiber.evidence[binding.id].push(Fiber.Evidence {
            .handler = binding.handler,
            .data = fiber.stack.data.ptr,
            .call = fiber.stack.call.ptr,
            .block = fiber.stack.block.ptr,
        });
    }

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            // if (!newBlock.kind.hasOutput()) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // }

            break :newBlockFrame Fiber.BlockFrame.value(newBlockIndex, yOp, handlerSetIndex);
        } else {
            // if (newBlock.kind.hasOutput()) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // }

            break :newBlockFrame Fiber.BlockFrame.noOutput(newBlockIndex, handlerSetIndex);
        }
    };

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn @"if"(fiber: *Fiber, thenBlockIndex: Bytecode.BlockIndex, elseBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, y: ?Bytecode.Operand, comptime zeroCheck: ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    // const currentCallFrame = try fiber.stack.call.topPtr();

    const cond = fiber.read(u8, x);

    // const thenBlockInBounds = @intFromBool(thenBlockIndex < currentCallFrame.function.value.bytecode.blocks.len);
    // const elseBlockInBounds = @intFromBool(elseBlockIndex < currentCallFrame.function.value.bytecode.blocks.len);
    // if (thenBlockInBounds & elseBlockInBounds != 1) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    // const thenBlock = &currentCallFrame.function.value.bytecode.blocks[thenBlockIndex];
    // const elseBlock = &currentCallFrame.function.value.bytecode.blocks[elseBlockIndex];

    // const thenBlockHasOutput = @intFromBool(thenBlock.kind.hasOutput());
    // const elseBlockHasOutput = @intFromBool(elseBlock.kind.hasOutput());

    const destBlockIndex = switch (zeroCheck) {
        .zero => if (cond == 0) thenBlockIndex else elseBlockIndex,
        .non_zero => if (cond != 0) thenBlockIndex else elseBlockIndex,
    };

    const newBlockFrame = newBlockFrame: {
        if (y) |yOp| {
            // if (thenBlockHasOutput & elseBlockHasOutput != 1) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // }

            break :newBlockFrame Fiber.BlockFrame.value(destBlockIndex, yOp, null);
        } else {
            // if (thenBlockHasOutput | elseBlockHasOutput != 0) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // }

            break :newBlockFrame Fiber.BlockFrame.noOutput(destBlockIndex, null);
        }
    };

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn addr(fiber: *Fiber, x: Bytecode.Operand, y: Bytecode.Operand) void {
    const bytes: [*]const u8 = fiber.addr(x);

    fiber.write(y, bytes);
}

fn dynCall(fiber: *Fiber, func: Bytecode.Operand, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const funcIndex = fiber.read(Bytecode.FunctionIndex, func);

    return call(fiber, funcIndex, args, style);
}

fn call(fiber: *Fiber, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    // if (funcIndex >= fiber.program.functions.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    return callImpl(fiber, Bytecode.EVIDENCE_SENTINEL, funcIndex, args, style);
}

fn prompt(fiber: *Fiber, evIndex: Bytecode.EvidenceIndex, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    // if (evIndex >= fiber.evidence.len) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.OutOfBounds;
    // }

    const evidence = fiber.evidence[evIndex].topPtrUnchecked();

    return callImpl(fiber, evIndex, evidence.handler, args, style);
}

fn callImpl(fiber: *Fiber, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const oldCallFrame = fiber.stack.call.topPtrUnchecked();
    const newFunction = &fiber.program.functions[funcIndex];

    // if (args.len != newFunction.layout_table.num_arguments) {
    //     @branchHint(.cold);
    //     return Fiber.Trap.ArgCountMismatch;
    // }

    const newBlockFrame, const isTail = callStyle: {
        switch (style) {
            .no_tail =>
            // if (newFunction.layout_table.return_layout != null) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // } else
            {
                break :callStyle .{
                    Fiber.BlockFrame.entryPoint(null),
                    false,
                };
            },
            .no_tail_v => |out|
            if (newFunction.layout_table.return_layout != null) {// |returnLayout| {
            //     _ = try fiber.addr(out, returnLayout.size);
                break :callStyle .{
                    Fiber.BlockFrame.entryPoint(out),
                    false,
                };
            } else
            {
                // @branchHint(.cold);
                // return Fiber.Trap.OutValueMismatch;
            },
            .tail =>
            // if (oldCallFrame.function.layout_table.return_layout != null) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
            // } else
            {
                break :callStyle .{
                    Fiber.BlockFrame.entryPoint(null),
                    true,
                };
            },
            .tail_v => {// if (oldCallFrame.function.layout_table.return_layout) |oldLayout| {
                // if (newFunction.layout_table.return_layout) |newLayout| {
                    // const sameSize = @intFromBool(oldLayout.size == newLayout.size);
                    // const sameAlign = @intFromBool(oldLayout.alignment == newLayout.alignment);
                    // if (sameSize & sameAlign != 1) {
                    //     @branchHint(.cold);
                    //     return Fiber.Trap.OutValueMismatch;
                    // }
                    const oldFunctionRootBlockFrame = fiber.stack.block.getPtrUnchecked(oldCallFrame.root_block);
                    const oldFunctionOutput = oldFunctionRootBlockFrame.out;
                    break :callStyle .{
                        Fiber.BlockFrame.entryPoint(oldFunctionOutput),
                        true,
                    };
            //     } else {
            //         @branchHint(.cold);
            //         return Fiber.Trap.OutValueMismatch;
            //     }
            // } else {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutValueMismatch;
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
        const arg = fiber.addr(args[i]);
        const offset = base + newFunction.layout_table.register_offsets[i];
        @memcpy(fiber.stack.data.memory[offset..offset + desiredSize], arg);
    }

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = if (evIndex != Bytecode.EVIDENCE_SENTINEL) ev: {
            // if (evIndex >= fiber.evidence.len) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.OutOfBounds;
            // }

            // if (fiber.evidence[evIndex].ptr == 0) {
            //     @branchHint(.cold);
            //     return Fiber.Trap.MissingEvidence;
            // }

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

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn term(fiber: *Fiber, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const evRef = currentCallFrame.evidence.?;
    // if (currentCallFrame.evidence) |e| e else {
    //     @branchHint(.cold);
    //     return Fiber.Trap.MissingEvidence;
    // };

    const evidence = fiber.evidence[evRef.index].getPtrUnchecked(evRef.offset);

    // const rootCallFrame = fiber.stack.call.getPtrUnchecked(evidence.call);
    const rootBlockFrame = fiber.stack.block.getPtrUnchecked(evidence.block);
    // const rootBlock = &rootCallFrame.function.value.bytecode.blocks[rootBlockFrame.index];

    if (out) |outOp| {
        // if (rootBlock.kind.hasOutput()) {
            const size = currentCallFrame.function.layout_table.term_layout.?.size;
            const src: [*]const u8 = fiber.addr(outOp);

            const dest: [*]u8 = fiber.addrImpl(evidence.call, rootBlockFrame.out);

            @memcpy(dest[0..size], src);
        // } else {
        //     @branchHint(.cold);
        //     return Fiber.Trap.OutValueMismatch;
        // }
    }

    fiber.stack.data.ptr = evidence.data;
    fiber.stack.call.ptr = evidence.call;
    fiber.stack.block.ptr = evidence.block - 1;
}

fn ret(fiber: *Fiber, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const rootBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);
    // const rootBlock = &currentCallFrame.function.value.bytecode.blocks[rootBlockFrame.index];

    if (out) |outOp| {
        // if (rootBlock.kind.hasOutput()) {
            const size = currentCallFrame.function.layout_table.return_layout.?.size;
            const src: [*]const u8 = fiber.addr(outOp);

            const dest: [*]u8 = fiber.addrImpl(fiber.stack.call.ptr -| 2, rootBlockFrame.out);

            @memcpy(dest[0..size], src);
        // } else {
        //     @branchHint(.cold);
        //     return Fiber.Trap.OutValueMismatch;
        // }
    }

    fiber.stack.data.ptr = currentCallFrame.stack.base;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = currentCallFrame.root_block;
}

