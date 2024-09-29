const std = @import("std");

const Support = @import("Support");
const Bytecode = @import("Bytecode");
const IO = @import("IO");

const Builder = @import("root.zig");
const Error = Builder.Error;
const BlockBuilder = Builder.BlockBuilder;

const FunctionBuilder = @This();


parent: *Builder,
index: Bytecode.FunctionIndex,
blocks: Builder.BlockList,
entry: *BlockBuilder,
evidence: ?Bytecode.EvidenceIndex,
num_arguments: usize,
num_locals: usize,



/// For use by the parent Builder only
pub fn init(parent: *Builder, index: Bytecode.FunctionIndex) Error!*FunctionBuilder {
    const ptr = try parent.allocator.create(FunctionBuilder);

    var blocks = Builder.BlockList {};
    try blocks.ensureTotalCapacity(parent.allocator, Bytecode.MAX_BLOCKS);

    ptr.* = FunctionBuilder {
        .parent = parent,
        .index = index,
        .blocks = blocks,
        .entry = undefined,
        .evidence = null,
        .num_arguments = 0,
        .num_locals = 0,
    };

    ptr.entry = try BlockBuilder.init(ptr, null, 0, .basic);
    ptr.blocks.appendAssumeCapacity(ptr.entry);

    return ptr;
}

pub fn assemble(self: *const FunctionBuilder, allocator: std.mem.Allocator) Error!Bytecode.Function {
    var num_instrs: usize = 0;

    for (self.blocks.items) |builder| {
        num_instrs += try builder.preassemble();
    }

    const blocks = try allocator.alloc([*]const Bytecode.Instruction, self.blocks.items.len);
    errdefer allocator.free(blocks);

    const instructions = try allocator.alloc(Bytecode.Instruction, num_instrs);
    errdefer allocator.free(instructions);

    var instr_offset: usize = 0;
    for (self.blocks.items, 0..) |builder, i| {
        const block = builder.assemble(instructions, &instr_offset);
        blocks[i] = block;
    }


    return Bytecode.Function {
        .num_arguments = @truncate(self.num_arguments),
        .num_registers = @truncate(self.num_arguments + self.num_locals),
        .value = .{
            .bytecode = .{
                .blocks = blocks,
                .instructions = instructions,
            },
        },
    };
}

pub fn getBlock(self: *const FunctionBuilder, index: Bytecode.BlockIndex) Error!*BlockBuilder {
    if (index >= self.blocks.items.len) {
        return Error.InvalidIndex;
    }

    return self.blocks.items[index];
}

/// for use by BlockBuilder only
pub fn newBlock(self: *FunctionBuilder, parent: ?Bytecode.BlockIndex, kind: BlockBuilder.Kind) Error!*BlockBuilder {
    const index = self.blocks.items.len;
    if (index >= Bytecode.MAX_BLOCKS) return Error.TooManyBlocks;

    const block = try BlockBuilder.init(self, parent, @truncate(index), kind);
    self.blocks.appendAssumeCapacity(block);

    return block;
}

pub fn arg(self: *FunctionBuilder) Error!Bytecode.RegisterIndex {
    if (self.num_locals > 0) return Error.ArgumentAfterLocals;

    const index = self.num_arguments;
    if (index >= Bytecode.MAX_REGISTERS) return Error.TooManyRegisters;

    self.num_arguments += 1;

    return @truncate(index);
}

pub fn local(self: *FunctionBuilder) Error!Bytecode.RegisterIndex {
    const index = self.num_arguments + self.num_locals;
    if (index >= Bytecode.MAX_REGISTERS) return Error.TooManyRegisters;

    self.num_locals += 1;

    return @truncate(index);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
