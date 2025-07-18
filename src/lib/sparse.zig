const std = @import("std");
const log = std.log.scoped(.sparse);

pub const Error = error{
    BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH,
    BACKEND_UNABLE_TO_GET_REFS,
    UNABLE_TO_SWITCH_BRANCHES,
    UNABLE_TO_PUSH_SLICE,
    CORRUPTED_FEATURE,
    REPARENTING_FAILED,
    UPDATE_REFS_FAILED,
    REBASE_IN_PROGRESS,
    UNABLE_TO_DETECT_CURRENT_FEATURE,
    RECOVERABLE_ORPHAN_SLICES_IN_FEATURE,
    RECOVERABLE_FORKED_SLICES_IN_FEATURE,
};

pub fn feature(
    feature_name: []const u8,
    slice_name: ?[]const u8,
    target: []const u8,
) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    try LibGit.init();
    defer LibGit.shutdown() catch @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");

    log.debug("feature:: feature_name:{s} slice_name:{s} target:{s}", .{
        feature_name,
        if (slice_name) |s| s else "null",
        target,
    });

    const _slice = if (slice_name) |s| s else constants.LAST_SLICE_NAME_POINTER;

    // once sparse branchinde olup olmadigimizi kontrol edelim
    // git show-ref --branches --head # butun branchleri ve suan ki HEAD i gormemizi
    // sagliyor
    var maybe_active_feature = try Feature.activeFeature(.{
        .alloc = allocator,
    });
    defer {
        if (maybe_active_feature) |*f| {
            f.free(allocator);
        }
    }

    var maybe_existing_feature = try Feature.findFeatureByName(.{
        .alloc = allocator,
        .feature_name = feature_name,
    });
    defer {
        if (maybe_existing_feature) |*f| {
            f.free(allocator);
        }
    }

    if (maybe_active_feature) |*active_feature| {
        log.debug(
            "feature:: active_feature:name={s}",
            .{
                active_feature.name,
            },
        );

        // I am already an active sparse feature and I want to go to a feature
        // right so lets check if it is necessary
        if (maybe_existing_feature) |*feature_to_go| {
            log.debug(
                "feature:: feature_to_go:name={s}",
                .{
                    feature_to_go.name,
                },
            );

            if (std.mem.eql(u8, feature_to_go.ref_name, active_feature.ref_name)) {
                // returning no need to do anything fancy
                log.info("feature:: already in same feature({s})", .{active_feature.name});
                return;
            } else {
                return try jump(.{
                    .allocator = allocator,
                    .from = active_feature.*,
                    .to = feature_to_go,
                    .slice = _slice,
                });
            }
        } else {
            var to = try Feature.new(.{
                .alloc = allocator,
                .name = feature_name,
            });
            defer to.free(allocator);
            return try jump(.{
                .allocator = allocator,
                .from = active_feature.*,
                .to = &to,
                .create = true,
                .slice = _slice,
                .start_point = target,
            });
        }
    } else {
        if (maybe_existing_feature) |*feature_to_go| {
            return try jump(.{
                .allocator = allocator,
                .to = feature_to_go,
                .slice = _slice,
            });
        } else {
            var to = try Feature.new(.{
                .alloc = allocator,
                .name = feature_name,
            });
            defer to.free(allocator);
            return try jump(.{
                .allocator = allocator,
                .to = &to,
                .create = true,
                .slice = _slice,
                .start_point = target,
            });
        }
    }
}

pub fn slice(o: struct { slice_name: ?[]const u8 }) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    try LibGit.init();
    defer LibGit.shutdown() catch @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");

    var current_feature = try Feature.activeFeature(.{ .alloc = allocator });
    defer {
        if (current_feature) |*f| f.free(allocator);
    }
    if (current_feature) |*cf| {
        if (cf.slices) |slices| {
            if (slices.items.len == 0) {
                log.warn("slice:: current_feature('{s}') doesnt have any slices, this is unexpected will try to create a slice anyways", .{current_feature.?.name});
            }
            const leaves = try Slice.leafNodes(.{ .alloc = allocator, .slice_pool = slices.items });
            defer allocator.free(leaves);
            if (leaves.len > 1) {
                log.err("slice:: current_feature('{s}') has more than 1 orphan slices", .{current_feature.?.name});
                return Error.RECOVERABLE_ORPHAN_SLICES_IN_FEATURE;
            }
            var start_point: ?[]const u8 = null;
            if (leaves.len == 0) {
                start_point = null;
            } else {
                // converting refname to branch name will be handled by jump command
                start_point = leaves[0].ref.name()["refs/heads/".len..];
            }

            var create = true;
            var slice_name: []const u8 = undefined;
            if (o.slice_name) |s| {
                slice_name = s;
                for (slices.items) |_s| {
                    if (std.mem.eql(u8, _s.name(), slice_name)) {
                        create = false;
                        break;
                    }
                }
            } else {
                slice_name = constants.LAST_SLICE_NAME_POINTER;
            }

            try jump(.{
                .allocator = allocator,
                .to = cf,
                .create = create,
                .slice = slice_name,
                .start_point = start_point,
            });
        } else {
            log.warn("slice:: current_feature('{s}') doesnt have any slices, this is unexpected will try to create a slice anyways", .{current_feature.?.name});
        }
    } else {
        log.err("slice:: couldn't find current feature, cannot execute slice commands outside of a feature, make sure you have commits in the repository", .{});
        return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
    }
}

/// Gets the active feature and its target, then checks for merged slices.
/// Finds the first unmerged slice searching from bottom to top. Then re-parents
/// it to the up-to-date target. Then updates all unmerged slices in the feature.
///
/// This function ensures that all unmerged slices are properly updated to the latest
/// target, ensuring a clean and consistent state within the feature.
pub fn update(o: struct {
    alloc: std.mem.Allocator,
    @"continue": bool = false,
}) !void {
    try LibGit.init();
    defer LibGit.shutdown() catch @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");
    const repo = try LibGit.GitRepository.open();
    defer repo.free();

    var state = try State.Update.load(o.alloc, repo);
    defer state.free(o.alloc);
    // Check if a rebase is in progress
    const is_rebase_in_progress = try Git.isRebaseInProgress(o.alloc, repo);
    if (is_rebase_in_progress) {
        log.err("update:: rebase in progress", .{});
        // TODO: print an informative message about the rebase in progress and
        // suggest user to fix the conflicts and run `git rebase --continue`
        // once it is done run `sparse update --continue`
        return Error.REBASE_IN_PROGRESS;
    } else {
        var current_feature = try Feature.activeFeature(.{ .alloc = o.alloc });
        defer {
            if (current_feature) |*f| f.free(o.alloc);
        }
        if (current_feature) |*cf| {
            // clean up the state
            try updateGoodWeather(.{ .alloc = o.alloc, .feature = cf, .state = &state });
        } else {
            if (!o.@"continue") {
                log.err("update:: not able to detect current branch", .{});
                return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
            }
            if (!state.inProgress()) {
                // TODO: return error indicating that there is no update in progress
                // so we cannot continue
                try state.delete();
                return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
            }
            log.err("update:: already in progress", .{});
            try handleUpdateInProgress(o.alloc, &state);
        }
    }
}

pub fn submit(opts: struct {}) !void {
    _ = opts;
    std.debug.print("\n===sparse-submit===\n\n", .{});
    std.debug.print("\n====================\n", .{});
}

fn updateRefs(o: struct {
    alloc: std.mem.Allocator,
    target_ref: GitReference,
}) !void {
    const rr_rebase = try Git.rebase(
        .{
            .allocator = o.alloc,
            .args = &.{
                o.target_ref.name(),
                "--update-refs",
            },
        },
    );
    defer o.alloc.free(rr_rebase.stdout);
    defer o.alloc.free(rr_rebase.stderr);
    log.debug("update:: rebase stdout: {s}", .{rr_rebase.stdout});
    if (rr_rebase.term.Exited != 0) {
        log.debug("update:: rebase stderr: {s}", .{rr_rebase.stderr});
        log.err(
            "update:: rebase failed with exit code {d}",
            .{rr_rebase.term.Exited},
        );
        return Error.UPDATE_REFS_FAILED;
    }
}

fn reparent(o: struct {
    alloc: std.mem.Allocator,
    tip_slice: *const Slice,
    new_parent: GitReference,
    old_parent: []const u8,
    branch_to_move: GitReference,
}) !void {
    // TODO: check if old_parent and new_parent are the same if so no need to re-parent
    const rr_rebase = try Git.rebase(.{
        .allocator = o.alloc,
        .args = &[_][]const u8{
            "-r",
            "--onto",
            o.new_parent.name(),
            o.old_parent,
            o.branch_to_move.name(),
            "--update-refs",
        },
    });
    defer o.alloc.free(rr_rebase.stderr);
    defer o.alloc.free(rr_rebase.stdout);
    log.debug("update:: rebase stdout: {s}", .{rr_rebase.stdout});
    log.debug("update:: rebase stderr: {s}", .{rr_rebase.stderr});
    if (rr_rebase.term.Exited != 0) {
        log.err(
            "update:: rebase failed during re-parenting with exit code {d}",
            .{rr_rebase.term.Exited},
        );
        // TODO: let user know what to do next
        return Error.REPARENTING_FAILED;
    }
    // do switching to tip no matter what
    {
        const rr_switch = try Git.@"switch"(.{
            .allocator = o.alloc,
            .args = &.{
                "-C",
                try o.tip_slice.ref.branchName(),
            },
        });
        defer o.alloc.free(rr_switch.stdout);
        defer o.alloc.free(rr_switch.stderr);
        if (rr_switch.term.Exited != 0) {
            log.debug("update:: switch stderr: {s}", .{rr_switch.stderr});
            log.err(
                "update:: switch failed with exit code {d}",
                .{rr_switch.term.Exited},
            );
            return Error.REPARENTING_FAILED;
        }
    }
}

fn updateGoodWeather(o: struct {
    alloc: std.mem.Allocator,
    feature: *Feature,
    state: *State.Update,
}) !void {
    // TODO: run git fetch to update remote branches
    const target = try o.feature.target(o.alloc);
    o.state.free(o.alloc);
    o.state._data.feature = try o.alloc.dupe(u8, o.feature.name);
    o.state._data.target = if (target) |t| try o.alloc.dupe(u8, t.name()) else null;
    o.state._data.last_operation = .Analyze;
    try o.state.save();
    log.debug("update:: current_feature.name:{s} current_feature.target:{s} current_feature.ref_name:{s}", .{
        o.feature.name,
        if (target) |t| t.name() else "null",
        o.feature.ref_name,
    });
    const leaves = try Slice.leafNodes(.{
        .alloc = o.alloc,
        .slice_pool = o.feature.slices.?.items,
    });
    defer o.alloc.free(leaves);
    var ss: ?*Slice = leaves[0];
    const upstream = try target.?.upstream(ss.?.repo);
    defer upstream.free();

    // TODO: double check if is merged working as expected for rebased changes
    var last_unmerged = res: {
        if (ss) |s| {
            if (try s.isMerged(.{ .alloc = o.alloc, .into = upstream })) {
                break :res null;
            } else {
                break :res s;
            }
        } else {
            break :res null;
        }
    };
    while (ss != null) : (ss = ss.?.target) {
        const is_merged = try ss.?.isMerged(.{
            .alloc = o.alloc,
            .into = upstream,
        });
        if (!is_merged) {
            last_unmerged = ss;
        } else break;
    }
    if (last_unmerged) |lu| {
        log.debug("update:: last_unmerged:{s}", .{lu.ref.name()});
        // re-parent last_unmerged to target
        // rebase all slices from tip to target
        // git rebase --onto <new-parent> <old-parent> <branch-to-move>
        const old_parent = res: {
            if (lu.ref.createdFrom(lu.repo)) |op_ref| {
                break :res op_ref.name();
            } else {
                if (target) |t| {
                    break :res t.name();
                } else {
                    // TODO: Handle the case when target is null
                    // At least fall back to default target for sparse in
                    // git config, maybe something like `sparse.default.target`
                    break :res "main";
                }
            }
        };
        log.debug("update:: old_parent:{s}", .{old_parent});

        // save state of the sparse update we need this information
        // in case there is a conflict or error during the rebase process
        // so that we can resume the update from where it left off
        o.state._data.last_operation = .Reparent;
        o.state._data.last_unmerged_slice = try o.alloc.dupe(u8, lu.ref.name());
        o.state._data.old_parent = try o.alloc.dupe(u8, old_parent);
        try o.state.save();

        try reparent(.{
            .alloc = o.alloc,
            .tip_slice = leaves[0],
            .old_parent = old_parent,
            .new_parent = upstream,
            .branch_to_move = lu.ref,
        });
        //try jump(.{ .allocator = o.alloc, .to = o.feature });
        try updateRefs(.{ .alloc = o.alloc, .target_ref = lu.ref });
        // push all unmerged slices in remotes
        ss = leaves[0];
        while (ss != null) : (ss = ss.?.target) {
            const is_merged = try ss.?.isMerged(.{
                .alloc = o.alloc,
                .into = upstream,
            });
            if (!is_merged) {
                try ss.?.activate(o.alloc);
                try ss.?.push(o.alloc);
            } else break;
        }
        try jump(.{ .allocator = o.alloc, .to = o.feature });
        try o.state.delete();

        // TODO: cleanup merged slices, loop forward since last_unmerged
        // is the last unmerged slice
        // var current = lu;
        // while (current != null) : (current = current.?.target) {
        //     if (current.?.isMerged(.{
        //         .alloc = o.alloc,
        //         .into = try target.?.upstream(current.?.repo),
        //     })) {
        //         current.?.cleanupMergedSlices(o.alloc);
        //     }
        // }
    } else {
        log.debug("update:: no unmerged slices", .{});
        try o.state.delete();
    }
}

fn handleUpdateInProgress(alloc: std.mem.Allocator, state: *State.Update) !void {
    var feature_updated = try Feature.findFeatureByName(.{
        .alloc = alloc,
        .feature_name = state._data.feature.?,
    });
    defer {
        if (feature_updated) |*f| f.free(alloc);
    }
    switch (state._data.last_operation) {
        .Create, .Analyze => {
            log.debug("update:: failed when create or analyze command is called before, retrying..", .{});
            if (feature_updated) |*f| {
                try jump(.{
                    .allocator = alloc,
                    .to = f,
                });
                try updateGoodWeather(.{ .alloc = alloc, .feature = f, .state = state });
            } else {
                return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
            }
            return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
        },
        .Reparent => {
            log.debug("update:: failed when reparent command is called before", .{});
            if (feature_updated) |*f| {
                var lu: ?Slice = null;
                for (f.slices.?.items) |s| {
                    if (std.mem.eql(
                        u8,
                        s.ref.name(),
                        state._data.last_unmerged_slice.?,
                    )) {
                        lu = s;
                    }
                }
                try jump(.{ .allocator = alloc, .to = f });
                try updateRefs(.{ .alloc = alloc, .target_ref = lu.?.ref });
                const leaves = try Slice.leafNodes(.{
                    .alloc = alloc,
                    .slice_pool = f.slices.?.items,
                });
                defer alloc.free(leaves);
                var ss: ?*Slice = leaves[0];
                var target = try GitReference.lookup(ss.?.repo, state._data.target.?);
                defer target.free();
                const upstream = try target.upstream(ss.?.repo);
                defer upstream.free();
                while (ss != null) : (ss = ss.?.target) {
                    const is_merged = try ss.?.isMerged(.{
                        .alloc = alloc,
                        .into = upstream,
                    });
                    if (!is_merged) {
                        try ss.?.activate(alloc);
                        try ss.?.push(alloc);
                    } else break;
                }
                try jump(.{ .allocator = alloc, .to = f });
                try state.delete();
            }
        },
        .Complete => {
            log.debug("update:: failed when complete command is called before, no need to continue updating", .{});
            try state.delete();
        },
    }
}

fn jump(o: struct {
    allocator: std.mem.Allocator,
    from: ?Feature = null,
    to: *Feature,
    create: bool = false,
    slice: []const u8 = constants.LAST_SLICE_NAME_POINTER,
    start_point: ?[]const u8 = null,
}) !void {
    log.debug(
        "jump:: from:{s} to.name:{s} to.ref_name:{s} slice:{s} start_point:{s} create:{any}",
        .{
            if (o.from) |f| f.name else "null",
            o.to.name,
            o.to.ref_name,
            o.slice,
            if (o.start_point) |s| s else "null",
            o.create,
        },
    );
    try LibGit.init();
    defer LibGit.shutdown() catch {
        @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");
    };
    const repo = try LibGit.GitRepository.open();
    defer repo.free();

    // TODO: handle gracefully saving things for current feature (`from`)
    // TODO: test if it is possible to use start_point as remote branch

    var result_start_point: ?[]const u8 = o.start_point;
    if (o.start_point) |start_point| {
        // check if start_point of `to` is valid
        const branch = GitBranch.lookup(
            repo,
            start_point,
            GitBranchType.git_branch_all,
        ) catch |err| res: {
            switch (err) {
                LibGit.GitError.GIT_ENOTFOUND => {
                    result_start_point = null;
                    break :res GitBranch{ ._ref = .{} };
                },
                else => return err,
            }
        };
        defer branch.free();
    }

    try o.to.activate(.{
        .allocator = o.allocator,
        .create = o.create,
        .slice_name = o.slice,
        .start_point = result_start_point,
    });
}

test {
    std.testing.refAllDecls(@This());
}

const constants = @import("constants.zig");
const LibGit = @import("libgit2/libgit2.zig");
const GitString = LibGit.GitString;
const GitBranch = LibGit.GitBranch;
const GitReference = LibGit.GitReference;
const GitBranchType = LibGit.GitBranchType;
const Git = @import("system/Git.zig");
const Feature = @import("Feature.zig");
const Slice = @import("slice.zig").Slice;
const State = @import("state.zig");
const Utils = @import("utils.zig");
