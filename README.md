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

Current total number of instructions: 468
#### Miscellaneous

+ [nop](#nop)
##### nop
Not an operation; does nothing
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0001` | **nop** | No operation |  |


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
| `0101` | **halt** | Halt execution |  |

##### trap
Stops execution of the program and triggers the `unreachable` trap
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0201` | **trap** | Trigger a trap |  |

##### block
Unconditionally enter the block designated by the block operand

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0301` | **block** | Enter a block | `B` |
| `0302` | **block_v** | Enter a block, placing the output value in the designated register | `B`,&nbsp;`R` |

##### with
Enter the block designated by the block operand, using the handler set operand to handle matching effects inside

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0401` | **with** | Enter a block, using the designated handler set | `B`,&nbsp;`H` |
| `0402` | **with_v** | Enter a block, using the designated handler set, and place the output value in the designated register | `B`,&nbsp;`H`,&nbsp;`R` |

##### if
If the 8-bit conditional value designated by the register operand matches the test:
+ Then: Enter the block designated by the block operand
+ Else: Enter the block designated by the else block operand

The block operands are absolute block indices
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0501` | **if_nz** | Enter the first block, if the condition is non-zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R` |
| `0502` | **if_z** | Enter the first block, if the condition is zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R` |

##### when
If the 8-bit conditional value designated by the register operand matches the test:
+ Enter the block designated by the block operand

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0601` | **when_nz** | Enter a block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0602` | **when_z** | Enter a block, if the condition is zero | `B`,&nbsp;`R` |

##### re
Restart the block designated by the block operand

The block operand is a relative block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0701` | **re** | Restart the designated block | `B` |
| `0702` | **re_nz** | Restart the designated block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0703` | **re_z** | Restart the designated block, if the condition is zero | `B`,&nbsp;`R` |

##### br
Exit the block designated by the block operand

The block operand is a relative block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0801` | **br** | Exit the designated block | `B` |
| `0802` | **br_nz** | Exit the designated block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0803` | **br_z** | Exit the designated block, if the condition is zero | `B`,&nbsp;`R` |
| `0804` | **br_v** | Exit the designated block, yielding the value in the designated register | `B`,&nbsp;`R` |
| `0805` | **br_nz_v** | Exit the designated block, if the condition is non-zero; yield the value in the secondary register | `B`,&nbsp;`R`,&nbsp;`R` |
| `0806` | **br_z_v** | Exit the designated block, if the condition is zero; yield the value in the secondary register | `B`,&nbsp;`R`,&nbsp;`R` |
| `0807` | **br_v_im** | Exit the designated block, yielding an immediate up to 32 bits | `B`,&nbsp;`i` |
| `0808` | **br_v_im_w** | Exit the designated block, yielding an immediate up to 64 bits | `B`&nbsp;+&nbsp;`w` |
| `0809` | **br_nz_v_im** | Exit the designated block, if the condition is non-zero; yield an immediate | `B`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `080a` | **br_z_v_im** | Exit the designated block, if the condition is zero; yield an immediate | `B`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### call
Call the function designated by the function operand; expect a number of arguments, designated by the byte value operand, to follow this instruction
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0901` | **call_im** | Call a static function, expecting no return value (discards the result, if there is one) | `F`,&nbsp;`b` |
| `0902` | **call_v_im** | Call a static function, and place the return value in the designated register | `F`,&nbsp;`b`,&nbsp;`R` |
| `0903` | **call_tail_im** | Call a static function in tail position, expecting no return value (discards the result, if there is one) | `F`,&nbsp;`b` |
| `0904` | **call_tail_v_im** | Call a static function in tail position, expecting a return value (places the result in the caller's return register) | `F`,&nbsp;`b` |
| `0905` | **call** | Call a dynamic function, expecting no return value (discards the result, if there is one) | `R`,&nbsp;`b` |
| `0906` | **call_v** | Call a dynamic function, and place the return value in the designated register | `R`,&nbsp;`b`,&nbsp;`R` |
| `0907` | **call_tail** | Call a dynamic function in tail position, expecting no return value (discards the result, if there is one) | `R`,&nbsp;`b` |
| `0908` | **call_tail_v** | Call a dynamic function in tail position, and place the result in the caller's return register | `R`,&nbsp;`b`,&nbsp;`R` |

##### prompt
Call the effect handler designated by the evidence operand; expect a number of arguments, designated by the byte value operand, to follow this instruction
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0a01` | **prompt** | Call an effect handler, expecting no return value (discards the result, if there is one) | `E`,&nbsp;`b` |
| `0a02` | **prompt_v** | Call an effect handler, and place the return value in the designated register | `E`,&nbsp;`b`,&nbsp;`R` |
| `0a03` | **prompt_tail** | Call an effect handler in tail position, expecting no return value (discards the result, if there is one) | `E`,&nbsp;`b` |
| `0a04` | **prompt_tail_v** | Call an effect handler in tail position, and place the return value in the caller's return register | `E`,&nbsp;`b` |

##### ret
Return from the current function, optionally placing the result in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0b01` | **ret** | Return from the current function, yielding no value |  |
| `0b02` | **ret_v** | Return from the current function, yielding the value in the designated register | `R` |
| `0b03` | **ret_v_im** | Return from the current function, yielding an immediate value up to 32 bits | `i` |
| `0b04` | **ret_v_im_w** | Return from the current function, yielding an immediate value up to 64 bits | `w` |

##### term
Trigger early-termination of an effect handler, ending the block it was introduced in
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0c01` | **term** | Terminate the current effect handler, yielding no value |  |
| `0c02` | **term_v** | Terminate the current effect handler, yielding the value in the designated register | `R` |
| `0c03` | **term_v_im** | Terminate the current effect handler, yielding an immediate value up to 32 bits | `i` |
| `0c04` | **term_v_im_w** | Terminate the current effect handler, yielding an immediate value up to 64 bits | `w` |


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
| `0d01` | **alloca** | Allocate a number of bytes (up to 65k) on the stack, placing the address in the register | `s`,&nbsp;`R` |

##### addr
Place the address of the value designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0e01` | **addr_global** | Place the address of the global into the register | `G`,&nbsp;`R` |
| `0e02` | **addr_upvalue** | Place the address of the upvalue into the register | `U`,&nbsp;`R` |
| `0e03` | **addr_local** | Place the address of the first register into the second register | `R`,&nbsp;`R` |

##### read_global
Copy a number of bits from the global designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0f01` | **read_global_8** | Copy 8 bits from the global into the register | `G`,&nbsp;`R` |
| `0f02` | **read_global_16** | Copy 16 bits from the global into the register | `G`,&nbsp;`R` |
| `0f03` | **read_global_32** | Copy 32 bits from the global into the register | `G`,&nbsp;`R` |
| `0f04` | **read_global_64** | Copy 64 bits from the global into the register | `G`,&nbsp;`R` |

##### read_upvalue
Copy a number of bits from the upvalue designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1001` | **read_upvalue_8** | Copy 8 bits from the upvalue into the register | `R`,&nbsp;`R` |
| `1002` | **read_upvalue_16** | Copy 16 bits from the upvalue into the register | `R`,&nbsp;`R` |
| `1003` | **read_upvalue_32** | Copy 32 bits from the upvalue into the register | `R`,&nbsp;`R` |
| `1004` | **read_upvalue_64** | Copy 64 bits from the upvalue into the register | `R`,&nbsp;`R` |

##### write_global
Copy a number of bits from the value designated by the first operand into the global provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1101` | **write_global_8** | Copy 8 bits from the register into the global | `R`,&nbsp;`G` |
| `1102` | **write_global_16** | Copy 16 bits from the register into the global | `R`,&nbsp;`G` |
| `1103` | **write_global_32** | Copy 32 bits from the register into the global | `R`,&nbsp;`G` |
| `1104` | **write_global_64** | Copy 64 bits from the register into the global | `R`,&nbsp;`G` |
| `1105` | **write_global_8_im** | Copy 8 bits from the immediate into the global | `b`,&nbsp;`G` |
| `1106` | **write_global_16_im** | Copy 16 bits from the immediate into the global | `s`,&nbsp;`G` |
| `1107` | **write_global_32_im** | Copy 32 bits from the immediate into the global | `i`,&nbsp;`G` |
| `1108` | **write_global_64_im** | Copy 64 bits from the immediate into the global | `G`&nbsp;+&nbsp;`w` |

##### write_upvalue
Copy a number of bits from the value designated by the first operand into the upvalue provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1201` | **write_upvalue_8** | Copy 8 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1202` | **write_upvalue_16** | Copy 16 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1203` | **write_upvalue_32** | Copy 32 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1204` | **write_upvalue_64** | Copy 64 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1205` | **write_upvalue_8_im** | Copy 8 bits from the immediate into the designated upvalue | `b`,&nbsp;`R` |
| `1206` | **write_upvalue_16_im** | Copy 16 bits from the immediate into the designated upvalue | `s`,&nbsp;`R` |
| `1207` | **write_upvalue_32_im** | Copy 32 bits from the register into the designated upvalue | `i`,&nbsp;`R` |
| `1208` | **write_upvalue_64_im** | Copy 64 bits from the immediate into the designated upvalue | `R`&nbsp;+&nbsp;`w` |

##### load
Copy a number of bits from the memory address designated by the first operand into the register provided in the second operand

The address must be located on the stack or global memory
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1301` | **load_8** | Copy 8 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `1302` | **load_16** | Copy 16 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `1303` | **load_32** | Copy 32 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `1304` | **load_64** | Copy 64 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |

##### store
Copy a number of bits from the value designated by the first operand into the memory address in the register provided in the second operand

The address must be located on the stack or global memory
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1401` | **store_8** | Copy 8 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1402` | **store_16** | Copy 16 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1403` | **store_32** | Copy 32 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1404` | **store_64** | Copy 64 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1405` | **store_8_im** | Copy 8 bits from the immediate into the memory address in the register | `b`,&nbsp;`R` |
| `1406` | **store_16_im** | Copy 16 bits from the immediate into the memory address in the register | `s`,&nbsp;`R` |
| `1407` | **store_32_im** | Copy 32 bits from the immediate into the memory address in the register | `i`,&nbsp;`R` |
| `1408` | **store_64_im** | Copy 64 bits from the immediate into the memory address in the register | `R`&nbsp;+&nbsp;`w` |

##### clear
Clear a number of bits in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1501` | **clear_8** | Clear 8 bits from the register | `R` |
| `1502` | **clear_16** | Clear 16 bits from the register | `R` |
| `1503` | **clear_32** | Clear 32 bits from the register | `R` |
| `1504` | **clear_64** | Clear 64 bits from the register | `R` |

##### swap
Swap a number of bits in the two designated registers
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1601` | **swap_8** | Swap 8 bits between the two registers | `R`,&nbsp;`R` |
| `1602` | **swap_16** | Swap 16 bits between the two registers | `R`,&nbsp;`R` |
| `1603` | **swap_32** | Swap 32 bits between the two registers | `R`,&nbsp;`R` |
| `1604` | **swap_64** | Swap 64 bits between the two registers | `R`,&nbsp;`R` |

##### copy
Copy a number of bits from the first register into the second register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1701` | **copy_8** | Copy 8 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1702` | **copy_16** | Copy 16 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1703` | **copy_32** | Copy 32 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1704` | **copy_64** | Copy 64 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1705` | **copy_8_im** | Copy 8-bits from an immediate value into the register | `b`,&nbsp;`R` |
| `1706` | **copy_16_im** | Copy 16-bits from an immediate value into the register | `s`,&nbsp;`R` |
| `1707` | **copy_32_im** | Copy 32-bits from an immediate value into the register | `i`,&nbsp;`R` |
| `1708` | **copy_64_im** | Copy 64-bits from an immediate value into the register | `R`&nbsp;+&nbsp;`w` |


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
| `1801` | **i_add_8** | Sign-agnostic addition on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1802` | **i_add_16** | Sign-agnostic addition on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1803` | **i_add_32** | Sign-agnostic addition on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1804` | **i_add_64** | Sign-agnostic addition on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1805` | **i_add_8_im** | Sign-agnostic addition on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `1806` | **i_add_16_im** | Sign-agnostic addition on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `1807` | **i_add_32_im** | Sign-agnostic addition on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `1808` | **i_add_64_im** | Sign-agnostic addition on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1809` | **f_add_32** | Addition on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `180a` | **f_add_64** | Addition on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `180b` | **f_add_32_im** | Addition on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `180c` | **f_add_64_im** | Addition on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### sub
Subtraction on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1901` | **i_sub_8** | Sign-agnostic subtraction on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1902` | **i_sub_16** | Sign-agnostic subtraction on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1903` | **i_sub_32** | Sign-agnostic subtraction on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1904` | **i_sub_64** | Sign-agnostic subtraction on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1905` | **i_sub_8_im_a** | Sign-agnostic subtraction on 8-bit integers; subtract register value from immediate value | `b`,&nbsp;`R`,&nbsp;`R` |
| `1906` | **i_sub_16_im_a** | Sign-agnostic subtraction on 16-bit integers; subtract register value from immediate value | `s`,&nbsp;`R`,&nbsp;`R` |
| `1907` | **i_sub_32_im_a** | Sign-agnostic subtraction on 32-bit integers; subtract register value from immediate value | `i`,&nbsp;`R`,&nbsp;`R` |
| `1908` | **i_sub_64_im_a** | Sign-agnostic subtraction on 64-bit integers; subtract register value from immediate value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1909` | **i_sub_8_im_b** | Sign-agnostic subtraction on 8-bit integers; subtract immediate value from register value | `R`,&nbsp;`b`,&nbsp;`R` |
| `190a` | **i_sub_16_im_b** | Sign-agnostic subtraction on 16-bit integers; subtract immediate value from register value | `R`,&nbsp;`s`,&nbsp;`R` |
| `190b` | **i_sub_32_im_b** | Sign-agnostic subtraction on 32-bit integers; subtract immediate value from register value | `R`,&nbsp;`i`,&nbsp;`R` |
| `190c` | **i_sub_64_im_b** | Sign-agnostic subtraction on 64-bit integers; subtract immediate value from register value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `190d` | **f_sub_32** | Subtraction on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `190e` | **f_sub_64** | Subtraction on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `190f` | **f_sub_32_im_a** | Subtraction on 32-bit floats; subtract register value from immediate value | `i`,&nbsp;`R`,&nbsp;`R` |
| `1910` | **f_sub_64_im_a** | Subtraction on 64-bit floats; subtract register value from immediate value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1911` | **f_sub_32_im_b** | Subtraction on 32-bit floats; subtract immediate value from register value | `R`,&nbsp;`i`,&nbsp;`R` |
| `1912` | **f_sub_64_im_b** | Subtraction on 64-bit floats; subtract immediate value from register value | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### mul
Multiplication on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1a01` | **i_mul_8** | Sign-agnostic multiplication on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a02` | **i_mul_16** | Sign-agnostic multiplication on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a03` | **i_mul_32** | Sign-agnostic multiplication on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a04` | **i_mul_64** | Sign-agnostic multiplication on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a05` | **i_mul_8_im** | Sign-agnostic multiplication on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `1a06` | **i_mul_16_im** | Sign-agnostic multiplication on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `1a07` | **i_mul_32_im** | Sign-agnostic multiplication on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `1a08` | **i_mul_64_im** | Sign-agnostic multiplication on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1a09` | **f_mul_32** | Multiplication on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a0a` | **f_mul_64** | Multiplication on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a0b` | **f_mul_32_im** | Multiplication on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `1a0c` | **f_mul_64_im** | Multiplication on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### div
Division on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1b01` | **u_div_8** | Unsigned division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b02` | **u_div_16** | Unsigned division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b03` | **u_div_32** | Unsigned division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b04` | **u_div_64** | Unsigned division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b05` | **u_div_8_im_a** | Unsigned division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `1b06` | **u_div_16_im_a** | Unsigned division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `1b07` | **u_div_32_im_a** | Unsigned division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `1b08` | **u_div_64_im_a** | Unsigned division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1b09` | **u_div_8_im_b** | Unsigned division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `1b0a` | **u_div_16_im_b** | Unsigned division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `1b0b` | **u_div_32_im_b** | Unsigned division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `1b0c` | **u_div_64_im_b** | Unsigned division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1b0d` | **s_div_8** | Signed division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b0e` | **s_div_16** | Signed division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b0f` | **s_div_32** | Signed division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b10` | **s_div_64** | Signed division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b11` | **s_div_8_im_a** | Signed division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `1b12` | **s_div_16_im_a** | Signed division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `1b13` | **s_div_32_im_a** | Signed division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `1b14` | **s_div_64_im_a** | Signed division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1b15` | **s_div_8_im_b** | Signed division on 8-bit integers; register dividend, immediate divisor | `b`,&nbsp;`i`,&nbsp;`R` |
| `1b16` | **s_div_16_im_b** | Signed division on 16-bit integers; register dividend, immediate divisor | `s`,&nbsp;`i`,&nbsp;`R` |
| `1b17` | **s_div_32_im_b** | Signed division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `1b18` | **s_div_64_im_b** | Signed division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1b19` | **f_div_32** | Division on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b1a` | **f_div_64** | Division on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b1b` | **f_div_32_im_a** | Division on 32-bit floats; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `1b1c` | **f_div_64_im_a** | Division on 64-bit floats; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1b1d` | **f_div_32_im_b** | Division on 32-bit floats; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `1b1e` | **f_div_64_im_b** | Division on 64-bit floats; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### rem
Remainder division on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1c01` | **u_rem_8** | Unsigned remainder division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c02` | **u_rem_16** | Unsigned remainder division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c03` | **u_rem_32** | Unsigned remainder division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c04` | **u_rem_64** | Unsigned remainder division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c05` | **u_rem_8_im_a** | Unsigned remainder division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `1c06` | **u_rem_16_im_a** | Unsigned remainder division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `1c07` | **u_rem_32_im_a** | Unsigned remainder division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `1c08` | **u_rem_64_im_a** | Unsigned remainder division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1c09` | **u_rem_8_im_b** | Unsigned remainder division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `1c0a` | **u_rem_16_im_b** | Unsigned remainder division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `1c0b` | **u_rem_32_im_b** | Unsigned remainder division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `1c0c` | **u_rem_64_im_b** | Unsigned remainder division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1c0d` | **s_rem_8** | Signed remainder division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c0e` | **s_rem_16** | Signed remainder division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c0f` | **s_rem_32** | Signed remainder division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c10` | **s_rem_64** | Signed remainder division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c11` | **s_rem_8_im_a** | Signed remainder division on 8-bit integers; immediate dividend, register divisor | `b`,&nbsp;`R`,&nbsp;`R` |
| `1c12` | **s_rem_16_im_a** | Signed remainder division on 16-bit integers; immediate dividend, register divisor | `s`,&nbsp;`R`,&nbsp;`R` |
| `1c13` | **s_rem_32_im_a** | Signed remainder division on 32-bit integers; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `1c14` | **s_rem_64_im_a** | Signed remainder division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1c15` | **s_rem_8_im_b** | Signed remainder division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`b`,&nbsp;`R` |
| `1c16` | **s_rem_16_im_b** | Signed remainder division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`s`,&nbsp;`R` |
| `1c17` | **s_rem_32_im_b** | Signed remainder division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `1c18` | **s_rem_64_im_b** | Signed remainder division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1c19` | **f_rem_32** | Remainder division on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c1a` | **f_rem_64** | Remainder division on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1c1b` | **f_rem_32_im_a** | Remainder division on 32-bit floats; immediate dividend, register divisor | `i`,&nbsp;`R`,&nbsp;`R` |
| `1c1c` | **f_rem_64_im_a** | Remainder division on 64-bit floats; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `1c1d` | **f_rem_32_im_b** | Remainder division on 32-bit floats; register dividend, immediate divisor | `R`,&nbsp;`i`,&nbsp;`R` |
| `1c1e` | **f_rem_64_im_b** | Remainder division on 64-bit floats; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### neg
Negation of a single operand, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1d01` | **s_neg_8** | Negation of an 8-bit integer | `R`,&nbsp;`R` |
| `1d02` | **s_neg_16** | Negation of a 16-bit integer | `R`,&nbsp;`R` |
| `1d03` | **s_neg_32** | Negation of a 32-bit integer | `R`,&nbsp;`R` |
| `1d04` | **s_neg_64** | Negation of a 64-bit integer | `R`,&nbsp;`R` |
| `1d05` | **f_neg_32** | Negation of a 32-bit float | `R`,&nbsp;`R` |
| `1d06` | **f_neg_64** | Negation of a 64-bit float | `R`,&nbsp;`R` |


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
| `1e01` | **band_8** | Bitwise AND on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e02` | **band_16** | Bitwise AND on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e03` | **band_32** | Bitwise AND on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e04` | **band_64** | Bitwise AND on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e05` | **band_8_im** | Bitwise AND on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `1e06` | **band_16_im** | Bitwise AND on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `1e07` | **band_32_im** | Bitwise AND on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `1e08` | **band_64_im** | Bitwise AND on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bor
Bitwise OR on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1f01` | **bor_8** | Bitwise OR on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f02` | **bor_16** | Bitwise OR on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f03` | **bor_32** | Bitwise OR on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f04` | **bor_64** | Bitwise OR on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f05` | **bor_8_im** | Bitwise OR on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `1f06` | **bor_16_im** | Bitwise OR on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `1f07` | **bor_32_im** | Bitwise OR on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `1f08` | **bor_64_im** | Bitwise OR on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bxor
Bitwise XOR on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2001` | **bxor_8** | Bitwise XOR on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2002` | **bxor_16** | Bitwise XOR on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2003` | **bxor_32** | Bitwise XOR on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2004` | **bxor_64** | Bitwise XOR on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2005` | **bxor_8_im** | Bitwise XOR on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `2006` | **bxor_16_im** | Bitwise XOR on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `2007` | **bxor_32_im** | Bitwise XOR on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `2008` | **bxor_64_im** | Bitwise XOR on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bnot
Bitwise NOT on a single operand, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2101` | **bnot_8** | Bitwise NOT on an 8-bit integer in a register | `R`,&nbsp;`R` |
| `2102` | **bnot_16** | Bitwise NOT on a 16-bit integer in registers | `R`,&nbsp;`R` |
| `2103` | **bnot_32** | Bitwise NOT on a 32-bit integer in a register | `R`,&nbsp;`R` |
| `2104` | **bnot_64** | Bitwise NOT on a 64-bit integer in a register | `R`,&nbsp;`R` |

##### bshiftl
Bitwise left shift on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2201` | **bshiftl_8** | Bitwise left shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2202` | **bshiftl_16** | Bitwise left shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2203` | **bshiftl_32** | Bitwise left shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2204` | **bshiftl_64** | Bitwise left shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2205` | **a_bshiftl_8_im** | Bitwise left shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `2206` | **a_bshiftl_16_im** | Bitwise left shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `2207` | **a_bshiftl_32_im** | Bitwise left shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `2208` | **a_bshiftl_64_im** | Bitwise left shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2209` | **b_bshiftl_8_im** | Bitwise left shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`b`,&nbsp;`R` |
| `220a` | **b_bshiftl_16_im** | Bitwise left shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`s`,&nbsp;`R` |
| `220b` | **b_bshiftl_32_im** | Bitwise left shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`i`,&nbsp;`R` |
| `220c` | **b_bshiftl_64_im** | Bitwise left shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### bshiftr
Bitwise right shift on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2301` | **u_bshiftr_8** | Logical bitwise right shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2302` | **u_bshiftr_16** | Logical bitwise right shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2303` | **u_bshiftr_32** | Logical bitwise right shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2304` | **u_bshiftr_64** | Logical bitwise right shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2305` | **u_bshiftr_8_im_a** | Logical bitwise right shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `2306` | **u_bshiftr_16_im_a** | Logical bitwise right shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `2307` | **u_bshiftr_32_im_a** | Logical bitwise right shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `2308` | **u_bshiftr_64_im_a** | Logical bitwise right shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2309` | **u_bshiftr_8_im_b** | Logical bitwise right shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`b`,&nbsp;`R` |
| `230a` | **u_bshiftr_16_im_b** | Logical bitwise right shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`s`,&nbsp;`R` |
| `230b` | **u_bshiftr_32_im_b** | Logical bitwise right shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`i`,&nbsp;`R` |
| `230c` | **u_bshiftr_64_im_b** | Logical bitwise right shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `230d` | **s_bshiftr_8** | Arithmetic bitwise right shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `230e` | **s_bshiftr_16** | Arithmetic bitwise right shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `230f` | **s_bshiftr_32** | Arithmetic bitwise right shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2310` | **s_bshiftr_64** | Arithmetic bitwise right shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2311` | **s_bshiftr_8_im_a** | Arithmetic bitwise right shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `2312` | **s_bshiftr_16_im_a** | Arithmetic bitwise right shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `2313` | **s_bshiftr_32_im_a** | Arithmetic bitwise right shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `2314` | **s_bshiftr_64_im_a** | Arithmetic bitwise right shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2315` | **s_bshiftr_8_im_b** | Arithmetic bitwise right shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`b`,&nbsp;`R` |
| `2316` | **s_bshiftr_16_im_b** | Arithmetic bitwise right shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`s`,&nbsp;`R` |
| `2317` | **s_bshiftr_32_im_b** | Arithmetic bitwise right shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`i`,&nbsp;`R` |
| `2318` | **s_bshiftr_64_im_b** | Arithmetic bitwise right shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |


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
| `2401` | **i_eq_8** | Sign-agnostic equality comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2402` | **i_eq_16** | Sign-agnostic equality comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2403` | **i_eq_32** | Sign-agnostic equality comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2404` | **i_eq_64** | Sign-agnostic equality comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2405` | **i_eq_8_im** | Sign-agnostic equality comparison on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `2406` | **i_eq_16_im** | Sign-agnostic equality comparison on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `2407` | **i_eq_32_im** | Sign-agnostic equality comparison on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `2408` | **i_eq_64_im** | Sign-agnostic equality comparison on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2409` | **f_eq_32** | Equality comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `240a` | **f_eq_64** | Equality comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `240b` | **f_eq_32_im** | Equality comparison on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `240c` | **f_eq_64_im** | Equality comparison on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### ne
Inequality comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2501` | **i_ne_8** | Sign-agnostic inequality comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2502` | **i_ne_16** | Sign-agnostic inequality comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2503` | **i_ne_32** | Sign-agnostic inequality comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2504` | **i_ne_64** | Sign-agnostic inequality comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2505` | **i_ne_8_im** | Sign-agnostic inequality comparison on 8-bit integers; one immediate, one in a register | `b`,&nbsp;`R`,&nbsp;`R` |
| `2506` | **i_ne_16_im** | Sign-agnostic inequality comparison on 16-bit integers; one immediate, one in a register | `s`,&nbsp;`R`,&nbsp;`R` |
| `2507` | **i_ne_32_im** | Sign-agnostic inequality comparison on 32-bit integers; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `2508` | **i_ne_64_im** | Sign-agnostic inequality comparison on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2509` | **f_ne_32** | Inequality comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `250a` | **f_ne_64** | Inequality comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `250b` | **f_ne_32_im** | Inequality comparison on 32-bit floats; one immediate, one in a register | `i`,&nbsp;`R`,&nbsp;`R` |
| `250c` | **f_ne_64_im** | Inequality comparison on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### lt
Less than comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2601` | **u_lt_8** | Unsigned less than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2602` | **u_lt_16** | Unsigned less than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2603` | **u_lt_32** | Unsigned less than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2604` | **u_lt_64** | Unsigned less than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2605` | **u_lt_8_im_a** | Unsigned less than comparison on 8-bit integers; check register less than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2606` | **u_lt_16_im_a** | Unsigned less than comparison on 16-bit integers; check register less than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2607` | **u_lt_32_im_a** | Unsigned less than comparison on 32-bit integers; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2608` | **u_lt_64_im_a** | Unsigned less than comparison on 64-bit integers; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2609` | **u_lt_8_im_b** | Unsigned less than comparison on 8-bit integers; check immediate less than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `260a` | **u_lt_16_im_b** | Unsigned less than comparison on 16-bit integers; check immediate less than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `260b` | **u_lt_32_im_b** | Unsigned less than comparison on 32-bit integers; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `260c` | **u_lt_64_im_b** | Unsigned less than comparison on 64-bit integers; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `260d` | **s_lt_8** | Signed less than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `260e` | **s_lt_16** | Signed less than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `260f` | **s_lt_32** | Signed less than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2610` | **s_lt_64** | Signed less than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2611` | **s_lt_8_im_a** | Signed less than comparison on 8-bit integers; check register less than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2612` | **s_lt_16_im_a** | Signed less than comparison on 16-bit integers; check register less than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2613` | **s_lt_32_im_a** | Signed less than comparison on 32-bit integers; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2614` | **s_lt_64_im_a** | Signed less than comparison on 64-bit integers; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2615` | **s_lt_8_im_b** | Signed less than comparison on 8-bit integers; check immediate less than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `2616` | **s_lt_16_im_b** | Signed less than comparison on 16-bit integers; check immediate less than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `2617` | **s_lt_32_im_b** | Signed less than comparison on 32-bit integers; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `2618` | **s_lt_64_im_b** | Signed less than comparison on 64-bit integers; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2619` | **f_lt_32** | Less than comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `261a` | **f_lt_64** | Less than comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `261b` | **f_lt_32_im_a** | Less than comparison on 32-bit floats; one immediate; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `261c` | **f_lt_64_im_a** | Less than comparison on 64-bit floats; one immediate; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `261d` | **f_lt_32_im_b** | Less than comparison on 32-bit floats; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `261e` | **f_lt_64_im_b** | Less than comparison on 64-bit floats; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### gt
Greater than comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2701` | **u_gt_8** | Unsigned greater than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2702` | **u_gt_16** | Unsigned greater than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2703` | **u_gt_32** | Unsigned greater than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2704` | **u_gt_64** | Unsigned greater than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2705` | **u_gt_8_im_a** | Unsigned greater than comparison on 8-bit integers; check register greater than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2706` | **u_gt_16_im_a** | Unsigned greater than comparison on 16-bit integers; check register greater than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2707` | **u_gt_32_im_a** | Unsigned greater than comparison on 32-bit integers; check register greater than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2708` | **u_gt_64_im_a** | Unsigned greater than comparison on 64-bit integers; check register greater than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2709` | **u_gt_8_im_b** | Unsigned greater than comparison on 8-bit integers; check immediate greater than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `270a` | **u_gt_16_im_b** | Unsigned greater than comparison on 16-bit integers; check immediate greater than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `270b` | **u_gt_32_im_b** | Unsigned greater than comparison on 32-bit integers; check immediate greater than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `270c` | **u_gt_64_im_b** | Unsigned greater than comparison on 64-bit integers; check immediate greater than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `270d` | **s_gt_8** | Signed greater than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `270e` | **s_gt_16** | Signed greater than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `270f` | **s_gt_32** | Signed greater than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2710` | **s_gt_64** | Signed greater than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2711` | **s_gt_8_im_a** | Signed greater than comparison on 8-bit integers; check register greater than immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2712` | **s_gt_16_im_a** | Signed greater than comparison on 16-bit integers; check register greater than immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2713` | **s_gt_32_im_a** | Signed greater than comparison on 32-bit integers; check register greater than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2714` | **s_gt_64_im_a** | Signed greater than comparison on 64-bit integers; check register greater than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2715` | **s_gt_8_im_b** | Signed greater than comparison on 8-bit integers; check immediate greater than register | `R`,&nbsp;`b`,&nbsp;`R` |
| `2716` | **s_gt_16_im_b** | Signed greater than comparison on 16-bit integers; check immediate greater than register | `R`,&nbsp;`s`,&nbsp;`R` |
| `2717` | **s_gt_32_im_b** | Signed greater than comparison on 32-bit integers; check immediate greater than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `2718` | **s_gt_64_im_b** | Signed greater than comparison on 64-bit integers; check immediate greater than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2719` | **f_gt_32** | Greater than comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `271a` | **f_gt_64** | Greater than comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `271b` | **f_gt_32_im_a** | Greater than comparison on 32-bit floats; one immediate; check register less than immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `271c` | **f_gt_64_im_a** | Greater than comparison on 64-bit floats; one immediate; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `271d` | **f_gt_32_im_b** | Greater than comparison on 32-bit floats; check immediate less than register | `R`,&nbsp;`i`,&nbsp;`R` |
| `271e` | **f_gt_64_im_b** | Greater than comparison on 64-bit floats; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### le
Less than or equal comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2801` | **u_le_8** | Unsigned less than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2802` | **u_le_16** | Unsigned less than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2803` | **u_le_32** | Unsigned less than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2804` | **u_le_64** | Unsigned less than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2805` | **u_le_8_im_a** | Unsigned less than or equal comparison on 8-bit integers; check register less than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2806` | **u_le_16_im_a** | Unsigned less than or equal comparison on 16-bit integers; check register less than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2807` | **u_le_32_im_a** | Unsigned less than or equal comparison on 32-bit integers; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2808` | **u_le_64_im_a** | Unsigned less than or equal comparison on 64-bit integers; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2809` | **u_le_8_im_b** | Unsigned less than or equal comparison on 8-bit integers; check immediate less than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `280a` | **u_le_16_im_b** | Unsigned less than or equal comparison on 16-bit integers; check immediate less than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `280b` | **u_le_32_im_b** | Unsigned less than or equal comparison on 32-bit integers; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `280c` | **u_le_64_im_b** | Unsigned less than or equal comparison on 64-bit integers; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `280d` | **s_le_8** | Signed less than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `280e` | **s_le_16** | Signed less than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `280f` | **s_le_32** | Signed less than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2810` | **s_le_64** | Signed less than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2811` | **s_le_8_im_a** | Signed less than or equal comparison on 8-bit integers; check register less than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2812` | **s_le_16_im_a** | Signed less than or equal comparison on 16-bit integers; check register less than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2813` | **s_le_32_im_a** | Signed less than or equal comparison on 32-bit integers; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2814` | **s_le_64_im_a** | Signed less than or equal comparison on 64-bit integers; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2815` | **s_le_8_im_b** | Signed less than or equal comparison on 8-bit integers; check immediate less than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `2816` | **s_le_16_im_b** | Signed less than or equal comparison on 16-bit integers; check immediate less than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `2817` | **s_le_32_im_b** | Signed less than or equal comparison on 32-bit integers; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `2818` | **s_le_64_im_b** | Signed less than or equal comparison on 64-bit integers; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2819` | **f_le_32** | Less than or equal comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `281a` | **f_le_64** | Less than or equal comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `281b` | **f_le_32_im_a** | Less than or equal comparison on 32-bit floats; one immediate; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `281c` | **f_le_64_im_a** | Less than or equal comparison on 64-bit floats; one immediate; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `281d` | **f_le_32_im_b** | Less than or equal comparison on 32-bit floats; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `281e` | **f_le_64_im_b** | Less than or equal comparison on 64-bit floats; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |

##### ge
Greater than or equal comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2901` | **u_ge_8** | Unsigned greater than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2902` | **u_ge_16** | Unsigned greater than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2903` | **u_ge_32** | Unsigned greater than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2904` | **u_ge_64** | Unsigned greater than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2905` | **u_ge_8_im_a** | Unsigned greater than or equal comparison on 8-bit integers; check register greater than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2906` | **u_ge_16_im_a** | Unsigned greater than or equal comparison on 16-bit integers; check register greater than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2907` | **u_ge_32_im_a** | Unsigned greater than or equal comparison on 32-bit integers; check register greater than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2908` | **u_ge_64_im_a** | Unsigned greater than or equal comparison on 64-bit integers; check register greater than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2909` | **u_ge_8_im_b** | Unsigned greater than or equal comparison on 8-bit integers; check immediate greater than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `290a` | **u_ge_16_im_b** | Unsigned greater than or equal comparison on 16-bit integers; check immediate greater than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `290b` | **u_ge_32_im_b** | Unsigned greater than or equal comparison on 32-bit integers; check immediate greater than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `290c` | **u_ge_64_im_b** | Unsigned greater than or equal comparison on 64-bit integers; check immediate greater than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `290d` | **s_ge_8** | Signed greater than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `290e` | **s_ge_16** | Signed greater than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `290f` | **s_ge_32** | Signed greater than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2910` | **s_ge_64** | Signed greater than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2911` | **s_ge_8_im_a** | Signed greater than or equal comparison on 8-bit integers; check register greater than or equal immediate | `b`,&nbsp;`R`,&nbsp;`R` |
| `2912` | **s_ge_16_im_a** | Signed greater than or equal comparison on 16-bit integers; check register greater than or equal immediate | `s`,&nbsp;`R`,&nbsp;`R` |
| `2913` | **s_ge_32_im_a** | Signed greater than or equal comparison on 32-bit integers; check register greater than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `2914` | **s_ge_64_im_a** | Signed greater than or equal comparison on 64-bit integers; check register greater than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2915` | **s_ge_8_im_b** | Signed greater than or equal comparison on 8-bit integers; check immediate greater than or equal register | `R`,&nbsp;`b`,&nbsp;`R` |
| `2916` | **s_ge_16_im_b** | Signed greater than or equal comparison on 16-bit integers; check immediate greater than or equal register | `R`,&nbsp;`s`,&nbsp;`R` |
| `2917` | **s_ge_32_im_b** | Signed greater than or equal comparison on 32-bit integers; check immediate greater than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `2918` | **s_ge_64_im_b** | Signed greater than or equal comparison on 64-bit integers; check immediate greater than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `2919` | **f_ge_32** | Greater than or equal comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `291a` | **f_ge_64** | Greater than or equal comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `291b` | **f_ge_32_im_a** | Greater than or equal comparison on 32-bit floats; one immediate; check register less than or equal immediate | `i`,&nbsp;`R`,&nbsp;`R` |
| `291c` | **f_ge_64_im_a** | Greater than or equal comparison on 64-bit floats; one immediate; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |
| `291d` | **f_ge_32_im_b** | Greater than or equal comparison on 32-bit floats; check immediate less than or equal register | `R`,&nbsp;`i`,&nbsp;`R` |
| `291e` | **f_ge_64_im_b** | Greater than or equal comparison on 64-bit floats; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`w` |


#### Conversion
Convert between different types and sizes of values
+ [ext](#ext)
+ [trunc](#trunc)
+ [to](#to)
##### ext
Convert a value in a register to a larger size, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2a01` | **u_ext_8_16** | Zero-extend an 8-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2a02` | **u_ext_8_32** | Zero-extend an 8-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2a03` | **u_ext_8_64** | Zero-extend an 8-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2a04` | **u_ext_16_32** | Zero-extend a 16-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2a05` | **u_ext_16_64** | Zero-extend a 16-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2a06` | **u_ext_32_64** | Zero-extend a 32-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2a07` | **s_ext_8_16** | Sign-extend an 8-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2a08` | **s_ext_8_32** | Sign-extend an 8-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2a09` | **s_ext_8_64** | Sign-extend an 8-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2a0a` | **s_ext_16_32** | Sign-extend a 16-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2a0b` | **s_ext_16_64** | Sign-extend a 16-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2a0c` | **s_ext_32_64** | Sign-extend a 32-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2a0d` | **f_ext_32_64** | Convert a 32-bit float to a 64-bit float | `R`,&nbsp;`R` |

##### trunc
Convert a value in a register to a smaller size, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2b01` | **i_trunc_64_32** | Truncate a 64-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2b02` | **i_trunc_64_16** | Truncate a 64-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2b03` | **i_trunc_64_8** | Truncate a 64-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `2b04` | **i_trunc_32_16** | Truncate a 32-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2b05` | **i_trunc_32_8** | Truncate a 32-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `2b06` | **i_trunc_16_8** | Truncate a 16-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `2b07` | **f_trunc_64_32** | Convert a 64-bit float to a 32-bit float | `R`,&nbsp;`R` |

##### to
Convert a value in a register to a different type, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2c01` | **u8_to_f32** | Convert an 8-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c02` | **u16_to_f32** | Convert a 16-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c03` | **u32_to_f32** | Convert a 32-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c04` | **u64_to_f32** | Convert a 64-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c05` | **s8_to_f32** | Convert an 8-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c06` | **s16_to_f32** | Convert a 16-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c07` | **s32_to_f32** | Convert a 32-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c08` | **s64_to_f32** | Convert a 64-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2c09` | **f32_to_u8** | Convert a 32-bit float to an 8-bit unsigned integer | `R`,&nbsp;`R` |
| `2c0a` | **f32_to_u16** | Convert a 32-bit float to a 16-bit unsigned integer | `R`,&nbsp;`R` |
| `2c0b` | **f32_to_u32** | Convert a 32-bit float to a 32-bit unsigned integer | `R`,&nbsp;`R` |
| `2c0c` | **f32_to_u64** | Convert a 32-bit float to a 64-bit unsigned integer | `R`,&nbsp;`R` |
| `2c0d` | **f32_to_s8** | Convert a 32-bit float to an 8-bit signed integer | `R`,&nbsp;`R` |
| `2c0e` | **f32_to_s16** | Convert a 32-bit float to a 16-bit signed integer | `R`,&nbsp;`R` |
| `2c0f` | **f32_to_s32** | Convert a 32-bit float to a 32-bit signed integer | `R`,&nbsp;`R` |
| `2c10` | **f32_to_s64** | Convert a 32-bit float to a 64-bit signed integer | `R`,&nbsp;`R` |
| `2c11` | **u8_to_f64** | Convert an 8-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c12` | **u16_to_f64** | Convert a 16-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c13` | **u32_to_f64** | Convert a 32-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c14` | **u64_to_f64** | Convert a 64-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c15` | **s8_to_f64** | Convert an 8-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c16` | **s16_to_f64** | Convert a 16-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c17` | **s32_to_f64** | Convert a 32-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c18` | **s64_to_f64** | Convert a 64-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2c19` | **f64_to_u8** | Convert a 64-bit float to an 8-bit unsigned integer | `R`,&nbsp;`R` |
| `2c1a` | **f64_to_u16** | Convert a 64-bit float to a 16-bit unsigned integer | `R`,&nbsp;`R` |
| `2c1b` | **f64_to_u32** | Convert a 64-bit float to a 32-bit unsigned integer | `R`,&nbsp;`R` |
| `2c1c` | **f64_to_u64** | Convert a 64-bit float to a 64-bit unsigned integer | `R`,&nbsp;`R` |
| `2c1d` | **f64_to_s8** | Convert a 64-bit float to an 8-bit signed integer | `R`,&nbsp;`R` |
| `2c1e` | **f64_to_s16** | Convert a 64-bit float to a 16-bit signed integer | `R`,&nbsp;`R` |
| `2c1f` | **f64_to_s32** | Convert a 64-bit float to a 32-bit signed integer | `R`,&nbsp;`R` |
| `2c20` | **f64_to_s64** | Convert a 64-bit float to a 64-bit signed integer | `R`,&nbsp;`R` |



