//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}

pub const Sparse = @import("lib/sparse.zig");
