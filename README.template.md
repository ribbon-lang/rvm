<div align="left">
  <img style="height: 10em"
       alt="Ribbon Language Logo"
       src="https://ribbon-lang.github.io/images/logo_full.svg"
       />
</div>

<div align="right">
  <h1>rvm</h1>
  <h3>The Ribbon Virtual Machine</h3>
  <sup><!--#Readme:Build version--></sup>
</div>

---

This is a virtual machine implementation for the
[Ribbon](https://ribbon-lang.github.io) programming language.


## Contents

+ [Roadmap](#roadmap)
    - [Todo for v0.1.0 release](#todo-for-v010-release)
+ [Discussion](#discussion)
+ [Usage](#usage)
    - [Building from source](#building-from-source)
        * [Zig Build Commands](#zig-build-commands)
        * [Zig Build Options](#zig-build-options)
    - [Inclusion as a library](#inclusion-as-a-library)
        * [From Zig](#from-zig)
        * [From C](#from-c)
        * [From other languages](#from-other-languages)
    - [CLI](#cli)
+ [ISA](#isa)
    - [High Level Properties](#high-level-properties)
    - [Parameter Legend](#parameter-legend)
    - [Op Codes](#op-codes)
        <!--#Readme:ISA toc-->

## Roadmap

+ ✅ Bytecode interpreter (90%)
+ 🟥 CLI (0%)
+ 🟥 C Api (0%)

Initial development of the interpreter itself is essentially complete, aside
from the foreign function interface. Some bug squashing is likely still
necessary, of course, as testing is minimal at this time. C-Api and CLI are
non-existent right now.

#### Todo for v0.1.0 release:
+ Foreign function interface
+ Implement CLI
+ Implement C Api
+ More testing and cleanup


## Discussion

Eventually I will create some places for public discourse about the language,
for now you can reach me via:
- Email: noxabellus@gmail.com
- Discord DM, or on various dev servers: my username is `noxabellus`
- For `rvm`-specific inquiries, feel free to create an issue on this repository


## Usage

### Building from source

You will need [`zig`](https://ziglang.org/); likely, a nightly build.
The latest version known to work is `<!--#Readme:Build zig-version-->`.

You can either:
+ Get it through [ZVM](https://www.zvm.app/) or [Zigup](https://marler8997.github.io/zigup/) (Recommended)
+ [Download it directly](https://ziglang.org/download)
+ Get the nightly build through a script like [night.zig](https://github.com/jsomedon/night.zig/)

#### Zig Build Commands
There are several commands available for `zig build` that can be run in usual fashion (i.e. `zig build run`):
<!--#Readme:Build commands-->

Running `zig build` alone will build with the designated or default target and optimization levels.

See `zig build --help` for more information.

#### Zig Build Options
In addition to typical zig build options, the build script supports the following options (though not all apply to every step):
<!--#Readme:Build options-->

See `zig build --help` for more information.

### Inclusion as a library

#### From Zig

1. Include Rvm in your `build.zig.zon` in the `.dependencies` section,
   either by linking the tar, `zig fetch`, or provide a local path to the source.
2. Add Rvm to your module imports like this:
```zig
const rvm = b.dependency("rvm", .{
    // these should always be passed to ensure ribbon is built correctly
    .target = target,
    .optimize = optimize,

    // additional options can be passed here, these are the same as the build options
    // i.e.
    // .logLevel = .info,
});
module.addImport("Rvm", rvm.module("Core"));
```
3. See [`src/bin/rvm.zig`](src/bin/rvm.zig) for usage

#### From C

Should be straight forward, when the API is in place. Current status: 0%

Use the included header file, then link your program with the `.lib`/`.a` file.

#### From other languages

If your host language has C FFI, it should be fairly straight forward. If you make a binding for another language, please [let me know](#discussion) and I will link it here.


### CLI

The `rvm` executable is a work in progress.

#### CLI Usage
<!--#Readme:CLI usage-->

#### CLI Options
<!--#Readme:CLI options-->


## ISA

The instruction set architecture for Rvm is still in flux,
but here is a preliminary rundown.


### High level properties

+ 64-bit instructions
+ Little-endian encoding
+ Instruction suffixes for extra large immediates and variable-length operand sets
+ 64-bit registers + stack allocation
+ Separated address spaces for global data, executable, and working memory
+ Heap access controlled by host environment
+ 16-bit indexed spaces for:
    - global data
    - functions
    - blocks within functions
    - effect handler sets
    - effect handlers
+ Floating point values are IEEE754
+ Floats are fixed width, in sizes `32` and `64`
+ Integers are always two's complement
+ Integers are fixed width, in sizes `8`, `16`, `32`, and `64`
+ Sign of integers is not a property of types; only instructions
+ Structured control flow
+ Expression-oriented
+ Effects-aware
+ Tail recursion

### Parameter Legend

| Symbol | Type | Description | Bit Size |
| ------ | ---- | ----------- | -------- |
| `R` | RegisterIndex | Designates a register | `8` |
| `H` | HandlerSetIndex | Designates an effect handler set | `16` |
| `E` | EvidenceIndex | Designates a specific effect handler on the stack of effect handlers | `16` |
| `G` | GlobalIndex | Designates a global variable | `16` |
| `U` | UpvalueIndex | Designates a register in the enclosing scope of an effect handler | `8` |
| `F` | FunctionIndex | Designates a specific function | `16` |
| `B` | BlockIndex | Designates a specific block; may be either relative to the function (called absolute below) or relative to the block the instruction is in, depending on instruction type | `16` |
| `b` | Immediate | Immediate value encoded within the instruction | `8` |
| `s` | Immediate | Immediate value encoded within the instruction | `16` |
| `i` | Immediate | Immediate value encoded within the instruction | `32` |
| `w` | Immediate | Immediate value encoded after the instruction | `64` |


### Op codes

<!--#Readme:ISA body-->
