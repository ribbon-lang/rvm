const std = @import("std");
const zig_config = @import("config");

pub const VERSION: std.SemanticVersion = zig_config.version;

pub const LOG_LEVEL: std.log.Level = @enumFromInt(@intFromEnum(zig_config.logLevel));

pub const LOG_SCOPES: []const u8 = zig_config.logScopes;

pub const USE_EMOJI_DEFAULT: bool = zig_config.useEmoji;
pub var USE_EMOJI = USE_EMOJI_DEFAULT;

pub const USE_ANSI_STYLES_DEFAULT: bool = zig_config.useAnsiStyles;
pub var USE_ANSI_STYLES = USE_ANSI_STYLES_DEFAULT;

test {
    std.testing.refAllDeclsRecursive(@This());
}
