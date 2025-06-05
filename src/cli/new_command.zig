const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(".new_command");

pub const Options = struct {
    orphan: bool = false,
    pub fn help(self: Options) ![]u8 {
        return self._help();
    }
    pub fn h(self: Options) ![]u8 {
        return self._help();
    }
    fn _help(self: Options) ![]u8 {
        _ = self;
        return @constCast("Hello Moto!");
    }
};

pub const Args = struct {
    advanced: ?struct {
        branch: [1][]u8 = undefined,
        target: ?[1][]u8 = .{@constCast("main")},
    } = undefined,
};

pub const NewCommand = struct {

    // sparse new [options] [<branch> [--target:-main>]]
    // options:
    //  -h, --help
    pub fn run(self: NewCommand, alloc: Allocator) !u8 {
        _ = self;
        var args: Args = .{};

        const cli_args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, cli_args);
        try command.parseArgs(Args, alloc, &args, cli_args);
        if (args.advanced) |details| {
            std.debug.print("{s} {s}\n", .{ details.branch[0], details.target.?[0] });
        }
        return 0;
    }
};
