const std = @import("std");

const Support = @import("Support");

const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Core = @import("root.zig");
const Fiber = Core.Fiber;


const Eval = @This();


pub fn step(fiber: *Fiber) !void {
    const callFrame = try fiber.stack.call.topPtr();
    const function = &fiber.program.functions[callFrame.functionIndex];

    switch (function.value) {
        .bytecode => |bc| stepBytecode(fiber, callFrame, &function.layout_table, bc),
        .native => |nat| stepNative(fiber, callFrame, &function.layout_table, nat),
    }
}

pub fn stepBytecode(fiber: *Fiber, callFrame: *Fiber.CallFrame, layout: *Bytecode.LayoutTable, bytecode: Bytecode) !void {
    const blockFrame = fiber.stack.block.topPtr();
    const block = &bytecode.blocks[blockFrame.blockIndex];

    const decoder = IO.Decoder {
        .memory = bytecode.instructions,
        .base = block.base,
        .offset = &blockFrame.ip_offset,
    };

    const instr: Bytecode.Op = try decoder.decode(Bytecode.Op);

    switch (instr) {
        .nop => {},
        .trap => return Fiber.Error.Trap,
        .i_add8 => |operands| {
            const x = try read(u8, &fiber.stack.data, callFrame, layout, operands.x);
            const y = try read(u8, &fiber.stack.data, callFrame, layout, operands.y);

            const result = x + y;

            try write(&fiber.stack.data, callFrame, layout, operands.z, result);
        },
        else => Support.todo(noreturn, {})
    }
}

pub fn stepNative(fiber: *Fiber, callFrame: *Fiber.CallFrame, layout: *Bytecode.LayoutTable, native: Bytecode.Function.Native) !void {
    Support.todo(noreturn, .{fiber, callFrame, layout, native});
}

pub inline fn read(comptime T: type, stack: *Fiber.DataStack, callFrame: *Fiber.CallFrame, layout: *Bytecode.LayoutTable, operand: Bytecode.Operand) !T {
    const size = @sizeOf(T);
    const base = try getRegisterOffset(callFrame, layout, operand.register);

    if (!layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Error.OutOfBounds;
    }

    const data = try stack.getSlice(base + operand.offset, size);

    const value: T = undefined;
    @memcpy(@as([*]u8, @ptrCast(&value)), data);

    return value;
}

pub inline fn write(stack: *Fiber.DataStack, callFrame: *Fiber.CallFrame, layout: *Bytecode.LayoutTable, operand: Bytecode.Operand, value: anytype) !void {
    const T = @TypeOf(value);
    const size = @sizeOf(T);
    const base = try getRegisterOffset(callFrame, layout, operand.register);

    if (!layout.inbounds(operand, size)) {
        @branchHint(.cold);
        return Fiber.Error.OutOfBounds;
    }

    const data = @as([*]u8, @ptrCast(&value))[0..size];

    try stack.setSlice(base + operand.offset, data);
}

pub inline fn getRegisterOffset(callFrame: *Fiber.CallFrame, layout: *Bytecode.LayoutTable, register: Bytecode.Register) !Fiber.DataStack.Ptr {
    var regNumber: Bytecode.RegisterIndex = @intFromEnum(register);
    if (regNumber < layout.num_params) {
        return callFrame.stack.origin + callFrame.argument_offsets[regNumber];
    } else {
        regNumber -= layout.num_params;

        if (regNumber < layout.num_locals) {
            return callFrame.stack.base + layout.local_offsets[regNumber];
        } else {
            @branchHint(.cold);

            return Fiber.Error.OutOfBounds;
        }
    }
}
