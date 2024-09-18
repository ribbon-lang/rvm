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

pub fn stepCall(fiber: *Fiber) Fiber.Trap!void {
    const start = fiber.stack.call.ptr;

    if (start == 0) {
        @branchHint(.unlikely);
        return;
    }

    while (fiber.stack.call.ptr >= start) {
        _ = try @call(Config.INLINING_CALL_MOD, step, .{fiber});
    }
}

pub fn step(fiber: *Fiber) Fiber.Trap!bool {
    return stepBytecode(false, fiber);
}

inline fn updateDecoder(fiber: *Fiber, decoder: *IO.Decoder) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const currentBlockFrame = fiber.stack.block.topPtrUnchecked();
    const currentBlock = &currentCallFrame.function.value.bytecode.blocks[currentBlockFrame.index];

    decoder.memory = currentCallFrame.function.value.bytecode.instructions;
    decoder.base = currentBlock.base;
    decoder.offset = &currentBlockFrame.ip_offset;
}

inline fn decodeOpCode(decoder: *const IO.Decoder) Bytecode.OpCode {
    return decoder.decodeUnchecked(Bytecode.OpCode);
}

// TODO: reimplement foreign calls as an instruction
inline fn stepBytecode(comptime reswitch: bool, fiber: *Fiber) Fiber.Trap!if (reswitch) void else bool {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA);

    var decoder: IO.Decoder = undefined;

    updateDecoder(fiber, &decoder);

    reswitch: switch (decodeOpCode(&decoder)) {
        .trap => return Fiber.Trap.Unreachable,
        .nop => {
            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .halt => if (comptime !reswitch) return false,

        .tail_call => {
            try call(fiber, &decoder, decoder.decodeUnchecked(Bytecode.FunctionIndex), decoder.decodeUnchecked(u8), .tail);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .tail_call_v => {
            try call(fiber, &decoder, decoder.decodeUnchecked(Bytecode.FunctionIndex), decoder.decodeUnchecked(u8), .tail_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_tail_call => {
            try dynCall(fiber, &decoder, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(u8), .tail);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_tail_call_v => {
            try dynCall(fiber, &decoder, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(u8), .tail_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .tail_prompt => {
            try prompt(fiber, &decoder, decoder.decodeUnchecked(Bytecode.EvidenceIndex), decoder.decodeUnchecked(u8), .tail);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .tail_prompt_v => {
            try prompt(fiber, &decoder, decoder.decodeUnchecked(Bytecode.EvidenceIndex), decoder.decodeUnchecked(u8), .tail_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .call => {
            try call(fiber, &decoder, decoder.decodeUnchecked(Bytecode.FunctionIndex), decoder.decodeUnchecked(u8), .no_tail);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .call_v => {
            try call(fiber, &decoder, decoder.decodeUnchecked(Bytecode.FunctionIndex), decoder.decodeUnchecked(u8), .no_tail_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_call => {
            try dynCall(fiber, &decoder, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(u8), .no_tail);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_call_v => {
            try dynCall(fiber, &decoder, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(u8), .no_tail_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .prompt => {
            try prompt(fiber, &decoder, decoder.decodeUnchecked(Bytecode.EvidenceIndex), decoder.decodeUnchecked(u8), .no_tail);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .prompt_v => {
            try prompt(fiber, &decoder, decoder.decodeUnchecked(Bytecode.EvidenceIndex), decoder.decodeUnchecked(u8), .no_tail_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .ret => {
            ret(fiber, &decoder, .no_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .ret_v => {
            ret(fiber, &decoder, .v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .term => {
            term(fiber, &decoder, .no_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .term_v => {
            term(fiber, &decoder, .v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .when_z => {
            when(fiber, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.Operand), .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .when_nz => {
            when(fiber, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.Operand), .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .re => {
            re(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), null);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .re_z => {
            re(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .re_nz => {
            re(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .br => {
            br(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .no_v, null);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_z => {
            br(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .no_v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_nz => {
            br(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .no_v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .br_v => {
            br(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .v, null);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_z_v => {
            br(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_nz_v => {
            br(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .block => {
            block(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .no_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .block_v => {
            block(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), .v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .with => {
            try with(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.HandlerSetIndex), .no_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .with_v => {
            try with(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.HandlerSetIndex), .v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .if_z => {
            @"if"(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.Operand), .no_v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .if_nz => {
            @"if"(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.Operand), .no_v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .if_z_v => {
            @"if"(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.Operand), .v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .if_nz_v => {
            @"if"(fiber, &decoder, decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.BlockIndex), decoder.decodeUnchecked(Bytecode.Operand), .v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .addr => {
            addr(fiber, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .load8 => {
            try fiber.load(u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .load16 => {
            try fiber.load(u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .load32 => {
            try fiber.load(u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .load64 => {
            try fiber.load(u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .store8 => {
            try fiber.store(u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .store16 => {
            try fiber.store(u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .store32 => {
            try fiber.store(u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .store64 => {
            try fiber.store(u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .clear8 => {
            fiber.clear(u8, decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .clear16 => {
            fiber.clear(u16, decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .clear32 => {
            fiber.clear(u32, decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .clear64 => {
            fiber.clear(u64, decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .swap8 => {
            fiber.swap(u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .swap16 => {
            fiber.swap(u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .swap32 => {
            fiber.swap(u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .swap64 => {
            fiber.swap(u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .copy8 => {
            fiber.copy(u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .copy16 => {
            fiber.copy(u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .copy32 => {
            fiber.copy(u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .copy64 => {
            fiber.copy(u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .b_not => {
            fiber.unary(bool, "not", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .b_and => {
            fiber.binary(bool, "and", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .b_or => {
            fiber.binary(bool, "or", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .f_add32 => {
            fiber.binary(f32, "add", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_add64 => {
            fiber.binary(f64, "add", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_sub32 => {
            fiber.binary(f32, "sub", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_sub64 => {
            fiber.binary(f64, "sub", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_mul32 => {
            fiber.binary(f32, "mul", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_mul64 => {
            fiber.binary(f64, "mul", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_div32 => {
            fiber.binary(f32, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_div64 => {
            fiber.binary(f64, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_rem32 => {
            fiber.binary(f32, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_rem64 => {
            fiber.binary(f64, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_neg32 => {
            fiber.unary(f32, "neg", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_neg64 => {
            fiber.unary(f64, "neg", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .f_eq32 => {
            fiber.binary(f32, "eq", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_eq64 => {
            fiber.binary(f64, "eq", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ne32 => {
            fiber.binary(f32, "ne", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ne64 => {
            fiber.binary(f64, "ne", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_lt32 => {
            fiber.binary(f32, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_lt64 => {
            fiber.binary(f64, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_gt32 => {
            fiber.binary(f32, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_gt64 => {
            fiber.binary(f64, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_le32 => {
            fiber.binary(f32, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_le64 => {
            fiber.binary(f64, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ge32 => {
            fiber.binary(f32, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ge64 => {
            fiber.binary(f64, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_add8 => {
            fiber.binary(u8, "add", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_add16 => {
            fiber.binary(u16, "add", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_add32 => {
            fiber.binary(u32, "add", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_add64 => {
            fiber.binary(u64, "add", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub8 => {
            fiber.binary(u8, "sub", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub16 => {
            fiber.binary(u16, "sub", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub32 => {
            fiber.binary(u32, "sub", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub64 => {
            fiber.binary(u64, "sub", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul8 => {
            fiber.binary(u8, "mul", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul16 => {
            fiber.binary(u16, "mul", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul32 => {
            fiber.binary(u32, "mul", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul64 => {
            fiber.binary(u64, "mul", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div8 => {
            fiber.binary(i8, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div16 => {
            fiber.binary(i16, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div32 => {
            fiber.binary(i32, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div64 => {
            fiber.binary(i64, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div8 => {
            fiber.binary(u8, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div16 => {
            fiber.binary(u16, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div32 => {
            fiber.binary(u32, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div64 => {
            fiber.binary(u64, "div", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem8 => {
            fiber.binary(i8, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem16 => {
            fiber.binary(i16, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem32 => {
            fiber.binary(i32, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem64 => {
            fiber.binary(i64, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem8 => {
            fiber.binary(u8, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem16 => {
            fiber.binary(u16, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem32 => {
            fiber.binary(u32, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem64 => {
            fiber.binary(u64, "rem", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg8 => {
            fiber.unary(i8, "neg", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg16 => {
            fiber.unary(i16, "neg", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg32 => {
            fiber.unary(i32, "neg", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg64 => {
            fiber.unary(i64, "neg", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_bitnot8 => {
            fiber.unary(u8, "bitnot", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitnot16 => {
            fiber.unary(u16, "bitnot", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitnot32 => {
            fiber.unary(u32, "bitnot", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitnot64 => {
            fiber.unary(u64, "bitnot", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand8 => {
            fiber.binary(u8, "bitand", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand16 => {
            fiber.binary(u16, "bitand", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand32 => {
            fiber.binary(u32, "bitand", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand64 => {
            fiber.binary(u64, "bitand", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor8 => {
            fiber.binary(u8, "bitor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor16 => {
            fiber.binary(u16, "bitor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor32 => {
            fiber.binary(u32, "bitor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor64 => {
            fiber.binary(u64, "bitor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor8 => {
            fiber.binary(u8, "bitxor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor16 => {
            fiber.binary(u16, "bitxor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor32 => {
            fiber.binary(u32, "bitxor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor64 => {
            fiber.binary(u64, "bitxor", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl8 => {
            fiber.binary(u8, "shiftl", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl16 => {
            fiber.binary(u16, "shiftl", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl32 => {
            fiber.binary(u32, "shiftl", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl64 => {
            fiber.binary(u64, "shiftl", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr8 => {
            fiber.binary(u8, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr16 => {
            fiber.binary(u16, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr32 => {
            fiber.binary(u32, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr64 => {
            fiber.binary(u64, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr8 => {
            fiber.binary(i8, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr16 => {
            fiber.binary(i16, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr32 => {
            fiber.binary(i32, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr64 => {
            fiber.binary(i64, "shiftr", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_eq8 => {
            fiber.binary(u8, "eq", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_eq16 => {
            fiber.binary(u16, "eq", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_eq32 => {
            fiber.binary(u32, "eq", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_eq64 => {
            fiber.binary(u64, "eq", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne8 => {
            fiber.binary(u8, "ne", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne16 => {
            fiber.binary(u16, "ne", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne32 => {
            fiber.binary(u32, "ne", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne64 => {
            fiber.binary(u64, "ne", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt8 => {
            fiber.binary(u8, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt16 => {
            fiber.binary(u16, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt32 => {
            fiber.binary(u32, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt64 => {
            fiber.binary(u64, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt8 => {
            fiber.binary(i8, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt16 => {
            fiber.binary(i16, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt32 => {
            fiber.binary(i32, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt64 => {
            fiber.binary(i64, "lt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt8 => {
            fiber.binary(u8, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt16 => {
            fiber.binary(u16, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt32 => {
            fiber.binary(u32, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt64 => {
            fiber.binary(u64, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt8 => {
            fiber.binary(i8, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt16 => {
            fiber.binary(i16, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt32 => {
            fiber.binary(i32, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt64 => {
            fiber.binary(i64, "gt", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le8 => {
            fiber.binary(u8, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le16 => {
            fiber.binary(u16, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le32 => {
            fiber.binary(u32, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le64 => {
            fiber.binary(u64, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le8 => {
            fiber.binary(i8, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le16 => {
            fiber.binary(i16, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le32 => {
            fiber.binary(i32, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le64 => {
            fiber.binary(i64, "le", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge8 => {
            fiber.binary(u8, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge16 => {
            fiber.binary(u16, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge32 => {
            fiber.binary(u32, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge64 => {
            fiber.binary(u64, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge8 => {
            fiber.binary(i8, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge16 => {
            fiber.binary(i16, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge32 => {
            fiber.binary(i32, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge64 => {
            fiber.binary(i64, "ge", decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .u_ext8x16 => {
            fiber.cast(u8, u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext8x32 => {
            fiber.cast(u8, u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext8x64 => {
            fiber.cast(u8, u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext16x32 => {
            fiber.cast(u16, u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext16x64 => {
            fiber.cast(u16, u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext32x64 => {
            fiber.cast(u32, u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext8x16 => {
            fiber.cast(i8, i16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext8x32 => {
            fiber.cast(i8, i32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext8x64 => {
            fiber.cast(i8, i64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext16x32 => {
            fiber.cast(i16, i32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext16x64 => {
            fiber.cast(i16, i64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext32x64 => {
            fiber.cast(i32, i64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ext32x64 => {
            fiber.cast(f32, i64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_trunc64x32 => {
            fiber.cast(u64, u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc64x16 => {
            fiber.cast(u64, u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc64x8 => {
            fiber.cast(u64, u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc32x16 => {
            fiber.cast(u32, u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc32x8 => {
            fiber.cast(u32, u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc16x8 => {
            fiber.cast(u16, u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_trunc64x32 => {
            fiber.cast(f64, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .u8_to_f32 => {
            fiber.cast(u8, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u8_to_f64 => {
            fiber.cast(u8, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u16_to_f32 => {
            fiber.cast(u16, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u16_to_f64 => {
            fiber.cast(u16, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u32_to_f32 => {
            fiber.cast(u32, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u32_to_f64 => {
            fiber.cast(u32, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u64_to_f32 => {
            fiber.cast(u64, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u64_to_f64 => {
            fiber.cast(u64, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s8_to_f32 => {
            fiber.cast(i8, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s8_to_f64 => {
            fiber.cast(i8, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s16_to_f32 => {
            fiber.cast(i16, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s16_to_f64 => {
            fiber.cast(i16, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s32_to_f32 => {
            fiber.cast(i32, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s32_to_f64 => {
            fiber.cast(i32, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s64_to_f32 => {
            fiber.cast(i64, f32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s64_to_f64 => {
            fiber.cast(i64, f64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u8 => {
            fiber.cast(f32, u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u16 => {
            fiber.cast(f32, u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u32 => {
            fiber.cast(f32, u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u64 => {
            fiber.cast(f32, u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u8 => {
            fiber.cast(f64, u8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u16 => {
            fiber.cast(f64, u16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u32 => {
            fiber.cast(f64, u32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u64 => {
            fiber.cast(f64, u64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s8 => {
            fiber.cast(f32, i8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s16 => {
            fiber.cast(f32, i16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s32 => {
            fiber.cast(f32, i32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s64 => {
            fiber.cast(f32, i64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s8 => {
            fiber.cast(f64, i8, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s16 => {
            fiber.cast(f64, i16, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s32 => {
            fiber.cast(f64, i32, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s64 => {
            fiber.cast(f64, i64, decoder.decodeUnchecked(Bytecode.Operand), decoder.decodeUnchecked(Bytecode.Operand));

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
    }

    if (comptime !reswitch) return true;
}

fn stepForeign(fiber: *Fiber) Fiber.Trap!void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const foreign = fiber.getForeign(currentCallFrame.function.value.foreign);

    const currentBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);

    var out: Fiber.ForeignOut = undefined;
    const control = foreign(fiber, currentBlockFrame.index, &out);

    switch (control) {
        .trap => return Fiber.convertForeignError(out.trap),
        .step => currentBlockFrame.index = out.step,
        .done => {
            fiber.stack.data.ptr = currentCallFrame.stack.base;
            fiber.stack.call.ptr -= 1;
            fiber.stack.block.ptr = currentCallFrame.root_block;
        },
        .done_v => {
            const rootBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);

            const size = currentCallFrame.function.layout_table.return_size;
            const src: [*]const u8 = fiber.addr(out.done_v);

            const dest: [*]u8 = fiber.addrImpl(fiber.stack.call.ptr -| 2, rootBlockFrame.out);

            @memcpy(dest[0..size], src);

            fiber.stack.data.ptr = currentCallFrame.stack.base;
            fiber.stack.call.ptr -= 1;
            fiber.stack.block.ptr = currentCallFrame.root_block;
        },
    }
}


fn when(fiber: *Fiber, newBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, comptime zeroCheck: ZeroCheck) void {
    const cond = fiber.read(u8, x);

    switch (zeroCheck) {
        .zero => if (cond == 0) fiber.stack.block.pushUnchecked(.noOutput(newBlockIndex, null)),
        .non_zero => if (cond != 0) fiber.stack.block.pushUnchecked(.noOutput(newBlockIndex, null)),
    }
}

fn br(fiber: *Fiber, decoder: *const IO.Decoder, terminatedBlockOffset: Bytecode.BlockIndex, comptime style: ReturnStyle, comptime zeroCheck: ?ZeroCheck) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const blockPtr = fiber.stack.block.ptr;

    const terminatedBlockPtr = blockPtr - (terminatedBlockOffset + 1);
    const terminatedBlockFrame = fiber.stack.block.getPtrUnchecked(terminatedBlockPtr);
    const terminatedBlock = &currentCallFrame.function.value.bytecode.blocks[terminatedBlockFrame.index];

    if (zeroCheck) |zc| {
        const cond = fiber.read(u8, decoder.decodeUnchecked(Bytecode.Operand));

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    if (style == .v) {
        const desiredSize = terminatedBlock.output_layout.?.size;
        const src = fiber.addr(decoder.decodeUnchecked(Bytecode.Operand));
        const dest = fiber.addr(terminatedBlockFrame.out);
        @memcpy(dest[0..desiredSize], src);
    }

    fiber.removeAnyHandlerSet(terminatedBlockFrame);

    fiber.stack.block.ptr = terminatedBlockPtr;
}

fn re(fiber: *Fiber, decoder: *const IO.Decoder, restartedBlockOffset: Bytecode.BlockIndex, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const blockPtr = fiber.stack.block.ptr;

    const restartedBlockPtr = blockPtr - (restartedBlockOffset + 1);

    const restartedBlockFrame = fiber.stack.block.getPtrUnchecked(restartedBlockPtr);

    if (zeroCheck) |zc| {
        const cond = fiber.read(u8, decoder.decodeUnchecked(Bytecode.Operand));

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    restartedBlockFrame.ip_offset = 0;

    fiber.stack.block.ptr = restartedBlockPtr + 1;
}

fn block(fiber: *Fiber, decoder: *const IO.Decoder, newBlockIndex: Bytecode.BlockIndex, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const newBlockFrame =
        if (comptime style == .v) Fiber.BlockFrame.value(newBlockIndex, decoder.decodeUnchecked(Bytecode.Operand), null)
        else Fiber.BlockFrame.noOutput(newBlockIndex, null);

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn with(fiber: *Fiber, decoder: *const IO.Decoder, newBlockIndex: Bytecode.BlockIndex, handlerSetIndex: Bytecode.HandlerSetIndex, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const handlerSet = fiber.program.handler_sets[handlerSetIndex];

    for (handlerSet) |binding| {
        try fiber.evidence[binding.id].push(Fiber.Evidence {
            .handler = binding.handler,
            .data = fiber.stack.data.ptr,
            .call = fiber.stack.call.ptr,
            .block = fiber.stack.block.ptr,
        });
    }

    const newBlockFrame =
        if (comptime style == .v) Fiber.BlockFrame.value(newBlockIndex, decoder.decodeUnchecked(Bytecode.Operand), handlerSetIndex)
        else Fiber.BlockFrame.noOutput(newBlockIndex, handlerSetIndex);

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn @"if"(fiber: *Fiber, decoder: *const IO.Decoder, thenBlockIndex: Bytecode.BlockIndex, elseBlockIndex: Bytecode.BlockIndex, x: Bytecode.Operand, comptime style: ReturnStyle, comptime zeroCheck: ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const cond = fiber.read(u8, x);

    const destBlockIndex = switch (zeroCheck) {
        .zero => if (cond == 0) thenBlockIndex else elseBlockIndex,
        .non_zero => if (cond != 0) thenBlockIndex else elseBlockIndex,
    };

    const newBlockFrame =
        if (comptime style == .v) Fiber.BlockFrame.value(destBlockIndex, decoder.decodeUnchecked(Bytecode.Operand), null)
        else Fiber.BlockFrame.noOutput(destBlockIndex, null);

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn addr(fiber: *Fiber, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) void {
    const bytes: [*]const u8 = fiber.addr(x);

    fiber.write(y, bytes);
}

inline fn dynCall(fiber: *Fiber, decoder: *const IO.Decoder, func: Bytecode.Operand, argCount: u8, comptime style: CallStyle) Fiber.Trap!void {
    const funcIndex = fiber.read(Bytecode.FunctionIndex, func);
    return callImpl(fiber, decoder, undefined, funcIndex, argCount, style);
}

inline fn call(fiber: *Fiber, decoder: *const IO.Decoder, funcIndex: Bytecode.FunctionIndex, argCount: u8, comptime style: CallStyle) Fiber.Trap!void {
    return callImpl(fiber, decoder, undefined, funcIndex, argCount, style);
}

inline fn prompt(fiber: *Fiber, decoder: *const IO.Decoder, evIndex: Bytecode.EvidenceIndex, argCount: u8, comptime style: CallStyle) Fiber.Trap!void {
    const evidence = fiber.evidence[evIndex].topPtrUnchecked();

    return callImpl(fiber, decoder, evIndex, evidence.handler, argCount, style);
}

fn callImpl(fiber: *Fiber, decoder: *const IO.Decoder, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, argCount: u8, comptime style: CallStyle) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const oldCallFrame = fiber.stack.call.topPtrUnchecked();
    const newFunction = &fiber.program.functions[funcIndex];

    const origin = fiber.stack.data.ptr;
    const padding = Support.alignmentDelta(origin, newFunction.layout_table.alignment);
    const base = origin + padding;

    try fiber.stack.data.pushUninit(newFunction.layout_table.size + padding);

    for (0..argCount) |i| {
        const info = newFunction.layout_table.registerInfo()[i];
        const desiredSize = info.size;
        const arg = fiber.addr(decoder.decodeUnchecked(Bytecode.Operand));
        const offset = base + info.offset;
        @memcpy(fiber.stack.data.memory[offset..offset + desiredSize], arg);
    }

    const newBlockFrame, const evidence =
        switch (style) {
            .no_tail => .{ Fiber.BlockFrame.entryPoint(null), Fiber.CallFrame.EvidenceRef.SENTINEL },
            .no_tail_v => .{ Fiber.BlockFrame.entryPoint(decoder.decodeUnchecked(Bytecode.Operand)), Fiber.CallFrame.EvidenceRef.SENTINEL },
            .tail => tail: {
                prepTail(fiber, oldCallFrame);

                break :tail .{ Fiber.BlockFrame.entryPoint(null), Fiber.CallFrame.EvidenceRef.SENTINEL };
            },
            .tail_v => tail_v: {
                const oldFunctionRootBlockFrame = fiber.stack.block.getPtrUnchecked(oldCallFrame.root_block);
                const oldFunctionOutput = oldFunctionRootBlockFrame.out;

                prepTail(fiber, oldCallFrame);

                break :tail_v .{ Fiber.BlockFrame.entryPoint(oldFunctionOutput), Fiber.CallFrame.EvidenceRef.SENTINEL };
            },
            .ev_no_tail => .{ Fiber.BlockFrame.entryPoint(null), .{
                .index = evIndex,
                .offset = fiber.evidence[evIndex].ptr - 1,
            } },
            .ev_no_tail_v => .{ Fiber.BlockFrame.entryPoint(decoder.decodeUnchecked(Bytecode.Operand)), .{
                .index = evIndex,
                .offset = fiber.evidence[evIndex].ptr - 1,
            } },
            .ev_tail => tail: {
                prepTail(fiber, oldCallFrame);

                break :tail .{ Fiber.BlockFrame.entryPoint(null), .{
                    .index = evIndex,
                    .offset = fiber.evidence[evIndex].ptr - 1,
                } };
            },
            .ev_tail_v => tail_v: {
                const oldFunctionRootBlockFrame = fiber.stack.block.getPtrUnchecked(oldCallFrame.root_block);
                const oldFunctionOutput = oldFunctionRootBlockFrame.out;

                prepTail(fiber, oldCallFrame);

                break :tail_v .{ Fiber.BlockFrame.entryPoint(oldFunctionOutput), .{
                    .index = evIndex,
                    .offset = fiber.evidence[evIndex].ptr - 1,
                } };
            },
        };

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = evidence,
        .root_block = fiber.stack.block.ptr,
        .stack = .{
            .base = base,
            .origin = origin,
        },
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

inline fn prepTail(fiber: *Fiber, oldCallFrame: *const Fiber.CallFrame) void {
    fiber.stack.data.ptr = oldCallFrame.stack.base;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = oldCallFrame.root_block - 1;
}

fn term(fiber: *Fiber, decoder: *const IO.Decoder, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const evRef = currentCallFrame.evidence;

    const evidence = fiber.evidence[evRef.index].getPtrUnchecked(evRef.offset);

    const rootBlockFrame = fiber.stack.block.getPtrUnchecked(evidence.block);

    if (style == .v) {
        const size = currentCallFrame.function.layout_table.term_size;
        const src: [*]const u8 = fiber.addr(decoder.decodeUnchecked(Bytecode.Operand));

        const dest: [*]u8 = fiber.addrImpl(evidence.call, rootBlockFrame.out);

        @memcpy(dest[0..size], src);
    }

    fiber.stack.data.ptr = evidence.data;
    fiber.stack.call.ptr = evidence.call;
    fiber.stack.block.ptr = evidence.block - 1;
}

fn ret(fiber: *Fiber, decoder: *const IO.Decoder, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const rootBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);

    if (style == .v) {
        const size = currentCallFrame.function.layout_table.return_size;
        const src: [*]const u8 = fiber.addr(decoder.decodeUnchecked(Bytecode.Operand));

        const dest: [*]u8 = fiber.addrImpl(fiber.stack.call.ptr -| 2, rootBlockFrame.out);

        @memcpy(dest[0..size], src);
    }

    fiber.stack.data.ptr = currentCallFrame.stack.base;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = currentCallFrame.root_block;
}
