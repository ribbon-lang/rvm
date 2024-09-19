const std = @import("std");

const clap = @import("clap");
const TypeUtils = @import("ZigTypeUtils");

const Bytecode = @import("Bytecode");
const OpCode = Bytecode.OpCode;
const prototypes = Bytecode.ISA.InstructionPrototypes;
const AVI = Bytecode.ISA.ArithmeticValueInfo;


pub const std_options = std.Options{
    .log_level = .warn,
};

const log = std.log.scoped(.@"templater:readme:isa");

const Mode = enum {
    TOC,
    BODY,
};

const TOC = "toc";
const BODY = "body";

pub fn main() !void {
    @setEvalBranchQuota(10_000);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        log.err("expected either `{s}` or `{s}`, got nothing", .{ TOC, BODY });
        return error.NotEnoughArguments;
    } else if (args.len > 2) {
        log.err("expected 1 argument, got {}:", .{args.len - 1});
        for (args[1..]) |arg| {
            log.err("`{s}`", .{arg});
        }
        return error.TooManyArguments;
    }

    const mode: Mode = mode: {
        if (std.mem.eql(u8, args[1], TOC)) {
            break :mode .TOC;
        } else if (std.mem.eql(u8, args[1], BODY)) {
            break :mode .BODY;
        } else {
            log.err("expected either ``{s}` or `{s}`, got `{s}`", .{ TOC, BODY, args[1] });
            return error.InvalidModeArgument;
        }
    };

    // const allocator = arena.allocator();

    const out = std.io.getStdOut().writer();

    switch (mode) {
        .TOC => try toc(out),
        .BODY => try body(out),
    }
}


fn toc(out: anytype) !void {
    inline for (comptime std.meta.fieldNames(@TypeOf(prototypes))) |categoryName| {
        if (comptime !(std.mem.endsWith(u8, categoryName, "_bits") or std.mem.endsWith(u8, categoryName, "_v"))) {
            try out.print("* [{s}](#{s})\n", .{categoryName, comptime kebabCase(categoryName)});
        }
    }
}

fn kebabCase(comptime str: []const u8) []const u8 {
    comptime var out: []const u8 = "";

    comptime var haveDash = true;

    inline for (str) |c| {
        out = out ++ dash: {
            if ((std.ascii.isUpper(c) or std.ascii.isWhitespace(c)) and !haveDash) {
                haveDash = true;
                break :dash "-";
            } else {
                haveDash = false;
                break :dash "";
            }
        } ++ if (!std.ascii.isWhitespace(c) and std.mem.indexOfScalar(u8, "<>", c) == null) .{ std.ascii.toLower(c) } else .{};
    }

    return out;
}

fn body(out: anytype) !void {
    inline for (comptime std.meta.fieldNames(@TypeOf(prototypes))) |categoryName| {
        const category = @field(prototypes, categoryName);

        if (comptime strCmp(categoryName, "Arithmetic")) {
            try out.print("\n#### {s}\n", .{categoryName});

            inline for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                const doc = proto[1];
                const multipliers: AVI = proto[2];
                const operands = proto[3];

                const numOperands = std.meta.fieldNames(operands).len;

                try out.print(
                    \\<table>
                    \\    <tr>
                    \\        <th colspan="3" align="left" width="100%">{s}<img width="960px" height="1" align="right"></th>
                    \\        <td colspan="2">Params</td>
                    \\    </tr>
                    \\    <tr>
                    \\        <td colspan="3" rowspan="{}" width="100%" align="center">{s}</td>
                    \\    </tr>
                    \\    {s}
                    \\    {s}
                    \\</table>
                    \\
                    , .{
                        name,
                        1 + numOperands, formatDoc(doc),
                        formatParams(operands),
                        switch (multipliers) {
                            .none => std.fmt.comptimePrint("<tr><td>`{s}`</td></tr>", .{name}),
                            .int_only => |signVariance| comptime makeIntFields(name, signVariance),
                            .float_only => comptime makeFloatFields(name),
                            .int_float => |signVariance| comptime makeIntFields(name, signVariance) ++ " " ++ makeFloatFields(name),
                        },
                    }
                );
            }
        } else if (comptime std.mem.endsWith(u8, categoryName, "_bits")) {
            inline for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                const doc = proto[1];
                const operands = proto[2];
                const numOperands = std.meta.fieldNames(operands).len;

                try out.print(
                    \\<table>
                    \\    <tr>
                    \\        <th colspan="3" align="left" width="100%">{s}<img width="960px" height="1" align="right"></th>
                    \\        <td colspan="2">Params</td>
                    \\    </tr>
                    \\    <tr>
                    \\        <td colspan="3" rowspan="{}" width="100%" align="center">{s}</td>
                    \\    </tr>
                    \\    {s}
                    \\    {s}
                    \\</table>
                    \\
                    , .{
                        name,
                        1 + numOperands, formatDoc(doc),
                        formatParams(operands),
                        comptime bitNames(name),
                    }
                );
            }
        } else if (comptime std.mem.endsWith(u8, categoryName, "_v")) {
            inline for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                const doc = proto[1];
                const operands = proto[2];
                const vDoc = proto[3];
                const vOperands = proto[4];
                const numOperands = (if (operands != void) std.meta.fieldNames(operands).len else 1)
                                  + (if (vOperands != void) std.meta.fieldNames(vOperands).len else 1);

                const fieldName = std.fmt.comptimePrint("{s}_v", .{name});
                const description = comptime longName(name);

                try out.print(
                    \\<table>
                    \\    <tr>
                    \\        <th colspan="3" align="left" width="100%">{s}<img width="960px" height="1" align="right"></th>
                    \\        <td colspan="2">Params&nbsp;(both)</td>
                    \\    </tr>
                    \\    <tr>
                    \\        <td colspan="3" rowspan="{}" width="100%" align="center">{s}<br><br>for <code>_v</code>, {s}</td>
                    \\    </tr>
                    \\    {s}
                    \\    <tr>
                    \\        <td colspan="2">Params&nbsp;(_v)</td>
                    \\    </tr>
                    \\    {s}
                    \\    <tr>
                    \\        <td align="right" width="1%"><code>0x{x:0>2}</code></td>
                    \\        <td align="left" width="1%"><code>{s}</code></td>
                    \\        <td align="center" colspan="3">{s}</td>
                    \\    </tr>
                    \\    <tr>
                    \\        <td align="right" width="1%"><code>0x{x:0>2}</code></td>
                    \\        <td align="left" width="1%"><code>{s}</code></td>
                    \\        <td align="center" colspan="3">{s} with a result value</td>
                    \\    </tr>
                    \\</table>
                    \\
                    , .{
                        name,
                        2 + numOperands, formatDoc(doc), formatDoc(vDoc),
                        formatParams(operands),
                        formatParams(vOperands),
                        @intFromEnum(@field(OpCode, name)), name, description,
                        @intFromEnum(@field(OpCode, fieldName)), fieldName, description,
                    }
                );
            }
        } else if (comptime std.mem.startsWith(u8, categoryName, "Size Cast")) {
            try out.print("\n#### {s}\n", .{categoryName});

            inline for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                const doc = proto[1];
                const order: AVI.SizeCast = proto[2];
                const operands = proto[3];

                const numOperands = std.meta.fieldNames(operands).len;

                try out.print(
                    \\<table>
                    \\    <tr>
                    \\        <th colspan="3" align="left" width="100%">{s}<img width="960px" height="1" align="right"></th>
                    \\        <td colspan="2">Params</td>
                    \\    </tr>
                    \\    <tr>
                    \\        <td colspan="3" rowspan="{}" width="100%" align="center">{s}</td>
                    \\    </tr>
                    \\    {s}
                    \\    {s}
                    \\</table>
                    \\
                    , .{
                        name,
                        1 + numOperands, formatDoc(doc),
                        formatParams(operands),
                        comptime makeSizeCastFields(name, categoryName, order),
                    }
                );
            }
        } else if (comptime strCmp(categoryName, "Int <-> Float Cast")) {
            try out.print("\n#### {s}\n", .{categoryName});

            const proto = category[0];

            const name = proto[0];
            const doc = proto[1];
            const operands = proto[2];
            const numOperands = std.meta.fieldNames(operands).len;

            try out.print(
                \\<table>
                \\    <tr>
                \\        <th colspan="3" align="left" width="100%">a_to_b<img width="960px" height="1" align="right"></th>
                \\        <td colspan="2">Params</td>
                \\    </tr>
                \\    <tr>
                \\        <td colspan="3" rowspan="{}" align="center">{s}</td>
                \\    </tr>
                \\    {s}
                \\    {s}
                \\</table>
                \\
                , .{
                    1 + numOperands, formatDoc(doc),
                    formatParams(operands),
                    comptime makeIntFloatCastFields(name),
                }
            );
        } else {
            try out.print("\n#### {s}\n", .{categoryName});
            inline for (0..category.len) |i| {
                const proto = category[i];

                const name = proto[0];
                const doc = proto[1];
                const operands = proto[2];

                const description = comptime longName(name);

                if (operands == void) {
                    try out.print(
                        \\<table>
                        \\    <tr>
                        \\        <th colspan="3" align="left" width="100%">{s}<img width="960px" height="1" align="right"></th>
                        \\        <td>Params</td>
                        \\    </tr>
                        \\    <tr>
                        \\        <td colspan="3" width="100%" align="center">{s}</td>
                        \\        <td>None</td>
                        \\    </tr>
                        \\    <tr>
                        \\        <td align="right" width="1%"><code>0x{x:0>2}</code></td>
                        \\        <td align="left" width="1%"><code>{s}</code></td>
                        \\        <td align="center" colspan="2">{s}</td>
                        \\    </tr>
                        \\</table>
                        \\
                        , .{
                            name,
                            formatDoc(doc),
                            @intFromEnum(@field(OpCode, name)), name,
                            description,
                        }
                    );
                } else {
                    const numOperands = std.meta.fieldNames(operands).len;

                    try out.print(
                        \\<table>
                        \\    <tr>
                        \\        <th colspan="3" align="left" width="100%">{s}<img width="960px" height="1" align="right"></th>
                        \\        <td colspan="2">Params</td>
                        \\    </tr>
                        \\    <tr>
                        \\        <td colspan="3" rowspan="{}" width="100%" align="center">{s}</td>
                        \\    </tr>
                        \\    {s}
                        \\    <tr>
                        \\        <td align="right" width="1%"><code>0x{x:0>2}</code></td>
                        \\        <td align="left" width="1%"><code>{s}</code></td>
                        \\        <td align="center" colspan="3">{s}</td>
                        \\    </tr>
                        \\</table>
                        \\
                        , .{
                            name,
                            1 + numOperands, formatDoc(doc),
                            formatParams(operands),
                            @intFromEnum(@field(OpCode, name)), name,
                            description,
                        }
                    );
                }
            }
        }
    }
}


fn formatDoc(comptime doc: []const u8) []const u8 {
    comptime var out: []const u8 = "";

    comptime var inCode: bool = false;
    comptime var inEm: bool = false;

    inline for (doc) |c| {
        if (c == '`') {
            inCode = !inCode;
            out = out ++ if (inCode) "<code>" else "</code>";
        } else if (c == '*') {
            inEm = !inEm;
            out = out ++ if (inEm) "<em>" else "</em>";
        } else if (c == '\n') {
            out = out ++ "<br>";
        } else {
            out = out ++ .{c};
        }
    }

    return out;
}

fn formatParams(comptime T: type) []const u8 {
    if (T == void) return "<tr><td colspan=\"2\">None</td></tr>";

    comptime var out: []const u8 = "";

    inline for (comptime std.meta.fields(T)) |field| {
        out = out ++ std.fmt.comptimePrint("<tr><td>{s}</td><td><code>{s}</code></td></tr>", .{field.name, comptime formatType(field.type)});
    }

    return out;
}

fn formatType(comptime T: type) []const u8 {
    switch (T) {
        u16 => return "I",
        else => switch (@typeInfo(T)) {
            .pointer => |info| if (info.size == .Slice) return "[" ++ formatType(info.child) ++ "]",
            else => {}
        }
    }
    @compileError("unknown type `" ++ @typeName(T) ++ "`");
}

fn strCmp(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn extraIntInfo(comptime sign: std.builtin.Signedness, comptime name: [:0]const u8) []const u8 {
    return
        if (strCmp(name, "shiftr")) switch (sign) {.signed => "arithmetic", .unsigned => "logical"}
        else std.fmt.comptimePrint("{s} integer", .{@tagName(sign)});
}

fn bitNames(comptime name: [:0]const u8) []const u8 {
    comptime var out: []const u8 = "";

    inline for (AVI.INTEGER_SIZE) |size| {
        const fieldName = std.fmt.comptimePrint("{s}{}", .{name, size});
        const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
        out = out
            ++ "<tr>"
                ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                ++ "<td align=\"center\" colspan=\"3\">"
                    ++ std.fmt.comptimePrint("{} bit {s}", .{size, comptime longName(name)})
                ++ "</td>"
            ++ "</tr>";
    }

    return out ++ "";
}

fn longName(comptime name: [:0]const u8) []const u8 {
    return
        if (strCmp(name, "add")) "addition"
        else if (strCmp(name, "sub")) "subtraction"
        else if (strCmp(name, "mul")) "multiplication"
        else if (strCmp(name, "div")) "division"
        else if (strCmp(name, "rem")) "remainder division"
        else if (strCmp(name, "neg")) "negation"

        else if (strCmp(name, "bitnot")) "bitwise not"
        else if (strCmp(name, "bitand")) "bitwise and"
        else if (strCmp(name, "bitor")) "bitwise or"
        else if (strCmp(name, "bitxor")) "bitwise exclusive or"
        else if (strCmp(name, "shiftl")) "left shift"
        else if (strCmp(name, "shiftr")) "right shift"

        else if (strCmp(name, "eq")) "equality comparison"
        else if (strCmp(name, "ne")) "inequality comparison"
        else if (strCmp(name, "lt")) "less than comparison"
        else if (strCmp(name, "gt")) "greater than comparison"
        else if (strCmp(name, "le")) "less than or equal comparison"
        else if (strCmp(name, "ge")) "greater than or equal comparison"

        else if (strCmp(name, "b_and")) "logical and"
        else if (strCmp(name, "b_or")) "logical or"
        else if (strCmp(name, "b_xor")) "logical exclusive or"
        else if (strCmp(name, "b_not")) "logical not"

        else if (strCmp(name, "trap")) "trigger a trap"
        else if (strCmp(name, "nop")) "no operation"
        else if (strCmp(name, "halt")) "stop execution"

        else if (strCmp(name, "dyn_call")) "dynamic function call"
        else if (strCmp(name, "dyn_tail_call")) "dynamic function tail call"
        else if (strCmp(name, "call")) "static function call"
        else if (strCmp(name, "tail_call")) "static function tail call"
        else if (strCmp(name, "prompt")) "dynamically bound effect handler call"
        else if (strCmp(name, "tail_prompt")) "dynamically bound effect handler tail call"
        else if (strCmp(name, "ret")) "function return"
        else if (strCmp(name, "term")) "effect handler termination"

        else if (strCmp(name, "when_z")) "one-way conditional block, based on the predicate being zero"
        else if (strCmp(name, "when_nz")) "one-way conditional block, based on the predicate being non-zero"
        else if (strCmp(name, "block")) "basic block"
        else if (strCmp(name, "with")) "effect handler block"
        else if (strCmp(name, "if_z")) "two-way conditional block, based on the predicate being zero"
        else if (strCmp(name, "if_nz")) "two-way conditional block, based on the predicate being non-zero"

        else if (strCmp(name, "br")) "unconditional branch out of block"
        else if (strCmp(name, "br_z")) "conditional branch out of block, based on the predicate being zero"
        else if (strCmp(name, "br_nz")) "conditional branch out of block, based on the predicate being non-zero"
        else if (strCmp(name, "re")) "unconditional branch to start of block"
        else if (strCmp(name, "re_z")) "conditional branch to start of block, based on the predicate being zero"
        else if (strCmp(name, "re_nz")) "conditional branch to start of block, based on the predicate being non-zero"

        else if (strCmp(name, "u_ext")) "unsigned integer extension"
        else if (strCmp(name, "s_ext")) "signed integer extension"
        else if (strCmp(name, "i_trunc")) "sign-agnostic integer truncation"

        else if (strCmp(name, "f_ext")) "floating point extension"
        else if (strCmp(name, "f_trunc")) "floating point truncation"

        else if (strCmp(name, "addr_local")) "address extraction of local register"
        else if (strCmp(name, "addr_global")) "address extraction of global variable"
        else if (strCmp(name, "addr_upvalue")) "address extraction of upvalue register"
        else if (strCmp(name, "read_global")) "value extraction of global variable"
        else if (strCmp(name, "write_global")) "value replacement of global variable"
        else if (strCmp(name, "read_upvalue")) "value extraction of upvalue register"
        else if (strCmp(name, "write_upvalue")) "value replacement of upvalue register"
        else if (strCmp(name, "load")) "read from address"
        else if (strCmp(name, "store")) "write to address"
        else if (strCmp(name, "copy")) "value copy"
        else if (strCmp(name, "swap")) "value swap"
        else if (strCmp(name, "clear")) "zeroing"

        else @compileError("unknown operation `" ++ name ++ "`");
}

fn makeFloatFields(comptime name: [:0]const u8) []const u8 {
    comptime var out: []const u8 = "";

    inline for (AVI.FLOAT_SIZE) |size| {
        const fieldName = std.fmt.comptimePrint("f_{s}{}", .{name, size});
        const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
        out = out
            ++ "<tr>"
                ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                ++ "<td align=\"center\" colspan=\"3\">"
                    ++ std.fmt.comptimePrint("{} bit floating point {s}", .{size, longName(name)})
                ++ "</td>"
            ++ "</tr>";
    }

    return out;
}

fn makeIntFields(comptime name: [:0]const u8, comptime signVariance: AVI.SignVariance) []const u8 {
    comptime var out: []const u8 = "";

    inline for (AVI.INTEGER_SIZE) |size| {
        switch (signVariance) {
            .different => {
                inline for (AVI.SIGNEDNESS) |sign| {
                    const fieldName = std.fmt.comptimePrint("{u}_{s}{}", .{AVI.signChar(sign), name, size});
                    const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
                    out = out
                        ++ "<tr>"
                            ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                            ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                            ++ "<td align=\"center\" colspan=\"3\">"
                                ++ std.fmt.comptimePrint("{} bit {s} {s}", .{size, extraIntInfo(sign, name), longName(name)})
                            ++ "</td>"
                        ++ "</tr>";
                }
            },
            .same => {
                const fieldName = std.fmt.comptimePrint("i_{s}{}", .{name, size});
                const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
                out = out
                    ++ "<tr>"
                        ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                        ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                        ++ "<td align=\"center\" colspan=\"3\">"
                            ++ std.fmt.comptimePrint("{} bit sign-agnostic integer {s}", .{size, longName(name)})
                        ++ "</td>"
                    ++ "</tr>";
            },
            .only_unsigned => {
                const fieldName = std.fmt.comptimePrint("u_{s}{}", .{name, size});
                const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
                out = out
                    ++ "<tr>"
                        ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                        ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                        ++ "<td align=\"center\" colspan=\"3\">"
                            ++ std.fmt.comptimePrint("{} bit unsigned integer {s}", .{size, longName(name)})
                        ++ "</td>"
                    ++ "</tr>";
            },
            .only_signed => {
                const fieldName = std.fmt.comptimePrint("s_{s}{}", .{name, size});
                const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
                out = out
                    ++ "<tr>"
                        ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                        ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                        ++ "<td align=\"center\" colspan=\"3\">"
                            ++ std.fmt.comptimePrint("{} bit signed integer {s}", .{size, longName(name)})
                        ++ "</td>"
                    ++ "</tr>";
            }
        }
    }
    return out;
}

fn makeSizeCastFields(comptime name: [:0]const u8, comptime categoryName: [:0]const u8, comptime order: AVI.SizeCast) []const u8 {
    const SIZE =
        if (comptime std.mem.endsWith(u8, categoryName, "Int")) AVI.INTEGER_SIZE
        else if (comptime std.mem.endsWith(u8, categoryName, "Float")) AVI.FLOAT_SIZE
        else {
            @compileError("unknown size cast type");
        };

    comptime var out: []const u8 = "";

    switch (order) {
        .up => {
            inline for (0..SIZE.len) |x| {
                const xsize = SIZE[x];
                inline for (x + 1..SIZE.len) |y| {
                    const ysize = SIZE[y];
                    const fieldName = std.fmt.comptimePrint("{s}{}x{}", .{name, xsize, ysize});
                    const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
                    out = out
                        ++ "<tr>"
                            ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                            ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                            ++ "<td align=\"center\" colspan=\"3\">"
                                ++ std.fmt.comptimePrint("{} bit to {} bit {s}", .{xsize, ysize, longName(name)})
                            ++ "</td>"
                        ++ "</tr>";
                }
            }
        },
        .down => {
            comptime var x: usize = SIZE.len;
            inline while (x > 0) : (x -= 1) {
                const xsize = SIZE[x - 1];
                comptime var y: usize = x - 1;
                inline while (y > 0) : (y -= 1) {
                    const ysize = SIZE[y - 1];
                    const fieldName = std.fmt.comptimePrint("{s}{}x{}", .{name, xsize, ysize});
                    const code = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldName))});
                    out = out
                        ++ "<tr>"
                            ++ "<td align=\"right\" width=\"1%\"><code>" ++ code ++ "</code></td>"
                            ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldName ++ "</code></td>"
                            ++ "<td align=\"center\" colspan=\"3\">"
                                ++ std.fmt.comptimePrint("{} bit to {} bit {s}", .{xsize, ysize, longName(name)})
                            ++ "</td>"
                        ++ "</tr>";
                }
            }
        },
    }

    return out;
}

fn makeIntFloatCastFields(comptime name: [:0]const u8) []const u8 {
    comptime var out: []const u8 = "";

    inline for (AVI.SIGNEDNESS) |sign| {
        inline for (AVI.INTEGER_SIZE) |int_size| {
            inline for (AVI.FLOAT_SIZE) |float_size| {
                const fieldNameA = std.fmt.comptimePrint("{u}{}_{s}_f{}", .{AVI.signChar(sign), int_size, name, float_size});
                const codeA = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldNameA))});
                out = out
                    ++ "<tr>"
                        ++ "<td align=\"right\" width=\"1%\"><code>" ++ codeA ++ "</code></td>"
                        ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldNameA ++ "</code></td>"
                        ++ "<td align=\"center\" colspan=\"3\">"
                            ++ std.fmt.comptimePrint("{} bit {s} integer to {} bit floating point conversion", .{int_size, @tagName(sign), float_size})
                        ++ "</td>"
                    ++ "</tr>";

                const fieldNameB = std.fmt.comptimePrint("f{}_{s}_{u}{}", .{float_size, name, AVI.signChar(sign), int_size});
                const codeB = std.fmt.comptimePrint("0x{x:0>2}", .{@intFromEnum(@field(OpCode, fieldNameA))});
                out = out
                    ++ "<tr>"
                        ++ "<td align=\"right\" width=\"1%\"><code>" ++ codeB ++ "</code></td>"
                        ++ "<td align=\"left\" width=\"1%\"><code>" ++ fieldNameB ++ "</code></td>"
                        ++ "<td align=\"center\" colspan=\"3\">"
                            ++ std.fmt.comptimePrint("{} bit floating point to {} bit {s} integer conversion", .{float_size, int_size, @tagName(sign)})
                        ++ "</td>"
                    ++ "</tr>";
            }
        }
    }

    return out;
}
