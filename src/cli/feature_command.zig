const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(.feature_command);

const Params = struct {
    feature_name: [1][]u8,
    slice_name: ?[1][]u8 = null,
    _options: struct {
        const Options = @This();
        @"--to": []const u8 = "main",
        @"--help": *const fn () void = Options.help,
        @"-h": *const fn () void = Options.help,

        pub fn help() void {
            std.io.getStdOut().writer().print(
                \\ sparse feature [ options ] <feature_name> [<slice_name>]
                \\ args:
                \\     <feature_name>: name of the feature to be created. If a feature with the
                \\                     same name exists, sparse simply switches to that feature.
                \\     <slice_name>:   name of the first slice in newly created feature. This
                \\                     argument is ignored if the feature already exists.
                \\ options:
                \\     --help: Shows this help message
                \\     --to <base_(feature/branch)>: branch or feature to build on top (default: main)
                \\
            , .{}) catch return;
        }
    } = .{},
};

///
/// sparse feature [ options ] <feature_name> [<slice_name>]
/// args:
///     <feature_name>: name of the feature to be created. If a feature with the
///                     same name exists, sparse simply switches to that feature.
///     <slice_name>:   name of the first slice in newly created feature. This
///                     argument is ignored if the feature already exists.
/// options:
///     --help: Shows this help message
///     --to <base_(feature/branch)>: branch or feature to build on top (default: main)
///
pub const FeatureCommand = struct {
    pub fn run(self: FeatureCommand, alloc: Allocator) !u8 {
        _ = self;
        var params = Params{ .feature_name = undefined };
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);
        log.debug("got cli arguments: {s}", .{args});

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
            "parsed feature command:: feature_name:{s} slice_name:{s} _options.--to:{s}",
            .{
                params.feature_name[0],
                if (params.slice_name) |s| s[0] else "null",
                params._options.@"--to",
            },
        );
        Sparse.feature(
            params.feature_name[0],
            if (params.slice_name) |s| s[0] else null,
            params._options.@"--to",
        ) catch |err| switch (err) {
            else => {
                log.err("error: {any}", .{err});
                return 1;
            },
        };

        return 0;
    }
};

const Sparse = @import("sparse_lib").Sparse;
const command = @import("command.zig");
