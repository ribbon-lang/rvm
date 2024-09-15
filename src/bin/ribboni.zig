const std = @import("std");

const zig_builtin = @import("builtin");

const Config = @import("Config");
const Support = @import("Support");
const CLIMetaData = @import("CLIMetaData");
const TextUtils = @import("ZigTextUtils");
const ANSI = @import("ANSI");
const Core = @import("Core");
const IO = @import("IO");
const Bytecode = @import("Bytecode");
const Builder = @import("Builder");
const Disassembler = @import("Disassembler");
const log = std.log.scoped(.ribboni);

pub const std_options = @import("Log").std_options;

const Error = Support.IOError || std.mem.Allocator.Error || CLIMetaData.CLIError || Core.Fiber.Trap || Builder.Error || error {
    TestExpectedEqual,
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
        .exit => return,
        .execute => |x| {
            try earlyTesting(gpa, stderr, x.rootFiles, scriptArgs);
        },
    }
}



fn earlyTesting(gpa: std.mem.Allocator, output: std.fs.File.Writer, _: []const []const u8, _: []const []const u8) Error!void {
    const context = try Core.Context.init(gpa);
    defer context.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var builder = try Builder.init(arena.allocator());

    const out_global = try builder.globalNative(@as(u8, 0));

    const main_t = try builder.typeId(.{.function = .{
        .result = Builder.i8_t,
        .term = Builder.void_t,
        .evidence = &[0]Bytecode.EvidenceIndex {},
        .params = &[_]Bytecode.TypeIndex {Builder.i8_t, Builder.i8_t},
    }});

    const func = try builder.main(main_t);

    const out = try func.local(Builder.i8_t);

    try func.entry.i_add8(.local(.r0, 0), .local(.r1, 0), .local(out, 0));
    try func.entry.ret_v(.local(out, 0));

    const program = try builder.assemble(gpa);
    defer program.deinit(gpa);

    try Disassembler.bytecode(program.functions[0].value.bytecode, output);

    const fiber = try Core.Fiber.init(context, &program, &[0] Core.Fiber.ForeignFunction {});
    defer fiber.deinit();

    try fiber.stack.data.pushUninit(program.functions[program.main.?].layout_table.size);
    try fiber.stack.call.push(Core.Fiber.CallFrame {
        .function = 0,
        .evidence = null,
        .root_block = 0,
        .stack = .{
            .base = 0,
            .origin = 0,
        },
    });
    try fiber.stack.block.push(Core.Fiber.BlockFrame {
        .index = 0,
        .ip_offset = 0,
        .out = .global(0, 0),
        .handler_set = Bytecode.HANDLER_SET_SENTINEL,
    });

    const registerData = try fiber.getRegisterData(try fiber.stack.call.getPtr(0), &program.functions[0]);

    try fiber.write(registerData, .local(.r0, 0), @as(u8, 243));
    try fiber.write(registerData, .local(.r1, 0), @as(u8, 10));

    try Core.Eval.step(fiber); // i_add8
    try Core.Eval.step(fiber); // ret_v

    const result = try fiber.read(u8, registerData, .global(out_global, 0));

    try output.print("result: {}\n", .{result});
    try std.testing.expectEqual(result, 253);
}


test {
    std.testing.refAllDeclsRecursive(@This());
}
