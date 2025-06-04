const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(".check_command");

pub const Options = struct {
    @"--orphan": bool = false,
    @"--test": u32 = 55,
    pub fn help(self: Options) ![]u8 {
        _ = self;
        return @constCast("Hello Moto!");
    }
};
pub const Args = struct {
    c: bool = false,
    a: u32 = 5,
    b: u32 = 10,
    branch: struct {
        branch: u32 = 0,
        target: u32 = 0,
    } = .{},
};

pub const CheckCommand = struct {
    pub fn run(self: CheckCommand, alloc: Allocator) !u8 {
        _ = self;
        var args: Args = .{};
        const cli_args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, cli_args);

        try command.parseArgs(Args, alloc, &args, cli_args);
        return 0;
        // check [options] [<branch>]
        // options:
        //  -h, --help
    }
};
