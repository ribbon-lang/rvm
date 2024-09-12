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

    const localData, const upvalueData = try registerData(fiber, callFrame, function);

    switch (function.value) {
        .bytecode => try @call(Config.INLINING_CALL_MOD, stepBytecode, .{fiber, function, callFrame, localData, upvalueData}),
        .native => |nat| try @call(Config.INLINING_CALL_MOD, stepNative, .{fiber, localData, upvalueData, nat}),
    }
}

pub fn stepBytecode(fiber: *Fiber, function: *Bytecode.Function, callFrame: *Fiber.CallFrame, localData: RegisterData, upvalueData: ?RegisterData) Fiber.Trap!void {
    @setEvalBranchQuota(Config.INLINING_BRANCH_QUOTA);

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
        .dyn_call => |operands| try dynCall(fiber, localData, upvalueData, operands.f, operands.as, null),
        .dyn_call_v => |operands| try dynCall(fiber, localData, upvalueData, operands.f, operands.as, operands.y),
        .prompt => |operands| try prompt(fiber, localData, upvalueData, operands.e, operands.as, null),
        .prompt_v => |operands| try prompt(fiber, localData, upvalueData, operands.e, operands.as, operands.y),

        .ret => try ret(fiber, function, callFrame, localData, upvalueData, null),
        .ret_v => |operands| try ret(fiber, function, callFrame, localData, upvalueData, operands.y),
        .term => try term(fiber, function, callFrame, localData, upvalueData, null),
        .term_v => |operands| try term(fiber, function, callFrame, localData, upvalueData, operands.y),

        .when_z => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const newBlockIndex = operands.b;

            if (newBlockIndex >= function.value.bytecode.blocks.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            const newBlock = &function.value.bytecode.blocks[newBlockIndex];

            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            if (cond == 0) {
                try fiber.stack.block.push(.noOutput(newBlockIndex));
            }
        },

        .when_nz => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const newBlockIndex = operands.b;

            if (newBlockIndex >= function.value.bytecode.blocks.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            const newBlock = &function.value.bytecode.blocks[newBlockIndex];

            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            if (cond != 0) {
                try fiber.stack.block.push(.noOutput(newBlockIndex));
            }
        },

        .re => |operands| {
            const restartedBlockOffset = operands.b;

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

            restartedBlockFrame.ip_offset = 0;

            fiber.stack.block.ptr = restartedBlockPtr + 1;
        },

        .re_z => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);

            const restartedBlockOffset = operands.b;

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

            if (cond == 0) {
                restartedBlockFrame.ip_offset = 0;

                fiber.stack.block.ptr = restartedBlockPtr + 1;
            }
        },

        .re_nz => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);

            const restartedBlockOffset = operands.b;

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

            if (cond != 0) {
                restartedBlockFrame.ip_offset = 0;

                fiber.stack.block.ptr = restartedBlockPtr + 1;
            }
        },

        .br => |operands | {
            const terminatedBlockOffset = operands.b;

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

            fiber.stack.block.ptr = terminatedBlockPtr;
        },

        .br_z => |operands | {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const terminatedBlockOffset = operands.b;

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

            if (cond == 0) {
                fiber.stack.block.ptr = terminatedBlockPtr;
            }
        },

        .br_nz => |operands | {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const terminatedBlockOffset = operands.b;

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

            if (cond != 0) {
                fiber.stack.block.ptr = terminatedBlockPtr;
            }
        },

        .br_v => |operands| {
            const terminatedBlockOffset = operands.b;

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

            const desiredSize = terminatedBlock.output_layout.?.size;
            const src = try addr(globals, stack, localData, upvalueData, operands.y, desiredSize);
            const dest = try addr(globals, stack, localData, upvalueData, terminatedBlockFrame.out, desiredSize);
            @memcpy(dest[0..desiredSize], src);

            fiber.stack.block.ptr = terminatedBlockPtr;
        },

        .br_z_v => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const terminatedBlockOffset = operands.b;

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

            const desiredSize = terminatedBlock.output_layout.?.size;
            const src = try addr(globals, stack, localData, upvalueData, operands.y, desiredSize);
            const dest = try addr(globals, stack, localData, upvalueData, terminatedBlockFrame.out, desiredSize);
            @memcpy(dest[0..desiredSize], src);

            if (cond == 0) {
                fiber.stack.block.ptr = terminatedBlockPtr;
            }
        },

        .br_nz_v => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const terminatedBlockOffset = operands.b;

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

            const desiredSize = terminatedBlock.output_layout.?.size;
            const src = try addr(globals, stack, localData, upvalueData, operands.y, desiredSize);
            const dest = try addr(globals, stack, localData, upvalueData, terminatedBlockFrame.out, desiredSize);
            @memcpy(dest[0..desiredSize], src);

            if (cond != 0) {
                fiber.stack.block.ptr = terminatedBlockPtr;
            }
        },

        .block => |operands| {
            const newBlockIndex = operands.b;

            if (newBlockIndex >= function.value.bytecode.blocks.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            const newBlock = &function.value.bytecode.blocks[newBlockIndex];

            if (newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            try fiber.stack.block.push(.noOutput(newBlockIndex));
        },

        .block_v => |operands| {
            const newBlockIndex = operands.b;

            if (newBlockIndex >= function.value.bytecode.blocks.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            const newBlock = &function.value.bytecode.blocks[newBlockIndex];

            if (!newBlock.kind.hasOutput()) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            try fiber.stack.block.push(.value(newBlockIndex, operands.y));
        },

        .if_nz => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const thenBlockIndex = operands.t;
            const elseBlockIndex = operands.e;

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
            if (thenBlockHasOutput | elseBlockHasOutput != 0) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            if (cond != 0) {
                try fiber.stack.block.push(.noOutput(thenBlockIndex));
            } else {
                try fiber.stack.block.push(.noOutput(elseBlockIndex));
            }
        },

        .if_nz_v => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const thenBlockIndex = operands.t;
            const elseBlockIndex = operands.e;

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
            if (thenBlockHasOutput & elseBlockHasOutput != 1) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            if (cond != 0) {
                try fiber.stack.block.push(.value(thenBlockIndex, operands.y));
            } else {
                try fiber.stack.block.push(.value(elseBlockIndex, operands.y));
            }
        },

        .if_z => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const thenBlockIndex = operands.t;
            const elseBlockIndex = operands.e;

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
            if (thenBlockHasOutput | elseBlockHasOutput != 0) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            if (cond == 0) {
                try fiber.stack.block.push(.noOutput(thenBlockIndex));
            } else {
                try fiber.stack.block.push(.noOutput(elseBlockIndex));
            }
        },

        .if_z_v => |operands| {
            const cond = try read(u8, globals, stack, localData, upvalueData, operands.x);
            const thenBlockIndex = operands.t;
            const elseBlockIndex = operands.e;

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
            if (thenBlockHasOutput & elseBlockHasOutput != 1) {
                @branchHint(.cold);
                return Fiber.Trap.OutValueMismatch;
            }

            if (cond == 0) {
                try fiber.stack.block.push(.value(thenBlockIndex, operands.y));
            } else {
                try fiber.stack.block.push(.value(elseBlockIndex, operands.y));
            }
        },

        .case => |operands| {
            const index = try read(u8, globals, stack, localData, upvalueData, operands.x);

            if (index >= operands.bs.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            // TODO: find a way to do this more efficiently
            for (operands.bs) |blockIndex| {
                const caseBlock = &function.value.bytecode.blocks[blockIndex];

                if (caseBlock.kind.hasOutput()) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            }

            const caseBlockIndex = operands.bs[index];

            try fiber.stack.block.push(.noOutput(caseBlockIndex));
        },

        .case_v => |operands| {
            const index = try read(u8, globals, stack, localData, upvalueData, operands.x);

            if (index >= operands.bs.len) {
                @branchHint(.cold);
                return Fiber.Trap.OutOfBounds;
            }

            // TODO: find a way to do this more efficiently
            for (operands.bs) |blockIndex| {
                const caseBlock = &function.value.bytecode.blocks[blockIndex];

                if (!caseBlock.kind.hasOutput()) {
                    @branchHint(.cold);
                    return Fiber.Trap.OutValueMismatch;
                }
            }

            const caseBlockIndex = operands.bs[index];

            try fiber.stack.block.push(.value(caseBlockIndex, operands.y));
        },

        .addr => |operands| {
            const bytes: [*]const u8 = try addr(globals, stack, localData, upvalueData, operands.x, 0);

            try write(globals, stack, localData, upvalueData, operands.y, bytes);
        },

        .load8 => |operands| try load(u8, globals, stack, localData, upvalueData, operands.x, operands.y),
        .load16 => |operands| try load(u16, globals, stack, localData, upvalueData, operands.x, operands.y),
        .load32 => |operands| try load(u32, globals, stack, localData, upvalueData, operands.x, operands.y),
        .load64 => |operands| try load(u64, globals, stack, localData, upvalueData, operands.x, operands.y),

        .store8 => |operands| try store(u8, globals, stack, localData, upvalueData, operands.x, operands.y),
        .store16 => |operands| try store(u16, globals, stack, localData, upvalueData, operands.x, operands.y),
        .store32 => |operands| try store(u32, globals, stack, localData, upvalueData, operands.x, operands.y),
        .store64 => |operands| try store(u64, globals, stack, localData, upvalueData, operands.x, operands.y),

        .clear8 => |operands| try clear(u8, globals, stack, localData, upvalueData, operands.x),
        .clear16 => |operands| try clear(u16, globals, stack, localData, upvalueData, operands.x),
        .clear32 => |operands| try clear(u32, globals, stack, localData, upvalueData, operands.x),
        .clear64 => |operands| try clear(u64, globals, stack, localData, upvalueData, operands.x),

        .swap8 => |operands| try swap(u8, globals, stack, localData, upvalueData, operands.x, operands.y),
        .swap16 => |operands| try swap(u16, globals, stack, localData, upvalueData, operands.x, operands.y),
        .swap32 => |operands| try swap(u32, globals, stack, localData, upvalueData, operands.x, operands.y),
        .swap64 => |operands| try swap(u64, globals, stack, localData, upvalueData, operands.x, operands.y),

        .copy8 => |operands| try copy(u8, globals, stack, localData, upvalueData, operands.x, operands.y),
        .copy16 => |operands| try copy(u16, globals, stack, localData, upvalueData, operands.x, operands.y),
        .copy32 => |operands| try copy(u32, globals, stack, localData, upvalueData, operands.x, operands.y),
        .copy64 => |operands| try copy(u64, globals, stack, localData, upvalueData, operands.x, operands.y),

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

fn registerData(fiber: *Fiber, callFrame: *Fiber.CallFrame, function: *Bytecode.Function) Fiber.Trap!struct {RegisterData, ?RegisterData} {
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

    return .{localData, upvalueData};
}

fn load(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = try read([*]const u8, globals, stack, localData, upvalueData, x);
    const outAddr: [*]u8 = try addr(globals, stack, localData, upvalueData, y, size);

    try boundsCheck(globals, stack, inAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

fn store(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const inAddr: [*]const u8 = try addr(globals, stack, localData, upvalueData, x, size);
    const outAddr: [*]u8 = try read([*]u8, globals, stack, localData, upvalueData, y);

    try boundsCheck(globals, stack, outAddr, size);

    const inAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(inAddr), alignment) == 0);
    const outAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(outAddr), alignment) == 0);
    if (inAligned & outAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(outAddr))).* = @as(*const T, @ptrCast(@alignCast(inAddr))).*;
}

fn clear(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, x: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const bytes: [*]u8 = try addr(globals, stack, localData, upvalueData, x, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), alignment) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(bytes))).* = 0;
}

fn swap(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const xBytes: [*]u8 = try addr(globals, stack, localData, upvalueData, x, size);
    const yBytes: [*]u8 = try addr(globals, stack, localData, upvalueData, y, size);

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

fn copy(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, x: Bytecode.Operand, y: Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);

    const xBytes: [*]const u8 = try addr(globals, stack, localData, upvalueData, x, size);
    const yBytes: [*]u8 = try addr(globals, stack, localData, upvalueData, y, size);

    const xAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(xBytes), alignment) == 0);
    const yAligned = @intFromBool(Support.alignmentDelta(@intFromPtr(yBytes), alignment) == 0);
    if (xAligned & yAligned != 1) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(yBytes))).* = @as(*const T, @ptrCast(@alignCast(xBytes))).*;
}

fn dynCall(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, func: Bytecode.Operand, args: []const Bytecode.Operand, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const funcIndex = try read(Bytecode.FunctionIndex, &fiber.program.globals, &fiber.stack.data, localData, upvalueData, func);

    return call(fiber, localData, upvalueData, funcIndex, args, out);
}

fn call(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, funcIndex: Bytecode.FunctionIndex, args: []const Bytecode.Operand, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (funcIndex >= fiber.program.functions.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return callImpl(fiber, localData, upvalueData, Bytecode.EVIDENCE_SENTINEL, funcIndex, args, out);
}

fn prompt(fiber: *Fiber, localData: RegisterData, upvalueData: ?RegisterData, evIndex: Bytecode.EvidenceIndex, args: []const Bytecode.Operand, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
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
    if (out) |outOperand| {
        if (newFunction.layout_table.return_layout) |returnLayout| {
            _ = try slice(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, outOperand, returnLayout.size);
        } else {
            @branchHint(.cold);
            return Fiber.Trap.OutValueMismatch;
        }
    }

    const origin = fiber.stack.data.ptr;
    const padding = Support.alignmentDelta(origin, newFunction.layout_table.alignment);
    const base = origin + padding;

    try fiber.stack.data.pushUninit(newFunction.layout_table.size + padding);

    for (0..args.len) |i| {
        const desiredSize = newFunction.layout_table.register_layouts[i].size;
        const arg = try slice(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, args[i], desiredSize);
        @memcpy(fiber.stack.data.memory[newFunction.layout_table.register_offsets[i]..].ptr, arg);
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

fn term(fiber: *Fiber, function: *Bytecode.Function, callFrame: *Fiber.CallFrame, localData: RegisterData, upvalueData: ?RegisterData, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    if (callFrame.evidence == Bytecode.EVIDENCE_SENTINEL) {
        @branchHint(.cold);
        return Fiber.Trap.MissingEvidence;
    }

    const evidence = &fiber.evidence[callFrame.evidence];

    const rootFunction = &fiber.program.functions[evidence.handler];
    const rootCallFrame = try fiber.stack.call.getPtr(evidence.call);
    const rootBlockFrame = try fiber.stack.block.getPtr(evidence.block);
    const rootBlock = &rootFunction.value.bytecode.blocks[rootBlockFrame.index];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = function.layout_table.term_layout.?.size;
            const src: [*]const u8 = try addr(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, outOp, size);

            const rootLocalData, const rootUpvalueData = try registerData(fiber, rootCallFrame, rootFunction);
            const dest: [*]u8 = try addr(&fiber.program.globals, &fiber.stack.data, rootLocalData, rootUpvalueData, rootBlockFrame.out, size);

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

fn ret(fiber: *Fiber, function: *Bytecode.Function, callFrame: *Fiber.CallFrame, localData: RegisterData, upvalueData: ?RegisterData, out: ?Bytecode.Operand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const rootBlockFrame = try fiber.stack.block.getPtr(callFrame.block);
    const rootBlock = &function.value.bytecode.blocks[rootBlockFrame.index];

    const callerFrame = try fiber.stack.call.getPtr(fiber.stack.call.ptr - 2);
    const callerFunction = &fiber.program.functions[callerFrame.function];

    if (out) |outOp| {
        if (rootBlock.kind.hasOutput()) {
            const size = function.layout_table.return_layout.?.size;
            const src: [*]const u8 = try addr(&fiber.program.globals, &fiber.stack.data, localData, upvalueData, outOp, size);

            const callerLocalData, const callerUpvalueData = try registerData(fiber, callerFrame, callerFunction);
            const dest: [*]u8 = try addr(&fiber.program.globals, &fiber.stack.data, callerLocalData, callerUpvalueData, rootBlockFrame.out, size);

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

inline fn read(comptime T: type, globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand) Fiber.Trap!T {
    switch (operand.kind) {
        .global => return readGlobal(T, globals, operand.data.global),
        .upvalue => return readReg(T, stack, try extractUp(upvalueData), operand.data.register),
        .local => return readReg(T, stack, localData, operand.data.register),
    }
}

inline fn write(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, value: anytype) Fiber.Trap!void {
    switch (operand.kind) {
        .global => return writeGlobal(globals, operand.data.global, value),
        .upvalue => return writeReg(stack, try extractUp(upvalueData), operand.data.register, value),
        .local => return writeReg(stack, localData, operand.data.register, value),
    }
}

inline fn addr(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) Fiber.Trap![*]u8 {
    switch (operand.kind) {
        .global => return addrGlobal(globals, operand.data.global, size),
        .upvalue => return addrReg(stack, try extractUp(upvalueData), operand.data.register, size),
        .local => return addrReg(stack, localData, operand.data.register, size),
    }
}

fn addrReg(stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, @truncate(size))) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(try stack.getPtr(base + operand.offset));
}

inline fn slice(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, localData: RegisterData, upvalueData: ?RegisterData, operand: Bytecode.Operand, size: Bytecode.RegisterLocalOffset) Fiber.Trap![]u8 {
    return (try addr(globals, stack, localData, upvalueData, operand, size))[0..size];
}

fn readGlobal(comptime T: type, globals: *Bytecode.GlobalSet, operand: Bytecode.GlobalOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const bytes = try addrGlobal(globals, operand, @sizeOf(T));

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

fn readReg(comptime T: type, stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!T {
    const size = @sizeOf(T);

    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = try stack.checkSlice(base + operand.offset, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    return @as(*T, @ptrCast(@alignCast(bytes))).*;
}

fn writeGlobal(globals: *Bytecode.GlobalSet, operand: Bytecode.GlobalOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const T = @TypeOf(value);
    const mem = try addrGlobal(globals, operand, @sizeOf(T));

    if (Support.alignmentDelta(@intFromPtr(mem), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(mem))).* = value;
}

fn writeReg(stack: *Fiber.DataStack, regData: RegisterData, operand: Bytecode.RegisterOperand, value: anytype) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);

    const base = try getOperandOffset(regData, operand.register);

    if (!regData.layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const bytes = try stack.checkSlice(base, size);

    if (Support.alignmentDelta(@intFromPtr(bytes), @alignOf(T)) != 0) {
        @branchHint(.cold);
        return Fiber.Trap.BadAlignment;
    }

    @as(*T, @ptrCast(@alignCast(bytes))).* = value;
}

fn addrGlobal(globals: *Bytecode.GlobalSet, operand: Bytecode.GlobalOperand, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap![*]u8 {
    if (operand.index >= globals.values.len) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    const data = &globals.values[operand.index];

    if (!data.layout.inbounds(operand.offset, size)) {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }

    return @ptrCast(&globals.memory[operand.offset]);
}

fn getOperandOffset(regData: RegisterData, register: Bytecode.Register) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!Fiber.DataStack.Ptr {
    const regNumber: Bytecode.RegisterIndex = @intFromEnum(register);

    if (regNumber < regData.layout.num_registers) {
        return regData.call.stack.base + regData.layout.register_offsets[regNumber];
    } else {
        @branchHint(.cold);
        return Fiber.Trap.OutOfBounds;
    }
}

fn boundsCheck(globals: *Bytecode.GlobalSet, stack: *Fiber.DataStack, address: [*]const u8, size: Bytecode.RegisterLocalOffset) callconv(Config.INLINING_CALL_CONV) Fiber.Trap!void {
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
