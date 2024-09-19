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

inline fn updateDecoder(fiber: *Fiber, decoder: *IO.Decoder) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const currentBlockFrame = fiber.stack.block.topPtrUnchecked();
    const currentBlock = &currentCallFrame.function.value.bytecode.blocks[currentBlockFrame.index];

    decoder.memory = currentCallFrame.function.value.bytecode.instructions;
    decoder.base = currentBlock.base;
    decoder.offset = &currentBlockFrame.ip_offset;
}

inline fn decodeOpCode(decoder: *const IO.Decoder) Bytecode.OpCode {
    const rx = decodeIndex(decoder);

    return @enumFromInt(rx);
}

inline fn decodeIndex(decoder: *const IO.Decoder) u16 {
    const start = decoder.base + decoder.offset.*;

    decoder.offset.* += 2;

    return @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start]))).*;
}

inline fn decodeIndex2(decoder: *const IO.Decoder) struct {u16, u16} {
    const start = decoder.base + decoder.offset.*;

    decoder.offset.* += 4;

    return .{
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 0]))).*,
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 2]))).*,
    };
}

inline fn decodeIndex3(decoder: *const IO.Decoder) struct {u16, u16, u16} {
    const start = decoder.base + decoder.offset.*;

    decoder.offset.* += 6;

    return .{
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 0]))).*,
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 2]))).*,
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 4]))).*,
    };
}

inline fn decodeIndex4(decoder: *const IO.Decoder) struct {u16,u16,u16,u16} {
    const start = decoder.base + decoder.offset.*;

    decoder.offset.* += 8;

    return .{
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 0]))).*,
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 2]))).*,
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 4]))).*,
        @as(*const u16, @alignCast(@ptrCast(&decoder.memory[start + 6]))).*,
    };
}


// TODO: reimplement foreign calls as an instruction
fn stepBytecode(comptime reswitch: bool, fiber: *Fiber) Fiber.Trap!if (reswitch) void else bool {
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
            const rs = decodeIndex2(&decoder);

            try callImpl_tail(fiber, &decoder, rs[0], rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .tail_call_v => {
            const rs = decodeIndex2(&decoder);

            try callImpl_tail_v(fiber, &decoder, rs[0], rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_tail_call => {
            const rs = decodeIndex2(&decoder);
            const funcIndex = fiber.readLocal(Bytecode.FunctionIndex, rs[0]);

            try callImpl_tail(fiber, &decoder, funcIndex, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_tail_call_v => {
            const rs = decodeIndex2(&decoder);
            const funcIndex = fiber.readLocal(Bytecode.FunctionIndex, rs[0]);

            try callImpl_tail_v(fiber, &decoder, funcIndex, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .tail_prompt => {
            const rs = decodeIndex2(&decoder);
            const evidence = fiber.evidence[rs[0]].topPtrUnchecked();

            try callImpl_ev_tail(fiber, &decoder, rs[0], evidence.handler, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .tail_prompt_v => {
            const rs = decodeIndex2(&decoder);
            const evidence = fiber.evidence[rs[0]].topPtrUnchecked();

            try callImpl_ev_tail_v(fiber, &decoder, rs[0], evidence.handler, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .call => {
            const rs = decodeIndex2(&decoder);

            try callImpl_no_tail(fiber, &decoder, rs[0], rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .call_v => {
            const rs = decodeIndex2(&decoder);

            try callImpl_no_tail_v(fiber, &decoder, rs[0], rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_call => {
            const rs = decodeIndex2(&decoder);
            const funcIndex = fiber.readLocal(Bytecode.FunctionIndex, rs[0]);

            try callImpl_no_tail(fiber, &decoder, funcIndex, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .dyn_call_v => {
            const rs = decodeIndex2(&decoder);
            const funcIndex = fiber.readLocal(Bytecode.FunctionIndex, rs[0]);

            try callImpl_no_tail_v(fiber, &decoder, funcIndex, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .prompt => {
            const rs = decodeIndex2(&decoder);
            const evidence = fiber.evidence[rs[0]].topPtrUnchecked();

            try callImpl_ev_no_tail(fiber, &decoder, rs[0], evidence.handler, rs[1]);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .prompt_v => {
            const rs = decodeIndex2(&decoder);
            const evidence = fiber.evidence[rs[0]].topPtrUnchecked();

            try callImpl_ev_no_tail_v(fiber, &decoder, rs[0], evidence.handler, rs[1]);

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
            const rs = decodeIndex2(&decoder);

            when(fiber, rs[0], rs[1], .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .when_nz => {
            const rs = decodeIndex2(&decoder);

            when(fiber, rs[0], rs[1], .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .re => {
            const rx = decodeIndex(&decoder);

            re(fiber, &decoder, rx, null);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .re_z => {
            const rx = decodeIndex(&decoder);

            re(fiber, &decoder, rx, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .re_nz => {
            const rx = decodeIndex(&decoder);

            re(fiber, &decoder, rx, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .br => {
            const rx = decodeIndex(&decoder);

            br(fiber, &decoder, rx, .no_v, null);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_z => {
            const rx = decodeIndex(&decoder);

            br(fiber, &decoder, rx, .no_v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_nz => {
            const rx = decodeIndex(&decoder);

            br(fiber, &decoder, rx, .no_v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .br_v => {
            const rx = decodeIndex(&decoder);

            br(fiber, &decoder, rx, .v, null);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_z_v => {
            const rx = decodeIndex(&decoder);

            br(fiber, &decoder, rx, .v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .br_nz_v => {
            const rx = decodeIndex(&decoder);

            br(fiber, &decoder, rx, .v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .block => {
            const rx = decodeIndex(&decoder);

            block(fiber, &decoder, rx, .no_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .block_v => {
            const rx = decodeIndex(&decoder);

            block(fiber, &decoder, rx, .v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .with => {
            const rs = decodeIndex2(&decoder);

            try with(fiber, &decoder, rs[0], rs[1], .no_v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .with_v => {
            const rs = decodeIndex2(&decoder);

            try with(fiber, &decoder, rs[0], rs[1], .v);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .if_z => {
            const rs = decodeIndex3(&decoder);

            @"if"(fiber, &decoder, rs[0], rs[1], rs[2], .no_v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .if_nz => {
            const rs = decodeIndex3(&decoder);

            @"if"(fiber, &decoder, rs[0], rs[1], rs[2], .no_v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .if_z_v => {
            const rs = decodeIndex3(&decoder);

            @"if"(fiber, &decoder, rs[0], rs[1], rs[2], .v, .zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },
        .if_nz_v => {
            const rs = decodeIndex3(&decoder);

            @"if"(fiber, &decoder, rs[0], rs[1], rs[2], .v, .non_zero);

            if (comptime reswitch) {
                updateDecoder(fiber, &decoder);
                continue :reswitch decodeOpCode(&decoder);
            }
        },

        .addr_local => {
            const rs = decodeIndex2(&decoder);

            addr_local(fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .addr_global => {
            const rs = decodeIndex2(&decoder);

            addr_global(fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .addr_upvalue => {
            const rs = decodeIndex2(&decoder);

            addr_upvalue(fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .read_global8 => {
            const rs = decodeIndex2(&decoder);

            read_global(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .read_global16 => {
            const rs = decodeIndex2(&decoder);

            read_global(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .read_global32 => {
            const rs = decodeIndex2(&decoder);

            read_global(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .read_global64 => {
            const rs = decodeIndex2(&decoder);

            read_global(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .write_global8 => {
            const rs = decodeIndex2(&decoder);

            write_global(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .write_global16 => {
            const rs = decodeIndex2(&decoder);

            write_global(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .write_global32 => {
            const rs = decodeIndex2(&decoder);

            write_global(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .write_global64 => {
            const rs = decodeIndex2(&decoder);

            write_global(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .read_upvalue8 => {
            const rs = decodeIndex2(&decoder);

            read_upvalue(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .read_upvalue16 => {
            const rs = decodeIndex2(&decoder);

            read_upvalue(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .read_upvalue32 => {
            const rs = decodeIndex2(&decoder);

            read_upvalue(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .read_upvalue64 => {
            const rs = decodeIndex2(&decoder);

            read_upvalue(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .write_upvalue8 => {
            const rs = decodeIndex2(&decoder);

            write_upvalue(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .write_upvalue16 => {
            const rs = decodeIndex2(&decoder);

            write_upvalue(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .write_upvalue32 => {
            const rs = decodeIndex2(&decoder);

            write_upvalue(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .write_upvalue64 => {
            const rs = decodeIndex2(&decoder);

            write_upvalue(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .load8 => {
            const rs = decodeIndex2(&decoder);

            try load(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .load16 => {
            const rs = decodeIndex2(&decoder);

            try load(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .load32 => {
            const rs = decodeIndex2(&decoder);

            try load(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .load64 => {
            const rs = decodeIndex2(&decoder);

            try load(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .store8 => {
            const rs = decodeIndex2(&decoder);

            try store(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .store16 => {
            const rs = decodeIndex2(&decoder);

            try store(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .store32 => {
            const rs = decodeIndex2(&decoder);

            try store(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .store64 => {
            const rs = decodeIndex2(&decoder);

            try store(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .clear8 => {
            const rx = decodeIndex(&decoder);

            clear(u8, fiber, rx);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .clear16 => {
            const rx = decodeIndex(&decoder);

            clear(u16, fiber, rx);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .clear32 => {
            const rx = decodeIndex(&decoder);

            clear(u32, fiber, rx);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .clear64 => {
            const rx = decodeIndex(&decoder);

            clear(u64, fiber, rx);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .swap8 => {
            const rs = decodeIndex2(&decoder);

            swap(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .swap16 => {
            const rs = decodeIndex2(&decoder);

            swap(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .swap32 => {
            const rs = decodeIndex2(&decoder);

            swap(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .swap64 => {
            const rs = decodeIndex2(&decoder);

            swap(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .copy8 => {
            const rs = decodeIndex2(&decoder);

            copy(u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .copy16 => {
            const rs = decodeIndex2(&decoder);

            copy(u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .copy32 => {
            const rs = decodeIndex2(&decoder);

            copy(u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .copy64 => {
            const rs = decodeIndex2(&decoder);

            copy(u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .b_not => {
            const rs = decodeIndex2(&decoder);

            unary(bool, fiber, "not", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .b_and => {
            const rs = decodeIndex3(&decoder);

            binary(bool, fiber, "and", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .b_or => {
            const rs = decodeIndex3(&decoder);

            binary(bool, fiber, "or", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .f_add32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "add", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_add64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "add", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_sub32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "sub", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_sub64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "sub", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_mul32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "mul", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_mul64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "mul", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_div32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_div64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_rem32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_rem64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_neg32 => {
            const rs = decodeIndex2(&decoder);

            unary(f32, fiber, "neg", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_neg64 => {
            const rs = decodeIndex2(&decoder);

            unary(f64, fiber, "neg", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .f_eq32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "eq", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_eq64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "eq", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ne32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "ne", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ne64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "ne", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_lt32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_lt64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_gt32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_gt64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_le32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_le64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ge32 => {
            const rs = decodeIndex3(&decoder);

            binary(f32, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ge64 => {
            const rs = decodeIndex3(&decoder);

            binary(f64, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_add8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "add", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_add16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "add", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_add32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "add", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_add64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "add", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "sub", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "sub", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "sub", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_sub64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "sub", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "mul", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "mul", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "mul", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_mul64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "mul", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_div64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_div64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "div", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_rem64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_rem64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "rem", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg8 => {
            const rs = decodeIndex2(&decoder);

            unary(i8, fiber, "neg", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg16 => {
            const rs = decodeIndex2(&decoder);

            unary(i16, fiber, "neg", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg32 => {
            const rs = decodeIndex2(&decoder);

            unary(i32, fiber, "neg", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_neg64 => {
            const rs = decodeIndex2(&decoder);

            unary(i64, fiber, "neg", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_bitnot8 => {
            const rs = decodeIndex2(&decoder);

            unary(u8, fiber, "bitnot", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitnot16 => {
            const rs = decodeIndex2(&decoder);

            unary(u16, fiber, "bitnot", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitnot32 => {
            const rs = decodeIndex2(&decoder);

            unary(u32, fiber, "bitnot", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitnot64 => {
            const rs = decodeIndex2(&decoder);

            unary(u64, fiber, "bitnot", rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "bitand", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "bitand", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "bitand", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitand64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "bitand", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "bitor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "bitor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "bitor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitor64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "bitor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "bitxor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "bitxor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "bitxor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_bitxor64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "bitxor", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "shiftl", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "shiftl", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "shiftl", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_shiftl64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "shiftl", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_shiftr64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_shiftr64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "shiftr", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_eq8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "eq", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_eq16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "eq", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_eq32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "eq", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_eq64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "eq", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "ne", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "ne", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "ne", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_ne64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "ne", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_lt64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_lt64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "lt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_gt64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_gt64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "gt", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_le64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_le64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "le", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge8 => {
            const rs = decodeIndex3(&decoder);

            binary(u8, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge16 => {
            const rs = decodeIndex3(&decoder);

            binary(u16, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge32 => {
            const rs = decodeIndex3(&decoder);

            binary(u32, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ge64 => {
            const rs = decodeIndex3(&decoder);

            binary(u64, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge8 => {
            const rs = decodeIndex3(&decoder);

            binary(i8, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge16 => {
            const rs = decodeIndex3(&decoder);

            binary(i16, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge32 => {
            const rs = decodeIndex3(&decoder);

            binary(i32, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ge64 => {
            const rs = decodeIndex3(&decoder);

            binary(i64, fiber, "ge", rs[0], rs[1], rs[2]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .u_ext8x16 => {
            const rs = decodeIndex2(&decoder);

            cast(u8, u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext8x32 => {
            const rs = decodeIndex2(&decoder);

            cast(u8, u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext8x64 => {
            const rs = decodeIndex2(&decoder);

            cast(u8, u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext16x32 => {
            const rs = decodeIndex2(&decoder);

            cast(u16, u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext16x64 => {
            const rs = decodeIndex2(&decoder);

            cast(u16, u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u_ext32x64 => {
            const rs = decodeIndex2(&decoder);

            cast(u32, u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext8x16 => {
            const rs = decodeIndex2(&decoder);

            cast(i8, i16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext8x32 => {
            const rs = decodeIndex2(&decoder);

            cast(i8, i32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext8x64 => {
            const rs = decodeIndex2(&decoder);

            cast(i8, i64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext16x32 => {
            const rs = decodeIndex2(&decoder);

            cast(i16, i32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext16x64 => {
            const rs = decodeIndex2(&decoder);

            cast(i16, i64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s_ext32x64 => {
            const rs = decodeIndex2(&decoder);

            cast(i32, i64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_ext32x64 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, i64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .i_trunc64x32 => {
            const rs = decodeIndex2(&decoder);

            cast(u64, u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc64x16 => {
            const rs = decodeIndex2(&decoder);

            cast(u64, u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc64x8 => {
            const rs = decodeIndex2(&decoder);

            cast(u64, u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc32x16 => {
            const rs = decodeIndex2(&decoder);

            cast(u32, u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc32x8 => {
            const rs = decodeIndex2(&decoder);

            cast(u32, u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .i_trunc16x8 => {
            const rs = decodeIndex2(&decoder);

            cast(u16, u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f_trunc64x32 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },

        .u8_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(u8, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u8_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(u8, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u16_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(u16, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u16_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(u16, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u32_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(u32, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u32_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(u32, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u64_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(u64, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .u64_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(u64, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s8_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(i8, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s8_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(i8, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s16_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(i16, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s16_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(i16, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s32_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(i32, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s32_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(i32, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s64_to_f32 => {
            const rs = decodeIndex2(&decoder);

            cast(i64, f32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .s64_to_f64 => {
            const rs = decodeIndex2(&decoder);

            cast(i64, f64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u8 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u16 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u32 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_u64 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u8 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, u8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u16 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, u16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u32 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, u32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_u64 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, u64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s8 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, i8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s16 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, i16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s32 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, i32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f32_to_s64 => {
            const rs = decodeIndex2(&decoder);

            cast(f32, i64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s8 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, i8, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s16 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, i16, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s32 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, i32, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
        .f64_to_s64 => {
            const rs = decodeIndex2(&decoder);

            cast(f64, i64, fiber, rs[0], rs[1]);

            if (comptime reswitch) continue :reswitch decodeOpCode(&decoder);
        },
    }

    if (comptime !reswitch) return true;
}

fn stepForeign(fiber: *Fiber) Fiber.Trap!void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();
    const foreign = fiber.getForeign(currentCallFrame.function.value.foreign);

    const currentBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);

    var foreignOut: Fiber.ForeignOut = undefined;
    const control = foreign(fiber, currentBlockFrame.index, &foreignOut);

    switch (control) {
        .trap => return Fiber.convertForeignError(foreignOut.trap),
        .step => currentBlockFrame.index = foreignOut.step,
        .done => {
            fiber.stack.data.ptr = currentCallFrame.stack.base;
            fiber.stack.call.ptr -= 1;
            fiber.stack.block.ptr = currentCallFrame.root_block;
        },
        .done_v => {
            const rootBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);

            const out = fiber.readLocal(u64, foreignOut.done_v);

            fiber.writeReg(fiber.stack.call.ptr -| 2, rootBlockFrame.out, out);

            fiber.stack.data.ptr = currentCallFrame.stack.base;
            fiber.stack.call.ptr -= 1;
            fiber.stack.block.ptr = currentCallFrame.root_block;
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
    try fiber.boundsCheck(@ptrCast(out), @sizeOf(T));
    out.* = in;
}

pub fn store(comptime T: type, fiber: *Fiber, x: Bytecode.RegisterIndex, y: Bytecode.RegisterIndex) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const in = fiber.readLocal(*T, x);
    try fiber.boundsCheck(@ptrCast(in), @sizeOf(T));
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

    const blockFrame = Fiber.BlockFrame.noOutput(newBlockIndex, null);

    switch (zeroCheck) {
        .zero => if (cond == 0) fiber.stack.block.pushUnchecked(blockFrame),
        .non_zero => if (cond != 0) fiber.stack.block.pushUnchecked(blockFrame),
    }
}

fn br(fiber: *Fiber, decoder: *const IO.Decoder, terminatedBlockOffset: Bytecode.BlockIndex, comptime style: ReturnStyle, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const blockPtr = fiber.stack.block.ptr;

    const terminatedBlockPtr = blockPtr - (terminatedBlockOffset + 1);
    const terminatedBlockFrame = fiber.stack.block.getPtrUnchecked(terminatedBlockPtr);

    if (zeroCheck) |zc| {
        const rx = decodeIndex(decoder);
        const cond = fiber.readLocal(u8, rx);

        switch (zc) {
            .zero => if (cond != 0) return,
            .non_zero => if (cond == 0) return,
        }
    }

    if (style == .v) {
        const rx = decodeIndex(decoder);
        const out = fiber.readLocal(u64, rx);
        fiber.writeLocal(terminatedBlockFrame.out, out);
    }

    fiber.removeAnyHandlerSet(terminatedBlockFrame);

    fiber.stack.block.ptr = terminatedBlockPtr;
}

fn re(fiber: *Fiber, decoder: *const IO.Decoder, restartedBlockOffset: Bytecode.BlockIndex, comptime zeroCheck: ?ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const blockPtr = fiber.stack.block.ptr;

    const restartedBlockPtr = blockPtr - (restartedBlockOffset + 1);

    const restartedBlockFrame = fiber.stack.block.getPtrUnchecked(restartedBlockPtr);

    if (zeroCheck) |zc| {
        const rx = decodeIndex(decoder);
        const cond = fiber.readLocal(u8, rx);

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
        if (comptime style == .v) v: {
            const rx = decodeIndex(decoder);
            break :v Fiber.BlockFrame.value(newBlockIndex, rx, null);
        }
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
        if (comptime style == .v) v: {
            const rx = decodeIndex(decoder);
            break :v Fiber.BlockFrame.value(newBlockIndex, rx, handlerSetIndex);
        }
        else Fiber.BlockFrame.noOutput(newBlockIndex, handlerSetIndex);

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn @"if"(fiber: *Fiber, decoder: *const IO.Decoder, thenBlockIndex: Bytecode.BlockIndex, elseBlockIndex: Bytecode.BlockIndex, x: Bytecode.RegisterIndex, comptime style: ReturnStyle, comptime zeroCheck: ZeroCheck) callconv(Config.INLINING_CALL_CONV) void {
    const cond = fiber.readLocal(u8, x);

    const destBlockIndex = switch (zeroCheck) {
        .zero => if (cond == 0) thenBlockIndex else elseBlockIndex,
        .non_zero => if (cond != 0) thenBlockIndex else elseBlockIndex,
    };

    const newBlockFrame =
        if (comptime style == .v) v: {
            const rx = decodeIndex(decoder);
            break :v Fiber.BlockFrame.value(destBlockIndex, rx, null);
        }
        else Fiber.BlockFrame.noOutput(destBlockIndex, null);

    fiber.stack.block.pushUnchecked(newBlockFrame);
}



fn callImpl_no_tail(fiber: *Fiber, decoder: *const IO.Decoder, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    const newBlockFrame = Fiber.BlockFrame.entryPoint(null);
    const evidence = Fiber.CallFrame.EvidenceRef.SENTINEL;

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = evidence,
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn callImpl_no_tail_v(fiber: *Fiber, decoder: *const IO.Decoder, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);


    switch (argCount) {
        0 => {},
        1 => {
            const rx = decodeIndex(decoder);
            const src = fiber.addrLocal(rx);
            const offset = base;
            const dest = fiber.stack.data.memory.ptr + offset;

            @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
        },
        2 => {
            const rs = decodeIndex2(decoder);

            const srcA = fiber.addrLocal(rs[0]);
            const srcB = fiber.addrLocal(rs[1]);

            const offsetA = base;
            const offsetB = base + 8;

            const destA = fiber.stack.data.memory.ptr + offsetA;
            const destB = fiber.stack.data.memory.ptr + offsetB;

            @as(*u64, @alignCast(@ptrCast(destA))).* = @as(*const u64, @alignCast(@ptrCast(srcA))).*;
            @as(*u64, @alignCast(@ptrCast(destB))).* = @as(*const u64, @alignCast(@ptrCast(srcB))).*;
        },
        3 => {
            const rs = decodeIndex3(decoder);

            const srcA = fiber.addrLocal(rs[0]);
            const srcB = fiber.addrLocal(rs[1]);
            const srcC = fiber.addrLocal(rs[2]);

            const offsetA = base;
            const offsetB = base + 8;
            const offsetC = base + 16;

            const destA = fiber.stack.data.memory.ptr + offsetA;
            const destB = fiber.stack.data.memory.ptr + offsetB;
            const destC = fiber.stack.data.memory.ptr + offsetC;

            @as(*u64, @alignCast(@ptrCast(destA))).* = @as(*const u64, @alignCast(@ptrCast(srcA))).*;
            @as(*u64, @alignCast(@ptrCast(destB))).* = @as(*const u64, @alignCast(@ptrCast(srcB))).*;
            @as(*u64, @alignCast(@ptrCast(destC))).* = @as(*const u64, @alignCast(@ptrCast(srcC))).*;
        },
        4 => {
            const rs = decodeIndex4(decoder);

            const srcA = fiber.addrLocal(rs[0]);
            const srcB = fiber.addrLocal(rs[1]);
            const srcC = fiber.addrLocal(rs[2]);
            const srcD = fiber.addrLocal(rs[3]);

            const offsetA = base;
            const offsetB = base + 8;
            const offsetC = base + 16;
            const offsetD = base + 24;

            const destA = fiber.stack.data.memory.ptr + offsetA;
            const destB = fiber.stack.data.memory.ptr + offsetB;
            const destC = fiber.stack.data.memory.ptr + offsetC;
            const destD = fiber.stack.data.memory.ptr + offsetD;

            @as(*u64, @alignCast(@ptrCast(destA))).* = @as(*const u64, @alignCast(@ptrCast(srcA))).*;
            @as(*u64, @alignCast(@ptrCast(destB))).* = @as(*const u64, @alignCast(@ptrCast(srcB))).*;
            @as(*u64, @alignCast(@ptrCast(destC))).* = @as(*const u64, @alignCast(@ptrCast(srcC))).*;
            @as(*u64, @alignCast(@ptrCast(destD))).* = @as(*const u64, @alignCast(@ptrCast(srcD))).*;
        },
        else => {
            @branchHint(.unlikely);

            for (0..argCount) |i| {
                const rx = decodeIndex(decoder);
                const src = fiber.addrLocal(rx);
                const offset = base + (i * 8);
                const dest = fiber.stack.data.memory.ptr + offset;

                @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
            }
        }
    }

    const rx = decodeIndex(decoder);
    const newBlockFrame = Fiber.BlockFrame.entryPoint(rx);

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = Fiber.CallFrame.EvidenceRef.SENTINEL,
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn callImpl_tail(fiber: *Fiber, decoder: *const IO.Decoder, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const oldCallFrame = fiber.stack.call.topPtrUnchecked();
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    fiber.stack.data.ptr = oldCallFrame.stack;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = oldCallFrame.root_block - 1;

    const newBlockFrame = Fiber.BlockFrame.entryPoint(null);

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = Fiber.CallFrame.EvidenceRef.SENTINEL,
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}


// FIXME: inlining here causes seemingly-infinite build time
fn callImpl_tail_v(fiber: *Fiber, decoder: *const IO.Decoder, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(.Unspecified) Fiber.Trap!void {
    const oldCallFrame = fiber.stack.call.topPtrUnchecked();
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    const oldFunctionRootBlockFrame = fiber.stack.block.getPtrUnchecked(oldCallFrame.root_block);
    const oldFunctionOutput = oldFunctionRootBlockFrame.out;
    const newBlockFrame = Fiber.BlockFrame.entryPoint(oldFunctionOutput);

    fiber.stack.data.ptr = oldCallFrame.stack;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = oldCallFrame.root_block - 1;

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = Fiber.CallFrame.EvidenceRef.SENTINEL,
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn callImpl_ev_no_tail(fiber: *Fiber, decoder: *const IO.Decoder, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    const newBlockFrame = Fiber.BlockFrame.entryPoint(null);

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = .{
            .index = evIndex,
            .offset = fiber.evidence[evIndex].ptr - 1
        },
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn callImpl_ev_no_tail_v(fiber: *Fiber, decoder: *const IO.Decoder, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    const rx = decodeIndex(decoder);
    const newBlockFrame = Fiber.BlockFrame.entryPoint(rx);

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = .{
            .index = evIndex,
            .offset = fiber.evidence[evIndex].ptr - 1
        },
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn callImpl_ev_tail(fiber: *Fiber, decoder: *const IO.Decoder, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const oldCallFrame = fiber.stack.call.topPtrUnchecked();
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    fiber.stack.data.ptr = oldCallFrame.stack;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = oldCallFrame.root_block - 1;

    const newBlockFrame = Fiber.BlockFrame.entryPoint(null);

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = .{
            .index = evIndex,
            .offset = fiber.evidence[evIndex].ptr - 1
        },
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}

fn callImpl_ev_tail_v(fiber: *Fiber, decoder: *const IO.Decoder, evIndex: Bytecode.EvidenceIndex, funcIndex: Bytecode.FunctionIndex, argCount: u16) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const oldCallFrame = fiber.stack.call.topPtrUnchecked();
    const newFunction = &fiber.program.functions[funcIndex];

    const base = fiber.stack.data.ptr;

    try fiber.stack.data.pushUninit(newFunction.num_registers * 8);

    for (0..argCount) |i| {
        const rx = decodeIndex(decoder);
        const src = fiber.addrLocal(rx);
        const offset = base + (i * 8);
        const dest = fiber.stack.data.memory.ptr + offset;

        @as(*u64, @alignCast(@ptrCast(dest))).* = @as(*const u64, @alignCast(@ptrCast(src))).*;
    }

    const oldFunctionRootBlockFrame = fiber.stack.block.getPtrUnchecked(oldCallFrame.root_block);
    const oldFunctionOutput = oldFunctionRootBlockFrame.out;

    fiber.stack.data.ptr = oldCallFrame.stack;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = oldCallFrame.root_block - 1;

    const newBlockFrame = Fiber.BlockFrame.entryPoint(oldFunctionOutput);

    try fiber.stack.call.push(Fiber.CallFrame {
        .function = newFunction,
        .evidence = .{
            .index = evIndex,
            .offset = fiber.evidence[evIndex].ptr - 1,
        },
        .root_block = fiber.stack.block.ptr,
        .stack = base,
    });

    fiber.stack.block.pushUnchecked(newBlockFrame);
}


fn term(fiber: *Fiber, decoder: *const IO.Decoder, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const evRef = currentCallFrame.evidence;

    const evidence = fiber.evidence[evRef.index].getPtrUnchecked(evRef.offset);

    const rootBlockFrame = fiber.stack.block.getPtrUnchecked(evidence.block);

    if (style == .v) {
        const rx = decodeIndex(decoder);
        const out = fiber.readLocal(u64, rx);
        fiber.writeReg(evidence.call, rootBlockFrame.out, out);
    }

    fiber.stack.data.ptr = evidence.data;
    fiber.stack.call.ptr = evidence.call;
    fiber.stack.block.ptr = evidence.block;
}

fn ret(fiber: *Fiber, decoder: *const IO.Decoder, comptime style: ReturnStyle) callconv(Config.INLINING_CALL_CONV) void {
    const currentCallFrame = fiber.stack.call.topPtrUnchecked();

    const rootBlockFrame = fiber.stack.block.getPtrUnchecked(currentCallFrame.root_block);

    if (style == .v) {
        const rx = decodeIndex(decoder);
        const out = fiber.readLocal(u64, rx);
        fiber.writeReg(fiber.stack.call.ptr - 2, rootBlockFrame.out, out);
    }

    fiber.stack.data.ptr = currentCallFrame.stack;
    fiber.stack.call.ptr -= 1;
    fiber.stack.block.ptr = currentCallFrame.root_block;
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
