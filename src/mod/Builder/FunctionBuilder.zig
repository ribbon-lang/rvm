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
type: Bytecode.TypeIndex,
blocks: Builder.BlockList,
entry: *BlockBuilder,
local_types: Builder.TypeList,
evidence: ?Bytecode.EvidenceIndex,


/// For use by the parent Builder only
pub fn init(parent: *Builder, typeIndex: Bytecode.TypeIndex, index: Bytecode.FunctionIndex) Error!*FunctionBuilder {
    const ty = try parent.getType(typeIndex);
    if (ty != .function) {
        return Error.TypeError;
    }

    const ptr = try parent.allocator.create(FunctionBuilder);

    var blocks = Builder.BlockList {};
    try blocks.ensureTotalCapacity(parent.allocator, Bytecode.MAX_BLOCKS);

    var local_types = Builder.TypeList {};
    try local_types.ensureTotalCapacity(parent.allocator, Bytecode.MAX_REGISTERS);

    for (ty.function.params, 0..) |paramTypeIndex, i| {
        if (i > Bytecode.MAX_REGISTERS) return Error.TooManyRegisters;
        local_types.appendAssumeCapacity(paramTypeIndex);
    }

    ptr.* = FunctionBuilder {
        .parent = parent,
        .index = index,
        .type = typeIndex,
        .blocks = blocks,
        .entry = undefined,
        .local_types = local_types,
        .evidence = null,
    };

    ptr.entry = try BlockBuilder.init(ptr, null, 0, if (ty.function.result != 0) .{ .entry_v = ty.function.result } else .entry);
    ptr.blocks.appendAssumeCapacity(ptr.entry);

    return ptr;
}

pub fn assemble(self: *const FunctionBuilder, allocator: std.mem.Allocator) Error!struct { Bytecode.Function, Bytecode.LayoutDetails } {
    const blocks = try allocator.alloc(Bytecode.Block, self.blocks.items.len);
    errdefer allocator.free(blocks);

    var encoder = IO.Encoder {};
    defer encoder.deinit(allocator);

    const blockTypes = try allocator.alloc(Bytecode.TypeIndex, self.blocks.items.len);

    for (self.blocks.items, 0..) |builder, i| {
        const block, const blockType = try builder.assemble(&encoder, allocator);
        blocks[i] = block;
        blockTypes[i] = blockType;
    }

    const instructions = try encoder.finalize(allocator);

    const num_registers, const layout_details = try self.generateLayouts(allocator, blockTypes);

    return .{
        Bytecode.Function {
            .index = self.index,
            .num_registers = num_registers,
            .value = .{
                .bytecode = .{
                    .blocks = blocks,
                    .instructions = instructions,
                },
            },
        },

        layout_details,
    };
}

pub fn generateLayouts(self: *const FunctionBuilder, allocator: std.mem.Allocator, block_types: []const Bytecode.TypeIndex) Error!struct { u16, Bytecode.LayoutDetails } {
    const typeInfo = (try self.parent.getType(self.type)).function;

    const register_types = try allocator.alloc(Bytecode.TypeIndex, self.local_types.items.len);
    errdefer allocator.free(register_types);

    const register_layouts = try allocator.alloc(Bytecode.Layout, self.local_types.items.len);
    errdefer allocator.free(register_layouts);

    const register_info = try allocator.alloc(Bytecode.LayoutTable.RegisterInfo, self.local_types.items.len);
    errdefer allocator.free(register_info);

    const block_layouts = try allocator.alloc(Bytecode.Layout, block_types.len);
    errdefer allocator.free(block_layouts);

    var size: Bytecode.LayoutTableSize = 0;
    var alignment: Bytecode.ValueAlignment = 0;

    for (self.local_types.items, 0..) |typeIndex, i| {
        const layout = try self.parent.getTypeLayout(typeIndex);

        size += Support.alignmentDelta(size, layout.alignment);
        alignment = @max(layout.alignment, alignment);

        register_types[i] = typeIndex;
        register_layouts[i] = layout;
        register_info[i] = .{
            .offset = size,
            .size = layout.size,
        };

        size += layout.size;
    }

    for (block_types, 0..) |typeIndex, i| {
        block_layouts[i] = try self.parent.getTypeLayout(typeIndex);
    }

    const term_layout = try self.parent.getTypeLayout(typeInfo.term);
    const return_layout = try self.parent.getTypeLayout(typeInfo.result);

    return .{
        @intCast(self.local_types.items.len),

        Bytecode.LayoutDetails {
            .term_type = typeInfo.term,
            .return_type = typeInfo.result,
            .register_types = register_types.ptr,
            .block_types = block_types.ptr,

            .term_layout = term_layout,
            .return_layout = return_layout,
            .register_layouts = register_layouts.ptr,
            .block_layouts = block_layouts.ptr,

            .num_arguments = @intCast(typeInfo.params.len),
            .num_registers = @intCast(self.local_types.items.len),
            .num_blocks = @intCast(block_types.len),
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

pub fn getUpvalueType(self: *const FunctionBuilder, u: Bytecode.UpvalueIndex) Error!Bytecode.TypeIndex {
    if (self.evidence) |evidenceIndex| {
        const ev = try self.parent.getEvidence(evidenceIndex);
        return ev.getUpvalueType(u);
    }

    return Error.InvalidOperand;
}

pub fn getLocalType(self: *const FunctionBuilder, l: Bytecode.RegisterIndex) Error!Bytecode.TypeIndex {
    if (l >= self.local_types.items.len) {
        return Error.InvalidOperand;
    }

    return self.local_types.items[l];
}

pub fn local(self: *FunctionBuilder, t: Bytecode.TypeIndex) Error!Bytecode.RegisterIndex {
    const index = self.local_types.items.len;
    if (index >= Bytecode.MAX_REGISTERS) return Error.TooManyRegisters;

    self.local_types.appendAssumeCapacity(t);

    return @truncate(index);
}

pub fn typecheckEvidence(self: *const FunctionBuilder, evidence: Bytecode.EvidenceIndex) Error!void {
    const ty = try self.parent.getType(self.type);

    for (ty.function.evidence) |usableEvidenceIndex| {
        if (evidence == usableEvidenceIndex) {
            return;
        }
    }

    return Error.MissingEvidence;
}

/// does not check evidence
pub fn typecheckCall(self: *const FunctionBuilder, calleeTypeIndex: Bytecode.TypeIndex, r: ?Bytecode.RegisterIndex, as: anytype) Error!void {
    const calleeType = try self.parent.getType(calleeTypeIndex);

    if (calleeType != .function) {
        return Error.TypeError;
    }

    if (calleeType.function.params.len > as.len) {
        return Error.NotEnoughArguments;
    } else if (calleeType.function.params.len < as.len) {
        return Error.TooManyArguments;
    }

    inline for (0..as.len) |i| {
        try self.typecheckLocal(calleeType.function.params[i], as[i]);
    }

    if (r) |returnReg| {
        try self.typecheckLocal(calleeType.function.result, returnReg);
    } // automatic discard is allowed
}

pub fn typecheckRet(self: *const FunctionBuilder, r: ?Bytecode.RegisterIndex) Error!void {
    const ty = try self.parent.getType(self.type);

    if (r) |returnReg| {
        try self.typecheckLocal(ty.function.result, returnReg);
    } else {
        try self.parent.typecheck(ty.function.result, Bytecode.Type.void_t);
    }
}

pub fn typecheckTerm(self: *const FunctionBuilder, t: ?Bytecode.RegisterIndex) Error!void {
    const ty = try self.parent.getType(self.type);

    if (t) |termReg| {
        try self.typecheckLocal(ty.function.term, termReg);
    } else {
        try self.parent.typecheck(ty.function.term, Bytecode.Type.void_t);
    }

    return Error.TypeError;
}

pub fn typecheckUpvalue(self: *const FunctionBuilder, t: Bytecode.TypeIndex, r: Bytecode.RegisterIndex) Error!void {
    const uTypeIndex = try self.getUpvalueType(r);

    return self.parent.typecheck(t, uTypeIndex);
}

pub fn typecheckLocal(self: *const FunctionBuilder, t: Bytecode.TypeIndex, r: Bytecode.RegisterIndex) Error!void {
    const lTypeIndex = try self.getLocalType(r);

    return self.parent.typecheck(t, lTypeIndex);
}


test {
    std.testing.refAllDeclsRecursive(@This());
}
