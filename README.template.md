<div align="center">
  <img style="height: 18em"
       alt="Ribbon Language Logo"
       src="https://ribbon-lang.github.io/images/logo_full.svg"
       />
</div>

<div align="right">
  <h1>Ribbon<sup>I</sup></h1>
  <h3>The Ribbon Virtual Machine</h3>
  <sup><!--#Readme:Build version--></sup>
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


## Discussion

Eventually I will create some places for public discourse about the language,
for now you can reach me via:
- Email: noxabellus@gmail.com
- Discord DM, or on various dev servers: my username is `noxabellus`


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
<!--#Readme:CLI usage-->

#### CLI Options
<!--#Readme:CLI options-->
