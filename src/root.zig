//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const LibGit = @import("lib/libgit2/libgit2.zig");

const std = @import("std");
const testing = std.testing;

pub fn add(a: i32, b: i32) !i32 {
    // var repo: ?*c.git_repository = null;
    // const res: c_int = c.git_repository_open_ext(@ptrCast(&repo), @ptrCast("."), c.GIT_REPOSITORY_OPEN_FROM_ENV, null);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    try LibGit.init();
    defer LibGit.shutdown() catch @panic("Oops something weird is cooking...");
    const repo = try LibGit.GitRepository.open();
    defer repo.free();
    const ref: LibGit.GitReference = try LibGit.GitReference.lookup(repo, "refs/heads/main");
    defer ref.free();

    var refs = try LibGit.GitReference.list(repo);
    defer refs.dispose();
    std.debug.print("Refs\n====\n", .{});
    for (refs.items(allocator)) |item| {
        std.debug.print("{s}\n", .{item});
    }
    std.debug.print("====\n", .{});

    std.debug.print("{any} {s} {any} {any}", .{ repo.isEmpty(), repo.path(), repo.state(), ref.value });
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
