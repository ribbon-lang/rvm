const std = @import("std");

const zig_builtin = @import("builtin");

const Config = @import("Config");

const Log = @import("Log");

pub const std_options = Log.std_options;

pub const ribbon_log = Log.scoped(.ribbon);

test {
    std.testing.refAllDecls(@This());
}
