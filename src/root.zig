//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const LibGit = @import("lib/libgit2/libgit2.zig");
const std = @import("std");

pub fn examples() !void {

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
    std.debug.print("ref.nameToID: {s}\n", .{(try LibGit.GitReference.nameToID(repo, "refs/heads/main")).?.str()});

    // Worktrees

    {
        var worktrees: LibGit.GitStrArray = try LibGit.GitWorktree.list(repo);
        std.debug.print("\nWorktrees\n====\n", .{});
        for (worktrees.items(allocator)) |item| {
            std.debug.print("{s}\n", .{item});
        }
        std.debug.print("====\n", .{});
    }
    {
        const worktree: ?LibGit.GitWorktree = LibGit.GitWorktree.lookup(repo, "hotfix") catch err: {
            break :err null;
        };
        if (worktree) |val| {
            defer val.free();
            std.debug.print("worktree.lookup(hotfix): [name={s}, path={s}]\n", .{ val.name(), val.path() });
        } else {
            std.debug.print("worktree.lookup(hotfix): <not_found>\n", .{});
        }
    }
    {
        const worktree: ?LibGit.GitWorktree = LibGit.GitWorktree.lookup(repo, "new_feature") catch err: {
            break :err null;
        };
        if (worktree) |val| {
            defer val.free();
            std.debug.print("worktree.lookup(new_feature): [name={s}, path={s}]\n", .{ val.name(), val.path() });
        } else {
            std.debug.print("worktree.lookup(new_feature): <not_found>\n", .{});
        }
    }
    {
        const worktree: ?LibGit.GitWorktree = LibGit.GitWorktree.lookup(repo, "hotfix") catch err: {
            break :err null;
        };
        if (worktree) |val| {
            defer val.free();
            std.debug.print("\nworktree({s}) locking.. res: {any}\n", .{ val.name(), val.lock("testing bro") });
            std.debug.print("worktree({s}) unlocking.. res: {any}\n", .{ val.name(), val.unlock() });
            std.debug.print("worktree({s}) validating.. res: {any}\n", .{ val.name(), val.validate() });
        }
    }
    const branch: LibGit.GitBranch = try LibGit.GitBranch.lookup(repo, "main", LibGit.GitBranchType.git_branch_all);

    std.debug.print("branch: {s}\n", .{branch.ref.name()});
    std.debug.print("branch_name: {s}\n", .{try branch.name()});

    const revspec: LibGit.GitRevSpec = try LibGit.GitRevSpec.revparse(repo, "origin/git");
    defer revspec.free();

    std.debug.print("revspec.from: {s} revspec.to: {any}\n", .{ revspec.from().?.id().?.str(), revspec.to() });
    // {
    //     const ref: LibGit.GitReference = try LibGit.GitReference.lookup(repo, "refs/heads/main");
    //     defer ref.free();

    //     const direct_ref: LibGit.GitReference = try ref.resolve();
    //     defer direct_ref.free();

    //     std.debug.print("ref: {s}\n", .{ref.name()});
    //     std.debug.print("direct ref: {s}\n", .{direct_ref.target().?.str()});

    //     const add_options = try LibGit.GitWorktreeAddOptions.create(.{
    //         .ref = ref,
    //         .checkout_existing = true,
    //     });
    //     std.debug.print("add_options: {any}\n", .{add_options.value});

    //     const path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ repo.commondir(), "sparse/hotfix" });
    //     defer allocator.free(path);
    //     std.debug.print("path: {s}\n", .{path});

    //     const worktree = try LibGit.GitWorktree.addWithOptions(repo, "hotfix", @ptrCast(path), add_options);
    //     defer worktree.free();
    // }
    // {
    //     var worktrees: LibGit.GitStrArray = try LibGit.GitWorktree.list(repo);
    //     std.debug.print("\nWorktrees\n====\n", .{});
    //     for (worktrees.items(allocator)) |item| {
    //         std.debug.print("{s}\n", .{item});
    //     }
    //     std.debug.print("====\n", .{});
    // }
}

pub fn exampleSparseFunctions() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    // try running tree
    const run_result: std.process.Child.RunResult = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "tree", "./.git/sparse", "-L", "1" },
    });
    defer allocator.free(run_result.stderr);
    defer allocator.free(run_result.stdout);
    std.debug.print("Return Signal: {any}", .{run_result.term});
    std.debug.print("Output:\n{s}", .{run_result.stdout});
    Git.@"switch"();
    const git_branch_result = try Git.branch(.{ .allocator = allocator });
    defer allocator.free(git_branch_result.stderr);
    defer allocator.free(git_branch_result.stdout);
    std.debug.print("Return Signal: {any}", .{git_branch_result.term});
    std.debug.print("Output:\n{s}", .{git_branch_result.stdout});
    try Sparse.feature(.{ .feature = .{ .name = .{"hello_moto"} }, ._options = .{ .@"--to" = .{ .name = .{"dev"} } } });
    try Sparse.slice(.{});
    try Sparse.submit(.{});
}

const Git = @import("lib/system/Git.zig");
const Sparse = @import("lib/sparse.zig");
