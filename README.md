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

+ Little-endian encoding
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
+ Effects-aware
+ Tail recursion

### Parameter Legend

| Symbol | Type | Description | Bit Size |
| ------ | ---- | ----------- | -------- |
| `R` | Register | Register index | `8` |
| `H` | HandlerSetIndex | Designates to an effect handler set | `16` |
| `E` | EvidenceIndex | Designates a specific effect handler on the stack of effect handlers | `16` |
| `G` | GlobalIndex | Designates a global variable | `16` |
| `U` | UpvalueIndex | Designates a register in the enclosing scope of an effect handler | `8` |
| `F` | FunctionIndex | Designates a specific function | `16` |
| `B` | BlockIndex | Designates a specific block; may be either relative to the function (called absolute below) or relative to the block the instruction is in, depending on instruction type | `16` |
| `b` | Byte Immediate | Number designating the amount of values to follow the instruction | `8` |
| `I` | Immediate | Immediate value encoded directly within the instruction | `32` |
| `W`| Wide Immediate | Immediate value encoded after the instruction | `64` |


### Op codes

Current total number of instructions: 467
#### Miscellaneous

+ [nop](#nop)
##### nop
Not an operation; does nothing
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0001` | nop | No operation |  |


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
| `0101` | halt | Halt execution |  |

##### trap
Stops execution of the program and triggers the `unreachable` trap
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0201` | trap | Trigger a trap |  |

##### block
Unconditionally enter the block designated by the block operand

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0301` | block | Enter a block | `B` |
| `0302` | block_v | Enter a block, placing the output value in the designated register | `B`,&nbsp;`R` |

##### with
Enter the block designated by the block operand, using the handler set operand to handle matching effects inside

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0401` | with | Enter a block, using the designated handler set | `B`,&nbsp;`H` |
| `0402` | with_v | Enter a block, using the designated handler set, and place the output value in the designated register | `B`,&nbsp;`H`,&nbsp;`R` |

##### if
If the 8-bit conditional value designated by the register operand matches the test:
+ Then: Enter the block designated by the block operand
+ Else: Enter the block designated by the else block operand

The block operands are absolute block indices
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0501` | if_nz | Enter the first block, if the condition is non-zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R` |
| `0502` | if_z | Enter the first block, if the condition is zero; otherwise, enter the second block | `B`,&nbsp;`B`,&nbsp;`R` |

##### when
If the 8-bit conditional value designated by the register operand matches the test:
+ Enter the block designated by the block operand

The block operand is an absolute block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0601` | when_nz | Enter a block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0602` | when_z | Enter a block, if the condition is zero | `B`,&nbsp;`R` |

##### re
Restart the block designated by the block operand

The block operand is a relative block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0701` | re | Restart the designated block | `B` |
| `0702` | re_nz | Restart the designated block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0703` | re_z | Restart the designated block, if the condition is zero | `B`,&nbsp;`R` |

##### br
Exit the block designated by the block operand

The block operand is a relative block index
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0801` | br | Exit the designated block | `B` |
| `0802` | br_nz | Exit the designated block, if the condition is non-zero | `B`,&nbsp;`R` |
| `0803` | br_z | Exit the designated block, if the condition is zero | `B`,&nbsp;`R` |
| `0804` | br_v | Exit the designated block, yielding the value in the designated register | `B`,&nbsp;`R` |
| `0805` | br_nz_v | Exit the designated block, if the condition is non-zero; yield the value in the secondary register | `B`,&nbsp;`R`,&nbsp;`R` |
| `0806` | br_z_v | Exit the designated block, if the condition is zero; yield the value in the secondary register | `B`,&nbsp;`R`,&nbsp;`R` |
| `0807` | im_br_v | Exit the designated block, yielding an immediate up to 32 bits | `B`,&nbsp;`I` |
| `0808` | im_w_br_v | Exit the designated block, yielding an immediate up to 64 bits | `B`&nbsp;+&nbsp;`W` |
| `0809` | im_br_nz_v | Exit the designated block, if the condition is non-zero; yield an immediate | `B`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `080a` | im_br_z_v | Exit the designated block, if the condition is zero; yield an immediate | `B`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### call
Call the function designated by the function operand; expect a number of arguments, designated by the byte value operand, to follow this instruction
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0901` | im_call | Call a static function, expecting no return value (discards the result, if there is one) | `F`,&nbsp;`b` |
| `0902` | im_call_v | Call a static function, and place the return value in the designated register | `F`,&nbsp;`b`,&nbsp;`R` |
| `0903` | im_call_tail | Call a static function in tail position, expecting no return value (discards the result, if there is one) | `F`,&nbsp;`b` |
| `0904` | im_call_tail_v | Call a static function in tail position, expecting a return value (places the result in the caller's return register) | `F`,&nbsp;`b` |
| `0905` | call | Call a dynamic function, expecting no return value (discards the result, if there is one) | `R`,&nbsp;`b` |
| `0906` | call_v | Call a dynamic function, and place the return value in the designated register | `R`,&nbsp;`b`,&nbsp;`R` |
| `0907` | call_tail | Call a dynamic function in tail position, expecting no return value (discards the result, if there is one) | `R`,&nbsp;`b` |
| `0908` | call_tail_v | Call a dynamic function in tail position, and place the result in the caller's return register | `R`,&nbsp;`b`,&nbsp;`R` |

##### prompt
Call the effect handler designated by the evidence operand; expect a number of arguments, designated by the byte value operand, to follow this instruction
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0a01` | prompt | Call an effect handler, expecting no return value (discards the result, if there is one) | `E`,&nbsp;`b` |
| `0a02` | prompt_v | Call an effect handler, and place the return value in the designated register | `E`,&nbsp;`b`,&nbsp;`R` |
| `0a03` | prompt_tail | Call an effect handler in tail position, expecting no return value (discards the result, if there is one) | `E`,&nbsp;`b` |
| `0a04` | prompt_tail_v | Call an effect handler in tail position, and place the return value in the caller's return register | `E`,&nbsp;`b` |

##### ret
Return from the current function, optionally placing the result in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0b01` | ret | Return from the current function, yielding no value |  |
| `0b02` | ret_v | Return from the current function, yielding the value in the designated register | `R` |
| `0b03` | im_ret_v | Return from the current function, yielding an immediate value up to 32 bits | `I` |
| `0b04` | im_w_ret_v | Return from the current function, yielding an immediate value up to 64 bits | `W` |

##### term
Trigger early-termination of an effect handler, ending the block it was introduced in
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0c01` | term | Terminate the current effect handler, yielding no value |  |
| `0c02` | term_v | Terminate the current effect handler, yielding the value in the designated register | `R` |
| `0c03` | im_term_v | Terminate the current effect handler, yielding an immediate value up to 32 bits | `I` |
| `0c04` | im_w_term_v | Terminate the current effect handler, yielding an immediate value up to 64 bits | `W` |


#### Memory
Instructions for memory access and manipulation
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
##### addr
Place the address of the value designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0d01` | addr_global | Place the address of the global into the register | `G`,&nbsp;`R` |
| `0d02` | addr_upvalue | Place the address of the upvalue into the register | `U`,&nbsp;`R` |
| `0d03` | addr_local | Place the address of the first register into the second register | `R`,&nbsp;`R` |

##### read_global
Copy a number of bits from the global designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0e01` | read_global_8 | Copy 8 bits from the global into the register | `G`,&nbsp;`R` |
| `0e02` | read_global_16 | Copy 16 bits from the global into the register | `G`,&nbsp;`R` |
| `0e03` | read_global_32 | Copy 32 bits from the global into the register | `G`,&nbsp;`R` |
| `0e04` | read_global_64 | Copy 64 bits from the global into the register | `G`,&nbsp;`R` |

##### read_upvalue
Copy a number of bits from the upvalue designated by the first operand into the register provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `0f01` | read_upvalue_8 | Copy 8 bits from the upvalue into the register | `R`,&nbsp;`R` |
| `0f02` | read_upvalue_16 | Copy 16 bits from the upvalue into the register | `R`,&nbsp;`R` |
| `0f03` | read_upvalue_32 | Copy 32 bits from the upvalue into the register | `R`,&nbsp;`R` |
| `0f04` | read_upvalue_64 | Copy 64 bits from the upvalue into the register | `R`,&nbsp;`R` |

##### write_global
Copy a number of bits from the value designated by the first operand into the global provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1001` | write_global_8 | Copy 8 bits from the register into the global | `R`,&nbsp;`G` |
| `1002` | write_global_16 | Copy 16 bits from the register into the global | `R`,&nbsp;`G` |
| `1003` | write_global_32 | Copy 32 bits from the register into the global | `R`,&nbsp;`G` |
| `1004` | write_global_64 | Copy 64 bits from the register into the global | `R`,&nbsp;`G` |
| `1005` | im_write_global_8 | Copy 8 bits from the immediate into the global | `I`,&nbsp;`G` |
| `1006` | im_write_global_16 | Copy 16 bits from the immediate into the global | `I`,&nbsp;`G` |
| `1007` | im_write_global_32 | Copy 32 bits from the immediate into the global | `R`,&nbsp;`G` |
| `1008` | im_write_global_64 | Copy 64 bits from the immediate into the global | `G`&nbsp;+&nbsp;`W` |

##### write_upvalue
Copy a number of bits from the value designated by the first operand into the upvalue provided in the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1101` | write_upvalue_8 | Copy 8 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1102` | write_upvalue_16 | Copy 16 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1103` | write_upvalue_32 | Copy 32 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1104` | write_upvalue_64 | Copy 64 bits from the register into the designated upvalue | `R`,&nbsp;`R` |
| `1105` | im_write_upvalue_8 | Copy 8 bits from the immediate into the designated upvalue | `I`,&nbsp;`R` |
| `1106` | im_write_upvalue_16 | Copy 16 bits from the immediate into the designated upvalue | `I`,&nbsp;`R` |
| `1107` | im_write_upvalue_32 | Copy 32 bits from the register into the designated upvalue | `I`,&nbsp;`R` |
| `1108` | im_write_upvalue_64 | Copy 64 bits from the immediate into the designated upvalue | `R`&nbsp;+&nbsp;`W` |

##### load
Copy a number of bits from the memory address designated by the first operand into the register provided in the second operand

The address must be located on the stack or global memory
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1201` | load_8 | Copy 8 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `1202` | load_16 | Copy 16 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `1203` | load_32 | Copy 32 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |
| `1204` | load_64 | Copy 64 bits from the memory address in the first register into the second register | `R`,&nbsp;`R` |

##### store
Copy a number of bits from the value designated by the first operand into the memory address in the register provided in the second operand

The address must be located on the stack or global memory
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1301` | store_8 | Copy 8 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1302` | store_16 | Copy 16 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1303` | store_32 | Copy 32 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1304` | store_64 | Copy 64 bits from the first register into the memory address in the second register | `R`,&nbsp;`R` |
| `1305` | im_store_8 | Copy 8 bits from the immediate into the memory address in the register | `I`,&nbsp;`R` |
| `1306` | im_store_16 | Copy 16 bits from the immediate into the memory address in the register | `I`,&nbsp;`R` |
| `1307` | im_store_32 | Copy 32 bits from the immediate into the memory address in the register | `I`,&nbsp;`R` |
| `1308` | im_store_64 | Copy 64 bits from the immediate into the memory address in the register | `R`&nbsp;+&nbsp;`W` |

##### clear
Clear a number of bits in the designated register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1401` | clear_8 | Clear 8 bits from the register | `R` |
| `1402` | clear_16 | Clear 16 bits from the register | `R` |
| `1403` | clear_32 | Clear 32 bits from the register | `R` |
| `1404` | clear_64 | Clear 64 bits from the register | `R` |

##### swap
Swap a number of bits in the two designated registers
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1501` | swap_8 | Swap 8 bits between the two registers | `R`,&nbsp;`R` |
| `1502` | swap_16 | Swap 16 bits between the two registers | `R`,&nbsp;`R` |
| `1503` | swap_32 | Swap 32 bits between the two registers | `R`,&nbsp;`R` |
| `1504` | swap_64 | Swap 64 bits between the two registers | `R`,&nbsp;`R` |

##### copy
Copy a number of bits from the first register into the second register
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1601` | copy_8 | Copy 8 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1602` | copy_16 | Copy 16 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1603` | copy_32 | Copy 32 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1604` | copy_64 | Copy 64 bits from the first register into the second register | `R`,&nbsp;`R` |
| `1605` | im_copy_8 | Copy 8-bits from an immediate value into the register | `I`,&nbsp;`R` |
| `1606` | im_copy_16 | Copy 16-bits from an immediate value into the register | `I`,&nbsp;`R` |
| `1607` | im_copy_32 | Copy 32-bits from an immediate value into the register | `I`,&nbsp;`R` |
| `1608` | im_copy_64 | Copy 64-bits from an immediate value into the register | `R`&nbsp;+&nbsp;`W` |


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
| `1701` | i_add_8 | Sign-agnostic addition on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1702` | i_add_16 | Sign-agnostic addition on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1703` | i_add_32 | Sign-agnostic addition on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1704` | i_add_64 | Sign-agnostic addition on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1705` | im_i_add_8 | Sign-agnostic addition on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1706` | im_i_add_16 | Sign-agnostic addition on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1707` | im_i_add_32 | Sign-agnostic addition on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1708` | im_i_add_64 | Sign-agnostic addition on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1709` | f_add_32 | Addition on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `170a` | f_add_64 | Addition on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `170b` | im_f_add_32 | Addition on 32-bit floats; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `170c` | im_f_add_64 | Addition on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### sub
Subtraction on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1801` | i_sub_8 | Sign-agnostic subtraction on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1802` | i_sub_16 | Sign-agnostic subtraction on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1803` | i_sub_32 | Sign-agnostic subtraction on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1804` | i_sub_64 | Sign-agnostic subtraction on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1805` | im_a_i_sub_8 | Sign-agnostic subtraction on 8-bit integers; subtract register value from immediate value | `I`,&nbsp;`R`,&nbsp;`R` |
| `1806` | im_a_i_sub_16 | Sign-agnostic subtraction on 16-bit integers; subtract register value from immediate value | `I`,&nbsp;`R`,&nbsp;`R` |
| `1807` | im_a_i_sub_32 | Sign-agnostic subtraction on 32-bit integers; subtract register value from immediate value | `I`,&nbsp;`R`,&nbsp;`R` |
| `1808` | im_a_i_sub_64 | Sign-agnostic subtraction on 64-bit integers; subtract register value from immediate value | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1809` | im_b_i_sub_8 | Sign-agnostic subtraction on 8-bit integers; subtract immediate value from register value | `R`,&nbsp;`I`,&nbsp;`R` |
| `180a` | im_b_i_sub_16 | Sign-agnostic subtraction on 16-bit integers; subtract immediate value from register value | `R`,&nbsp;`I`,&nbsp;`R` |
| `180b` | im_b_i_sub_32 | Sign-agnostic subtraction on 32-bit integers; subtract immediate value from register value | `R`,&nbsp;`I`,&nbsp;`R` |
| `180c` | im_b_i_sub_64 | Sign-agnostic subtraction on 64-bit integers; subtract immediate value from register value | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `180d` | f_sub_32 | Subtraction on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `180e` | f_sub_64 | Subtraction on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `180f` | im_a_f_sub_32 | Subtraction on 32-bit floats; subtract register value from immediate value | `I`,&nbsp;`R`,&nbsp;`R` |
| `1810` | im_a_f_sub_64 | Subtraction on 64-bit floats; subtract register value from immediate value | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1811` | im_b_f_sub_32 | Subtraction on 32-bit floats; subtract immediate value from register value | `R`,&nbsp;`I`,&nbsp;`R` |
| `1812` | im_b_f_sub_64 | Subtraction on 64-bit floats; subtract immediate value from register value | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### mul
Multiplication on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1901` | i_mul_8 | Sign-agnostic multiplication on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1902` | i_mul_16 | Sign-agnostic multiplication on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1903` | i_mul_32 | Sign-agnostic multiplication on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1904` | i_mul_64 | Sign-agnostic multiplication on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1905` | im_i_mul_8 | Sign-agnostic multiplication on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1906` | im_i_mul_16 | Sign-agnostic multiplication on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1907` | im_i_mul_32 | Sign-agnostic multiplication on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1908` | im_i_mul_64 | Sign-agnostic multiplication on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1909` | f_mul_32 | Multiplication on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `190a` | f_mul_64 | Multiplication on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `190b` | im_f_mul_32 | Multiplication on 32-bit floats; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `190c` | im_f_mul_64 | Multiplication on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### div
Division on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1a01` | u_div_8 | Unsigned division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a02` | u_div_16 | Unsigned division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a03` | u_div_32 | Unsigned division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a04` | u_div_64 | Unsigned division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a05` | im_a_u_div_8 | Unsigned division on 8-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a06` | im_a_u_div_16 | Unsigned division on 16-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a07` | im_a_u_div_32 | Unsigned division on 32-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a08` | im_a_u_div_64 | Unsigned division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1a09` | im_b_u_div_8 | Unsigned division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a0a` | im_b_u_div_16 | Unsigned division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a0b` | im_b_u_div_32 | Unsigned division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a0c` | im_b_u_div_64 | Unsigned division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1a0d` | s_div_8 | Signed division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a0e` | s_div_16 | Signed division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a0f` | s_div_32 | Signed division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a10` | s_div_64 | Signed division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a11` | im_a_s_div_8 | Signed division on 8-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a12` | im_a_s_div_16 | Signed division on 16-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a13` | im_a_s_div_32 | Signed division on 32-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a14` | im_a_s_div_64 | Signed division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1a15` | im_b_s_div_8 | Signed division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a16` | im_b_s_div_16 | Signed division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a17` | im_b_s_div_32 | Signed division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a18` | im_b_s_div_64 | Signed division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1a19` | f_div_32 | Division on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a1a` | f_div_64 | Division on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1a1b` | im_a_f_div_32 | Division on 32-bit floats; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1a1c` | im_a_f_div_64 | Division on 64-bit floats; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1a1d` | im_b_f_div_32 | Division on 32-bit floats; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1a1e` | im_b_f_div_64 | Division on 64-bit floats; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### rem
Remainder division on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1b01` | u_rem_8 | Unsigned remainder division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b02` | u_rem_16 | Unsigned remainder division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b03` | u_rem_32 | Unsigned remainder division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b04` | u_rem_64 | Unsigned remainder division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b05` | im_a_u_rem_8 | Unsigned remainder division on 8-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b06` | im_a_u_rem_16 | Unsigned remainder division on 16-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b07` | im_a_u_rem_32 | Unsigned remainder division on 32-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b08` | im_a_u_rem_64 | Unsigned remainder division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1b09` | im_b_u_rem_8 | Unsigned remainder division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b0a` | im_b_u_rem_16 | Unsigned remainder division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b0b` | im_b_u_rem_32 | Unsigned remainder division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b0c` | im_b_u_rem_64 | Unsigned remainder division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1b0d` | s_rem_8 | Signed remainder division on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b0e` | s_rem_16 | Signed remainder division on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b0f` | s_rem_32 | Signed remainder division on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b10` | s_rem_64 | Signed remainder division on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b11` | im_a_s_rem_8 | Signed remainder division on 8-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b12` | im_a_s_rem_16 | Signed remainder division on 16-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b13` | im_a_s_rem_32 | Signed remainder division on 32-bit integers; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b14` | im_a_s_rem_64 | Signed remainder division on 64-bit integers; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1b15` | im_b_s_rem_8 | Signed remainder division on 8-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b16` | im_b_s_rem_16 | Signed remainder division on 16-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b17` | im_b_s_rem_32 | Signed remainder division on 32-bit integers; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b18` | im_b_s_rem_64 | Signed remainder division on 64-bit integers; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1b19` | f_rem_32 | Remainder division on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b1a` | f_rem_64 | Remainder division on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1b1b` | im_a_f_rem_32 | Remainder division on 32-bit floats; immediate dividend, register divisor | `I`,&nbsp;`R`,&nbsp;`R` |
| `1b1c` | im_a_f_rem_64 | Remainder division on 64-bit floats; immediate dividend, register divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `1b1d` | im_b_f_rem_32 | Remainder division on 32-bit floats; register dividend, immediate divisor | `R`,&nbsp;`I`,&nbsp;`R` |
| `1b1e` | im_b_f_rem_64 | Remainder division on 64-bit floats; register dividend, immediate divisor | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### neg
Negation of a single operand, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1c01` | s_neg_8 | Negation of an 8-bit integer | `R`,&nbsp;`R` |
| `1c02` | s_neg_16 | Negation of a 16-bit integer | `R`,&nbsp;`R` |
| `1c03` | s_neg_32 | Negation of a 32-bit integer | `R`,&nbsp;`R` |
| `1c04` | s_neg_64 | Negation of a 64-bit integer | `R`,&nbsp;`R` |
| `1c05` | f_neg_32 | Negation of a 32-bit float | `R`,&nbsp;`R` |
| `1c06` | f_neg_64 | Negation of a 64-bit float | `R`,&nbsp;`R` |


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
| `1d01` | band_8 | Bitwise AND on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1d02` | band_16 | Bitwise AND on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1d03` | band_32 | Bitwise AND on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1d04` | band_64 | Bitwise AND on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1d05` | im_band_8 | Bitwise AND on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1d06` | im_band_16 | Bitwise AND on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1d07` | im_band_32 | Bitwise AND on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1d08` | im_band_64 | Bitwise AND on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### bor
Bitwise OR on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1e01` | bor_8 | Bitwise OR on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e02` | bor_16 | Bitwise OR on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e03` | bor_32 | Bitwise OR on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e04` | bor_64 | Bitwise OR on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1e05` | im_bor_8 | Bitwise OR on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1e06` | im_bor_16 | Bitwise OR on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1e07` | im_bor_32 | Bitwise OR on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1e08` | im_bor_64 | Bitwise OR on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### bxor
Bitwise XOR on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `1f01` | bxor_8 | Bitwise XOR on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f02` | bxor_16 | Bitwise XOR on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f03` | bxor_32 | Bitwise XOR on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f04` | bxor_64 | Bitwise XOR on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `1f05` | im_bxor_8 | Bitwise XOR on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1f06` | im_bxor_16 | Bitwise XOR on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1f07` | im_bxor_32 | Bitwise XOR on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `1f08` | im_bxor_64 | Bitwise XOR on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### bnot
Bitwise NOT on a single operand, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2001` | bnot_8 | Bitwise NOT on an 8-bit integer in a register | `R`,&nbsp;`R` |
| `2002` | bnot_16 | Bitwise NOT on a 16-bit integer in registers | `R`,&nbsp;`R` |
| `2003` | bnot_32 | Bitwise NOT on a 32-bit integer in a register | `R`,&nbsp;`R` |
| `2004` | bnot_64 | Bitwise NOT on a 64-bit integer in a register | `R`,&nbsp;`R` |

##### bshiftl
Bitwise left shift on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2101` | bshiftl_8 | Bitwise left shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2102` | bshiftl_16 | Bitwise left shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2103` | bshiftl_32 | Bitwise left shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2104` | bshiftl_64 | Bitwise left shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2105` | im_a_bshiftl_8 | Bitwise left shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2106` | im_a_bshiftl_16 | Bitwise left shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2107` | im_a_bshiftl_32 | Bitwise left shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2108` | im_a_bshiftl_64 | Bitwise left shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2109` | im_b_bshiftl_8 | Bitwise left shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `210a` | im_b_bshiftl_16 | Bitwise left shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `210b` | im_b_bshiftl_32 | Bitwise left shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `210c` | im_b_bshiftl_64 | Bitwise left shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### bshiftr
Bitwise right shift on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2201` | u_bshiftr_8 | Logical bitwise right shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2202` | u_bshiftr_16 | Logical bitwise right shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2203` | u_bshiftr_32 | Logical bitwise right shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2204` | u_bshiftr_64 | Logical bitwise right shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2205` | im_a_u_bshiftr_8 | Logical bitwise right shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2206` | im_a_u_bshiftr_16 | Logical bitwise right shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2207` | im_a_u_bshiftr_32 | Logical bitwise right shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2208` | im_a_u_bshiftr_64 | Logical bitwise right shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2209` | im_b_u_bshiftr_8 | Logical bitwise right shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `220a` | im_b_u_bshiftr_16 | Logical bitwise right shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `220b` | im_b_u_bshiftr_32 | Logical bitwise right shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `220c` | im_b_u_bshiftr_64 | Logical bitwise right shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `220d` | s_bshiftr_8 | Arithmetic bitwise right shift on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `220e` | s_bshiftr_16 | Arithmetic bitwise right shift on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `220f` | s_bshiftr_32 | Arithmetic bitwise right shift on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2210` | s_bshiftr_64 | Arithmetic bitwise right shift on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2211` | im_a_s_bshiftr_8 | Arithmetic bitwise right shift on 8-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2212` | im_a_s_bshiftr_16 | Arithmetic bitwise right shift on 16-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2213` | im_a_s_bshiftr_32 | Arithmetic bitwise right shift on 32-bit integers; the shifted value is immediate, the shift count is in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2214` | im_a_s_bshiftr_64 | Arithmetic bitwise right shift on 64-bit integers; the shifted value is immediate, the shift count is in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2215` | im_b_s_bshiftr_8 | Arithmetic bitwise right shift on 8-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `2216` | im_b_s_bshiftr_16 | Arithmetic bitwise right shift on 16-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `2217` | im_b_s_bshiftr_32 | Arithmetic bitwise right shift on 32-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`I`,&nbsp;`R` |
| `2218` | im_b_s_bshiftr_64 | Arithmetic bitwise right shift on 64-bit integers; the shifted value is in a register, the shift count is immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |


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
| `2301` | i_eq_8 | Sign-agnostic equality comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2302` | i_eq_16 | Sign-agnostic equality comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2303` | i_eq_32 | Sign-agnostic equality comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2304` | i_eq_64 | Sign-agnostic equality comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2305` | im_i_eq_8 | Sign-agnostic equality comparison on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2306` | im_i_eq_16 | Sign-agnostic equality comparison on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2307` | im_i_eq_32 | Sign-agnostic equality comparison on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2308` | im_i_eq_64 | Sign-agnostic equality comparison on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2309` | f_eq_32 | Equality comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `230a` | f_eq_64 | Equality comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `230b` | im_f_eq_32 | Equality comparison on 32-bit floats; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `230c` | im_f_eq_64 | Equality comparison on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### ne
Inequality comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2401` | i_ne_8 | Sign-agnostic inequality comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2402` | i_ne_16 | Sign-agnostic inequality comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2403` | i_ne_32 | Sign-agnostic inequality comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2404` | i_ne_64 | Sign-agnostic inequality comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2405` | im_i_ne_8 | Sign-agnostic inequality comparison on 8-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2406` | im_i_ne_16 | Sign-agnostic inequality comparison on 16-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2407` | im_i_ne_32 | Sign-agnostic inequality comparison on 32-bit integers; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `2408` | im_i_ne_64 | Sign-agnostic inequality comparison on 64-bit integers; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2409` | f_ne_32 | Inequality comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `240a` | f_ne_64 | Inequality comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `240b` | im_f_ne_32 | Inequality comparison on 32-bit floats; one immediate, one in a register | `I`,&nbsp;`R`,&nbsp;`R` |
| `240c` | im_f_ne_64 | Inequality comparison on 64-bit floats; one immediate, one in a register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### lt
Less than comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2501` | u_lt_8 | Unsigned less than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2502` | u_lt_16 | Unsigned less than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2503` | u_lt_32 | Unsigned less than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2504` | u_lt_64 | Unsigned less than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2505` | im_a_u_lt_8 | Unsigned less than comparison on 8-bit integers; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2506` | im_a_u_lt_16 | Unsigned less than comparison on 16-bit integers; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2507` | im_a_u_lt_32 | Unsigned less than comparison on 32-bit integers; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2508` | im_a_u_lt_64 | Unsigned less than comparison on 64-bit integers; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2509` | im_b_u_lt_8 | Unsigned less than comparison on 8-bit integers; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `250a` | im_b_u_lt_16 | Unsigned less than comparison on 16-bit integers; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `250b` | im_b_u_lt_32 | Unsigned less than comparison on 32-bit integers; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `250c` | im_b_u_lt_64 | Unsigned less than comparison on 64-bit integers; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `250d` | s_lt_8 | Signed less than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `250e` | s_lt_16 | Signed less than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `250f` | s_lt_32 | Signed less than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2510` | s_lt_64 | Signed less than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2511` | im_a_s_lt_8 | Signed less than comparison on 8-bit integers; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2512` | im_a_s_lt_16 | Signed less than comparison on 16-bit integers; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2513` | im_a_s_lt_32 | Signed less than comparison on 32-bit integers; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2514` | im_a_s_lt_64 | Signed less than comparison on 64-bit integers; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2515` | im_b_s_lt_8 | Signed less than comparison on 8-bit integers; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2516` | im_b_s_lt_16 | Signed less than comparison on 16-bit integers; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2517` | im_b_s_lt_32 | Signed less than comparison on 32-bit integers; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2518` | im_b_s_lt_64 | Signed less than comparison on 64-bit integers; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2519` | f_lt_32 | Less than comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `251a` | f_lt_64 | Less than comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `251b` | im_a_f_lt_32 | Less than comparison on 32-bit floats; one immediate; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `251c` | im_a_f_lt_64 | Less than comparison on 64-bit floats; one immediate; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `251d` | im_b_f_lt_32 | Less than comparison on 32-bit floats; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `251e` | im_b_f_lt_64 | Less than comparison on 64-bit floats; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### gt
Greater than comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2601` | u_gt_8 | Unsigned greater than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2602` | u_gt_16 | Unsigned greater than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2603` | u_gt_32 | Unsigned greater than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2604` | u_gt_64 | Unsigned greater than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2605` | im_a_u_gt_8 | Unsigned greater than comparison on 8-bit integers; check register greater than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2606` | im_a_u_gt_16 | Unsigned greater than comparison on 16-bit integers; check register greater than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2607` | im_a_u_gt_32 | Unsigned greater than comparison on 32-bit integers; check register greater than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2608` | im_a_u_gt_64 | Unsigned greater than comparison on 64-bit integers; check register greater than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2609` | im_b_u_gt_8 | Unsigned greater than comparison on 8-bit integers; check immediate greater than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `260a` | im_b_u_gt_16 | Unsigned greater than comparison on 16-bit integers; check immediate greater than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `260b` | im_b_u_gt_32 | Unsigned greater than comparison on 32-bit integers; check immediate greater than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `260c` | im_b_u_gt_64 | Unsigned greater than comparison on 64-bit integers; check immediate greater than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `260d` | s_gt_8 | Signed greater than comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `260e` | s_gt_16 | Signed greater than comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `260f` | s_gt_32 | Signed greater than comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2610` | s_gt_64 | Signed greater than comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2611` | im_a_s_gt_8 | Signed greater than comparison on 8-bit integers; check register greater than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2612` | im_a_s_gt_16 | Signed greater than comparison on 16-bit integers; check register greater than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2613` | im_a_s_gt_32 | Signed greater than comparison on 32-bit integers; check register greater than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2614` | im_a_s_gt_64 | Signed greater than comparison on 64-bit integers; check register greater than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2615` | im_b_s_gt_8 | Signed greater than comparison on 8-bit integers; check immediate greater than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2616` | im_b_s_gt_16 | Signed greater than comparison on 16-bit integers; check immediate greater than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2617` | im_b_s_gt_32 | Signed greater than comparison on 32-bit integers; check immediate greater than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2618` | im_b_s_gt_64 | Signed greater than comparison on 64-bit integers; check immediate greater than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2619` | f_gt_32 | Greater than comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `261a` | f_gt_64 | Greater than comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `261b` | im_a_f_gt_32 | Greater than comparison on 32-bit floats; one immediate; check register less than immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `261c` | im_a_f_gt_64 | Greater than comparison on 64-bit floats; one immediate; check register less than immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `261d` | im_b_f_gt_32 | Greater than comparison on 32-bit floats; check immediate less than register | `R`,&nbsp;`I`,&nbsp;`R` |
| `261e` | im_b_f_gt_64 | Greater than comparison on 64-bit floats; check immediate less than register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### le
Less than or equal comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2701` | u_le_8 | Unsigned less than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2702` | u_le_16 | Unsigned less than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2703` | u_le_32 | Unsigned less than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2704` | u_le_64 | Unsigned less than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2705` | im_a_u_le_8 | Unsigned less than or equal comparison on 8-bit integers; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2706` | im_a_u_le_16 | Unsigned less than or equal comparison on 16-bit integers; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2707` | im_a_u_le_32 | Unsigned less than or equal comparison on 32-bit integers; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2708` | im_a_u_le_64 | Unsigned less than or equal comparison on 64-bit integers; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2709` | im_b_u_le_8 | Unsigned less than or equal comparison on 8-bit integers; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `270a` | im_b_u_le_16 | Unsigned less than or equal comparison on 16-bit integers; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `270b` | im_b_u_le_32 | Unsigned less than or equal comparison on 32-bit integers; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `270c` | im_b_u_le_64 | Unsigned less than or equal comparison on 64-bit integers; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `270d` | s_le_8 | Signed less than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `270e` | s_le_16 | Signed less than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `270f` | s_le_32 | Signed less than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2710` | s_le_64 | Signed less than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2711` | im_a_s_le_8 | Signed less than or equal comparison on 8-bit integers; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2712` | im_a_s_le_16 | Signed less than or equal comparison on 16-bit integers; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2713` | im_a_s_le_32 | Signed less than or equal comparison on 32-bit integers; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2714` | im_a_s_le_64 | Signed less than or equal comparison on 64-bit integers; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2715` | im_b_s_le_8 | Signed less than or equal comparison on 8-bit integers; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2716` | im_b_s_le_16 | Signed less than or equal comparison on 16-bit integers; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2717` | im_b_s_le_32 | Signed less than or equal comparison on 32-bit integers; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2718` | im_b_s_le_64 | Signed less than or equal comparison on 64-bit integers; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2719` | f_le_32 | Less than or equal comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `271a` | f_le_64 | Less than or equal comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `271b` | im_a_f_le_32 | Less than or equal comparison on 32-bit floats; one immediate; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `271c` | im_a_f_le_64 | Less than or equal comparison on 64-bit floats; one immediate; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `271d` | im_b_f_le_32 | Less than or equal comparison on 32-bit floats; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `271e` | im_b_f_le_64 | Less than or equal comparison on 64-bit floats; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |

##### ge
Greater than or equal comparison on two operands, with the result placed in a register designated by the third operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2801` | u_ge_8 | Unsigned greater than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2802` | u_ge_16 | Unsigned greater than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2803` | u_ge_32 | Unsigned greater than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2804` | u_ge_64 | Unsigned greater than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2805` | im_a_u_ge_8 | Unsigned greater than or equal comparison on 8-bit integers; check register greater than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2806` | im_a_u_ge_16 | Unsigned greater than or equal comparison on 16-bit integers; check register greater than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2807` | im_a_u_ge_32 | Unsigned greater than or equal comparison on 32-bit integers; check register greater than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2808` | im_a_u_ge_64 | Unsigned greater than or equal comparison on 64-bit integers; check register greater than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2809` | im_b_u_ge_8 | Unsigned greater than or equal comparison on 8-bit integers; check immediate greater than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `280a` | im_b_u_ge_16 | Unsigned greater than or equal comparison on 16-bit integers; check immediate greater than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `280b` | im_b_u_ge_32 | Unsigned greater than or equal comparison on 32-bit integers; check immediate greater than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `280c` | im_b_u_ge_64 | Unsigned greater than or equal comparison on 64-bit integers; check immediate greater than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `280d` | s_ge_8 | Signed greater than or equal comparison on 8-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `280e` | s_ge_16 | Signed greater than or equal comparison on 16-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `280f` | s_ge_32 | Signed greater than or equal comparison on 32-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2810` | s_ge_64 | Signed greater than or equal comparison on 64-bit integers in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `2811` | im_a_s_ge_8 | Signed greater than or equal comparison on 8-bit integers; check register greater than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2812` | im_a_s_ge_16 | Signed greater than or equal comparison on 16-bit integers; check register greater than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2813` | im_a_s_ge_32 | Signed greater than or equal comparison on 32-bit integers; check register greater than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `2814` | im_a_s_ge_64 | Signed greater than or equal comparison on 64-bit integers; check register greater than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2815` | im_b_s_ge_8 | Signed greater than or equal comparison on 8-bit integers; check immediate greater than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2816` | im_b_s_ge_16 | Signed greater than or equal comparison on 16-bit integers; check immediate greater than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2817` | im_b_s_ge_32 | Signed greater than or equal comparison on 32-bit integers; check immediate greater than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `2818` | im_b_s_ge_64 | Signed greater than or equal comparison on 64-bit integers; check immediate greater than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `2819` | f_ge_32 | Greater than or equal comparison on 32-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `281a` | f_ge_64 | Greater than or equal comparison on 64-bit floats in registers | `R`,&nbsp;`R`,&nbsp;`R` |
| `281b` | im_a_f_ge_32 | Greater than or equal comparison on 32-bit floats; one immediate; check register less than or equal immediate | `I`,&nbsp;`R`,&nbsp;`R` |
| `281c` | im_a_f_ge_64 | Greater than or equal comparison on 64-bit floats; one immediate; check register less than or equal immediate | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |
| `281d` | im_b_f_ge_32 | Greater than or equal comparison on 32-bit floats; check immediate less than or equal register | `R`,&nbsp;`I`,&nbsp;`R` |
| `281e` | im_b_f_ge_64 | Greater than or equal comparison on 64-bit floats; check immediate less than or equal register | `R`,&nbsp;`R`&nbsp;+&nbsp;`W` |


#### Conversion
Convert between different types and sizes of values
+ [ext](#ext)
+ [trunc](#trunc)
+ [to](#to)
##### ext
Convert a value in a register to a larger size, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2901` | u_ext_8_16 | Zero-extend an 8-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2902` | u_ext_8_32 | Zero-extend an 8-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2903` | u_ext_8_64 | Zero-extend an 8-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2904` | u_ext_16_32 | Zero-extend a 16-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2905` | u_ext_16_64 | Zero-extend a 16-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2906` | u_ext_32_64 | Zero-extend a 32-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `2907` | s_ext_8_16 | Sign-extend an 8-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2908` | s_ext_8_32 | Sign-extend an 8-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2909` | s_ext_8_64 | Sign-extend an 8-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `290a` | s_ext_16_32 | Sign-extend a 16-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `290b` | s_ext_16_64 | Sign-extend a 16-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `290c` | s_ext_32_64 | Sign-extend a 32-bit integer to a 64-bit integer | `R`,&nbsp;`R` |
| `290d` | f_ext_32_64 | Convert a 32-bit float to a 64-bit float | `R`,&nbsp;`R` |

##### trunc
Convert a value in a register to a smaller size, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2a01` | i_trunc_64_32 | Truncate a 64-bit integer to a 32-bit integer | `R`,&nbsp;`R` |
| `2a02` | i_trunc_64_16 | Truncate a 64-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2a03` | i_trunc_64_8 | Truncate a 64-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `2a04` | i_trunc_32_16 | Truncate a 32-bit integer to a 16-bit integer | `R`,&nbsp;`R` |
| `2a05` | i_trunc_32_8 | Truncate a 32-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `2a06` | i_trunc_16_8 | Truncate a 16-bit integer to an 8-bit integer | `R`,&nbsp;`R` |
| `2a07` | f_trunc_64_32 | Convert a 64-bit float to a 32-bit float | `R`,&nbsp;`R` |

##### to
Convert a value in a register to a different type, with the result placed in a register designated by the second operand
| Op code | Name | Description | Operands |
| ------- | ---- | ----------- | -------- |
| `2b01` | u8_to_f32 | Convert an 8-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b02` | u16_to_f32 | Convert a 16-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b03` | u32_to_f32 | Convert a 32-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b04` | u64_to_f32 | Convert a 64-bit unsigned integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b05` | s8_to_f32 | Convert an 8-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b06` | s16_to_f32 | Convert a 16-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b07` | s32_to_f32 | Convert a 32-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b08` | s64_to_f32 | Convert a 64-bit signed integer to a 32-bit float | `R`,&nbsp;`R` |
| `2b09` | f32_to_u8 | Convert a 32-bit float to an 8-bit unsigned integer | `R`,&nbsp;`R` |
| `2b0a` | f32_to_u16 | Convert a 32-bit float to a 16-bit unsigned integer | `R`,&nbsp;`R` |
| `2b0b` | f32_to_u32 | Convert a 32-bit float to a 32-bit unsigned integer | `R`,&nbsp;`R` |
| `2b0c` | f32_to_u64 | Convert a 32-bit float to a 64-bit unsigned integer | `R`,&nbsp;`R` |
| `2b0d` | f32_to_s8 | Convert a 32-bit float to an 8-bit signed integer | `R`,&nbsp;`R` |
| `2b0e` | f32_to_s16 | Convert a 32-bit float to a 16-bit signed integer | `R`,&nbsp;`R` |
| `2b0f` | f32_to_s32 | Convert a 32-bit float to a 32-bit signed integer | `R`,&nbsp;`R` |
| `2b10` | f32_to_s64 | Convert a 32-bit float to a 64-bit signed integer | `R`,&nbsp;`R` |
| `2b11` | u8_to_f64 | Convert an 8-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b12` | u16_to_f64 | Convert a 16-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b13` | u32_to_f64 | Convert a 32-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b14` | u64_to_f64 | Convert a 64-bit unsigned integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b15` | s8_to_f64 | Convert an 8-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b16` | s16_to_f64 | Convert a 16-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b17` | s32_to_f64 | Convert a 32-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b18` | s64_to_f64 | Convert a 64-bit signed integer to a 64-bit float | `R`,&nbsp;`R` |
| `2b19` | f64_to_u8 | Convert a 64-bit float to an 8-bit unsigned integer | `R`,&nbsp;`R` |
| `2b1a` | f64_to_u16 | Convert a 64-bit float to a 16-bit unsigned integer | `R`,&nbsp;`R` |
| `2b1b` | f64_to_u32 | Convert a 64-bit float to a 32-bit unsigned integer | `R`,&nbsp;`R` |
| `2b1c` | f64_to_u64 | Convert a 64-bit float to a 64-bit unsigned integer | `R`,&nbsp;`R` |
| `2b1d` | f64_to_s8 | Convert a 64-bit float to an 8-bit signed integer | `R`,&nbsp;`R` |
| `2b1e` | f64_to_s16 | Convert a 64-bit float to a 16-bit signed integer | `R`,&nbsp;`R` |
| `2b1f` | f64_to_s32 | Convert a 64-bit float to a 32-bit signed integer | `R`,&nbsp;`R` |
| `2b20` | f64_to_s64 | Convert a 64-bit float to a 64-bit signed integer | `R`,&nbsp;`R` |



