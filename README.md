<!-- File generated from README.template.md -->

<div align="center">
  <img style="height: 18em"
       alt="Ribbon Language Logo"
       src="https://ribbon-lang.github.io/images/logo_full.svg"
       />
</div>

<div align="right">
  <h1>Ribbon<sup>I</sup></h1>
  <h3>The Ribbon Virtual Machine</h3>
  <sup>v0.0.0</sup>
</div>

---

This is a virtual machine implementation for the Ribbon programming language. This
project is still in the very early development stages. For now, issues are
turned off and pull requests without prior [discussion](#discussion) are
discouraged.


## Contents

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
        * [Miscellaneous](#miscellaneous)
        * [Control Flow](#control-flow)
        * [Memory](#memory)
        * [Arithmetic](#arithmetic)
        * [Bitwise](#bitwise)
        * [Comparison](#comparison)
        * [Conversion](#conversion)


## Discussion

Eventually I will create some places for public discourse about the language,
for now you can reach me via:
- Email: noxabellus@gmail.com
- Discord DM, or on various dev servers: my username is `noxabellus`


## Usage

### Building from source

You will need [`zig`](https://ziglang.org/); likely, a nightly build.
The latest version known to work is `0.14.0-dev.1583+812557bfd`.

You can either:
+ Get it through [ZVM](https://www.zvm.app/) or [Zigup](https://marler8997.github.io/zigup/) (Recommended)
+ [Download it directly](https://ziglang.org/download)
+ Get the nightly build through a script like [night.zig](https://github.com/jsomedon/night.zig/)

#### Zig Build Commands
There are several commands available for `zig build` that can be run in usual fashion (i.e. `zig build run`):
| Command | Description |
|-|-|
|`run`| Build and run a quick debug test version of ribboni only (No headers, readme, lib ...) |
|`quick`| Build a quick debug test version of ribboni only (No headers, readme, lib ...) |
|`full`| Runs the following commands: test, readme, header |
|`verify`| Runs the following commands: verify-readme, verify-header, verify-tests |
|`check`| Run semantic analysis on all files referenced by a unit test; do not build artifacts (Useful with `zls` build on save) |
|`release`| Build the release versions of RibbonI for all targets |
|`unit-tests`| Run unit tests |
|`cli-tests`| Run cli tests |
|`c-tests`| Run C tests |
|`test`| Runs the following commands: unit-tests, cli-tests, c-tests |
|`readme`| Generate `./README.md` |
|`header`| Generate `./include/ribboni.h` |
|`verify-readme`| Verify that `./README.md` is up to date |
|`verify-header`| Verify that `./include/ribboni.h` is up to date |
|`verify-tests`| Verify that all tests pass (this is an alias for `test`) |


Running `zig build` alone will build with the designated or default target and optimization levels.

See `zig build --help` for more information.

#### Zig Build Options
In addition to typical zig build options, the build script supports the following options (though not all apply to every step):
<table>
    <tr>
        <td>Option</td>
        <td>Description</td>
        <td>Default</td>
    <tr>
        <td><code>-DlogLevel=&lt;log.Level&gt;</code></td>
        <td>Logging output level to display</td>
        <td><code>.err</code></td>
    </tr>
    <tr>
        <td><code>-DlogScopes=&lt;string&gt;</code></td>
        <td>Logging scopes to display</td>
        <td><code>ribboni</code></td>
    </tr>
    <tr>
        <td><code>-DuseEmoji=&lt;bool&gt;</code></td>
        <td>Use emoji in the output</td>
        <td><code>true</code></td>
    </tr>
    <tr>
        <td><code>-DuseAnsiStyles=&lt;bool&gt;</code></td>
        <td>Use ANSI styles in the output</td>
        <td><code>true</code></td>
    </tr>
    <tr>
        <td><code>-DforceNewSnapshot=&lt;bool&gt;</code></td>
        <td>(Tests) Force a new snapshot to be created instead of referring to an existing one</td>
        <td><code>false</code></td>
    </tr>
    <tr>
        <td><code>-DstripDebugInfo=&lt;bool&gt;</code></td>
        <td colspan="2">Override for optimization-specific settings for stripping debug info from the binary. This will default to <code>true</code> when <code>-Doptimize</code> is not set to <code>Debug</code></td>
    </tr>
    <tr>
        <td><code>-DmaximumInlining=&lt;bool&gt;</code></td>
        <td colspan="2">Override for optimization-specific settings for inlining as much as possible in the interpreter. This will default to <code>true</code> when <code>-Doptimize</code> is not set to <code>Debug</code></td>
    </tr>
</table>


See `zig build --help` for more information.

### Inclusion as a library

#### From Zig

1. Include RibbonI in your `build.zig.zon` in the `.dependencies` section,
   either by linking the tar, `zig fetch`, or provide a local path to the source.
2. Add RibbonI to your module imports like this:
```zig
const ribbon_i = b.dependency("ribbon-i", .{
    // these should always be passed to ensure ribbon is built correctly
    .target = target,
    .optimize = optimize,

    // additional options can be passed here, these are the same as the build options
    // i.e.
    // .logLevel = .info,
});
module.addImport("RibbonI", ribbon_i.module("Core"));
```
3. See [`src/bin/ribboni.zig`](src/bin/ribboni.zig) for usage

#### From C

Should be straight forward, though the API is limited as of now.
Use the included header file, then link your program with the `.lib`/`.a` file.

#### From other languages

If your host language has C FFI, it should be fairly straight forward. If you make a binding for another language, please [let me know](#discussion) and I will link it here.


### CLI

The `ribboni` executable is a work in progress, but offers a functional command line interface for RibbonI.

#### CLI Usage
```
ribboni [--use-emoji <bool>] [--use-ansi-styles <bool>] <path>...
```
```
ribboni --help
```
```
ribboni --version
```

#### CLI Options
| Option | Description |
|-|-|
|`--help`| Display options help message, and exit |
|`--version`| Display SemVer2 version number for RibbonI, and exit |
|`--use-emoji <bool>`| Use emoji in the output [Default: true] |
|`--use-ansi-styles <bool>`| Use ANSI styles in the output [Default: true] |
|`<path>...`| Files to execute |


## ISA

The instruction set architecture for RibbonI is still in flux,
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

Current total number of instructions: 470
#### Miscellaneous

+ [nop](#nop)
##### nop
Not an operation; does nothing
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0000` | **nop** | No operation |  |


#### Control Flow
Control the flow of program execution
+ [halt](#halt)
+ [trap](#trap)
+ [block](#block)
+ [with](#with)
+ [if](#if)
+ [when](#when)
+ [re](#re)
+ [br](#br)
+ [call](#call)
+ [prompt](#prompt)
+ [ret](#ret)
+ [term](#term)
##### halt
Stops execution of the program
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0001` | **halt** | Halt execution |  |

##### trap
Stops execution of the program and triggers the `unreachable` trap
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0002` | **trap** | Trigger a trap |  |

##### block
Unconditionally enter the block designated by the block operand

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0003` | **block** | Enter a block | `B` |
| `0004` | **block_v** | Enter a block, placing the output value in the designated register | `B`,&nbsp;`R` |

##### with
Enter the block designated by the block operand, using the handler set operand to handle matching effects inside

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0005` | **with** | Enter a block, using the designated handler set | `B`,&nbsp;`H` |
| `0006` | **with_v** | Enter a block, using the designated handler set, and place the output value in the designated register | `B`,&nbsp;`H`,&nbsp;`R` |

##### if
If the 8-bit conditional value designated by the register operand matches the test:
+ Then: Enter the block designated by the block operand
+ Else: Enter the block designated by the else block operand

The block operands are absolute block indices
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0007` | **if_nz** | Enter the first block, if the condition is non-zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R` |
| `0008` | **if_nz_v** | Enter the first block, if the condition is non-zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R`,&nbsp;`R` |
| `0009` | **if_z** | Enter the first block, if the condition is zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R` |
| `000a` | **if_z_v** | Enter the first block, if the condition is zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R`,&nbsp;`R` |

##### when
If the 8-bit conditional value designated by the register operand matches the test:
+ Enter the block designated by the block operand

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `000b` | **when_nz** | Enter a block, if the condition is non-zero | `B`,&nbsp;`R` |
| `000c` | **when_z** | Enter a block, if the condition is zero | `B`,&nbsp;`R` |

##### re
Restart the block designated by the block operand

The block operand is a relative block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `000d` | **re** | Restart the designated block | `B` |
| `000e` | **re_nz** | Restart the designated block, if the condition is non-zero | `B`,&nbsp;`R` |
| `000f` | **re_z** | Restart the designated block, if the condition is zero | `B`,&nbsp;`R` |

##### br
Exit the block designated by the block operand

The block operand is a relative block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0010` | **br** | Exit the designated block | `B` |
| `0011` | **br_nz** | Exit the designated block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0012` | **br_z** | Exit the designated block, if the condition is zero | `B`,&nbsp;`R` |
| `0013` | **br_v** | Exit the designated block, yielding the value in the designated register | `B`,&nbsp;`R` |
| `0014` | **br_nz_v** | Exit the designated block, if the condition is non-zero; yield the value in the secondary register | `B`,&nbsp;`R`,&nbsp;`R` |
| `0015` | **br_z_v** | Exit the designated block, if the condition is zero; yield the value in the secondary register | `B`,&nbsp;`R`,&nbsp;`R` |
| `0016` | **br_im_v** | Exit the designated block, yielding an immediate up to 32 bits | `B`,&nbsp;`i` |
| `0017` | **br_im_w_v** | Exit the designated block, yielding an immediate up to 64 bits | `B`&nbsp;+&nbsp;`w` |
| `0018` | **br_nz_im_v** | Exit the designated block, if the condition is non-zero; yield an immediate | `B`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0019` | **br_z_im_v** | Exit the designated block, if the condition is zero; yield an immediate | `B`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### call
Call the function designated by the function operand; expects a number of arguments matching that of the callee to follow this instruction
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `001a` | **call_im** | Call a static function, expecting no return value (discards the result, if there is one) | `F` |
| `001b` | **call_im_v** | Call a static function, and place the return value in the designated register | `F`,&nbsp;`R` |
| `001c` | **tail_call_im** | Call a static function in tail position, expecting no return value (discards the result, if there is one) | `F` |
| `001d` | **tail_call_im_v** | Call a static function in tail position, expecting a return value (places the result in the caller's return register) | `F` |
| `001e` | **call** | Call a dynamic function, expecting no return value (discards the result, if there is one) | `R` |
| `001f` | **call_v** | Call a dynamic function, and place the return value in the designated register | `R`,&nbsp;`R` |
| `0020` | **tail_call** | Call a dynamic function in tail position, expecting no return value (discards the result, if there is one) | `R` |
| `0021` | **tail_call_v** | Call a dynamic function in tail position, and place the result in the caller's return register | `R`,&nbsp;`R` |

##### prompt
Call the effect handler designated by the evidence operand; expects a number of arguments matching that of the callee to follow this instruction
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0022` | **prompt** | Call an effect handler, expecting no return value (discards the result, if there is one) | `E` |
| `0023` | **prompt_v** | Call an effect handler, and place the return value in the designated register | `E`,&nbsp;`R` |
| `0024` | **tail_prompt** | Call an effect handler in tail position, expecting no return value (discards the result, if there is one) | `E` |
| `0025` | **tail_prompt_v** | Call an effect handler in tail position, and place the return value in the caller's return register | `E` |

##### ret
Return from the current function, optionally placing the result in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0026` | **ret** | Return from the current function, yielding no value |  |
| `0027` | **ret_v** | Return from the current function, yielding the value in the designated register | `R` |
| `0028` | **ret_im_v** | Return from the current function, yielding an immediate value up to 32 bits | `i` |
| `0029` | **ret_im_w_v** | Return from the current function, yielding an immediate value up to 64 bits | `w` |

##### term
Trigger early-termination of an effect handler, ending the block it was introduced in
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `002a` | **term** | Terminate the current effect handler, yielding no value |  |
| `002b` | **term_v** | Terminate the current effect handler, yielding the value in the designated register | `R` |
| `002c` | **term_im_v** | Terminate the current effect handler, yielding an immediate value up to 32 bits | `i` |
| `002d` | **term_im_w_v** | Terminate the current effect handler, yielding an immediate value up to 64 bits | `w` |


#### Memory
Instructions for memory access and manipulation
+ [alloca](#alloca)
+ [addr](#addr)
+ [read_global](#read_global)
+ [read_upvalue](#read_upvalue)
+ [write_global](#write_global)
+ [write_upvalue](#write_upvalue)
+ [load](#load)
+ [store](#store)
+ [clear](#clear)
+ [swap](#swap)
+ [copy](#copy)
##### alloca
Allocate a number of bytes on the stack, placing the address in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `002e` | **alloca** | Allocate a number of bytes (up to 65k) on the stack, placing the address in the register | `s`,&nbsp;`R` |

##### addr
Place the address of the value designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `002f` | **addr_global** | Place the address of the global into the register | `G`,&nbsp;`R` |
| `0030` | **addr_upvalue** | Place the address of the upvalue into the register | `U`,&nbsp;`R` |
| `0031` | **addr_local** | Place the address of the first register into the second register | `R`,&nbsp;`R` |

##### read_global
Copy a number of bits from the global designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0032` | **read_global_8** | Copy 8 bits from the global into the register | `G`,&nbsp;`R` |
| `0033` | **read_global_16** | Copy 16 bits from the global into the register | `G`,&nbsp;`R` |
| `0034` | **read_global_32** | Copy 32 bits from the global into the register | `G`,&nbsp;`R` |
| `0035` | **read_global_64** | Copy 64 bits from the global into the register | `G`,&nbsp;`R` |

##### read_upvalue
Copy a number of bits from the upvalue designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0036` | **read_upvalue_8** | Copy 8 bits from the upvalue into the register | `U`,&nbsp;`R` |
| `0037` | **read_upvalue_16** | Copy 16 bits from the upvalue into the register | `U`,&nbsp;`R` |
| `0038` | **read_upvalue_32** | Copy 32 bits from the upvalue into the register | `U`,&nbsp;`R` |
| `0039` | **read_upvalue_64** | Copy 64 bits from the upvalue into the register | `U`,&nbsp;`R` |

##### write_global
Copy a number of bits from the value designated by the first operand into the global provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `003a` | **write_global_8** | Copy 8 bits from the register into the global | `R`,&nbsp;`G` |
| `003b` | **write_global_16** | Copy 16 bits from the register into the global | `R`,&nbsp;`G` |
| `003c` | **write_global_32** | Copy 32 bits from the register into the global | `R`,&nbsp;`G` |
| `003d` | **write_global_64** | Copy 64 bits from the register into the global | `R`,&nbsp;`G` |
| `003e` | **write_global_8_im** | Copy 8 bits from the immediate into the global | `b`,&nbsp;`G` |
| `003f` | **write_global_16_im** | Copy 16 bits from the immediate into the global | `s`,&nbsp;`G` |
| `0040` | **write_global_32_im** | Copy 32 bits from the immediate into the global | `i`,&nbsp;`G` |
| `0041` | **write_global_64_im** | Copy 64 bits from the immediate into the global | `G`&nbsp;+&nbsp;`w` |

##### write_upvalue
Copy a number of bits from the value designated by the first operand into the upvalue provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0042` | **write_upvalue_8** | Copy 8 bits from the register into the designated upvalue | `R`,&nbsp;`U` |
| `0043` | **write_upvalue_16** | Copy 16 bits from the register into the designated upvalue | `R`,&nbsp;`U` |
| `0044` | **write_upvalue_32** | Copy 32 bits from the register into the designated upvalue | `R`,&nbsp;`U` |
| `0045` | **write_upvalue_64** | Copy 64 bits from the register into the designated upvalue | `R`,&nbsp;`U` |
| `0046` | **write_upvalue_8_im** | Copy 8 bits from the immediate into the designated upvalue | `b`,&nbsp;`R` |
| `0047` | **write_upvalue_16_im** | Copy 16 bits from the immediate into the designated upvalue | `s`,&nbsp;`R` |
| `0048` | **write_upvalue_32_im** | Copy 32 bits from the register into the designated upvalue | `i`,&nbsp;`R` |
| `0049` | **write_upvalue_64_im** | Copy 64 bits from the immediate into the designated upvalue | `R`&nbsp;+&nbsp;`w` |

##### load
Copy a number of bits from the memory address designated by the first operand into the register provided in the second operand

The address must be located on the stack or global memory
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `004a` | **load_8** | Copy 8 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `004b` | **load_16** | Copy 16 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `004c` | **load_32** | Copy 32 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `004d` | **load_64** | Copy 64 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |

##### store
Copy a number of bits from the value designated by the first operand into the memory address in the register provided in the second operand

The address must be located on the stack or global memory
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `004e` | **store_8** | Copy 8 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `004f` | **store_16** | Copy 16 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `0050` | **store_32** | Copy 32 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `0051` | **store_64** | Copy 64 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `0052` | **store_8_im** | Copy 8 bits from the immediate into the memory address in the register | `b`,&nbsp;`R` |
| `0053` | **store_16_im** | Copy 16 bits from the immediate into the memory address in the register | `s`,&nbsp;`R` |
| `0054` | **store_32_im** | Copy 32 bits from the immediate into the memory address in the register | `i`,&nbsp;`R` |
| `0055` | **store_64_im** | Copy 64 bits from the immediate into the memory address in the register | `R`&nbsp;+&nbsp;`w` |

##### clear
Clear a number of bits in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0056` | **clear_8** | Clear 8 bits from the register | `R` |
| `0057` | **clear_16** | Clear 16 bits from the register | `R` |
| `0058` | **clear_32** | Clear 32 bits from the register | `R` |
| `0059` | **clear_64** | Clear 64 bits from the register | `R` |

##### swap
Swap a number of bits in the two designated registers
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `005a` | **swap_8** | Swap 8 bits between the two registers | `R`,&nbsp;`R` |
| `005b` | **swap_16** | Swap 16 bits between the two registers | `R`,&nbsp;`R` |
| `005c` | **swap_32** | Swap 32 bits between the two registers | `R`,&nbsp;`R` |
| `005d` | **swap_64** | Swap 64 bits between the two registers | `R`,&nbsp;`R` |

##### copy
Copy a number of bits from the first register into the second register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `005e` | **copy_8** | Copy 8 bits from the first register into the second register | `R`,&nbsp;`R` |
| `005f` | **copy_16** | Copy 16 bits from the first register into the second register | `R`,&nbsp;`R` |
| `0060` | **copy_32** | Copy 32 bits from the first register into the second register | `R`,&nbsp;`R` |
| `0061` | **copy_64** | Copy 64 bits from the first register into the second register | `R`,&nbsp;`R` |
| `0062` | **copy_8_im** | Copy 8-bits from an immediate value into the register | `b`,&nbsp;`R` |
| `0063` | **copy_16_im** | Copy 16-bits from an immediate value into the register | `s`,&nbsp;`R` |
| `0064` | **copy_32_im** | Copy 32-bits from an immediate value into the register | `i`,&nbsp;`R` |
| `0065` | **copy_64_im** | Copy 64-bits from an immediate value into the register | `R`&nbsp;+&nbsp;`w` |


#### Arithmetic
Basic arithmetic operations
+ [add](#add)
+ [sub](#sub)
+ [mul](#mul)
+ [div](#div)
+ [rem](#rem)
+ [neg](#neg)
##### add
Addition on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0066` | **i_add_8** | Sign-agnostic addition on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0067` | **i_add_16** | Sign-agnostic addition on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0068` | **i_add_32** | Sign-agnostic addition on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0069` | **i_add_64** | Sign-agnostic addition on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `006a` | **i_add_8_im** | Sign-agnostic addition on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `006b` | **i_add_16_im** | Sign-agnostic addition on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `006c` | **i_add_32_im** | Sign-agnostic addition on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `006d` | **i_add_64_im** | Sign-agnostic addition on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `006e` | **f_add_32** | Addition on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `006f` | **f_add_64** | Addition on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0070` | **f_add_32_im** | Addition on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `0071` | **f_add_64_im** | Addition on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### sub
Subtraction on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0072` | **i_sub_8** | Sign-agnostic subtraction on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0073` | **i_sub_16** | Sign-agnostic subtraction on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0074` | **i_sub_32** | Sign-agnostic subtraction on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0075` | **i_sub_64** | Sign-agnostic subtraction on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0076` | **i_sub_8_im_a** | Sign-agnostic subtraction on 8-bit integers; subtract register value from immediate value | `b`,&nbsp;`R`,&nbsp;`R` |
| `0077` | **i_sub_16_im_a** | Sign-agnostic subtraction on 16-bit integers; subtract register value from immediate value | `s`,&nbsp;`R`,&nbsp;`R` |
| `0078` | **i_sub_32_im_a** | Sign-agnostic subtraction on 32-bit integers; subtract register value from immediate value | `i`,&nbsp;`R`,&nbsp;`R` |
| `0079` | **i_sub_64_im_a** | Sign-agnostic subtraction on 64-bit integers; subtract register value from immediate value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `007a` | **i_sub_8_im_b** | Sign-agnostic subtraction on 8-bit integers; subtract immediate value from register value | `R`,&nbsp;`b`,&nbsp;`R` |
| `007b` | **i_sub_16_im_b** | Sign-agnostic subtraction on 16-bit integers; subtract immediate value from register value | `R`,&nbsp;`s`,&nbsp;`R` |
| `007c` | **i_sub_32_im_b** | Sign-agnostic subtraction on 32-bit integers; subtract immediate value from register value | `R`,&nbsp;`i`,&nbsp;`R` |
| `007d` | **i_sub_64_im_b** | Sign-agnostic subtraction on 64-bit integers; subtract immediate value from register value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `007e` | **f_sub_32** | Subtraction on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `007f` | **f_sub_64** | Subtraction on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0080` | **f_sub_32_im_a** | Subtraction on 32-bit floats; subtract register value from immediate value | `i`,&nbsp;`R`,&nbsp;`R` |
| `0081` | **f_sub_64_im_a** | Subtraction on 64-bit floats; subtract register value from immediate value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0082` | **f_sub_32_im_b** | Subtraction on 32-bit floats; subtract immediate value from register value | `R`,&nbsp;`i`,&nbsp;`R` |
| `0083` | **f_sub_64_im_b** | Subtraction on 64-bit floats; subtract immediate value from register value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### mul
Multiplication on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0084` | **i_mul_8** | Sign-agnostic multiplication on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0085` | **i_mul_16** | Sign-agnostic multiplication on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0086` | **i_mul_32** | Sign-agnostic multiplication on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0087` | **i_mul_64** | Sign-agnostic multiplication on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0088` | **i_mul_8_im** | Sign-agnostic multiplication on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `0089` | **i_mul_16_im** | Sign-agnostic multiplication on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `008a` | **i_mul_32_im** | Sign-agnostic multiplication on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `008b` | **i_mul_64_im** | Sign-agnostic multiplication on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `008c` | **f_mul_32** | Multiplication on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `008d` | **f_mul_64** | Multiplication on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `008e` | **f_mul_32_im** | Multiplication on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `008f` | **f_mul_64_im** | Multiplication on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### div
Division on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0090` | **u_div_8** | Unsigned division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0091` | **u_div_16** | Unsigned division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0092` | **u_div_32** | Unsigned division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0093` | **u_div_64** | Unsigned division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0094` | **u_div_8_im_a** | Unsigned division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `0095` | **u_div_16_im_a** | Unsigned division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `0096` | **u_div_32_im_a** | Unsigned division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `0097` | **u_div_64_im_a** | Unsigned division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0098` | **u_div_8_im_b** | Unsigned division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `0099` | **u_div_16_im_b** | Unsigned division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `009a` | **u_div_32_im_b** | Unsigned division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `009b` | **u_div_64_im_b** | Unsigned division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `009c` | **s_div_8** | Signed division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `009d` | **s_div_16** | Signed division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `009e` | **s_div_32** | Signed division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `009f` | **s_div_64** | Signed division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00a0` | **s_div_8_im_a** | Signed division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `00a1` | **s_div_16_im_a** | Signed division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `00a2` | **s_div_32_im_a** | Signed division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `00a3` | **s_div_64_im_a** | Signed division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00a4` | **s_div_8_im_b** | Signed division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `00a5` | **s_div_16_im_b** | Signed division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `00a6` | **s_div_32_im_b** | Signed division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `00a7` | **s_div_64_im_b** | Signed division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00a8` | **f_div_32** | Division on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00a9` | **f_div_64** | Division on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00aa` | **f_div_32_im_a** | Division on 32-bit floats; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `00ab` | **f_div_64_im_a** | Division on 64-bit floats; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00ac` | **f_div_32_im_b** | Division on 32-bit floats; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `00ad` | **f_div_64_im_b** | Division on 64-bit floats; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### rem
Remainder division on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00ae` | **u_rem_8** | Unsigned remainder division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00af` | **u_rem_16** | Unsigned remainder division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00b0` | **u_rem_32** | Unsigned remainder division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00b1` | **u_rem_64** | Unsigned remainder division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00b2` | **u_rem_8_im_a** | Unsigned remainder division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `00b3` | **u_rem_16_im_a** | Unsigned remainder division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `00b4` | **u_rem_32_im_a** | Unsigned remainder division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `00b5` | **u_rem_64_im_a** | Unsigned remainder division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00b6` | **u_rem_8_im_b** | Unsigned remainder division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `00b7` | **u_rem_16_im_b** | Unsigned remainder division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `00b8` | **u_rem_32_im_b** | Unsigned remainder division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `00b9` | **u_rem_64_im_b** | Unsigned remainder division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00ba` | **s_rem_8** | Signed remainder division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00bb` | **s_rem_16** | Signed remainder division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00bc` | **s_rem_32** | Signed remainder division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00bd` | **s_rem_64** | Signed remainder division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00be` | **s_rem_8_im_a** | Signed remainder division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `00bf` | **s_rem_16_im_a** | Signed remainder division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `00c0` | **s_rem_32_im_a** | Signed remainder division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `00c1` | **s_rem_64_im_a** | Signed remainder division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00c2` | **s_rem_8_im_b** | Signed remainder division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `00c3` | **s_rem_16_im_b** | Signed remainder division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `00c4` | **s_rem_32_im_b** | Signed remainder division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `00c5` | **s_rem_64_im_b** | Signed remainder division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00c6` | **f_rem_32** | Remainder division on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00c7` | **f_rem_64** | Remainder division on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00c8` | **f_rem_32_im_a** | Remainder division on 32-bit floats; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `00c9` | **f_rem_64_im_a** | Remainder division on 64-bit floats; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00ca` | **f_rem_32_im_b** | Remainder division on 32-bit floats; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `00cb` | **f_rem_64_im_b** | Remainder division on 64-bit floats; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### neg
Negation of a single operand, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00cc` | **s_neg_8** | Negation of an 8-bit integer | `R`,&nbsp;`R` |
| `00cd` | **s_neg_16** | Negation of a 16-bit integer | `R`,&nbsp;`R` |
| `00ce` | **s_neg_32** | Negation of a 32-bit integer | `R`,&nbsp;`R` |
| `00cf` | **s_neg_64** | Negation of a 64-bit integer | `R`,&nbsp;`R` |
| `00d0` | **f_neg_32** | Negation of a 32-bit float | `R`,&nbsp;`R` |
| `00d1` | **f_neg_64** | Negation of a 64-bit float | `R`,&nbsp;`R` |


#### Bitwise
Basic bitwise operations
+ [band](#band)
+ [bor](#bor)
+ [bxor](#bxor)
+ [bnot](#bnot)
+ [bshiftl](#bshiftl)
+ [bshiftr](#bshiftr)
##### band
Bitwise AND on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00d2` | **band_8** | Bitwise AND on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00d3` | **band_16** | Bitwise AND on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00d4` | **band_32** | Bitwise AND on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00d5` | **band_64** | Bitwise AND on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00d6` | **band_8_im** | Bitwise AND on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `00d7` | **band_16_im** | Bitwise AND on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `00d8` | **band_32_im** | Bitwise AND on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `00d9` | **band_64_im** | Bitwise AND on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bor
Bitwise OR on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00da` | **bor_8** | Bitwise OR on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00db` | **bor_16** | Bitwise OR on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00dc` | **bor_32** | Bitwise OR on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00dd` | **bor_64** | Bitwise OR on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00de` | **bor_8_im** | Bitwise OR on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `00df` | **bor_16_im** | Bitwise OR on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `00e0` | **bor_32_im** | Bitwise OR on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `00e1` | **bor_64_im** | Bitwise OR on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bxor
Bitwise XOR on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00e2` | **bxor_8** | Bitwise XOR on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00e3` | **bxor_16** | Bitwise XOR on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00e4` | **bxor_32** | Bitwise XOR on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00e5` | **bxor_64** | Bitwise XOR on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00e6` | **bxor_8_im** | Bitwise XOR on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `00e7` | **bxor_16_im** | Bitwise XOR on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `00e8` | **bxor_32_im** | Bitwise XOR on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `00e9` | **bxor_64_im** | Bitwise XOR on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bnot
Bitwise NOT on a single operand, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00ea` | **bnot_8** | Bitwise NOT on an 8-bit integer in a register | `R`,&nbsp;`R` |
| `00eb` | **bnot_16** | Bitwise NOT on a 16-bit integer in registers | `R`,&nbsp;`R` |
| `00ec` | **bnot_32** | Bitwise NOT on a 32-bit integer in a register | `R`,&nbsp;`R` |
| `00ed` | **bnot_64** | Bitwise NOT on a 64-bit integer in a register | `R`,&nbsp;`R` |

##### bshiftl
Bitwise left shift on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00ee` | **bshiftl_8** | Bitwise left shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00ef` | **bshiftl_16** | Bitwise left shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00f0` | **bshiftl_32** | Bitwise left shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00f1` | **bshiftl_64** | Bitwise left shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00f2` | **bshiftl_8_im_a** | Bitwise left shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `00f3` | **bshiftl_16_im_a** | Bitwise left shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `00f4` | **bshiftl_32_im_a** | Bitwise left shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `00f5` | **bshiftl_64_im_a** | Bitwise left shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `00f6` | **bshiftl_8_im_b** | Bitwise left shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`b`,&nbsp;`R` |
| `00f7` | **bshiftl_16_im_b** | Bitwise left shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`s`,&nbsp;`R` |
| `00f8` | **bshiftl_32_im_b** | Bitwise left shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`i`,&nbsp;`R` |
| `00f9` | **bshiftl_64_im_b** | Bitwise left shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bshiftr
Bitwise right shift on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `00fa` | **u_bshiftr_8** | Logical bitwise right shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00fb` | **u_bshiftr_16** | Logical bitwise right shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00fc` | **u_bshiftr_32** | Logical bitwise right shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00fd` | **u_bshiftr_64** | Logical bitwise right shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `00fe` | **u_bshiftr_8_im_a** | Logical bitwise right shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `00ff` | **u_bshiftr_16_im_a** | Logical bitwise right shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `0100` | **u_bshiftr_32_im_a** | Logical bitwise right shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `0101` | **u_bshiftr_64_im_a** | Logical bitwise right shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0102` | **u_bshiftr_8_im_b** | Logical bitwise right shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`b`,&nbsp;`R` |
| `0103` | **u_bshiftr_16_im_b** | Logical bitwise right shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`s`,&nbsp;`R` |
| `0104` | **u_bshiftr_32_im_b** | Logical bitwise right shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`i`,&nbsp;`R` |
| `0105` | **u_bshiftr_64_im_b** | Logical bitwise right shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0106` | **s_bshiftr_8** | Arithmetic bitwise right shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0107` | **s_bshiftr_16** | Arithmetic bitwise right shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0108` | **s_bshiftr_32** | Arithmetic bitwise right shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0109` | **s_bshiftr_64** | Arithmetic bitwise right shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `010a` | **s_bshiftr_8_im_a** | Arithmetic bitwise right shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `010b` | **s_bshiftr_16_im_a** | Arithmetic bitwise right shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `010c` | **s_bshiftr_32_im_a** | Arithmetic bitwise right shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `010d` | **s_bshiftr_64_im_a** | Arithmetic bitwise right shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `010e` | **s_bshiftr_8_im_b** | Arithmetic bitwise right shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`b`,&nbsp;`R` |
| `010f` | **s_bshiftr_16_im_b** | Arithmetic bitwise right shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`s`,&nbsp;`R` |
| `0110` | **s_bshiftr_32_im_b** | Arithmetic bitwise right shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`i`,&nbsp;`R` |
| `0111` | **s_bshiftr_64_im_b** | Arithmetic bitwise right shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |


#### Comparison
Value comparison operations
+ [eq](#eq)
+ [ne](#ne)
+ [lt](#lt)
+ [gt](#gt)
+ [le](#le)
+ [ge](#ge)
##### eq
Equality comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0112` | **i_eq_8** | Sign-agnostic equality comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0113` | **i_eq_16** | Sign-agnostic equality comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0114` | **i_eq_32** | Sign-agnostic equality comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0115` | **i_eq_64** | Sign-agnostic equality comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0116` | **i_eq_8_im** | Sign-agnostic equality comparison on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `0117` | **i_eq_16_im** | Sign-agnostic equality comparison on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `0118` | **i_eq_32_im** | Sign-agnostic equality comparison on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `0119` | **i_eq_64_im** | Sign-agnostic equality comparison on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `011a` | **f_eq_32** | Equality comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `011b` | **f_eq_64** | Equality comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `011c` | **f_eq_32_im** | Equality comparison on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `011d` | **f_eq_64_im** | Equality comparison on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### ne
Inequality comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `011e` | **i_ne_8** | Sign-agnostic inequality comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `011f` | **i_ne_16** | Sign-agnostic inequality comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0120` | **i_ne_32** | Sign-agnostic inequality comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0121` | **i_ne_64** | Sign-agnostic inequality comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0122` | **i_ne_8_im** | Sign-agnostic inequality comparison on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `0123` | **i_ne_16_im** | Sign-agnostic inequality comparison on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `0124` | **i_ne_32_im** | Sign-agnostic inequality comparison on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `0125` | **i_ne_64_im** | Sign-agnostic inequality comparison on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0126` | **f_ne_32** | Inequality comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0127` | **f_ne_64** | Inequality comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0128` | **f_ne_32_im** | Inequality comparison on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `0129` | **f_ne_64_im** | Inequality comparison on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### lt
Less than comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `012a` | **u_lt_8** | Unsigned less than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `012b` | **u_lt_16** | Unsigned less than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `012c` | **u_lt_32** | Unsigned less than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `012d` | **u_lt_64** | Unsigned less than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `012e` | **u_lt_8_im_a** | Unsigned less than comparison on 8-bit integers; check register less than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `012f` | **u_lt_16_im_a** | Unsigned less than comparison on 16-bit integers; check register less than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `0130` | **u_lt_32_im_a** | Unsigned less than comparison on 32-bit integers; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `0131` | **u_lt_64_im_a** | Unsigned less than comparison on 64-bit integers; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0132` | **u_lt_8_im_b** | Unsigned less than comparison on 8-bit integers; check immediate less than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `0133` | **u_lt_16_im_b** | Unsigned less than comparison on 16-bit integers; check immediate less than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `0134` | **u_lt_32_im_b** | Unsigned less than comparison on 32-bit integers; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0135` | **u_lt_64_im_b** | Unsigned less than comparison on 64-bit integers; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0136` | **s_lt_8** | Signed less than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0137` | **s_lt_16** | Signed less than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0138` | **s_lt_32** | Signed less than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0139` | **s_lt_64** | Signed less than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `013a` | **s_lt_8_im_a** | Signed less than comparison on 8-bit integers; check register less than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `013b` | **s_lt_16_im_a** | Signed less than comparison on 16-bit integers; check register less than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `013c` | **s_lt_32_im_a** | Signed less than comparison on 32-bit integers; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `013d` | **s_lt_64_im_a** | Signed less than comparison on 64-bit integers; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `013e` | **s_lt_8_im_b** | Signed less than comparison on 8-bit integers; check immediate less than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `013f` | **s_lt_16_im_b** | Signed less than comparison on 16-bit integers; check immediate less than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `0140` | **s_lt_32_im_b** | Signed less than comparison on 32-bit integers; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0141` | **s_lt_64_im_b** | Signed less than comparison on 64-bit integers; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0142` | **f_lt_32** | Less than comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0143` | **f_lt_64** | Less than comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0144` | **f_lt_32_im_a** | Less than comparison on 32-bit floats; one immediate; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `0145` | **f_lt_64_im_a** | Less than comparison on 64-bit floats; one immediate; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0146` | **f_lt_32_im_b** | Less than comparison on 32-bit floats; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0147` | **f_lt_64_im_b** | Less than comparison on 64-bit floats; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### gt
Greater than comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0148` | **u_gt_8** | Unsigned greater than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0149` | **u_gt_16** | Unsigned greater than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `014a` | **u_gt_32** | Unsigned greater than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `014b` | **u_gt_64** | Unsigned greater than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `014c` | **u_gt_8_im_a** | Unsigned greater than comparison on 8-bit integers; check register greater than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `014d` | **u_gt_16_im_a** | Unsigned greater than comparison on 16-bit integers; check register greater than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `014e` | **u_gt_32_im_a** | Unsigned greater than comparison on 32-bit integers; check register greater than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `014f` | **u_gt_64_im_a** | Unsigned greater than comparison on 64-bit integers; check register greater than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0150` | **u_gt_8_im_b** | Unsigned greater than comparison on 8-bit integers; check immediate greater than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `0151` | **u_gt_16_im_b** | Unsigned greater than comparison on 16-bit integers; check immediate greater than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `0152` | **u_gt_32_im_b** | Unsigned greater than comparison on 32-bit integers; check immediate greater than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0153` | **u_gt_64_im_b** | Unsigned greater than comparison on 64-bit integers; check immediate greater than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0154` | **s_gt_8** | Signed greater than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0155` | **s_gt_16** | Signed greater than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0156` | **s_gt_32** | Signed greater than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0157` | **s_gt_64** | Signed greater than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0158` | **s_gt_8_im_a** | Signed greater than comparison on 8-bit integers; check register greater than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `0159` | **s_gt_16_im_a** | Signed greater than comparison on 16-bit integers; check register greater than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `015a` | **s_gt_32_im_a** | Signed greater than comparison on 32-bit integers; check register greater than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `015b` | **s_gt_64_im_a** | Signed greater than comparison on 64-bit integers; check register greater than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `015c` | **s_gt_8_im_b** | Signed greater than comparison on 8-bit integers; check immediate greater than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `015d` | **s_gt_16_im_b** | Signed greater than comparison on 16-bit integers; check immediate greater than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `015e` | **s_gt_32_im_b** | Signed greater than comparison on 32-bit integers; check immediate greater than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `015f` | **s_gt_64_im_b** | Signed greater than comparison on 64-bit integers; check immediate greater than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0160` | **f_gt_32** | Greater than comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0161` | **f_gt_64** | Greater than comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0162` | **f_gt_32_im_a** | Greater than comparison on 32-bit floats; one immediate; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `0163` | **f_gt_64_im_a** | Greater than comparison on 64-bit floats; one immediate; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0164` | **f_gt_32_im_b** | Greater than comparison on 32-bit floats; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0165` | **f_gt_64_im_b** | Greater than comparison on 64-bit floats; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### le
Less than or equal comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0166` | **u_le_8** | Unsigned less than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0167` | **u_le_16** | Unsigned less than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0168` | **u_le_32** | Unsigned less than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0169` | **u_le_64** | Unsigned less than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `016a` | **u_le_8_im_a** | Unsigned less than or equal comparison on 8-bit integers; check register less than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `016b` | **u_le_16_im_a** | Unsigned less than or equal comparison on 16-bit integers; check register less than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `016c` | **u_le_32_im_a** | Unsigned less than or equal comparison on 32-bit integers; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `016d` | **u_le_64_im_a** | Unsigned less than or equal comparison on 64-bit integers; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `016e` | **u_le_8_im_b** | Unsigned less than or equal comparison on 8-bit integers; check immediate less than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `016f` | **u_le_16_im_b** | Unsigned less than or equal comparison on 16-bit integers; check immediate less than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `0170` | **u_le_32_im_b** | Unsigned less than or equal comparison on 32-bit integers; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0171` | **u_le_64_im_b** | Unsigned less than or equal comparison on 64-bit integers; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0172` | **s_le_8** | Signed less than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0173` | **s_le_16** | Signed less than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0174` | **s_le_32** | Signed less than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0175` | **s_le_64** | Signed less than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0176` | **s_le_8_im_a** | Signed less than or equal comparison on 8-bit integers; check register less than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `0177` | **s_le_16_im_a** | Signed less than or equal comparison on 16-bit integers; check register less than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `0178` | **s_le_32_im_a** | Signed less than or equal comparison on 32-bit integers; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `0179` | **s_le_64_im_a** | Signed less than or equal comparison on 64-bit integers; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `017a` | **s_le_8_im_b** | Signed less than or equal comparison on 8-bit integers; check immediate less than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `017b` | **s_le_16_im_b** | Signed less than or equal comparison on 16-bit integers; check immediate less than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `017c` | **s_le_32_im_b** | Signed less than or equal comparison on 32-bit integers; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `017d` | **s_le_64_im_b** | Signed less than or equal comparison on 64-bit integers; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `017e` | **f_le_32** | Less than or equal comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `017f` | **f_le_64** | Less than or equal comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0180` | **f_le_32_im_a** | Less than or equal comparison on 32-bit floats; one immediate; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `0181` | **f_le_64_im_a** | Less than or equal comparison on 64-bit floats; one immediate; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0182` | **f_le_32_im_b** | Less than or equal comparison on 32-bit floats; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `0183` | **f_le_64_im_b** | Less than or equal comparison on 64-bit floats; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### ge
Greater than or equal comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0184` | **u_ge_8** | Unsigned greater than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0185` | **u_ge_16** | Unsigned greater than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0186` | **u_ge_32** | Unsigned greater than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0187` | **u_ge_64** | Unsigned greater than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0188` | **u_ge_8_im_a** | Unsigned greater than or equal comparison on 8-bit integers; check register greater than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `0189` | **u_ge_16_im_a** | Unsigned greater than or equal comparison on 16-bit integers; check register greater than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `018a` | **u_ge_32_im_a** | Unsigned greater than or equal comparison on 32-bit integers; check register greater than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `018b` | **u_ge_64_im_a** | Unsigned greater than or equal comparison on 64-bit integers; check register greater than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `018c` | **u_ge_8_im_b** | Unsigned greater than or equal comparison on 8-bit integers; check immediate greater than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `018d` | **u_ge_16_im_b** | Unsigned greater than or equal comparison on 16-bit integers; check immediate greater than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `018e` | **u_ge_32_im_b** | Unsigned greater than or equal comparison on 32-bit integers; check immediate greater than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `018f` | **u_ge_64_im_b** | Unsigned greater than or equal comparison on 64-bit integers; check immediate greater than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0190` | **s_ge_8** | Signed greater than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0191` | **s_ge_16** | Signed greater than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0192` | **s_ge_32** | Signed greater than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0193` | **s_ge_64** | Signed greater than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `0194` | **s_ge_8_im_a** | Signed greater than or equal comparison on 8-bit integers; check register greater than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `0195` | **s_ge_16_im_a** | Signed greater than or equal comparison on 16-bit integers; check register greater than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `0196` | **s_ge_32_im_a** | Signed greater than or equal comparison on 32-bit integers; check register greater than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `0197` | **s_ge_64_im_a** | Signed greater than or equal comparison on 64-bit integers; check register greater than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `0198` | **s_ge_8_im_b** | Signed greater than or equal comparison on 8-bit integers; check immediate greater than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `0199` | **s_ge_16_im_b** | Signed greater than or equal comparison on 16-bit integers; check immediate greater than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `019a` | **s_ge_32_im_b** | Signed greater than or equal comparison on 32-bit integers; check immediate greater than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `019b` | **s_ge_64_im_b** | Signed greater than or equal comparison on 64-bit integers; check immediate greater than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `019c` | **f_ge_32** | Greater than or equal comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `019d` | **f_ge_64** | Greater than or equal comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `019e` | **f_ge_32_im_a** | Greater than or equal comparison on 32-bit floats; one immediate; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `019f` | **f_ge_64_im_a** | Greater than or equal comparison on 64-bit floats; one immediate; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `01a0` | **f_ge_32_im_b** | Greater than or equal comparison on 32-bit floats; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `01a1` | **f_ge_64_im_b** | Greater than or equal comparison on 64-bit floats; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |


#### Conversion
Convert between different types and sizes of values
+ [ext](#ext)
+ [trunc](#trunc)
+ [to](#to)
##### ext
Convert a value in a register to a larger size, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `01a2` | **u_ext_8_16** | Zero-extend an 8-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `01a3` | **u_ext_8_32** | Zero-extend an 8-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `01a4` | **u_ext_8_64** | Zero-extend an 8-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `01a5` | **u_ext_16_32** | Zero-extend a 16-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `01a6` | **u_ext_16_64** | Zero-extend a 16-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `01a7` | **u_ext_32_64** | Zero-extend a 32-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `01a8` | **s_ext_8_16** | Sign-extend an 8-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `01a9` | **s_ext_8_32** | Sign-extend an 8-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `01aa` | **s_ext_8_64** | Sign-extend an 8-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `01ab` | **s_ext_16_32** | Sign-extend a 16-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `01ac` | **s_ext_16_64** | Sign-extend a 16-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `01ad` | **s_ext_32_64** | Sign-extend a 32-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `01ae` | **f_ext_32_64** | Convert a 32-bit float to a 64-bit float | `R`,&nbsp;`R` |

##### trunc
Convert a value in a register to a smaller size, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `01af` | **i_trunc_64_32** | Truncate a 64-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `01b0` | **i_trunc_64_16** | Truncate a 64-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `01b1` | **i_trunc_64_8** | Truncate a 64-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `01b2` | **i_trunc_32_16** | Truncate a 32-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `01b3` | **i_trunc_32_8** | Truncate a 32-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `01b4` | **i_trunc_16_8** | Truncate a 16-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `01b5` | **f_trunc_64_32** | Convert a 64-bit float to a 32-bit float | `R`,&nbsp;`R` |

##### to
Convert a value in a register to a different type, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `01b6` | **u8_to_f32** | Convert an 8-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `01b7` | **u16_to_f32** | Convert a 16-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `01b8` | **u32_to_f32** | Convert a 32-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `01b9` | **u64_to_f32** | Convert a 64-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `01ba` | **s8_to_f32** | Convert an 8-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `01bb` | **s16_to_f32** | Convert a 16-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `01bc` | **s32_to_f32** | Convert a 32-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `01bd` | **s64_to_f32** | Convert a 64-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `01be` | **f32_to_u8** | Convert a 32-bit float to an 8-bit unsigned integer | `R`,&nbsp;`R` |
| `01bf` | **f32_to_u16** | Convert a 32-bit float to a 16-bit unsigned integer | `R`,&nbsp;`R` |
| `01c0` | **f32_to_u32** | Convert a 32-bit float to a 32-bit unsigned integer | `R`,&nbsp;`R` |
| `01c1` | **f32_to_u64** | Convert a 32-bit float to a 64-bit unsigned integer | `R`,&nbsp;`R` |
| `01c2` | **f32_to_s8** | Convert a 32-bit float to an 8-bit signed integer | `R`,&nbsp;`R` |
| `01c3` | **f32_to_s16** | Convert a 32-bit float to a 16-bit signed integer | `R`,&nbsp;`R` |
| `01c4` | **f32_to_s32** | Convert a 32-bit float to a 32-bit signed integer | `R`,&nbsp;`R` |
| `01c5` | **f32_to_s64** | Convert a 32-bit float to a 64-bit signed integer | `R`,&nbsp;`R` |
| `01c6` | **u8_to_f64** | Convert an 8-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `01c7` | **u16_to_f64** | Convert a 16-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `01c8` | **u32_to_f64** | Convert a 32-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `01c9` | **u64_to_f64** | Convert a 64-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `01ca` | **s8_to_f64** | Convert an 8-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `01cb` | **s16_to_f64** | Convert a 16-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `01cc` | **s32_to_f64** | Convert a 32-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `01cd` | **s64_to_f64** | Convert a 64-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `01ce` | **f64_to_u8** | Convert a 64-bit float to an 8-bit unsigned integer | `R`,&nbsp;`R` |
| `01cf` | **f64_to_u16** | Convert a 64-bit float to a 16-bit unsigned integer | `R`,&nbsp;`R` |
| `01d0` | **f64_to_u32** | Convert a 64-bit float to a 32-bit unsigned integer | `R`,&nbsp;`R` |
| `01d1` | **f64_to_u64** | Convert a 64-bit float to a 64-bit unsigned integer | `R`,&nbsp;`R` |
| `01d2` | **f64_to_s8** | Convert a 64-bit float to an 8-bit signed integer | `R`,&nbsp;`R` |
| `01d3` | **f64_to_s16** | Convert a 64-bit float to a 16-bit signed integer | `R`,&nbsp;`R` |
| `01d4` | **f64_to_s32** | Convert a 64-bit float to a 32-bit signed integer | `R`,&nbsp;`R` |
| `01d5` | **f64_to_s64** | Convert a 64-bit float to a 64-bit signed integer | `R`,&nbsp;`R` |



