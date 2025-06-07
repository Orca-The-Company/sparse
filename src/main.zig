//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const sparse_lib = @import("sparse_lib");

pub fn main() !void {
    _ = try sparse_lib.add(5, 5);

    //try cli.run();
}

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const cli = @import("cli.zig");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("sparse_lib");
