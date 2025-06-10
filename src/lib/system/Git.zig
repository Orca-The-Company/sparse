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
    defer options.allocator.free(run_result.stderr);
    defer options.allocator.free(run_result.stdout);
    std.debug.print("Return Signal: {any}", .{run_result.term});
    std.debug.print("Output:\n{s}", .{run_result.stdout});
}
