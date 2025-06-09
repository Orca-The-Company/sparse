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

    //using ref iterator
    var ref_iterator = try LibGit.GitReferenceIterator.create(repo);
    defer ref_iterator.free();
    std.debug.print("Refs Iter\n====\n", .{});
    while (try ref_iterator.next()) |r| {
        std.debug.print("{s}\n", .{r.name()});
    }
    std.debug.print("====\n", .{});

    const glob = "*heads*";
    var ref_glob_iter = try LibGit.GitReferenceIterator.fromGlob(glob, repo);
    defer ref_glob_iter.free();
    std.debug.print("Refs Iter(glob: {s})\n====\n", .{glob});
    while (try ref_glob_iter.next()) |r| {
        std.debug.print("{s}\n", .{r.name()});
    }
    std.debug.print("====\n", .{});

    const name1 = "refs/sparse/hello_moto";
    const name2 = "refs/sparse/*";
    std.debug.print("is_name_valid({s}): {any}\n", .{ name1, LibGit.GitReference.isNameValid(name1) });
    std.debug.print("is_name_valid({s}): {any}\n", .{ name2, LibGit.GitReference.isNameValid(name2) });
    std.debug.print("repo.path: {s}\n", .{repo.path()});
    std.debug.print("repo.commondir: {s}\n", .{repo.commondir()});
    // git worktree add -b test2 .git/sparse/test2 464fea667f9604b9ee40d2b2e1c430ff2780c293
    // ^^ can be used to create a worktree based on an oid
    std.debug.print("ref.target: {any}\n", .{ref.target().?.id()});
    std.debug.print("ref.target: {s}\n", .{ref.target().?.str()});

    std.debug.print("{any} {s} {any} {any}", .{ repo.isEmpty(), repo.path(), repo.state(), ref.value });
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
