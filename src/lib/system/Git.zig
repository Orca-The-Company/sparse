const std = @import("std");
const RunResult = std.process.Child.RunResult;

pub fn getBranchRefs(options: struct {
    allocator: std.mem.Allocator,
    withHead: bool = true,
}) !RunResult {
    return try @"show-ref"(.{
        .allocator = options.allocator,
        .args = &.{ "--branches", (if (options.withHead) "--head" else "") },
    });
}

/// git rev-parse --symbolic-full-name --glob="refs/sparse/*"
pub fn getSparseRefs(o: struct {
    allocator: std.mem.Allocator,
}) !std.ArrayListUnmanaged([]const u8) {
    const refs_result = try @"show-ref"(.{
        .allocator = o.allocator,
    });
    defer o.allocator.free(refs_result.stdout);
    defer o.allocator.free(refs_result.stderr);

    if (refs_result.term.Exited == 0) {
        var lines = std.mem.splitScalar(u8, refs_result.stdout, '\n');
        var refs = try std.ArrayListUnmanaged([]const u8).initCapacity(o.allocator, lines.rest().len);
        while (lines.next()) |l| {
            const line = utils.trimString(l, .{});
            if (std.mem.count(u8, line, "refs/sparse") > 0) {
                const new_line = try o.allocator.dupe(u8, line);
                try refs.append(o.allocator, new_line);
            }
        }
        return refs;
    }
    return SparseError.BACKEND_UNABLE_TO_GET_REFS;
}

pub fn @"switch"() void {}
pub fn branch(options: struct {
    allocator: std.mem.Allocator,
}) !RunResult {
    const run_result: RunResult = try std.process.Child.run(.{
        .allocator = options.allocator,
        .argv = &.{ "git", "branch", "-vva" },
    });
    return run_result;
}

fn @"show-ref"(options: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8 = &.{},
}) !RunResult {
    const command: []const []const u8 = &.{
        "git",
        "show-ref",
    };

    const argv = try utils.combine([]const u8, options.allocator, command, options.args);
    defer options.allocator.free(argv);

    const run_result: RunResult = try std.process.Child.run(.{
        .allocator = options.allocator,
        .argv = argv,
    });
    return run_result;
}

fn @"rev-parse"(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
}) !RunResult {
    const command: []const []const u8 = &.{
        "git",
        "rev-parse",
    };
    const argv = try utils.combine([]const u8, o.allocator, command, o.args);
    defer o.allocator.free(argv);
    std.debug.print("running {s} ...\n", .{argv});

    return try std.process.Child.run(.{
        .allocator = o.allocator,
        .argv = argv,
    });
}

const utils = @import("../utils.zig");
const SparseError = @import("../sparse.zig").Error;
