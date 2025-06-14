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
pub const Positionals = struct {
    c: bool = false,
    a: u32 = 5,
    b: u32 = 10,
    rest: [][:0]u8 = undefined,
};

pub const CheckCommand = struct {
    pub fn run(self: CheckCommand, alloc: Allocator) !u8 {
        _ = self;
        //       var positionals: Positionals = .{};

        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        //        try command.parsePositionals(Positionals, alloc, &positionals, args);
        return 0;
        // check [options] [<branch>]
        // options:
        //  -h, --help
    }
};
