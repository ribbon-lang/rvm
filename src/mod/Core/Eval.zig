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

const CallStyle = enum {
    tail,
    tail_v,
    no_tail,
    no_tail_v,

    ev_tail,
    ev_tail_v,
    ev_no_tail,
    ev_no_tail_v,
};

const ReturnStyle = enum {
    v,
    no_v
};

pub fn run(fiber: *Fiber) Fiber.Trap!void {
    return stepBytecode(true, fiber);
}

// pub fn stepCall(fiber: *Fiber) Fiber.Trap!void {
//     const start = fiber.stack.call.ptr;

//     if (start == 0) {
//         @branchHint(.unlikely);
//         return;
//     }

//     while (fiber.stack.call.ptr >= start) {
//         _ = try @call(Config.INLINING_CALL_MOD, step, .{fiber});
//     }
// }

// pub fn step(fiber: *Fiber) Fiber.Trap!bool {
//     return stepBytecode(false, fiber);
// }

inline fn decodeInstr(fiber: *Fiber, out_data: *Bytecode.OpData) Bytecode.OpCode {
    const currentBlockFrame = fiber.blocks.top();
    const instr = currentBlockFrame.ip[0];
    out_data.* = instr.data;
    // std.debug.print("{}\t|\t{s} {any}\n", .{@intFromPtr(currentBlockFrame.ip), @tagName(instr.code), @call(.never_inline, Bytecode.Info.extractInstructionInfo, .{instr})});
    currentBlockFrame.ip += 1;
    return instr.code;
}

inline fn decodeArguments(fiber: *Fiber, count: usize) [*]const Bytecode.RegisterIndex {
    const currentBlockFrame = fiber.blocks.top();

    const out: [*]const Bytecode.RegisterIndex = @ptrCast(currentBlockFrame.ip);

    const byteCount = count * @sizeOf(Bytecode.RegisterIndex);
    const byteOffset = @divTrunc(byteCount, @sizeOf(Bytecode.Instruction));
    const padding = @intFromBool(Support.alignmentDelta(byteCount, @sizeOf(Bytecode.Instruction)) > 0);

    currentBlockFrame.ip += byteOffset + padding;

    return out;
}


// TODO: reimplement foreign calls as an instruction
fn stepBytecode(comptime reswitch: bool, fiber: *Fiber) Fiber.Trap!if (reswitch) void else bool {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA);

    var lastData: Bytecode.OpData = undefined;

    reswitch: switch (decodeInstr(fiber, &lastData)) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData),
        .halt => if (comptime !reswitch) return false,

        .tail_call => {
            try callImpl_tail(fiber, fiber.readLocal(Bytecode.FunctionIndex, lastData.tail_call.R0));

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .tail_call_v => {
            try callImpl_tail_v(fiber, fiber.readLocal(Bytecode.FunctionIndex, lastData.tail_call_v.R0));

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .tail_call_im => {
            try callImpl_tail(fiber, lastData.tail_call_im.F0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .tail_call_im_v => {
            try callImpl_tail_v(fiber, lastData.tail_call_im_v.F0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .tail_prompt => {
            try callImpl_ev_tail(fiber, lastData.tail_prompt.E0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .tail_prompt_v => {
            try callImpl_ev_tail_v(fiber, lastData.tail_prompt_v.E0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .call => {
            try callImpl_no_tail(fiber, fiber.readLocal(Bytecode.FunctionIndex, lastData.call.R0), undefined);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .call_v => {
            try callImpl_no_tail(fiber, fiber.readLocal(Bytecode.FunctionIndex, lastData.call_v.R0), lastData.call_v.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .call_im => {
            try callImpl_no_tail(fiber, lastData.call_im.F0, undefined);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .call_im_v => {
            try callImpl_no_tail(fiber, lastData.call_im_v.F0, lastData.call_im_v.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .prompt => {
            try callImpl_ev_no_tail(fiber, lastData.prompt.E0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .prompt_v => {
            try callImpl_ev_no_tail_v(fiber, lastData.prompt_v.E0, lastData.prompt_v.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .ret => {
            ret(fiber, undefined, .no_v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .ret_v => {
            ret(fiber, lastData.ret_v.R0, .v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .term => {
            term(fiber, undefined, .no_v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .term_v => {
            term(fiber, lastData.term_v.R0, .v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .when_z => {
            when(fiber, lastData.when_z.B0, lastData.when_z.R0, .zero);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .when_nz => {
            when(fiber, lastData.when_nz.B0, lastData.when_nz.R0, .non_zero);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .re => {
            re(fiber, lastData.re.B0, undefined, null);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .re_z => {
            re(fiber, lastData.re_z.B0, lastData.re_z.R0, .zero);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .re_nz => {
            re(fiber, lastData.re_nz.B0, lastData.re_nz.R0, .non_zero);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .br => {
            br(fiber, lastData.br.B0, undefined, null, undefined, .no_v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .br_z => {
            br(fiber, lastData.br_z.B0, lastData.br_z.R0, .zero, undefined, .no_v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .br_nz => {
            br(fiber, lastData.br_nz.B0, lastData.br_nz.R0, .non_zero, undefined, .no_v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .br_v => {
            br(fiber, lastData.br_v.B0, undefined, null, lastData.br_v.R0, .v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .br_z_v => {
            br(fiber, lastData.br_z_v.B0, lastData.br_z_v.R0, .zero, lastData.br_z_v.R1, .v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .br_nz_v => {
            br(fiber, lastData.br_nz_v.B0, lastData.br_nz_v.R0, .non_zero, lastData.br_nz_v.R1, .v);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .block => {
            block(fiber, lastData.block.B0, undefined);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .block_v => {
            block(fiber, lastData.block_v.B0, lastData.block_v.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .with => {
            try with(fiber, lastData.with.B0, lastData.with.H0, undefined);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .with_v => {
            try with(fiber, lastData.with_v.B0, lastData.with_v.H0, lastData.with_v.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .if_z => {
            @"if"(fiber, lastData.if_z.B0, lastData.if_z.B1, lastData.if_z.R0, .zero, undefined);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .if_nz => {
            @"if"(fiber, lastData.if_nz.B0, lastData.if_nz.B1, lastData.if_nz.R0, .non_zero, undefined);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .if_z_v => {
            @"if"(fiber, lastData.if_z_v.B0, lastData.if_z_v.B1, lastData.if_z_v.R0, .zero, lastData.if_z_v.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .if_nz_v => {
            @"if"(fiber, lastData.if_nz_v.B0, lastData.if_nz_v.B1, lastData.if_nz_v.R0, .non_zero, lastData.if_nz_v.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .addr_local => {
            addr_local(fiber, lastData.addr_local.R0, lastData.addr_local.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .addr_global => {
            addr_global(fiber, lastData.addr_global.G0, lastData.addr_global.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .addr_upvalue => {
            addr_upvalue(fiber, lastData.addr_upvalue.U0, lastData.addr_upvalue.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .read_global_8 => {
            read_global(u8, fiber, lastData.read_global_8.G0, lastData.read_global_8.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .read_global_16 => {
            read_global(u16, fiber, lastData.read_global_16.G0, lastData.read_global_16.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .read_global_32 => {
            read_global(u32, fiber, lastData.read_global_32.G0, lastData.read_global_32.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .read_global_64 => {
            read_global(u64, fiber, lastData.read_global_64.G0, lastData.read_global_64.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .write_global_8 => {
            write_global(u8, fiber, lastData.write_global_8.G0, lastData.write_global_8.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .write_global_16 => {
            write_global(u16, fiber, lastData.write_global_16.G0, lastData.write_global_16.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .write_global_32 => {
            write_global(u32, fiber, lastData.write_global_32.G0, lastData.write_global_32.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .write_global_64 => {
            write_global(u64, fiber, lastData.write_global_64.G0, lastData.write_global_64.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .read_upvalue_8 => {
            read_upvalue(u8, fiber, lastData.read_upvalue_8.U0, lastData.read_upvalue_8.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .read_upvalue_16 => {
            read_upvalue(u16, fiber, lastData.read_upvalue_16.U0, lastData.read_upvalue_16.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .read_upvalue_32 => {
            read_upvalue(u32, fiber, lastData.read_upvalue_32.U0, lastData.read_upvalue_32.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .read_upvalue_64 => {
            read_upvalue(u64, fiber, lastData.read_upvalue_64.U0, lastData.read_upvalue_64.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .write_upvalue_8 => {
            write_upvalue(u8, fiber, lastData.write_upvalue_8.U0, lastData.write_upvalue_8.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .write_upvalue_16 => {
            write_upvalue(u16, fiber, lastData.write_upvalue_16.U0, lastData.write_upvalue_16.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .write_upvalue_32 => {
            write_upvalue(u32, fiber, lastData.write_upvalue_32.U0, lastData.write_upvalue_32.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .write_upvalue_64 => {
            write_upvalue(u64, fiber, lastData.write_upvalue_64.U0, lastData.write_upvalue_64.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .load_8 => {
            try load(u8, fiber, lastData.load_8.R0, lastData.load_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .load_16 => {
            try load(u16, fiber, lastData.load_16.R0, lastData.load_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .load_32 => {
            try load(u32, fiber, lastData.load_32.R0, lastData.load_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .load_64 => {
            try load(u64, fiber, lastData.load_64.R0, lastData.load_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .store_8 => {
            try store(u8, fiber, lastData.store_8.R0, lastData.store_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .store_16 => {
            try store(u16, fiber, lastData.store_16.R0, lastData.store_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .store_32 => {
            try store(u32, fiber, lastData.store_32.R0, lastData.store_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .store_64 => {
            try store(u64, fiber, lastData.store_64.R0, lastData.store_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .clear_8 => {
            clear(u8, fiber, lastData.clear_8.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .clear_16 => {
            clear(u16, fiber, lastData.clear_16.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .clear_32 => {
            clear(u32, fiber, lastData.clear_32.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .clear_64 => {
            clear(u64, fiber, lastData.clear_64.R0);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .swap_8 => {
            swap(u8, fiber, lastData.swap_8.R0, lastData.swap_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .swap_16 => {
            swap(u16, fiber, lastData.swap_16.R0, lastData.swap_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .swap_32 => {
            swap(u32, fiber, lastData.swap_32.R0, lastData.swap_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .swap_64 => {
            swap(u64, fiber, lastData.swap_64.R0, lastData.swap_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .copy_8 => {
            copy(u8, fiber, lastData.copy_8.R0, lastData.copy_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .copy_16 => {
            copy(u16, fiber, lastData.copy_16.R0, lastData.copy_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .copy_32 => {
            copy(u32, fiber, lastData.copy_32.R0, lastData.copy_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .copy_64 => {
            copy(u64, fiber, lastData.copy_64.R0, lastData.copy_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .f_add_32 => {
            binary(f32, fiber, "add", lastData.f_add_32.R0, lastData.f_add_32.R1, lastData.f_add_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_add_64 => {
            binary(f64, fiber, "add", lastData.f_add_64.R0, lastData.f_add_64.R1, lastData.f_add_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_sub_32 => {
            binary(f32, fiber, "sub", lastData.f_sub_32.R0, lastData.f_sub_32.R1, lastData.f_sub_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_sub_64 => {
            binary(f64, fiber, "sub", lastData.f_sub_64.R0, lastData.f_sub_64.R1, lastData.f_sub_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_mul_32 => {
            binary(f32, fiber, "mul", lastData.f_mul_32.R0, lastData.f_mul_32.R1, lastData.f_mul_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_mul_64 => {
            binary(f64, fiber, "mul", lastData.f_mul_64.R0, lastData.f_mul_64.R1, lastData.f_mul_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_div_32 => {
            binary(f32, fiber, "div", lastData.f_div_32.R0, lastData.f_div_32.R1, lastData.f_div_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_div_64 => {
            binary(f64, fiber, "div", lastData.f_div_64.R0, lastData.f_div_64.R1, lastData.f_div_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_rem_32 => {
            binary(f32, fiber, "rem", lastData.f_rem_32.R0, lastData.f_rem_32.R1, lastData.f_rem_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_rem_64 => {
            binary(f64, fiber, "rem", lastData.f_rem_64.R0, lastData.f_rem_64.R1, lastData.f_rem_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_neg_32 => {
            unary(f32, fiber, "neg", lastData.f_neg_32.R0, lastData.f_neg_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_neg_64 => {
            unary(f64, fiber, "neg", lastData.f_neg_64.R0, lastData.f_neg_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .f_eq_32 => {
            binary(f32, fiber, "eq", lastData.f_eq_32.R0, lastData.f_eq_32.R1, lastData.f_eq_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_eq_64 => {
            binary(f64, fiber, "eq", lastData.f_eq_64.R0, lastData.f_eq_64.R1, lastData.f_eq_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_ne_32 => {
            binary(f32, fiber, "ne", lastData.f_ne_32.R0, lastData.f_ne_32.R1, lastData.f_ne_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_ne_64 => {
            binary(f64, fiber, "ne", lastData.f_ne_64.R0, lastData.f_ne_64.R1, lastData.f_ne_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_lt_32 => {
            binary(f32, fiber, "lt", lastData.f_lt_32.R0, lastData.f_lt_32.R1, lastData.f_lt_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_lt_64 => {
            binary(f64, fiber, "lt", lastData.f_lt_64.R0, lastData.f_lt_64.R1, lastData.f_lt_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_gt_32 => {
            binary(f32, fiber, "gt", lastData.f_gt_32.R0, lastData.f_gt_32.R1, lastData.f_gt_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_gt_64 => {
            binary(f64, fiber, "gt", lastData.f_gt_64.R0, lastData.f_gt_64.R1, lastData.f_gt_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_le_32 => {
            binary(f32, fiber, "le", lastData.f_le_32.R0, lastData.f_le_32.R1, lastData.f_le_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_le_64 => {
            binary(f64, fiber, "le", lastData.f_le_64.R0, lastData.f_le_64.R1, lastData.f_le_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_ge_32 => {
            binary(f32, fiber, "ge", lastData.f_ge_32.R0, lastData.f_ge_32.R1, lastData.f_ge_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_ge_64 => {
            binary(f64, fiber, "ge", lastData.f_ge_64.R0, lastData.f_ge_64.R1, lastData.f_ge_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .i_add_8 => {
            binary(u8, fiber, "add", lastData.i_add_8.R0, lastData.i_add_8.R1, lastData.i_add_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_add_16 => {
            binary(u16, fiber, "add", lastData.i_add_16.R0, lastData.i_add_16.R1, lastData.i_add_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_add_32 => {
            binary(u32, fiber, "add", lastData.i_add_32.R0, lastData.i_add_32.R1, lastData.i_add_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_add_64 => {
            binary(u64, fiber, "add", lastData.i_add_64.R0, lastData.i_add_64.R1, lastData.i_add_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_sub_8 => {
            binary(u8, fiber, "sub", lastData.i_sub_8.R0, lastData.i_sub_8.R1, lastData.i_sub_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_sub_16 => {
            binary(u16, fiber, "sub", lastData.i_sub_16.R0, lastData.i_sub_16.R1, lastData.i_sub_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_sub_32 => {
            binary(u32, fiber, "sub", lastData.i_sub_32.R0, lastData.i_sub_32.R1, lastData.i_sub_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_sub_64 => {
            binary(u64, fiber, "sub", lastData.i_sub_64.R0, lastData.i_sub_64.R1, lastData.i_sub_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_mul_8 => {
            binary(u8, fiber, "mul", lastData.i_mul_8.R0, lastData.i_mul_8.R1, lastData.i_mul_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_mul_16 => {
            binary(u16, fiber, "mul", lastData.i_mul_16.R0, lastData.i_mul_16.R1, lastData.i_mul_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_mul_32 => {
            binary(u32, fiber, "mul", lastData.i_mul_32.R0, lastData.i_mul_32.R1, lastData.i_mul_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_mul_64 => {
            binary(u64, fiber, "mul", lastData.i_mul_64.R0, lastData.i_mul_64.R1, lastData.i_mul_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_div_8 => {
            binary(i8, fiber, "div", lastData.s_div_8.R0, lastData.s_div_8.R1, lastData.s_div_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_div_16 => {
            binary(i16, fiber, "div", lastData.s_div_16.R0, lastData.s_div_16.R1, lastData.s_div_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_div_32 => {
            binary(i32, fiber, "div", lastData.s_div_32.R0, lastData.s_div_32.R1, lastData.s_div_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_div_64 => {
            binary(i64, fiber, "div", lastData.s_div_64.R0, lastData.s_div_64.R1, lastData.s_div_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_div_8 => {
            binary(u8, fiber, "div", lastData.u_div_8.R0, lastData.u_div_8.R1, lastData.u_div_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_div_16 => {
            binary(u16, fiber, "div", lastData.u_div_16.R0, lastData.u_div_16.R1, lastData.u_div_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_div_32 => {
            binary(u32, fiber, "div", lastData.u_div_32.R0, lastData.u_div_32.R1, lastData.u_div_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_div_64 => {
            binary(u64, fiber, "div", lastData.u_div_64.R0, lastData.u_div_64.R1, lastData.u_div_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_rem_8 => {
            binary(i8, fiber, "rem", lastData.s_rem_8.R0, lastData.s_rem_8.R1, lastData.s_rem_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_rem_16 => {
            binary(i16, fiber, "rem", lastData.s_rem_16.R0, lastData.s_rem_16.R1, lastData.s_rem_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_rem_32 => {
            binary(i32, fiber, "rem", lastData.s_rem_32.R0, lastData.s_rem_32.R1, lastData.s_rem_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_rem_64 => {
            binary(i64, fiber, "rem", lastData.s_rem_64.R0, lastData.s_rem_64.R1, lastData.s_rem_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_rem_8 => {
            binary(u8, fiber, "rem", lastData.u_rem_8.R0, lastData.u_rem_8.R1, lastData.u_rem_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_rem_16 => {
            binary(u16, fiber, "rem", lastData.u_rem_16.R0, lastData.u_rem_16.R1, lastData.u_rem_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_rem_32 => {
            binary(u32, fiber, "rem", lastData.u_rem_32.R0, lastData.u_rem_32.R1, lastData.u_rem_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_rem_64 => {
            binary(u64, fiber, "rem", lastData.u_rem_64.R0, lastData.u_rem_64.R1, lastData.u_rem_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_neg_8 => {
            unary(i8, fiber, "neg", lastData.s_neg_8.R0, lastData.s_neg_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_neg_16 => {
            unary(i16, fiber, "neg", lastData.s_neg_16.R0, lastData.s_neg_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_neg_32 => {
            unary(i32, fiber, "neg", lastData.s_neg_32.R0, lastData.s_neg_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_neg_64 => {
            unary(i64, fiber, "neg", lastData.s_neg_64.R0, lastData.s_neg_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .bnot_8 => {
            unary(u8, fiber, "bitnot", lastData.bnot_8.R0, lastData.bnot_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bnot_16 => {
            unary(u16, fiber, "bitnot", lastData.bnot_16.R0, lastData.bnot_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bnot_32 => {
            unary(u32, fiber, "bitnot", lastData.bnot_32.R0, lastData.bnot_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bnot_64 => {
            unary(u64, fiber, "bitnot", lastData.bnot_64.R0, lastData.bnot_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .band_8 => {
            binary(u8, fiber, "bitand", lastData.band_8.R0, lastData.band_8.R1, lastData.band_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .band_16 => {
            binary(u16, fiber, "bitand", lastData.band_16.R0, lastData.band_16.R1, lastData.band_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .band_32 => {
            binary(u32, fiber, "bitand", lastData.band_32.R0, lastData.band_32.R1, lastData.band_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .band_64 => {
            binary(u64, fiber, "bitand", lastData.band_64.R0, lastData.band_64.R1, lastData.band_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bor_8 => {
            binary(u8, fiber, "bitor", lastData.bor_8.R0, lastData.bor_8.R1, lastData.bor_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bor_16 => {
            binary(u16, fiber, "bitor", lastData.bor_16.R0, lastData.bor_16.R1, lastData.bor_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bor_32 => {
            binary(u32, fiber, "bitor", lastData.bor_32.R0, lastData.bor_32.R1, lastData.bor_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bor_64 => {
            binary(u64, fiber, "bitor", lastData.bor_64.R0, lastData.bor_64.R1, lastData.bor_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bxor_8 => {
            binary(u8, fiber, "bitxor", lastData.bxor_8.R0, lastData.bxor_8.R1, lastData.bxor_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bxor_16 => {
            binary(u16, fiber, "bitxor", lastData.bxor_16.R0, lastData.bxor_16.R1, lastData.bxor_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bxor_32 => {
            binary(u32, fiber, "bitxor", lastData.bxor_32.R0, lastData.bxor_32.R1, lastData.bxor_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bxor_64 => {
            binary(u64, fiber, "bitxor", lastData.bxor_64.R0, lastData.bxor_64.R1, lastData.bxor_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bshiftl_8 => {
            binary(u8, fiber, "shiftl", lastData.bshiftl_8.R0, lastData.bshiftl_8.R1, lastData.bshiftl_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bshiftl_16 => {
            binary(u16, fiber, "shiftl", lastData.bshiftl_16.R0, lastData.bshiftl_16.R1, lastData.bshiftl_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bshiftl_32 => {
            binary(u32, fiber, "shiftl", lastData.bshiftl_32.R0, lastData.bshiftl_32.R1, lastData.bshiftl_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .bshiftl_64 => {
            binary(u64, fiber, "shiftl", lastData.bshiftl_64.R0, lastData.bshiftl_64.R1, lastData.bshiftl_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_bshiftr_8 => {
            binary(u8, fiber, "shiftr", lastData.u_bshiftr_8.R0, lastData.u_bshiftr_8.R1, lastData.u_bshiftr_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_bshiftr_16 => {
            binary(u16, fiber, "shiftr", lastData.u_bshiftr_16.R0, lastData.u_bshiftr_16.R1, lastData.u_bshiftr_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_bshiftr_32 => {
            binary(u32, fiber, "shiftr", lastData.u_bshiftr_32.R0, lastData.u_bshiftr_32.R1, lastData.u_bshiftr_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_bshiftr_64 => {
            binary(u64, fiber, "shiftr", lastData.u_bshiftr_64.R0, lastData.u_bshiftr_64.R1, lastData.u_bshiftr_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_bshiftr_8 => {
            binary(i8, fiber, "shiftr", lastData.s_bshiftr_8.R0, lastData.s_bshiftr_8.R1, lastData.s_bshiftr_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_bshiftr_16 => {
            binary(i16, fiber, "shiftr", lastData.s_bshiftr_16.R0, lastData.s_bshiftr_16.R1, lastData.s_bshiftr_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_bshiftr_32 => {
            binary(i32, fiber, "shiftr", lastData.s_bshiftr_32.R0, lastData.s_bshiftr_32.R1, lastData.s_bshiftr_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_bshiftr_64 => {
            binary(i64, fiber, "shiftr", lastData.s_bshiftr_64.R0, lastData.s_bshiftr_64.R1, lastData.s_bshiftr_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .i_eq_8 => {
            binary(u8, fiber, "eq", lastData.i_eq_8.R0, lastData.i_eq_8.R1, lastData.i_eq_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_eq_16 => {
            binary(u16, fiber, "eq", lastData.i_eq_16.R0, lastData.i_eq_16.R1, lastData.i_eq_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_eq_32 => {
            binary(u32, fiber, "eq", lastData.i_eq_32.R0, lastData.i_eq_32.R1, lastData.i_eq_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_eq_64 => {
            binary(u64, fiber, "eq", lastData.i_eq_64.R0, lastData.i_eq_64.R1, lastData.i_eq_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_ne_8 => {
            binary(u8, fiber, "ne", lastData.i_ne_8.R0, lastData.i_ne_8.R1, lastData.i_ne_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_ne_16 => {
            binary(u16, fiber, "ne", lastData.i_ne_16.R0, lastData.i_ne_16.R1, lastData.i_ne_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_ne_32 => {
            binary(u32, fiber, "ne", lastData.i_ne_32.R0, lastData.i_ne_32.R1, lastData.i_ne_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_ne_64 => {
            binary(u64, fiber, "ne", lastData.i_ne_64.R0, lastData.i_ne_64.R1, lastData.i_ne_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_lt_8 => {
            binary(u8, fiber, "lt", lastData.u_lt_8.R0, lastData.u_lt_8.R1, lastData.u_lt_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_lt_16 => {
            binary(u16, fiber, "lt", lastData.u_lt_16.R0, lastData.u_lt_16.R1, lastData.u_lt_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_lt_32 => {
            binary(u32, fiber, "lt", lastData.u_lt_32.R0, lastData.u_lt_32.R1, lastData.u_lt_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_lt_64 => {
            binary(u64, fiber, "lt", lastData.u_lt_64.R0, lastData.u_lt_64.R1, lastData.u_lt_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_lt_8 => {
            binary(i8, fiber, "lt", lastData.s_lt_8.R0, lastData.s_lt_8.R1, lastData.s_lt_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_lt_16 => {
            binary(i16, fiber, "lt", lastData.s_lt_16.R0, lastData.s_lt_16.R1, lastData.s_lt_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_lt_32 => {
            binary(i32, fiber, "lt", lastData.s_lt_32.R0, lastData.s_lt_32.R1, lastData.s_lt_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_lt_64 => {
            binary(i64, fiber, "lt", lastData.s_lt_64.R0, lastData.s_lt_64.R1, lastData.s_lt_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_gt_8 => {
            binary(u8, fiber, "gt", lastData.u_gt_8.R0, lastData.u_gt_8.R1, lastData.u_gt_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_gt_16 => {
            binary(u16, fiber, "gt", lastData.u_gt_16.R0, lastData.u_gt_16.R1, lastData.u_gt_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_gt_32 => {
            binary(u32, fiber, "gt", lastData.u_gt_32.R0, lastData.u_gt_32.R1, lastData.u_gt_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_gt_64 => {
            binary(u64, fiber, "gt", lastData.u_gt_64.R0, lastData.u_gt_64.R1, lastData.u_gt_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_gt_8 => {
            binary(i8, fiber, "gt", lastData.s_gt_8.R0, lastData.s_gt_8.R1, lastData.s_gt_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_gt_16 => {
            binary(i16, fiber, "gt", lastData.s_gt_16.R0, lastData.s_gt_16.R1, lastData.s_gt_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_gt_32 => {
            binary(i32, fiber, "gt", lastData.s_gt_32.R0, lastData.s_gt_32.R1, lastData.s_gt_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_gt_64 => {
            binary(i64, fiber, "gt", lastData.s_gt_64.R0, lastData.s_gt_64.R1, lastData.s_gt_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_le_8 => {
            binary(u8, fiber, "le", lastData.u_le_8.R0, lastData.u_le_8.R1, lastData.u_le_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_le_16 => {
            binary(u16, fiber, "le", lastData.u_le_16.R0, lastData.u_le_16.R1, lastData.u_le_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_le_32 => {
            binary(u32, fiber, "le", lastData.u_le_32.R0, lastData.u_le_32.R1, lastData.u_le_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_le_64 => {
            binary(u64, fiber, "le", lastData.u_le_64.R0, lastData.u_le_64.R1, lastData.u_le_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_le_8 => {
            binary(i8, fiber, "le", lastData.s_le_8.R0, lastData.s_le_8.R1, lastData.s_le_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_le_16 => {
            binary(i16, fiber, "le", lastData.s_le_16.R0, lastData.s_le_16.R1, lastData.s_le_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_le_32 => {
            binary(i32, fiber, "le", lastData.s_le_32.R0, lastData.s_le_32.R1, lastData.s_le_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_le_64 => {
            binary(i64, fiber, "le", lastData.s_le_64.R0, lastData.s_le_64.R1, lastData.s_le_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ge_8 => {
            binary(u8, fiber, "ge", lastData.u_ge_8.R0, lastData.u_ge_8.R1, lastData.u_ge_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ge_16 => {
            binary(u16, fiber, "ge", lastData.u_ge_16.R0, lastData.u_ge_16.R1, lastData.u_ge_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ge_32 => {
            binary(u32, fiber, "ge", lastData.u_ge_32.R0, lastData.u_ge_32.R1, lastData.u_ge_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ge_64 => {
            binary(u64, fiber, "ge", lastData.u_ge_64.R0, lastData.u_ge_64.R1, lastData.u_ge_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ge_8 => {
            binary(i8, fiber, "ge", lastData.s_ge_8.R0, lastData.s_ge_8.R1, lastData.s_ge_8.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ge_16 => {
            binary(i16, fiber, "ge", lastData.s_ge_16.R0, lastData.s_ge_16.R1, lastData.s_ge_16.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ge_32 => {
            binary(i32, fiber, "ge", lastData.s_ge_32.R0, lastData.s_ge_32.R1, lastData.s_ge_32.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ge_64 => {
            binary(i64, fiber, "ge", lastData.s_ge_64.R0, lastData.s_ge_64.R1, lastData.s_ge_64.R2);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .u_ext_8_16 => {
            cast(u8, u16, fiber, lastData.u_ext_8_16.R0, lastData.u_ext_8_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ext_8_32 => {
            cast(u8, u32, fiber, lastData.u_ext_8_32.R0, lastData.u_ext_8_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ext_8_64 => {
            cast(u8, u64, fiber, lastData.u_ext_8_64.R0, lastData.u_ext_8_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ext_16_32 => {
            cast(u16, u32, fiber, lastData.u_ext_16_32.R0, lastData.u_ext_16_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ext_16_64 => {
            cast(u16, u64, fiber, lastData.u_ext_16_64.R0, lastData.u_ext_16_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u_ext_32_64 => {
            cast(u32, u64, fiber, lastData.u_ext_32_64.R0, lastData.u_ext_32_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ext_8_16 => {
            cast(i8, i16, fiber, lastData.s_ext_8_16.R0, lastData.s_ext_8_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ext_8_32 => {
            cast(i8, i32, fiber, lastData.s_ext_8_32.R0, lastData.s_ext_8_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ext_8_64 => {
            cast(i8, i64, fiber, lastData.s_ext_8_64.R0, lastData.s_ext_8_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ext_16_32 => {
            cast(i16, i32, fiber, lastData.s_ext_16_32.R0, lastData.s_ext_16_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ext_16_64 => {
            cast(i16, i64, fiber, lastData.s_ext_16_64.R0, lastData.s_ext_16_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s_ext_32_64 => {
            cast(i32, i64, fiber, lastData.s_ext_32_64.R0, lastData.s_ext_32_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_ext_32_64 => {
            cast(f32, i64, fiber, lastData.f_ext_32_64.R0, lastData.f_ext_32_64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .i_trunc_64_32 => {
            cast(u64, u32, fiber, lastData.i_trunc_64_32.R0, lastData.i_trunc_64_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_trunc_64_16 => {
            cast(u64, u16, fiber, lastData.i_trunc_64_16.R0, lastData.i_trunc_64_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_trunc_64_8 => {
            cast(u64, u8, fiber, lastData.i_trunc_64_8.R0, lastData.i_trunc_64_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_trunc_32_16 => {
            cast(u32, u16, fiber, lastData.i_trunc_32_16.R0, lastData.i_trunc_32_16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_trunc_32_8 => {
            cast(u32, u8, fiber, lastData.i_trunc_32_8.R0, lastData.i_trunc_32_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .i_trunc_16_8 => {
            cast(u16, u8, fiber, lastData.i_trunc_16_8.R0, lastData.i_trunc_16_8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f_trunc_64_32 => {
            cast(f64, f32, fiber, lastData.f_trunc_64_32.R0, lastData.f_trunc_64_32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        .u8_to_f32 => {
            cast(u8, f32, fiber, lastData.u8_to_f32.R0, lastData.u8_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u8_to_f64 => {
            cast(u8, f64, fiber, lastData.u8_to_f64.R0, lastData.u8_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u16_to_f32 => {
            cast(u16, f32, fiber, lastData.u16_to_f32.R0, lastData.u16_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u16_to_f64 => {
            cast(u16, f64, fiber, lastData.u16_to_f64.R0, lastData.u16_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u32_to_f32 => {
            cast(u32, f32, fiber, lastData.u32_to_f32.R0, lastData.u32_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u32_to_f64 => {
            cast(u32, f64, fiber, lastData.u32_to_f64.R0, lastData.u32_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u64_to_f32 => {
            cast(u64, f32, fiber, lastData.u64_to_f32.R0, lastData.u64_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .u64_to_f64 => {
            cast(u64, f64, fiber, lastData.u64_to_f64.R0, lastData.u64_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s8_to_f32 => {
            cast(i8, f32, fiber, lastData.s8_to_f32.R0, lastData.s8_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s8_to_f64 => {
            cast(i8, f64, fiber, lastData.s8_to_f64.R0, lastData.s8_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s16_to_f32 => {
            cast(i16, f32, fiber, lastData.s16_to_f32.R0, lastData.s16_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s16_to_f64 => {
            cast(i16, f64, fiber, lastData.s16_to_f64.R0, lastData.s16_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s32_to_f32 => {
            cast(i32, f32, fiber, lastData.s32_to_f32.R0, lastData.s32_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s32_to_f64 => {
            cast(i32, f64, fiber, lastData.s32_to_f64.R0, lastData.s32_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s64_to_f32 => {
            cast(i64, f32, fiber, lastData.s64_to_f32.R0, lastData.s64_to_f32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .s64_to_f64 => {
            cast(i64, f64, fiber, lastData.s64_to_f64.R0, lastData.s64_to_f64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_u8 => {
            cast(f32, u8, fiber, lastData.f32_to_u8.R0, lastData.f32_to_u8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_u16 => {
            cast(f32, u16, fiber, lastData.f32_to_u16.R0, lastData.f32_to_u16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_u32 => {
            cast(f32, u32, fiber, lastData.f32_to_u32.R0, lastData.f32_to_u32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_u64 => {
            cast(f32, u64, fiber, lastData.f32_to_u64.R0, lastData.f32_to_u64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_u8 => {
            cast(f64, u8, fiber, lastData.f64_to_u8.R0, lastData.f64_to_u8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_u16 => {
            cast(f64, u16, fiber, lastData.f64_to_u16.R0, lastData.f64_to_u16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_u32 => {
            cast(f64, u32, fiber, lastData.f64_to_u32.R0, lastData.f64_to_u32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_u64 => {
            cast(f64, u64, fiber, lastData.f64_to_u64.R0, lastData.f64_to_u64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_s8 => {
            cast(f32, i8, fiber, lastData.f32_to_s8.R0, lastData.f32_to_s8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_s16 => {
            cast(f32, i16, fiber, lastData.f32_to_s16.R0, lastData.f32_to_s16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_s32 => {
            cast(f32, i32, fiber, lastData.f32_to_s32.R0, lastData.f32_to_s32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f32_to_s64 => {
            cast(f32, i64, fiber, lastData.f32_to_s64.R0, lastData.f32_to_s64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_s8 => {
            cast(f64, i8, fiber, lastData.f64_to_s8.R0, lastData.f64_to_s8.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_s16 => {
            cast(f64, i16, fiber, lastData.f64_to_s16.R0, lastData.f64_to_s16.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_s32 => {
            cast(f64, i32, fiber, lastData.f64_to_s32.R0, lastData.f64_to_s32.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },
        .f64_to_s64 => {
            cast(f64, i64, fiber, lastData.f64_to_s64.R0, lastData.f64_to_s64.R1);

            if (comptime reswitch) continue :reswitch decodeInstr(fiber, &lastData);
        },

        inline else => Support.todo(noreturn, {}),
    }

    if (comptime !reswitch) return true;
}

fn stepForeign(fiber: *Fiber) Fiber.Trap!void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const foreign = fiber.getForeign(currentCallFrame.function.value.foreign);

    const currentBlockFrame = fiber.blocks.getPtrUnchecked(currentCallFrame.root_block);

    var foreignOut: Fiber.ForeignOut = undefined;
    const control = foreign(fiber, currentBlockFrame.index, &foreignOut);

    switch (control) {
        .trap => return Fiber.convertForeignError(foreignOut.trap),
        .step => currentBlockFrame.index = foreignOut.step,
        .done => {
            fiber.stack.data.ptr = currentCallFrame.stack.base;
            fiber.stack.call.ptr -= 1;
            fiber.blocks.ptr = currentCallFrame.root_block;
        },
        .done_v => {
            const rootBlockFrame = fiber.blocks.getPtrUnchecked(currentCallFrame.root_block);

            const out = fiber.readLocal(u64, foreignOut.done_v);

            fiber.writeReg(fiber.stack.call.ptr -| 2, rootBlockFrame.out, out);

            fiber.stack.data.ptr = currentCallFrame.stack.base;
            fiber.stack.call.ptr -= 1;
            fiber.blocks.ptr = currentCallFrame.root_block;
        },
    }
}

fn addr_local(fiber: *Fiber, x: Bytecode.RegisterIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const local = fiber.addrLocal(x);
    fiber.writeLocal(y, local);
}

pub fn addr_global(fiber: *Fiber, g: Bytecode.GlobalIndex, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const global = fiber.addrGlobal(g);
    fiber.writeLocal(x, global);
}

pub fn addr_upvalue(fiber: *Fiber, u: Bytecode.UpvalueIndex, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const upvalue = fiber.addrUpvalue(u);
    fiber.writeLocal(x, upvalue);
}

pub fn read_global(comptime T: type, fiber: *Fiber, g: Bytecode.GlobalIndex, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const global = fiber.readGlobal(T, g);
    fiber.writeLocal(x, global);
}

pub fn write_global(comptime T: type, fiber: *Fiber, g: Bytecode.GlobalIndex, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const local = fiber.readLocal(T, x);
    fiber.writeGlobal(g, local);
}

pub fn read_upvalue(comptime T: type, fiber: *Fiber, u: Bytecode.UpvalueIndex, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const upvalue = fiber.readUpvalue(T, u);
    fiber.writeLocal(x, upvalue);
}

pub fn write_upvalue(comptime T: type, fiber: *Fiber, u: Bytecode.UpvalueIndex, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const local = fiber.readLocal(T, x);
    fiber.writeUpvalue(u, local);
}

pub fn load(comptime T: type, fiber: *Fiber, x: Bytecode.RegisterIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const out = fiber.readLocal(*T, y);
    const in = fiber.readLocal(T, x);
    try fiber.boundsCheck(out, @sizeOf(T));
    out.* = in;
}

pub fn store(comptime T: type, fiber: *Fiber, x: Bytecode.RegisterIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const in = fiber.readLocal(*T, x);
    try fiber.boundsCheck(in, @sizeOf(T));
    fiber.writeLocal(y, in.*);
}

pub fn clear(comptime T: type, fiber: *Fiber, x: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    fiber.writeLocal(x, @as(T, 0));
}

pub fn swap(comptime T: type, fiber: *Fiber, x: Bytecode.RegisterIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const temp = fiber.readLocal(T, x);
    const yVal = fiber.readLocal(T, y);
    fiber.writeLocal(x, yVal);
    fiber.writeLocal(y, temp);
}

pub fn copy(comptime T: type, fiber: *Fiber, x: Bytecode.RegisterIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const xVal = fiber.readLocal(T, x);
    fiber.writeLocal(y, xVal);
}


fn when(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, x: Bytecode.RegisterIndex, comptime zeroCheck: ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const cond = fiber.readLocal(u8, x);

    const newBlock = fiber.calls.top().function.value.bytecode.blocks[newBlockIndex];

    const newBlockFrame = Fiber.BlockFrame {
        .base = newBlock,
        .ip = newBlock,
        .out = undefined,
        .handler_set = null,
    };

    switch (zeroCheck) {
        .zero => if (cond == 0) fiber.blocks.push(newBlockFrame),
        .non_zero => if (cond != 0) fiber.blocks.push(newBlockFrame),
    }
}

fn br(fiber: *Fiber, terminatedBlockOffset: Bytecode.BlockIndex, x: Bytecode.RegisterIndex, comptime zeroCheck: ?ZeroCheck, y: Bytecode.RegisterIndex, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const terminatedBlockPtr: [*]Fiber.BlockFrame = fiber.blocks.top_ptr - terminatedBlockOffset;

    if (zeroCheck) |zc| {
        const cond = fiber.readLocal(u8, x);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    if (style == .v) {
        const out = fiber.readLocal(u64, y);
        fiber.writeLocal(terminatedBlockPtr[0].out, out);
    }

    fiber.removeAnyHandlerSet(@ptrCast(terminatedBlockPtr));

    fiber.blocks.top_ptr = terminatedBlockPtr;
}

fn re(fiber: *Fiber, restartedBlockOffset: Bytecode.BlockIndex, x: Bytecode.RegisterIndex, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const restartedBlockPtr: [*]Fiber.BlockFrame = fiber.blocks.top_ptr - restartedBlockOffset;

    if (zeroCheck) |zc| {
        const cond = fiber.readLocal(u8, x);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    restartedBlockPtr[0].ip = restartedBlockPtr[0].base;
    fiber.blocks.top_ptr = restartedBlockPtr;
}

fn block(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const newBlock = fiber.calls.top().function.value.bytecode.blocks[newBlockIndex];

    const newBlockFrame = Fiber.BlockFrame {
        .base = newBlock,
        .ip = newBlock,
        .out = y,
        .handler_set = null,
    };

    fiber.blocks.push(newBlockFrame);
}

fn with(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, handlerSetIndex: Bytecode.HandlerSetIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const handlerSet = &fiber.program.handler_sets[handlerSetIndex];

    const newBlock = fiber.calls.top().function.value.bytecode.blocks[newBlockIndex];

    const newBlockFrame = Fiber.BlockFrame {
        .base = newBlock,
        .ip = newBlock,
        .out = y,
        .handler_set = handlerSet,
    };

    fiber.blocks.push(newBlockFrame);

    for (handlerSet.*) |binding| {
        fiber.evidence[binding.id].push(Fiber.Evidence {
            .handler = &fiber.program.functions[binding.handler],
            .call = fiber.calls.top(),
            .block = fiber.blocks.top(),
        });
    }
}

fn @"if"(fiber: *Fiber, thenBlockIndex: Bytecode.BlockIndex, elseBlockIndex: Bytecode.BlockIndex, x: Bytecode.RegisterIndex, comptime zeroCheck: ZeroCheck, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const cond = fiber.readLocal(u8, x);

    const newBlockIndex = switch (zeroCheck) {
        .zero => if (cond == 0) thenBlockIndex else elseBlockIndex,
        .non_zero => if (cond != 0) thenBlockIndex else elseBlockIndex,
    };

    const newBlock = fiber.calls.top().function.value.bytecode.blocks[newBlockIndex];

    const newBlockFrame = Fiber.BlockFrame {
        .base = newBlock,
        .ip = newBlock,
        .out = y,
        .handler_set = null,
    };

    fiber.blocks.push(newBlockFrame);
}



fn callImpl_no_tail(fiber: *Fiber, funcIndex: Bytecode.FunctionIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    if (( fiber.data.hasSpaceU1(newFunction.num_registers)
        & fiber.calls.hasSpaceU1(1)
        ) != 1) {
        @branchHint(.cold);
        if (!fiber.data.hasSpace(newFunction.num_registers)) {
            std.debug.print("stack overflow @{}\n", .{Fiber.DATA_STACK_SIZE});
        }
        if (!fiber.calls.hasSpace(1)) {
            std.debug.print("call overflow @{}\n", .{Fiber.CALL_STACK_SIZE});
        }
        return Fiber.Trap.Overflow;
    }

    const arguments = decodeArguments(fiber, newFunction.num_arguments);

    const data = fiber.data.incrGetMulti(newFunction.num_registers);

    const newBlock = newFunction.value.bytecode.blocks[0];

    const newBlockFrame = fiber.blocks.pushGet(Fiber.BlockFrame {
        .base = newBlock,
        .ip = newBlock,
        .out = y,
        .handler_set = null,
    });

    const oldCallFrame = fiber.calls.top();

    fiber.calls.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = undefined,
        .block = newBlockFrame,
        .data = data,
    });

    for (0..newFunction.num_arguments) |i| {
        const value = Fiber.readReg(u64, oldCallFrame, arguments[i]);
        Fiber.writeReg(fiber.calls.top(), @truncate(i), value);
    }
}

fn callImpl_tail(fiber: *Fiber, funcIndex: Bytecode.FunctionIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, funcIndex});
}

fn callImpl_tail_v(fiber: *Fiber, funcIndex: Bytecode.FunctionIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, funcIndex});
}

fn callImpl_ev_no_tail(fiber: *Fiber, evIndex: Bytecode.EvidenceIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, evIndex});
}

fn callImpl_ev_no_tail_v(fiber: *Fiber, evIndex: Bytecode.EvidenceIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, evIndex, y});
}

fn callImpl_ev_tail(fiber: *Fiber, evIndex: Bytecode.EvidenceIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, evIndex});
}

fn callImpl_ev_tail_v(fiber: *Fiber, evIndex: Bytecode.EvidenceIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    Support.todo(noreturn, .{fiber, evIndex});
}


fn term(fiber: *Fiber, y: Bytecode.RegisterIndex, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    Support.todo(noreturn, .{fiber, y, style});
}

fn ret(fiber: *Fiber, y: Bytecode.RegisterIndex, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.calls.top();

    const rootBlockFrame = currentCallFrame.block;

    if (style == .v) {
        const out = fiber.readLocal(u64, y);
        Fiber.writeReg(@ptrCast(fiber.calls.top_ptr - 1), rootBlockFrame.out, out);
    }

    fiber.data.top_ptr = currentCallFrame.data;
    fiber.calls.pop();
    fiber.blocks.top_ptr = @as([*]Fiber.BlockFrame, @ptrCast(rootBlockFrame)) - 1;
}

pub fn cast(comptime X: type, comptime Y: type, fiber: *Fiber, xOp: Bytecode.RegisterIndex, yOp: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const x = fiber.readLocal(X, xOp);

    const xKind = @as(std.builtin.TypeId, @typeInfo(X));
    const yKind = @as(std.builtin.TypeId, @typeInfo(Y));

    const y =
        if (comptime xKind == yKind) (
            if (comptime xKind == .int) ops.intCast(Y, x)
            else ops.floatCast(Y, x)
        ) else ops.typeCast(Y, x);

    fiber.writeLocal(yOp, y);
}

pub fn unary(comptime T: type, fiber: *Fiber, comptime op: []const u8, xOp: Bytecode.RegisterIndex, yOp: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const x = fiber.readLocal(T, xOp);

    const y = @field(ops, op)(x);

    fiber.writeLocal(yOp, y);
}

pub fn binary(comptime T: type, fiber: *Fiber, comptime op: []const u8, xOp: Bytecode.RegisterIndex, yOp: Bytecode.RegisterIndex, zOp: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) void {
    const x = fiber.readLocal(T, xOp);
    const y = fiber.readLocal(T, yOp);

    const z = @field(ops, op)(x, y);

    fiber.writeLocal(zOp, z);
}

const ops = struct {
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

    inline fn neg(a: anytype) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return -% a,
            else => return -a,
        }
    }

    inline fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return a +% b,
            else => return a + b,
        }
    }

    inline fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return a -% b,
            else => return a - b,
        }
    }

    inline fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return a *% b,
            else => return a * b,
        }
    }

    inline fn div(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(a))) {
            .int => return @divTrunc(a, b),
            else => return a / b,
        }
    }

    inline fn rem(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return @rem(a, b);
    }

    inline fn bitnot(a: anytype) @TypeOf(a) {
        return ~a;
    }

    inline fn not(a: anytype) @TypeOf(a) {
        return !a;
    }

    inline fn bitand(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a & b;
    }

    inline fn @"and"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a and b;
    }

    inline fn bitor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a | b;
    }

    inline fn @"or"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a or b;
    }

    inline fn bitxor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a ^ b;
    }

    inline fn shiftl(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        const bits = @bitSizeOf(T);
        const S = std.meta.Int(.unsigned, std.math.log2(bits));
        const U = std.meta.Int(.unsigned, bits);
        const bu: U = @bitCast(b);
        const bs: U = @rem(std.math.maxInt(S), bu);
        return a << @truncate(bs);
    }

    inline fn shiftr(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        const bits = @bitSizeOf(T);
        const S = std.meta.Int(.unsigned, std.math.log2(bits));
        const U = std.meta.Int(.unsigned, bits);
        const bu: U = @bitCast(b);
        const bs: U = @rem(std.math.maxInt(S), bu);
        return a >> @truncate(bs);
    }

    inline fn eq(a: anytype, b: @TypeOf(a)) bool {
        return a == b;
    }

    inline fn ne(a: anytype, b: @TypeOf(a)) bool {
        return a != b;
    }

    inline fn lt(a: anytype, b: @TypeOf(a)) bool {
        return a < b;
    }

    inline fn gt(a: anytype, b: @TypeOf(a)) bool {
        return a > b;
    }

    inline fn le(a: anytype, b: @TypeOf(a)) bool {
        return a <= b;
    }

    inline fn ge(a: anytype, b: @TypeOf(a)) bool {
        return a >= b;
    }
};
