const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(.feature_command);
const help_strings = @import("help_strings");

/// sparse update [ options ] [<slice_name>]
///
/// Update all slices in current feature
const Params = struct {
    /// options:
    _options: struct {
        const Options = @This();

        /// -h, --help:    shows this help message.
        @"--help": *const fn () void = Options.help,
        @"-h": *const fn () void = Options.help,

        pub fn help() void {
            std.io.getStdOut().writer().print(help_strings.sparse_update, .{}) catch return;
        }
    } = .{},
};

///
/// sparse update [ options ]
///
pub const UpdateCommand = struct {
    pub fn run(self: UpdateCommand, alloc: Allocator) !u8 {
        _ = self;
        var params = Params{};
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);
        log.debug("run:: args: {s}", .{args});

        const cli_positionals = command.parseOptions(
            @TypeOf(params._options),
            alloc,
            &params._options,
            args,
        ) catch |err| switch (err) {
            command.Error.OptionHandledAlready => return 0,
            else => return err,
        };

        defer alloc.free(cli_positionals);
        try command.parsePositionals(
            Params,
            alloc,
            &params,
            cli_positionals,
        );
        log.debug("parsed update command:: ", .{});

        return 0;
    }
};

const Sparse = @import("sparse_lib").Sparse;
const command = @import("command.zig");
