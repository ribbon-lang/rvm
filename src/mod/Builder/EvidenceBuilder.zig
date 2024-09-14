const std = @import("std");

const Bytecode = @import("Bytecode");

const Builder = @import("root.zig");
const Error = Builder.Error;


const EvidenceBuilder = @This();


parent: *Builder,
index: Bytecode.EvidenceIndex,
type: Bytecode.TypeIndex,
term_type: Bytecode.TypeIndex,
upvalue_types: Builder.TypeList,


/// For use by the parent Builder only
pub fn init(parent: *Builder, t: Bytecode.TypeIndex, tt: Bytecode.TypeIndex, index: Bytecode.EvidenceIndex) std.mem.Allocator.Error!*EvidenceBuilder {
    const ptr = try parent.allocator.create(EvidenceBuilder);

    var upvalue_types = Builder.TypeList {};
    try upvalue_types.ensureTotalCapacity(parent.allocator, 8);

    ptr.* = EvidenceBuilder {
        .parent = parent,
        .index = index,
        .type = t,
        .term_type = tt,
        .upvalue_types = upvalue_types,
    };

    return ptr;
}

pub fn upvalue(self: *EvidenceBuilder, t: Bytecode.TypeIndex) Error!Bytecode.Register {
    const index = self.upvalue_types.items.len;
    if (index >= Bytecode.MAX_REGISTERS) {
        return Error.TooManyRegisters;
    }

    try self.upvalue_types.append(self.parent.allocator, t);

    return @enumFromInt(index);
}

pub fn getUpvalueType(self: *const EvidenceBuilder, operand: Bytecode.RegisterOperand) Error!Bytecode.TypeIndex {
    const index = @intFromEnum(operand.register);

    if (index >= self.upvalue_types.items.len) {
        return Error.InvalidOperand;
    }

    const operandType = self.upvalue_types.items[index];
    return self.parent.getOffsetType(operandType, operand.offset);
}


test {
    std.testing.refAllDeclsRecursive(@This());
}
