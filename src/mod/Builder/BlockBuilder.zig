const std = @import("std");

const Support = @import("Support");
const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Builder = @import("root.zig");
const Error = Builder.Error;
const FunctionBuilder = Builder.FunctionBuilder;

const BlockBuilder = @This();


function: *FunctionBuilder,
parent: ?Bytecode.BlockIndex,
index: Bytecode.BlockIndex,
kind: Kind,
ops: Builder.OpList,
exit: ?Bytecode.Op,


pub const Kind = union(enum) {
     basic: void, basic_v: Bytecode.TypeIndex,
      with: With,  with_v: WithV,
     entry: void, entry_v: Bytecode.TypeIndex,

    pub const With = struct {
        handler_set: Bytecode.HandlerSetIndex,
    };

    pub const WithV = struct {
        handler_set: Bytecode.HandlerSetIndex,
        type: Bytecode.TypeIndex,
    };

    pub fn getType(self: BlockBuilder.Kind) ?Bytecode.TypeIndex {
        return switch (self) {
             .basic => null, .basic_v => |t| t,
              .with => null,  .with_v => |w| w.type,
             .entry => null, .entry_v => |t| t,
        };
    }

    pub fn getHandlerSet(self: BlockBuilder.Kind) ?Bytecode.HandlerSetIndex {
        return switch (self) {
             .basic => null,              .basic_v => null,
              .with => |w| w.handler_set,  .with_v => |w| w.handler_set,
             .entry => null,              .entry_v => null,
        };
    }

    pub fn bytecodeKind(self: BlockBuilder.Kind) Bytecode.Block.Kind {
        return switch (self) {
             .basic => .basic, .basic_v => .basic_v,
              .with => .with,  .with_v => .with_v,
             .entry => .entry, .entry_v => .entry_v,
        };
    }

    pub fn assemble(self: BlockBuilder.Kind) struct {Bytecode.Block.Kind, ?Bytecode.TypeIndex, ?Bytecode.HandlerSetIndex} {
        return .{
            self.bytecodeKind(),
            self.getType(),
            self.getHandlerSet(),
        };
    }
};

/// for use by the FunctionBuilder only
pub fn init(func: *FunctionBuilder, parent: ?Bytecode.BlockIndex, index: Bytecode.BlockIndex, kind: Kind) std.mem.Allocator.Error!*BlockBuilder {
    const ptr = try func.parent.allocator.create(BlockBuilder);

    var ops = Builder.OpList {};
    try ops.ensureTotalCapacity(func.parent.allocator, 256);

    ptr.* = BlockBuilder {
        .function = func,
        .parent = parent,
        .index = index,
        .kind = kind,
        .ops = ops,
        .exit = null,
    };

    return ptr;
}

pub fn exited(self: *const BlockBuilder) bool {
    return self.exit != null;
}



pub fn assemble(self: *const BlockBuilder, encoder: *IO.Encoder, allocator: std.mem.Allocator) Error!Bytecode.Block {
    const exit = self.exit orelse return Error.UnfinishedBlock;

    const start = encoder.len();

    if (start >= Bytecode.MAX_INSTRUCTIONS) return Error.TooManyInstructions;

    for (self.ops.items) |x| {
        try encoder.encode(allocator, x);
    }

    try encoder.encode(allocator, exit);

    const end = encoder.len();
    if (end > Bytecode.MAX_INSTRUCTIONS) return Error.TooManyInstructions;

    const size = end - start;

    if (size > Bytecode.MAX_INSTRUCTION_OFFSET) return Error.TooManyInstructions;

    const kind, const typeIndex, const handlers = self.kind.assemble();

    const layout = if (typeIndex) |t| try self.function.parent.getTypeLayout(t) else null;

    return .{
        .kind = kind,
        .base = @truncate(start),
        .size = @truncate(size),
        .handlers = handlers orelse Bytecode.HANDLER_SET_SENTINEL,
        .output_layout = layout,
    };
}

pub fn op(self: *BlockBuilder, x: Bytecode.Op) Error!void {
    if (self.exited()) return Error.InstructionsAfterExit;
    try self.ops.append(self.function.parent.allocator, x);
}

fn exitOp(self: *BlockBuilder, x: Bytecode.Op) Error!void {
    if (self.exited()) return Error.MultipleExits;
    self.exit = x;
}

pub fn typecheckEvidence(self: *const BlockBuilder, e: Bytecode.EvidenceIndex) Error!void {
    if (self.kind.getHandlerSet()) |handlerSetIndex| {
        const handlerSet = try self.function.parent.getHandlerSet(handlerSetIndex);
        if (handlerSet.containsEvidence(e)) {
            return;
        }
    }

    if (self.parent) |parentIndex| {
        const parent = try self.function.getBlock(parentIndex);

        return parent.typecheckEvidence(e);
    }

    return self.function.typecheckEvidence(e);
}

pub fn typecheckEvidenceSet(self: *const BlockBuilder, es: []const Bytecode.EvidenceIndex) Error!void {
    for (es) |e| try self.typecheckEvidence(e);
}

pub fn typecheckCall(self: *const BlockBuilder, calleeTypeIndex: Bytecode.TypeIndex, r: ?Bytecode.Operand, as: anytype) Error!void {
    try self.function.typecheckCall(calleeTypeIndex, r, as);
    const calleeType = try self.function.parent.getType(calleeTypeIndex);
    return self.typecheckEvidenceSet(calleeType.function.evidence);
}

pub fn typecheckBr(self: *const BlockBuilder, absoluteBlockIndex: Bytecode.BlockIndex, y: ?Bytecode.Operand) Error!void {
    if (absoluteBlockIndex == self.index) {
        if (self.kind.getType()) |expectedType| {
            if (y) |operand| {
                return self.function.typecheck(expectedType, operand);
            } else {
                return Error.TypeError;
            }
        } else if (y != null) {
            return Error.TypeError;
        }
    }
}


pub fn findRelativeBlockIndex(self: *const BlockBuilder, absoluteBlockIndex: Bytecode.BlockIndex) Error!Bytecode.BlockIndex {
    if (self.index == absoluteBlockIndex) {
        return 0;
    }

    if (self.parent) |p| {
        if (p == absoluteBlockIndex) {
            return 1;
        }

        const parent = try self.function.getBlock(p);
        return 1 + try findRelativeBlockIndex(parent, absoluteBlockIndex);
    }

    return Error.InvalidIndex;
}

pub fn extractBlockIndex(self: *const BlockBuilder, b: anytype) Bytecode.BlockIndex {
    switch (@TypeOf(b)) {
        BlockBuilder => return self.extractBlockIndex(&b),
        *BlockBuilder => return self.extractBlockIndex(@as(*const BlockBuilder, b)),
        *const BlockBuilder => {
            if (b.function != self.function) {
                return Error.InvalidIndex;
            }
            return self.extractBlockIndex(b.index);
        },

        *Bytecode.BlockIndex => return self.extractBlockIndex(b.*),
        Bytecode.BlockIndex => return b,

        else => @compileError(std.fmt.comptimePrint(
            "invalid block index parameter, expected either `Bytecode.BlockIndex` or `*Builder.BlockBuilder`, got `{s}`",
            .{@typeName(@TypeOf(b))}
        )),
    }
}







pub fn trap(self: *BlockBuilder) Error!void { try self.exitOp(.trap); }
pub fn nop(self: *BlockBuilder) Error!void { try self.op(.nop); }
pub fn halt(self: *BlockBuilder) Error!void { try self.exitOp(.halt); }

pub fn tail_call(self: *BlockBuilder, f: anytype, as: anytype) Error!void {
    const calleeIndex = try self.function.parent.extractFunctionIndex(f);
    const calleeType = try self.function.parent.getFunctionType(calleeIndex);

    try self.typecheckCall(calleeType, null, as);

    const asBuf = try self.parent.allocator.alloc(Bytecode.Op, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.exitOp(.{.tail_call = .{ .f = calleeIndex, .as = asBuf }});
}

pub fn tail_call_v(self: *BlockBuilder, f: anytype, y: Bytecode.Operand, as: anytype) Error!void {
    const calleeIndex = try self.function.parent.extractFunctionIndex(f);
    const calleeType = try self.function.parent.getFunctionType(calleeIndex);

    try self.typecheckCall(calleeType, y, as);

    const asBuf = try self.parent.allocator.alloc(Bytecode.Op, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.exitOp(.{.tail_call = .{ .f = calleeIndex, .y = y, .as = asBuf }});
}

pub fn dyn_tail_call(self: *BlockBuilder, f: Bytecode.Operand, as: anytype) Error!void {
    const calleeType = try self.function.getOperandType(f);

    try self.typecheckCall(calleeType, null, as);

    const asBuf = try self.parent.allocator.alloc(Bytecode.Op, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.exitOp(.{.tail_call = .{ .f = f, .as = asBuf }});
}

pub fn dyn_tail_call_v(self: *BlockBuilder, f: Bytecode.Operand, y: Bytecode.Operand, as: anytype) Error!void {
    const calleeType = try self.function.getOperandType(f);

    try self.typecheckCall(calleeType, y, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.exitOp(.{.tail_call = .{ .f = f, .y = y, .as = asBuf }});
}

pub fn tail_prompt(self: *BlockBuilder, e: Bytecode.EvidenceIndex, as: anytype) Error!void {
    const calleeType = try self.function.parent.getEvidenceType(e);

    try self.typecheckCall(calleeType, null, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.exitOp(.{.tail_prompt = .{ .e = e, .as = asBuf }});
}

pub fn tail_prompt_v(self: *BlockBuilder, e: Bytecode.EvidenceIndex, y: Bytecode.Operand, as: anytype) Error!void {
    const calleeType = try self.function.parent.getEvidenceType(e);

    try self.typecheckCall(calleeType, y, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.exitOp(.{.tail_prompt_v = .{ .e = e, .as = asBuf, .y = y }});
}

pub fn call(self: *BlockBuilder, f: anytype, as: anytype) Error!void {
    const calleeIndex = try self.function.parent.extractFunctionIndex(f);
    const calleeType = try self.function.parent.getFunctionType(calleeIndex);

    try self.typecheckCall(calleeType, null, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.op(.{.call = .{ .f = calleeIndex, .as = asBuf }});
}

pub fn call_v(self: *BlockBuilder, f: anytype, y: Bytecode.Operand, as: anytype) Error!void {
    const calleeIndex = try self.function.parent.extractFunctionIndex(f);
    const calleeType = try self.function.parent.getFunctionType(calleeIndex);

    try self.typecheckCall(calleeType, y, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.op(.{.call_v = .{ .f = calleeIndex, .as = asBuf, .y = y }});
}

pub fn dyn_call(self: *BlockBuilder, f: Bytecode.Operand, as: anytype) Error!void {
    const calleeType = try self.function.getOperandType(f);

    try self.typecheckCall(calleeType, null, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.op(.{.dyn_call = .{ .f = f, .as = asBuf }});
}

pub fn dyn_call_v(self: *BlockBuilder, f: Bytecode.Operand, y: Bytecode.Operand, as: anytype) Error!void {
    const calleeType = try self.function.getOperandType(f);

    try self.typecheckCall(calleeType, y, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.op(.{.dyn_call_v = .{ .f = f, .as = asBuf, .y = y }});
}

pub fn prompt(self: *BlockBuilder, e: Bytecode.EvidenceIndex, as: anytype) Error!void {
    const calleeType = try self.function.parent.getEvidenceType(e);

    try self.typecheckCall(calleeType, null, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.op(.{.prompt = .{ .e = e, .as = asBuf }});
}

pub fn prompt_v(self: *BlockBuilder, e: Bytecode.EvidenceIndex, y: Bytecode.Operand, as: anytype) Error!void {
    const calleeType = try self.function.parent.getEvidenceType(e);

    try self.typecheckCall(calleeType, y, as);

    const asBuf = try self.function.parent.allocator.alloc(Bytecode.Operand, as.len);
    inline for (0..as.len) |i| asBuf[i] = as[i];

    try self.op(.{.prompt_v = .{ .e = e, .as = asBuf, .y = y }});
}

pub fn ret(self: *BlockBuilder) Error!void {
    try self.function.typecheckRet(null);

    try self.exitOp(.ret);
}
pub fn ret_v(self: *BlockBuilder, y: Bytecode.Operand) Error!void {
    try self.function.typecheckRet(y);

    try self.exitOp(.{.ret_v = .{ .y = y }});
}

pub fn term(self: *BlockBuilder) Error!void {
    try self.function.typecheckTerm(null);

    try self.exitOp(.term);
}
pub fn term_v(self: *BlockBuilder, y: Bytecode.Operand) Error!void {
    try self.function.typecheckTerm(y);

    try self.exitOp(.{.term_v = .{ .y = y }});
}

pub fn when_z(self: *BlockBuilder, x: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const newBlock = try self.function.newBlock(self.index, .basic);

    try self.op(.{.when_z = .{ .b = newBlock.index, .x = x }});
}
pub fn when_nz(self: *BlockBuilder, x: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const newBlock = try self.function.newBlock(self.index, .basic);

    try self.op(.{.when_nz = .{ .b = newBlock.index, .x = x }});
}

pub fn re(self: *BlockBuilder, b: anytype) Error!void {
    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);

    try self.exitOp(.{.re = .{ .b = relativeBlockIndex }});
}
pub fn re_z(self: *BlockBuilder, b: anytype, x: Bytecode.Operand) Error!void {
    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    try self.exitOp(.{.re_z = .{ .b = relativeBlockIndex, .x = x }});
}
pub fn re_nz(self: *BlockBuilder, b: anytype, x: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);

    try self.exitOp(.{.re_nz = .{ .b = relativeBlockIndex, .x = x }});
}

pub fn br(self: *BlockBuilder, b: anytype) Error!void {
    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);

    try self.exitOp(.{.br = .{ .b = relativeBlockIndex }});
}
pub fn br_z(self: *BlockBuilder, b: anytype, x: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);

    try self.exitOp(.{.br_z = .{ .b = relativeBlockIndex, .x = x }});
}
pub fn br_nz(self: *BlockBuilder, b: anytype, x: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);

    try self.exitOp(.{.br_nz = .{ .b = relativeBlockIndex, .x = x }});
}

pub fn br_v(self: *BlockBuilder, b: anytype, y: Bytecode.Operand) Error!void {
    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);

    try self.exitOp(.{.br_v = .{ .b = relativeBlockIndex, .y = y }});
}
pub fn br_z_v(self: *BlockBuilder, b: anytype, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    try self.exitOp(.{.br_z_v = .{ .b = relativeBlockIndex, .x = x, .y = y }});
}
pub fn br_nz_v(self: *BlockBuilder, b: anytype, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const absoluteBlockIndex = try self.extractBlockIndex(b);
    const relativeBlockIndex = try self.findRelativeBlockIndex(absoluteBlockIndex);

    try self.typecheckBr(absoluteBlockIndex, null);
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    try self.exitOp(.{.br_nz_v = .{ .b = relativeBlockIndex, .x = x, .y = y }});
}

pub fn block(self: *BlockBuilder) Error!*BlockBuilder {
    const newBlock = try self.function.newBlock(self.index, .basic);

    try self.op(.{.block = .{ .b = newBlock.index }});

    return newBlock;
}
pub fn block_v(self: *BlockBuilder, y: Bytecode.Operand) Error!*BlockBuilder {
    const operandType = try self.function.getOperandType(y);
    const newBlock = try self.function.newBlock(self.index, .{.basic_v = operandType});

    try self.op(.{.block_v = .{ .b = newBlock.index, .y = y }});

    return newBlock;
}

pub fn with(self: *BlockBuilder, h: anytype) Error!*BlockBuilder {
    const handlerSetIndex = self.function.parent.extractHandlerSetIndex(h);
    const newBlock = try self.function.newBlock(self.index, .{.with = .{ .handler_set = handlerSetIndex }});

    try self.op(.{.with = .{ .b = newBlock.index, .h = handlerSetIndex }});
}
pub fn with_v(self: *BlockBuilder, h: anytype, y: Bytecode.Operand) Error!void {
    const handlerSetIndex = try self.function.parent.extractHandlerSet(h);
    const operandType = try self.function.getOperandType(y);
    const newBlock = try self.function.newBlock(self.index, .{.with_v = .{ .handler_set = handlerSetIndex, .type = operandType }});

    try self.op(.{.with_v = .{ .b = newBlock.index, .h = handlerSetIndex, .y = y }});
}

pub fn if_z(self: *BlockBuilder, x: Bytecode.Operand) Error!struct { *BlockBuilder, *BlockBuilder } {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const thenBlock = try self.function.newBlock(self.index, .basic);
    const elseBlock = try self.function.newBlock(self.index, .basic);

    try self.op(.{.if_z = .{ .t = thenBlock.index, .e = elseBlock.index, .x = x }});

    return .{ thenBlock, elseBlock };
}
pub fn if_nz(self: *BlockBuilder, x: Bytecode.Operand) Error!struct { *BlockBuilder, *BlockBuilder } {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const thenBlock = try self.function.newBlock(self.index, .basic);
    const elseBlock = try self.function.newBlock(self.index, .basic);

    try self.op(.{.if_nz = .{ .t = thenBlock.index, .e = elseBlock.index, .x = x }});

    return .{ thenBlock, elseBlock };
}
pub fn if_z_v(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!struct { *BlockBuilder, *BlockBuilder } {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const operandType = try self.function.getOperandType(y);
    const thenBlock = try self.function.newBlock(self.index, .{ .basic_v = operandType });
    const elseBlock = try self.function.newBlock(self.index, .{ .basic_v = operandType });

    try self.op(.{.if_z_v = .{ .t = thenBlock.index, .e = elseBlock.index, .x = x, .y = y }});

    return .{ thenBlock, elseBlock };
}
pub fn if_nz_v(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!struct { *BlockBuilder, *BlockBuilder } {
    try self.function.typecheck(Bytecode.Type.bool_t, x);

    const operandType = try self.function.getOperandType(y);
    const thenBlock = try self.function.newBlock(self.index, .{ .basic_v = operandType });
    const elseBlock = try self.function.newBlock(self.index, .{ .basic_v = operandType });

    try self.op(.{.if_nz_v = .{ .t = thenBlock.index, .e = elseBlock.index, .x = x, .y = y }});

    return .{ thenBlock, elseBlock };
}

pub fn addr(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const xType = try self.function.getOperandType(x);
    const pType = try self.function.parent.typeId(.{ .pointer = .{ .target = xType }});

    try self.function.typecheck(pType, y);

    try self.op(.{.addr = .{ .x = x, .y = y }});
}

pub fn load(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const yType = try self.function.getOperandType(x);
    const pType = try self.function.parent.typeId(.{ .pointer = .{ .target = yType }});

    try self.function.typecheck(pType, x);

    switch (bit_width) {
        .i8 => try self.op(.{.load8 = .{ .x = x, .y = y }}),
        .i16 => try self.op(.{.load16 = .{ .x = x, .y = y }}),
        .i32 => try self.op(.{.load32 = .{ .x = x, .y = y }}),
        .i64 => try self.op(.{.load64 = .{ .x = x, .y = y }}),
    }
}

pub fn load8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.load(.i8, x, y); }
pub fn load16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.load(.i16, x, y); }
pub fn load32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.load(.i32, x, y); }
pub fn load64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.load(.i64, x, y); }

pub fn store(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const xType = try self.function.getOperandType(x);
    const pType = try self.function.parent.typeId(.{ .pointer = .{ .target = xType }});

    try self.function.typecheck(pType, y);

    switch (bit_width) {
        .i8 => try self.op(.{.store8 = .{ .x = x, .y = y }}),
        .i16 => try self.op(.{.store16 = .{ .x = x, .y = y }}),
        .i32 => try self.op(.{.store32 = .{ .x = x, .y = y }}),
        .i64 => try self.op(.{.store64 = .{ .x = x, .y = y }}),
    }
}

pub fn store8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.store(.i8, x, y); }
pub fn store16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.store(.i16, x, y); }
pub fn store32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.store(.i32, x, y); }
pub fn store64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.store(.i64, x, y); }

pub fn clear(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand) Error!void {
    const xType = try self.function.getOperandType(x);
    const xLayout = try self.function.parent.getTypeLayout(xType);

    switch (bit_width) {
        .i8 => {
            if (xLayout.size < 1) return Error.TypeError;
            try self.op(.{.clear8 = .{ .x = x }});
        },
        .i16 => {
            if (xLayout.size < 2) return Error.TypeError;
            try self.op(.{.clear16 = .{ .x = x }});
        },
        .i32 => {
            if (xLayout.size < 4) return Error.TypeError;
            try self.op(.{.clear32 = .{ .x = x }});
        },
        .i64 => {
            if (xLayout.size < 8) return Error.TypeError;
            try self.op(.{.clear64 = .{ .x = x }});
        },
    }
}

pub fn clear8(self: *BlockBuilder, x: Bytecode.Operand) Error!void { try self.clear(.i8, x); }
pub fn clear16(self: *BlockBuilder, x: Bytecode.Operand) Error!void { try self.clear(.i16, x); }
pub fn clear32(self: *BlockBuilder, x: Bytecode.Operand) Error!void { try self.clear(.i32, x); }
pub fn clear64(self: *BlockBuilder, x: Bytecode.Operand) Error!void { try self.clear(.i64, x); }

pub fn swap(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const xType = try self.function.getOperandType(x);
    try self.function.typecheck(xType, y);

    const xLayout = try self.function.parent.getTypeLayout(xType);

    switch (bit_width) {
        .i8 => {
            if (xLayout.size < 1) return Error.TypeError;
            try self.op(.{.swap8 = .{ .x = x, .y = y }});
        },
        .i16 => {
            if (xLayout.size < 2) return Error.TypeError;
            try self.op(.{.swap16 = .{ .x = x, .y = y }});
        },
        .i32 => {
            if (xLayout.size < 4) return Error.TypeError;
            try self.op(.{.swap32 = .{ .x = x, .y = y }});
        },
        .i64 => {
            if (xLayout.size < 8) return Error.TypeError;
            try self.op(.{.swap64 = .{ .x = x, .y = y }});
        },
    }
}

pub fn swap8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.swap(.i8, x, y); }
pub fn swap16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.swap(.i16, x, y); }
pub fn swap32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.swap(.i32, x, y); }
pub fn swap64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.swap(.i64, x, y); }

pub fn copy(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const xType = try self.function.getOperandType(x);
    try self.function.typecheck(xType, y);

    const xLayout = try self.function.parent.getTypeLayout(xType);

    switch (bit_width) {
        .i8 => {
            if (xLayout.size < 1) return Error.TypeError;
            try self.op(.{.copy8 = .{ .x = x, .y = y }});
        },
        .i16 => {
            if (xLayout.size < 2) return Error.TypeError;
            try self.op(.{.copy16 = .{ .x = x, .y = y }});
        },
        .i32 => {
            if (xLayout.size < 4) return Error.TypeError;
            try self.op(.{.copy32 = .{ .x = x, .y = y }});
        },
        .i64 => {
            if (xLayout.size < 8) return Error.TypeError;
            try self.op(.{.copy64 = .{ .x = x, .y = y }});
        },
    }
}

pub fn copy8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.copy(.i8, x, y); }
pub fn copy16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.copy(.i16, x, y); }
pub fn copy32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.copy(.i32, x, y); }
pub fn copy64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.copy(.i64, x, y); }

pub fn b_not(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);
    try self.function.typecheck(Bytecode.Type.bool_t, y);

    try self.op(.{.b_not = .{ .x = x, .y = y }});
}
pub fn b_and(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);
    try self.function.typecheck(Bytecode.Type.bool_t, y);

    try self.op(.{.b_and = .{ .x = x, .y = y, .z = z }});
}
pub fn b_or(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.bool_t, x);
    try self.function.typecheck(Bytecode.Type.bool_t, y);

    try self.op(.{.b_or = .{ .x = x, .y = y, .z = z }});
}

pub fn f_add(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_add32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_add64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_add32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_add(.f32, x, y, z); }
pub fn f_add64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_add(.f64, x, y, z); }

pub fn f_sub(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_sub32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_sub64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_sub32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_sub(.f32, x, y, z); }
pub fn f_sub64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_sub(.f64, x, y, z); }

pub fn f_mul(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_mul32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_mul64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_mul32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_mul(.f32, x, y, z); }
pub fn f_mul64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_mul(.f64, x, y, z); }

pub fn f_div(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_div32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_div64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_div32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_div(.f32, x, y, z); }
pub fn f_div64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_div(.f64, x, y, z); }

pub fn f_rem(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_rem32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_rem64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_rem32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_rem(.f32, x, y, z); }
pub fn f_rem64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_rem(.f64, x, y, z); }

pub fn f_neg(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);

    switch (bit_width) {
        .f32 => try self.op(.{.f_neg32 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f_neg64 = .{ .x = x, .y = y }}),
    }
}

pub fn f_neg32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.f_neg(.f32, x, y); }
pub fn f_neg64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.f_neg(.f64, x, y); }

pub fn f_eq(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_eq32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_eq64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_eq32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_eq(.f32, x, y, z); }
pub fn f_eq64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_eq(.f64, x, y, z); }

pub fn f_ne(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_ne32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_ne64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_ne32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_ne(.f32, x, y, z); }
pub fn f_ne64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_ne(.f64, x, y, z); }

pub fn f_lt(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_lt32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_lt64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_lt32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_lt(.f32, x, y, z); }
pub fn f_lt64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_lt(.f64, x, y, z); }

pub fn f_gt(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_gt32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_gt64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_gt32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_gt(.f32, x, y, z); }
pub fn f_gt64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_gt(.f64, x, y, z); }

pub fn f_le(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_le32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_le64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_le32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_le(.f32, x, y, z); }
pub fn f_le64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_le(.f64, x, y, z); }

pub fn f_ge(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.f32 => Bytecode.Type.f32_t, .f64 => Bytecode.Type.f64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .f32 => try self.op(.{.f_ge32 = .{ .x = x, .y = y, .z = z }}),
        .f64 => try self.op(.{.f_ge64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn f_ge32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_ge(.f32, x, y, z); }
pub fn f_ge64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.f_ge(.f64, x, y, z); }

pub fn i_add(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_add8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_add16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_add32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_add64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_add8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_add(.i8, x, y, z); }
pub fn i_add16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_add(.i16, x, y, z); }
pub fn i_add32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_add(.i32, x, y, z); }
pub fn i_add64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_add(.i64, x, y, z); }

pub fn i_sub(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_sub8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_sub16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_sub32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_sub64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_sub8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_sub(.i8, x, y, z); }
pub fn i_sub16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_sub(.i16, x, y, z); }
pub fn i_sub32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_sub(.i32, x, y, z); }
pub fn i_sub64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_sub(.i64, x, y, z); }

pub fn i_mul(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_mul8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_mul32 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_mul16 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_mul64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_mul8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_mul(.i8, x, y, z); }
pub fn i_mul16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_mul(.i16, x, y, z); }
pub fn i_mul32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_mul(.i32, x, y, z); }
pub fn i_mul64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_mul(.i64, x, y, z); }

pub fn i_div(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_div(bit_width, x, y, z);
    } else {
        try self.u_div(bit_width, x, y, z);
    }
}

pub fn s_div(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_div8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_div16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_div32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_div64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_div8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_div(.i8, x, y, z); }
pub fn s_div16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_div(.i16, x, y, z); }
pub fn s_div32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_div(.i32, x, y, z); }
pub fn s_div64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_div(.i64, x, y, z); }

pub fn u_div(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_div8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_div16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_div32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_div64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_div8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_div(.i8, x, y, z); }
pub fn u_div16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_div(.i16, x, y, z); }
pub fn u_div32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_div(.i32, x, y, z); }
pub fn u_div64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_div(.i64, x, y, z); }

pub fn i_rem(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_rem(bit_width, x, y, z);
    } else {
        try self.u_rem(bit_width, x, y, z);
    }
}

pub fn s_rem(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_rem8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_rem16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_rem32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_rem64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_rem8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_rem(.i8, x, y, z); }
pub fn s_rem16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_rem(.i16, x, y, z); }
pub fn s_rem32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_rem(.i32, x, y, z); }
pub fn s_rem64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_rem(.i64, x, y, z); }

pub fn u_rem(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_rem8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_rem16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_rem32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_rem64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_rem8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_rem(.i8, x, y, z); }
pub fn u_rem16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_rem(.i16, x, y, z); }
pub fn u_rem32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_rem(.i32, x, y, z); }
pub fn u_rem64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_rem(.i64, x, y, z); }

pub fn s_neg(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);

    switch (bit_width) {
        .i8 => try self.op(.{.s_neg8 = .{ .x = x, .y = y }}),
        .i16 => try self.op(.{.s_neg16 = .{ .x = x, .y = y }}),
        .i32 => try self.op(.{.s_neg32 = .{ .x = x, .y = y }}),
        .i64 => try self.op(.{.s_neg64 = .{ .x = x, .y = y }}),
    }
}

pub fn s_neg8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.s_neg(.i8, x, y); }
pub fn s_neg16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.s_neg(.i16, x, y); }
pub fn s_neg32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.s_neg(.i32, x, y); }
pub fn s_neg64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.s_neg(.i64, x, y); }

pub fn i_bitnot(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);

    switch (bit_width) {
        .i8 => try self.op(.{.i_bitnot8 = .{ .x = x, .y = y }}),
        .i16 => try self.op(.{.i_bitnot16 = .{ .x = x, .y = y }}),
        .i32 => try self.op(.{.i_bitnot32 = .{ .x = x, .y = y }}),
        .i64 => try self.op(.{.i_bitnot64 = .{ .x = x, .y = y }}),
    }
}

pub fn i_bitnot8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.i_bitnot(.i8, x, y); }
pub fn i_bitnot16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.i_bitnot(.i16, x, y); }
pub fn i_bitnot32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.i_bitnot(.i32, x, y); }
pub fn i_bitnot64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { try self.i_bitnot(.i64, x, y); }

pub fn i_bitand(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_bitand8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_bitand16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_bitand32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_bitand64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_bitand8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitand(.i8, x, y, z); }
pub fn i_bitand16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitand(.i16, x, y, z); }
pub fn i_bitand32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitand(.i32, x, y, z); }
pub fn i_bitand64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitand(.i64, x, y, z); }

pub fn i_bitor(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_bitor8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_bitor16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_bitor32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_bitor64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_bitor8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitor(.i8, x, y, z); }
pub fn i_bitor16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitor(.i16, x, y, z); }
pub fn i_bitor32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitor(.i32, x, y, z); }
pub fn i_bitor64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitor(.i64, x, y, z); }

pub fn i_bitxor(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_bitxor8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_bitxor16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_bitxor32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_bitxor64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_bitxor8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitxor(.i8, x, y, z); }
pub fn i_bitxor16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitxor(.i16, x, y, z); }
pub fn i_bitxor32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitxor(.i32, x, y, z); }
pub fn i_bitxor64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_bitxor(.i64, x, y, z); }

pub fn i_shiftl(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_shiftl8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_shiftl16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_shiftl32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_shiftl64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_shiftl8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_shiftl(.i8, x, y, z); }
pub fn i_shiftl16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_shiftl(.i16, x, y, z); }
pub fn i_shiftl32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_shiftl(.i32, x, y, z); }
pub fn i_shiftl64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_shiftl(.i64, x, y, z); }

pub fn i_shiftr(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_shiftr(bit_width, x, y, z);
    } else {
        try self.u_shiftr(bit_width, x, y, z);
    }
}

pub fn u_shiftr(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_shiftr8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_shiftr16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_shiftr32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_shiftr64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_shiftr8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_shiftr(.i8, x, y, z); }
pub fn u_shiftr16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_shiftr(.i16, x, y, z); }
pub fn u_shiftr32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_shiftr(.i32, x, y, z); }
pub fn u_shiftr64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_shiftr(.i64, x, y, z); }

pub fn s_shiftr(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_shiftr8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_shiftr16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_shiftr32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_shiftr64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_shiftr8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_shiftr(.i8, x, y, z); }
pub fn s_shiftr16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_shiftr(.i16, x, y, z); }
pub fn s_shiftr32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_shiftr(.i32, x, y, z); }
pub fn s_shiftr64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_shiftr(.i64, x, y, z); }

pub fn i_eq(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_eq8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_eq16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_eq32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_eq64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_eq8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_eq(.i8, x, y, z); }
pub fn i_eq16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_eq(.i16, x, y, z); }
pub fn i_eq32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_eq(.i32, x, y, z); }
pub fn i_eq64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_eq(.i64, x, y, z); }

pub fn i_ne(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .i8 => try self.op(.{.i_ne8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.i_ne16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.i_ne32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.i_ne64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn i_ne8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_ne(.i8, x, y, z); }
pub fn i_ne16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_ne(.i16, x, y, z); }
pub fn i_ne32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_ne(.i32, x, y, z); }
pub fn i_ne64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.i_ne(.i64, x, y, z); }

pub fn i_lt(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_lt(bit_width, x, y, z);
    } else {
        try self.u_lt(bit_width, x, y, z);
    }
}

pub fn u_lt(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_lt8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_lt16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_lt32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_lt64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_lt8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_lt(.i8, x, y, z); }
pub fn u_lt16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_lt(.i16, x, y, z); }
pub fn u_lt32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_lt(.i32, x, y, z); }
pub fn u_lt64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_lt(.i64, x, y, z); }

pub fn s_lt(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_lt8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_lt16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_lt32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_lt64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_lt8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_lt(.i8, x, y, z); }
pub fn s_lt16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_lt(.i16, x, y, z); }
pub fn s_lt32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_lt(.i32, x, y, z); }
pub fn s_lt64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_lt(.i64, x, y, z); }

pub fn i_gt(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    if (is_signed) {
        try self.s_gt(bit_width, x, y, z);
    } else {
        try self.u_gt(bit_width, x, y, z);
    }
}

pub fn u_gt(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_gt8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_gt16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_gt32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_gt64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_gt8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_gt(.i8, x, y, z); }
pub fn u_gt16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_gt(.i16, x, y, z); }
pub fn u_gt32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_gt(.i32, x, y, z); }
pub fn u_gt64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_gt(.i64, x, y, z); }

pub fn s_gt(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(Bytecode.Type.bool_t, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_gt8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_gt16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_gt32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_gt64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_gt8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_gt(.i8, x, y, z); }
pub fn s_gt16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_gt(.i16, x, y, z); }
pub fn s_gt32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_gt(.i32, x, y, z); }
pub fn s_gt64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_gt(.i64, x, y, z); }

pub fn i_le(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_le(bit_width, x, y, z);
    } else {
        try self.u_le(bit_width, x, y, z);
    }
}

pub fn u_le(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_le8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_le16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_le32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_le64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_le8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_le(.i8, x, y, z); }
pub fn u_le16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_le(.i16, x, y, z); }
pub fn u_le32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_le(.i32, x, y, z); }
pub fn u_le64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_le(.i64, x, y, z); }

pub fn s_le(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_le8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_le16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_le32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_le64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_le8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_le(.i8, x, y, z); }
pub fn s_le16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_le(.i16, x, y, z); }
pub fn s_le32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_le(.i32, x, y, z); }
pub fn s_le64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_le(.i64, x, y, z); }

pub fn i_ge(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_ge(bit_width, x, y, z);
    } else {
        try self.u_ge(bit_width, x, y, z);
    }
}

pub fn u_ge(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.u_ge8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.u_ge16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.u_ge32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.u_ge64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn u_ge8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_ge(.i8, x, y, z); }
pub fn u_ge16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_ge(.i16, x, y, z); }
pub fn u_ge32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_ge(.i32, x, y, z); }
pub fn u_ge64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.u_ge(.i64, x, y, z); }

pub fn s_ge(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void {
    const expectedType = switch (bit_width) {.i8 => Bytecode.Type.i8_t, .i16 => Bytecode.Type.i16_t, .i32 => Bytecode.Type.i32_t, .i64 => Bytecode.Type.i64_t};
    try self.function.typecheck(expectedType, x);
    try self.function.typecheck(expectedType, y);
    try self.function.typecheck(expectedType, z);

    switch (bit_width) {
        .i8 => try self.op(.{.s_ge8 = .{ .x = x, .y = y, .z = z }}),
        .i16 => try self.op(.{.s_ge16 = .{ .x = x, .y = y, .z = z }}),
        .i32 => try self.op(.{.s_ge32 = .{ .x = x, .y = y, .z = z }}),
        .i64 => try self.op(.{.s_ge64 = .{ .x = x, .y = y, .z = z }}),
    }
}

pub fn s_ge8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_ge(.i8, x, y, z); }
pub fn s_ge16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_ge(.i16, x, y, z); }
pub fn s_ge32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_ge(.i32, x, y, z); }
pub fn s_ge64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand, z: Bytecode.Operand) Error!void { try self.s_ge(.i64, x, y, z); }

pub fn i_ext8x16(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.s_ext8x16(x, y); } else { try self.u_ext8x16(x, y); } }
pub fn i_ext8x32(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.s_ext8x32(x, y); } else { try self.u_ext8x32(x, y); } }
pub fn i_ext8x64(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.s_ext8x64(x, y); } else { try self.u_ext8x64(x, y); } }
pub fn i_ext16x32(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.s_ext16x32(x, y); } else { try self.u_ext16x32(x, y); } }
pub fn i_ext16x64(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.s_ext16x64(x, y); } else { try self.u_ext16x64(x, y); } }
pub fn i_ext32x64(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.s_ext32x64(x, y); } else { try self.u_ext32x64(x, y); } }

pub fn u_ext8x16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.u_ext8x16 = .{ .x = x, .y = y }});
}
pub fn u_ext8x32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.u_ext8x32 = .{ .x = x, .y = y }});
}
pub fn u_ext8x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.u_ext8x64 = .{ .x = x, .y = y }});
}
pub fn u_ext16x32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.u_ext16x32 = .{ .x = x, .y = y }});
}
pub fn u_ext16x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.u_ext16x64 = .{ .x = x, .y = y }});
}
pub fn u_ext32x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.u_ext32x64 = .{ .x = x, .y = y }});
}
pub fn s_ext8x16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.s_ext8x16 = .{ .x = x, .y = y }});
}
pub fn s_ext8x32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.s_ext8x32 = .{ .x = x, .y = y }});
}
pub fn s_ext8x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.s_ext8x64 = .{ .x = x, .y = y }});
}
pub fn s_ext16x32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.s_ext16x32 = .{ .x = x, .y = y }});
}
pub fn s_ext16x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.s_ext16x64 = .{ .x = x, .y = y }});
}
pub fn s_ext32x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.s_ext32x64 = .{ .x = x, .y = y }});
}

pub fn f_ext32x64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.f_ext32x64 = .{ .x = x, .y = y }});
}

pub fn i_trunc64x32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.i_trunc64x32 = .{ .x = x, .y = y }});
}
pub fn i_trunc64x16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.i_trunc64x16 = .{ .x = x, .y = y }});
}
pub fn i_trunc64x8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.i_trunc64x8 = .{ .x = x, .y = y }});
}
pub fn i_trunc32x16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.i_trunc32x16 = .{ .x = x, .y = y }});
}
pub fn i_trunc32x8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.i_trunc32x8 = .{ .x = x, .y = y }});
}
pub fn i_trunc16x8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.i_trunc16x8 = .{ .x = x, .y = y }});
}

pub fn f_trunc64x32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.f_trunc64x32 = .{ .x = x, .y = y }});
}

pub fn i_to_f(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.s_to_f(bit_width, float_bit_width, x, y);
    } else {
        try self.u_to_f(bit_width, float_bit_width, x, y);
    }
}

pub fn u_to_f(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.u8_to_f(float_bit_width, x, y),
        .i16 => try self.u16_to_f(float_bit_width, x, y),
        .i32 => try self.u32_to_f(float_bit_width, x, y),
        .i64 => try self.u64_to_f(float_bit_width, x, y),
    }
}

pub fn s_to_f(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.s8_to_f(float_bit_width, x, y),
        .i16 => try self.s16_to_f(float_bit_width, x, y),
        .i32 => try self.s32_to_f(float_bit_width, x, y),
        .i64 => try self.s64_to_f(float_bit_width, x, y),
    }
}

pub fn u_to_f32(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.u8_to_f32(x, y),
        .i16 => try self.u16_to_f32(x, y),
        .i32 => try self.u32_to_f32(x, y),
        .i64 => try self.u64_to_f32(x, y),
    }
}

pub fn u_to_f64(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.u8_to_f64(x, y),
        .i16 => try self.u16_to_f64(x, y),
        .i32 => try self.u32_to_f64(x, y),
        .i64 => try self.u64_to_f64(x, y),
    }
}

pub fn s_to_f32(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.s8_to_f32(x, y),
        .i16 => try self.s16_to_f32(x, y),
        .i32 => try self.s32_to_f32(x, y),
        .i64 => try self.s64_to_f32(x, y),
    }
}

pub fn s_to_f64(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.s8_to_f64(x, y),
        .i16 => try self.s16_to_f64(x, y),
        .i32 => try self.s32_to_f64(x, y),
        .i64 => try self.s64_to_f64(x, y),
    }
}

pub fn u8_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.u8_to_f32(x, y),
        .f64 => try self.u8_to_f64(x, y),
    }
}

pub fn u16_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.u16_to_f32(x, y),
        .f64 => try self.u16_to_f64(x, y),
    }
}

pub fn u32_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.u32_to_f32(x, y),
        .f64 => try self.u32_to_f64(x, y),
    }
}

pub fn u64_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.u64_to_f32(x, y),
        .f64 => try self.u64_to_f64(x, y),
    }
}

pub fn s8_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.s8_to_f32(x, y),
        .f64 => try self.s8_to_f64(x, y),
    }
}

pub fn s16_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.s16_to_f32(x, y),
        .f64 => try self.s16_to_f64(x, y),
    }
}

pub fn s32_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.s32_to_f32(x, y),
        .f64 => try self.s32_to_f64(x, y),
    }
}

pub fn s64_to_f(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.s64_to_f32(x, y),
        .f64 => try self.s64_to_f64(x, y),
    }
}

pub fn u8_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.u8_to_f32 = .{ .x = x, .y = y}});
}
pub fn u8_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.u8_to_f64 = .{ .x = x, .y = y}});
}
pub fn u16_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.u16_to_f32 = .{ .x = x, .y = y}});
}
pub fn u16_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.u16_to_f64 = .{ .x = x, .y = y}});
}
pub fn u32_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.u32_to_f32 = .{ .x = x, .y = y}});
}
pub fn u32_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.u32_to_f64 = .{ .x = x, .y = y}});
}
pub fn u64_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.u64_to_f32 = .{ .x = x, .y = y}});
}
pub fn u64_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.u64_to_f64 = .{ .x = x, .y = y}});
}
pub fn s8_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.s8_to_f32 = .{ .x = x, .y = y}});
}
pub fn s8_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i8_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.s8_to_f64 = .{ .x = x, .y = y}});
}
pub fn s16_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.s16_to_f32 = .{ .x = x, .y = y}});
}
pub fn s16_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i16_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.s16_to_f64 = .{ .x = x, .y = y}});
}
pub fn s32_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.s32_to_f32 = .{ .x = x, .y = y}});
}
pub fn s32_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i32_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.s32_to_f64 = .{ .x = x, .y = y}});
}
pub fn s64_to_f32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.f32_t, y);
    try self.op(.{.s64_to_f32 = .{ .x = x, .y = y}});
}
pub fn s64_to_f64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.i64_t, x);
    try self.function.typecheck(Bytecode.Type.f64_t, y);
    try self.op(.{.s64_to_f64 = .{ .x = x, .y = y}});
}

pub fn f_to_i(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, int_bit_width: Bytecode.Type.Int.BitWidth, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.f32_to_i(is_signed, int_bit_width, x, y),
        .f64 => try self.f64_to_i(is_signed, int_bit_width, x, y),
    }
}

pub fn f_to_u(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, int_bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.f32_to_u(int_bit_width, x, y),
        .f64 => try self.f64_to_u(int_bit_width, x, y),
    }
}

pub fn f_to_s(self: *BlockBuilder, float_bit_width: Bytecode.Type.Float.BitWidth, int_bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (float_bit_width) {
        .f32 => try self.f32_to_s(int_bit_width, x, y),
        .f64 => try self.f64_to_s(int_bit_width, x, y),
    }
}

pub fn f_to_u8(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_u8 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_u8 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_u16(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_u16 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_u16 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_u32(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_u32 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_u32 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_u64(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_u64 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_u64 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_s8(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_s8 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_s8 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_s16(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_s16 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_s16 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_s32(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_s32 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_s32 = .{ .x = x, .y = y }}),
    }
}

pub fn f_to_s64(self: *BlockBuilder, bit_width: Bytecode.Type.Float.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .f32 => try self.op(.{.f32_to_s64 = .{ .x = x, .y = y }}),
        .f64 => try self.op(.{.f64_to_s64 = .{ .x = x, .y = y }}),
    }
}

pub fn f32_to_i(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.f32_to_s(bit_width, x, y);
    } else {
        try self.f32_to_u(bit_width, x, y);
    }
}

pub fn f64_to_i(self: *BlockBuilder, is_signed: bool, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    if (is_signed) {
        try self.f64_to_s(bit_width, x, y);
    } else {
        try self.f64_to_u(bit_width, x, y);
    }
}

pub fn f32_to_u(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.f32_to_u8(x, y),
        .i16 => try self.f32_to_u16(x, y),
        .i32 => try self.f32_to_u32(x, y),
        .i64 => try self.f32_to_u64(x, y),
    }
}

pub fn f32_to_s(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.f32_to_s8(x, y),
        .i16 => try self.f32_to_s16(x, y),
        .i32 => try self.f32_to_s32(x, y),
        .i64 => try self.f32_to_s64(x, y),
    }
}

pub fn f64_to_u(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.f64_to_u8(x, y),
        .i16 => try self.f64_to_u16(x, y),
        .i32 => try self.f64_to_u32(x, y),
        .i64 => try self.f64_to_u64(x, y),
    }
}

pub fn f64_to_s(self: *BlockBuilder, bit_width: Bytecode.Type.Int.BitWidth, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    switch (bit_width) {
        .i8 => try self.f64_to_s8(x, y),
        .i16 => try self.f64_to_s16(x, y),
        .i32 => try self.f64_to_s32(x, y),
        .i64 => try self.f64_to_s64(x, y),
    }
}

pub fn f32_to_i8(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f32_to_s8(x, y); } else { try self.f32_to_u8(x, y); } }
pub fn f32_to_i16(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f32_to_s16(x, y); } else { try self.f32_to_u16(x, y); } }
pub fn f32_to_i32(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f32_to_s32(x, y); } else { try self.f32_to_u32(x, y); } }
pub fn f32_to_i64(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f32_to_s64(x, y); } else { try self.f32_to_u64(x, y); } }

pub fn f64_to_i8(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f64_to_s8(x, y); } else { try self.f64_to_u8(x, y); } }
pub fn f64_to_i16(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f64_to_s16(x, y); } else { try self.f64_to_u16(x, y); } }
pub fn f64_to_i32(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f64_to_s32(x, y); } else { try self.f64_to_u32(x, y); } }
pub fn f64_to_i64(self: *BlockBuilder, is_signed: bool, x: Bytecode.Operand, y: Bytecode.Operand) Error!void { if (is_signed) { try self.f64_to_s64(x, y); } else { try self.f64_to_u64(x, y); } }

pub fn f32_to_u8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.f32_to_u8 = .{ .x = x, .y = y}});
}
pub fn f32_to_u16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.f32_to_u16 = .{ .x = x, .y = y}});
}
pub fn f32_to_u32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.f32_to_u32 = .{ .x = x, .y = y}});
}
pub fn f32_to_u64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.f32_to_u64 = .{ .x = x, .y = y}});
}
pub fn f64_to_u8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.f64_to_u8 = .{ .x = x, .y = y}});
}
pub fn f64_to_u16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.f64_to_u16 = .{ .x = x, .y = y}});
}
pub fn f64_to_u32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.f64_to_u32 = .{ .x = x, .y = y}});
}
pub fn f64_to_u64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.f64_to_u64 = .{ .x = x, .y = y}});
}
pub fn f32_to_s8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.f32_to_s8 = .{ .x = x, .y = y}});
}
pub fn f32_to_s16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.f32_to_s16 = .{ .x = x, .y = y}});
}
pub fn f32_to_s32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.f32_to_s32 = .{ .x = x, .y = y}});
}
pub fn f32_to_s64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f32_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.f32_to_s64 = .{ .x = x, .y = y}});
}
pub fn f64_to_s8(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i8_t, y);
    try self.op(.{.f64_to_s8 = .{ .x = x, .y = y}});
}
pub fn f64_to_s16(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i16_t, y);
    try self.op(.{.f64_to_s16 = .{ .x = x, .y = y}});
}
pub fn f64_to_s32(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i32_t, y);
    try self.op(.{.f64_to_s32 = .{ .x = x, .y = y}});
}
pub fn f64_to_s64(self: *BlockBuilder, x: Bytecode.Operand, y: Bytecode.Operand) Error!void {
    try self.function.typecheck(Bytecode.Type.f64_t, x);
    try self.function.typecheck(Bytecode.Type.i64_t, y);
    try self.op(.{.f64_to_s64 = .{ .x = x, .y = y}});
}


comptime {
    for (std.meta.fieldNames(Bytecode.Op)) |name| {
        if (!@hasDecl(BlockBuilder, name)) {
            @compileError("missing method: BlockBuilder." ++ name);
        }
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
