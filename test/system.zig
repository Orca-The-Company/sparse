const std = @import("std");
const log = std.log.scoped(.system);
const RunResult = std.process.Child.RunResult;

pub fn git(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    cwd: ?[]const u8 = null,
}) !RunResult {
    const command: []const []const u8 = &.{
        "git",
        "-c",
        "commit.gpgSign=false",
        "-c",
        "log.showSignature=false",
        "-c",
        "init.defaultBranch=main",
    };
    const argv = try combine([]const u8, o.allocator, command, o.args);
    defer o.allocator.free(argv);
    for (argv) |arg| {
        log.debug("git:: args:{s} cwd:{s}", .{
            arg,
            if (o.cwd) |c| c else "null",
        });
    }
    // log.debug(
    //     "git:: args:{any} cwd:{s}",
    //     .{
    //         argv,
    //         if (o.cwd) |c| c else "null",
    //     },
    // );

    return try std.process.Child.run(.{
        .allocator = o.allocator,
        .argv = argv,
        .cwd = o.cwd,
    });
}

pub fn system(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    cwd: ?[]const u8 = null,
}) !RunResult {
    for (o.args) |arg| {
        log.debug("system:: args:{s} cwd:{s}", .{
            arg,
            if (o.cwd) |c| c else "null",
        });
    }
    // log.debug(
    //     "system:: args:{any} cwd:{s}",
    //     .{
    //         o.args,
    //         if (o.cwd) |c| c else "null",
    //     },
    // );

    return try std.process.Child.run(.{
        .allocator = o.allocator,
        .argv = o.args,
        .cwd = o.cwd,
    });
}

pub fn combine(
    comptime T: type,
    allocator: std.mem.Allocator,
    arr1: []const T,
    arr2: []const T,
) ![]T {
    var arr_list: std.ArrayList(T) = try std.ArrayList(T).initCapacity(allocator, arr1.len + arr2.len);

    for (arr1) |item| {
        try arr_list.append(allocator, item);
    }
    for (arr2) |item| {
        try arr_list.append(allocator, item);
    }
    return try arr_list.toOwnedSlice(allocator);
}
