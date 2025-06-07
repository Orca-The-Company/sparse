//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const c = @cImport({
    @cInclude("git2.h");
});

const std = @import("std");

pub export fn add(a: i32, b: i32) i32 {
    var repo: ?*c.git_repository = undefined;
    const res: c_int = c.git_repository_open(&repo, null);

    std.debug.print("{any}", .{res});
    return a + b;
}

pub fn exampleSparseFunctions() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    const git_branch_result = try Git.branch(.{ .allocator = allocator });
    defer allocator.free(git_branch_result.stderr);
    defer allocator.free(git_branch_result.stdout);
    std.debug.print("Return Signal: {any}", .{git_branch_result.term});
    std.debug.print("Output:\n{s}", .{git_branch_result.stdout});
    var refs = try Git.getBranchRefs(.{ .allocator = allocator });
    defer refs.free(allocator);
    // try Sparse.feature(.{
    //     .feature = .{ .name = .{"sparse-test"} },
    //     ._options = .{
    //         .@"--to" = "dev",
    //     },
    // });
    try Sparse.slice(.{});
    try Sparse.submit(.{});
}

// test {
//     std.testing.refAllDecls(@This());
// }

const Git = @import("lib/system/Git.zig");
pub const Sparse = @import("lib/sparse.zig");
