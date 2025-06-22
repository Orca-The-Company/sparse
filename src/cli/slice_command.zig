const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(.feature_command);
const help_strings = @import("help_strings");

/// sparse slice [ options ] [<slice_name>]
const Params = struct {
    /// args:
    /// <slice_name>: name of the new slice in feature.
    ///                 If the slice with the same name exists, then sparse switches to that slice.
    ///                 If <slice_name> is not provided, then sparse creates the slice based on the number of slices currently in the feature.
    slice_name: ?[1][]u8,
    ///
    /// options:
    _options: struct {
        const Options = @This();

        /// -h, --help:    shows this help message.
        @"--help": *const fn () void = Options.help,
        @"-h": *const fn () void = Options.help,

        pub fn help() void {
            std.io.getStdOut().writer().print(help_strings.sparse_slice, .{}) catch return;
        }
    } = .{},
};

///
/// sparse slice [ options ] [<slice_name>]
///
pub const SliceCommand = struct {
    pub fn run(self: SliceCommand, alloc: Allocator) !u8 {
        _ = self;
        var params = Params{ .slice_name = undefined };
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
        log.debug(
            "parsed slice command:: slice_name:{s}",
            .{
                params.slice_name[0],
            },
        );

        return 0;
    }
};

const Sparse = @import("sparse_lib").Sparse;
const command = @import("command.zig");
