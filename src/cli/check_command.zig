const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(".check_command");

pub const Options = struct {
    @"--orphan": bool = false,
    pub fn help(self: Options) ![]u8 {
        _ = self;
        return @constCast("Hello Moto!");
    }
};
pub const Args = struct {
    options: Options = .{},

    branch: ?[]u8 = undefined,
};

pub const CheckCommand = struct {
    pub fn run(self: CheckCommand, alloc: Allocator) !u8 {
        _ = self;
        var args: Args = .{};
        var iterator = try std.process.argsWithAllocator(alloc);
        defer iterator.deinit();
        // skip sparse and command
        _ = iterator.skip();
        if (iterator.skip()) {
            try command.parseArgs(Args, alloc, &args, &iterator);
        }
        return 0;
        // check [options] [<branch>]
        // options:
        //  -h, --help
    }
};
