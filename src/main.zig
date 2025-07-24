const std = @import("std");
// pub const std_options: std.Options = .{
//     .log_level = .info,
// };

pub fn main() !void {
    try cli.run();
}

test {
    std.testing.refAllDecls(@This());
}

const cli = @import("cli.zig");
