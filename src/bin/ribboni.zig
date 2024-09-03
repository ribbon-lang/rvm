const std = @import("std");

const zig_builtin = @import("builtin");

const Config = @import("Config");
const Support = @import("Support");
const CLIMetaData = @import("CLIMetaData");
const TextUtils = @import("ZigTextUtils");
const ANSI = @import("ANSI");
const log = std.log.scoped(.ribboni);

pub const std_options = @import("Log").std_options;

const Error = Support.IOError || std.mem.Allocator.Error || error {

};

pub const main = main: {
    if (zig_builtin.mode == .Debug) {
        break :main entry;
    } else {
        break :main struct {
            fn fun() u8 {
                entry() catch {
                    return 1;
                };

                return 0;
            }
        }.fun;
    }
};

fn entry() Error!void {
    if (zig_builtin.os.tag == .windows) {
        const succ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
        if (succ == 0) {
            const lastErr = std.os.windows.kernel32.GetLastError();
            const safeToPrint = @intFromEnum(lastErr) >= @intFromEnum(std.os.windows.Win32Error.SUCCESS) and @intFromEnum(lastErr) <= @intFromEnum(std.os.windows.Win32Error.IO_REISSUE_AS_CACHED);

            if (safeToPrint) {
                log.warn("failed to set console output code page to UTF-8, error was {s}", .{@tagName(lastErr)});
            } else {
                log.warn("failed to set console output code page to UTF-8, error was {}", .{@intFromEnum(lastErr)});
            }
        }
    }

    const stderr = std.io.getStdErr().writer();

    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();

    const gpa = GPA.allocator();

    const args = std.process.argsAlloc(gpa) catch |err| {
        log.err("failed to get command line arguments: {}", .{err});
        return error.Unexpected;
    };
    defer gpa.free(args);

    const endOfOwnArgs =
        for (args, 0..) |arg, i| {
            if (std.mem.eql(u8, arg, "--")) {
                break i;
            }
        } else args.len;

    const scriptArgs = args[@min(endOfOwnArgs + 1, args.len)..];

    const argsResult = try CLIMetaData.processArgs(gpa, args[1..endOfOwnArgs]);
    defer argsResult.deinit();

    switch (argsResult) {
        .Exit => return,
        .Execute => |x| {
            Support.todo(noreturn, .{x, scriptArgs, stderr});
        },
    }
}
