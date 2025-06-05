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

pub const Positionals = struct {
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
        var positionals: Positionals = .{};
        const options: Options = .{};
        _ = options;

        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        var cli_struct = try command.splitArgs(alloc, args);
        defer cli_struct.@"0".deinit(alloc);
        defer cli_struct.@"1".deinit(alloc);

        std.debug.print("{any}", .{cli_struct});

        try command.parsePositionals(Positionals, alloc, &positionals, args);
        if (positionals.advanced) |details| {
            std.debug.print("{s} {s}\n", .{ details.branch[0], details.target.?[0] });
        }
        return 0;
    }
};
