const std = @import("std");

const zig_builtin = @import("builtin");

const Config = @import("Config");

const Log = @import("Log");

pub const std_options = Log.std_options;

pub const log = Log.scoped(.ribboni);

pub const Context = @import("Context.zig");
pub const Trap = @import("Trap.zig");

test {
    std.testing.refAllDecls(@This());
}
