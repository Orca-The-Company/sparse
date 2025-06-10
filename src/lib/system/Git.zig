const std = @import("std");
const RunResult = std.process.Child.RunResult;

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
