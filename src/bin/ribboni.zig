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

// pub const main = main: {
//     if (zig_builtin.mode == .Debug) {
//         break :main entry;
//     } else {
//         break :main struct {
//             fn fun() u8 {
//                 entry() catch {
//                     return 1;
//                 };

//                 return 0;
//             }
//         }.fun;
//     }
// };

// fn entry() Error!void {
//     if (zig_builtin.os.tag == .windows) {
//         const succ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
//         if (succ == 0) {
//             const lastErr = std.os.windows.kernel32.GetLastError();
//             const safeToPrint = @intFromEnum(lastErr) >= @intFromEnum(std.os.windows.Win32Error.SUCCESS) and @intFromEnum(lastErr) <= @intFromEnum(std.os.windows.Win32Error.IO_REISSUE_AS_CACHED);

//             if (safeToPrint) {
//                 log.warn("failed to set console output code page to UTF-8, error was {s}", .{@tagName(lastErr)});
//             } else {
//                 log.warn("failed to set console output code page to UTF-8, error was {}", .{@intFromEnum(lastErr)});
//             }
//         }
//     }

//     const stderr = std.io.getStdErr().writer();

//     var GPA = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = GPA.deinit();

//     const gpa = GPA.allocator();

//     const args = std.process.argsAlloc(gpa) catch |err| {
//         log.err("failed to get command line arguments: {}", .{err});
//         return error.Unexpected;
//     };
//     defer gpa.free(args);

//     const endOfOwnArgs =
//         for (args, 0..) |arg, i| {
//             if (std.mem.eql(u8, arg, "--")) {
//                 break i;
//             }
//         } else args.len;

//     const scriptArgs = args[@min(endOfOwnArgs + 1, args.len)..];

//     const argsResult = try CLIMetaData.processArgs(gpa, args[1..endOfOwnArgs]);
//     defer argsResult.deinit();

//     switch (argsResult) {
//         .exit => return,
//         .execute => |x| {
//             try earlyTesting(gpa, stderr, x.rootFiles, scriptArgs);
//         },
//     }
// }



pub fn main() Error!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const context = try Core.Context.init(arena.allocator());
    // defer context.deinit();

    var builder = try Builder.init(arena.allocator());

    // const out_global = try builder.globalNative(@as(i64, 0));

    const main_t = try builder.typeId(.{.function = .{
        .result = Bytecode.Type.i64_t,
        .term = Bytecode.Type.void_t,
        .evidence = &[0]Bytecode.EvidenceIndex {},
        .params = &[_]Bytecode.TypeIndex {Bytecode.Type.i64_t},
    }});

    const one = try builder.globalNative(@as(i64, 1));
    const two = try builder.globalNative(@as(i64, 2));

    const func = try builder.main(main_t);



    const cond = try func.local(Bytecode.Type.bool_t);
    try func.entry.s_lt64(.local(.r0, 0), .global(two, 0), .local(cond, 0));
    const thenBlock, const elseBlock = try func.entry.if_nz(.local(cond, 0));

    try func.entry.trap();

    try thenBlock.ret_v(.local(.r0, 0));

    const a = try func.local(Bytecode.Type.i64_t);
    try elseBlock.i_sub64(.local(.r0, 0), .global(one, 0), .local(a, 0));
    try elseBlock.call_v(func, .local(a, 0), .{Bytecode.Operand.local(a, 0)});

    const b = try func.local(Bytecode.Type.i64_t);
    try elseBlock.i_sub64(.local(.r0, 0), .global(two, 0), .local(b, 0));
    try elseBlock.call_v(func, .local(b, 0), .{Bytecode.Operand.local(b, 0)});

    try elseBlock.i_add64(.local(a, 0), .local(b, 0), .local(a, 0));
    try elseBlock.ret_v(.local(a, 0));

    const program = try builder.assemble(arena.allocator());
    // defer program.deinit(arena.allocator());

    // try Disassembler.bytecode(program.functions[0].value.bytecode, output);

    const fiber = try Core.Fiber.init(context, &program, &[0] Core.Fiber.ForeignFunction {});
    defer fiber.deinit();

    const n: i64 = 32;

    const start = std.time.nanoTimestamp();

    const result = try fiber.invoke(i64, program.main.?, .{ n });

    const end = std.time.nanoTimestamp();

    const time = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_s;


    try std.io.getStdOut().writer().print("result: {} (in {d:.3}s)\n", .{result, time});
    try std.testing.expectEqual(2178309, result);
}

// fn fib(n: i64) i64 {
//     return if (n < 2) n else fib(n - 1) + fib(n - 2);
// }


test {
    std.testing.refAllDeclsRecursive(@This());
}
