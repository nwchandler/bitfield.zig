## bitfield.zig

This library provides a simple abstraction of bitfields for the Zig programming
language. Bitfields can be convenient for representing dense information in
small representations, and they are common in protocol headers, file formats,
and more.

Zig makes it fairly straightforward to produce bitfields, however this library
aims to make it a bit simpler while also providing some helpers for validation.
Bitfield types are produced at comptime, making them programmatically dynamic
but without a runtime construction cost.

> Note: The Zig language is still in active development and changes frequently.
It was originally developed using Zig v0.15.2, but it appears there will be some
breaking underlying changes in 0.16, and there could be more in the future. I'll
try to keep this up-to-date as new versions release, but issues or PRs are
welcome.

### Installation

1. Add bitfield as a dependency in your `build.zig.zon` file. (Can be done
automatically using the following.)

```sh
zig fetch --save "git+https://www.github.com/nwchandler/bitfield.zig"
```

2. Add bitfield as a build dependency for your executable in `build.zig`. For
instance:

```zig
const bitfield = b.dependency("bitfield", .{
  .target = target,
  .optimize = optimize,
});

exe.root_module.addImport("bitfield", bitfield.module("bitfield"));
```

### Examples

Examples are provided in the `./examples` directory. They are also added to
build targets so that you can execute them using, for instance,
`zig build example-dns`.
