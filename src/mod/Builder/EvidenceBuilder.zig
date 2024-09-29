const std = @import("std");

const Bytecode = @import("Bytecode");

const Builder = @import("root.zig");
const Error = Builder.Error;


const EvidenceBuilder = @This();


parent: *Builder,
index: Bytecode.EvidenceIndex,
num_upvalues: usize,


/// For use by the parent Builder only
pub fn init(parent: *Builder, index: Bytecode.EvidenceIndex) std.mem.Allocator.Error!*EvidenceBuilder {
    const ptr = try parent.allocator.create(EvidenceBuilder);

    ptr.* = EvidenceBuilder {
        .parent = parent,
        .index = index,
        .num_upvalues = 0,
    };

    return ptr;
}

pub fn upvalue(self: *EvidenceBuilder) Error!Bytecode.UpvalueIndex {
    const index = self.num_upvalues;

    if (index >= Bytecode.MAX_REGISTERS) {
        return Error.TooManyRegisters;
    }

    self.num_upvalues += 1;

    return @truncate(index);
}


test {
    std.testing.refAllDeclsRecursive(@This());
}
