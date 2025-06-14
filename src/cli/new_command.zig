const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(.new_command);

pub const Options = struct {
    @"--orphan": ?bool = false,
    @"--bele": ?i12 = 10,
    @"--test": ?bool = false,
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
    _options: struct {
        @"--to": []const u8 = "main",
        @"--hello": bool = false,
        @"--from": []const u8 = "bla",
    } = .{},
};

pub const NewCommand = struct {

    // sparse new [options] [<branch> [--target:-main>]]
    // options:
    //  -h, --help
    pub fn run(self: NewCommand, alloc: Allocator) !u8 {
        _ = self;
        var positionals: Positionals = .{};
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        const cli_positionals = try command.parseOptions(@TypeOf(positionals._options), alloc, &positionals._options, args);
        defer alloc.free(cli_positionals);
        try command.parsePositionals(Positionals, alloc, &positionals, cli_positionals);
        //if (positionals.advanced) |details| {
        //    std.debug.print("{s} {s}\n", .{ details.branch[0], details.target.?[0] });
        //}
        std.debug.print("branch {s}\n", .{positionals.advanced.?.branch});
        std.debug.print("target {s}\n", .{positionals.advanced.?.target.?});
        std.debug.print("options {s}\n", .{positionals._options.@"--to"});
        std.debug.print("options {any}\n", .{positionals._options.@"--hello"});
        std.debug.print("options {s}\n", .{positionals._options.@"--from"});

        return 0;
    }
};
