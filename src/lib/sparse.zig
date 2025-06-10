const std = @import("std");

const Feature = struct {
    name: [1]GitString,
};

const Slice = struct {
    name: [1]GitString,
};

pub fn feature(args: struct {
    feature: Feature,
    slice: ?Slice = null,
    _options: ?struct {
        @"--to": ?Feature = .{ .name = .{"main"} },
    } = .{},
}) !void {
    std.debug.print("\n===sparse-feature===\n\n", .{});
    std.debug.print("opts: feature:name:{s} slice:{any} --to:{s}\n", .{ args.feature.name, args.slice, args._options.?.@"--to".?.name });
    std.debug.print("\n====================\n", .{});
}

pub fn slice(opts: struct {}) !void {
    _ = opts;
    std.debug.print("\n===sparse-slice===\n\n", .{});
    std.debug.print("\n====================\n", .{});
}

pub fn submit(opts: struct {}) !void {
    _ = opts;
    std.debug.print("\n===sparse-submit===\n\n", .{});
    std.debug.print("\n====================\n", .{});
}

const GitString = @import("libgit2/types.zig").GitString;
