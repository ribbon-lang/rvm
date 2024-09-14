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
const log = std.log.scoped(.ribboni);

pub const std_options = @import("Log").std_options;

const Error = Support.IOError || std.mem.Allocator.Error || CLIMetaData.CLIError || Core.Fiber.Trap || error {
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


const void_t: Bytecode.TypeIndex = 0;
const bool_t: Bytecode.TypeIndex = 1;
const u8_t: Bytecode.TypeIndex   = 2;
const u16_t: Bytecode.TypeIndex  = 3;
const u32_t: Bytecode.TypeIndex  = 4;
const u64_t: Bytecode.TypeIndex  = 5;
const s8_t: Bytecode.TypeIndex   = 6;
const s16_t: Bytecode.TypeIndex  = 7;
const s32_t: Bytecode.TypeIndex  = 8;
const s64_t: Bytecode.TypeIndex  = 9;
const f32_t: Bytecode.TypeIndex  = 10;
const f64_t: Bytecode.TypeIndex  = 11;

const basic_types = [_]Bytecode.Type {
    .void,
    .bool,
    .{ .int = Bytecode.Type.Int { .bit_width = .i8,  .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i16, .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i32, .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i64, .is_signed = false } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i8,  .is_signed = true } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i16, .is_signed = true } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i32, .is_signed = true } },
    .{ .int = Bytecode.Type.Int { .bit_width = .i64, .is_signed = true } },
    .{ .float = Bytecode.Type.Float { .bit_width = .f32 } },
    .{ .float = Bytecode.Type.Float { .bit_width = .f64 } },
};

fn earlyTesting(gpa: std.mem.Allocator, output: std.fs.File.Writer, _: []const []const u8, _: []const []const u8) Error!void {
    const context = try Core.Context.init(gpa);
    defer context.deinit();

    var encoder = IO.Encoder {};

    try encoder.encode(gpa, Bytecode.Op {
        .i_add8 = . {
            .x = .local(.r0, 0),
            .y = .local(.r1, 0),
            .z = .local(.r2, 0),
        },
    });

    try encoder.encode(gpa, Bytecode.Op {
        .ret_v = . {
            .y = .local(.r2, 0),
        },
    });

    var globalMemory = [1]u8 {undefined};

    const program = Bytecode.Program {
        .types = &basic_types,
        .globals = Bytecode.GlobalSet {
            .memory = &globalMemory,
            .values = &[_]Bytecode.Global {
                .{
                    .type = u8_t,
                    .layout = Bytecode.typeLayout(&basic_types, u8_t).?,
                    .offset = 0,
                }
            },
        },
        .functions = &[_]Bytecode.Function {
            .{
                .layout_table = Bytecode.LayoutTable {
                    .term_type = void_t,
                    .return_type = void_t,
                    .register_types = &[_] Bytecode.TypeIndex {},

                    .term_layout = null,
                    .return_layout = Bytecode.typeLayout(&basic_types, u8_t).?,
                    .register_layouts = &[_] Bytecode.Layout {
                        Bytecode.typeLayout(&basic_types, u8_t).?,
                        Bytecode.typeLayout(&basic_types, u8_t).?,
                        Bytecode.typeLayout(&basic_types, u8_t).?,
                    },

                    .register_offsets = &[_] Bytecode.RegisterBaseOffset {
                        0, 1, 2,
                    },

                    .size = 3,
                    .alignment = 1,

                    .num_arguments = 2,
                    .num_registers = 3,
                },
                .value = .{ .bytecode = Bytecode {
                    .blocks = &[_]Bytecode.Block {
                        .{
                            .kind = .entry_v,
                            .base = 0,
                            .size = @intCast(encoder.len()),
                            .handlers = Bytecode.HANDLER_SET_SENTINEL,
                            .output_layout = Bytecode.Layout {
                                .size = 0,
                                .alignment = 0,
                            },
                        }
                    },
                    .instructions = try encoder.finalize(gpa),
                } }
            }
        },
        .handler_sets = &[_]Bytecode.HandlerSet {},
        .main = 0,
    };

    const fiber = try Core.Fiber.init(context, &program, &[0] Core.Fiber.ForeignFunction {});
    defer fiber.deinit();

    try fiber.stack.data.pushUninit(program.functions[0].layout_table.size);
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

    const result = try fiber.read(u8, registerData, .global(0, 0));

    try output.print("result: {}\n", .{result});
    try std.testing.expectEqual(result, 253);
}


test {
    std.testing.refAllDeclsRecursive(@This());
}
