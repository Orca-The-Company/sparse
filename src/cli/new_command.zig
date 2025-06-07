const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(".new_command");

pub const Options = struct {
    @"--orphan": bool = false,
    @"--bele": usize = 10,
    //fields: []std.builtin.Type.StructField = undefined,
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

//pub const OptionsSex = struct {
//    fields: []const std.builtin.Type.StructField = @typeInfo(Options).@"struct".fields,
//};
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
        comptime var option_fields = command.getFields(Options);
        var positionals: Positionals = .{};
        // TODO: make it var when parseOptions is implemented
        const options: Options = .{};
        _ = options;
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        var cli_options, var cli_positionals = try command.splitArgs(alloc, args, option_fields);
        defer cli_positionals.deinit(alloc);
        defer cli_options.deinit(alloc);

        for (cli_options.items) |item| {
            std.debug.print("item:{s}\n", .{item});
        }
        try command.parsePositionals(Positionals, alloc, &positionals, args);
        if (positionals.advanced) |details| {
            std.debug.print("{s} {s}\n", .{ details.branch[0], details.target.?[0] });
        }
        option_fields = undefined;
        return 0;
    }
};
