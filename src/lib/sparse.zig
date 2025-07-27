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
    NO_UPDATE_IN_PROGRESS,
    UNABLE_TO_DETECT_CURRENT_FEATURE,
    RECOVERABLE_ORPHAN_SLICES_IN_FEATURE,
    RECOVERABLE_FORKED_SLICES_IN_FEATURE,
    // TODO: Add error types for git notes operations to preserve slice relationships
    // These errors should handle failures in git notes operations without breaking core functionality:
    // NOTES_CREATE_FAILED,          // Failed to create git note for slice parent relationship
    // NOTES_READ_FAILED,            // Failed to read git note for slice parent information
    // NOTES_PUSH_FAILED,            // Failed to push git notes to remote repository
    // NOTES_FETCH_FAILED,           // Failed to fetch git notes from remote repository
    // NOTES_PARSE_FAILED,           // Failed to parse slice parent information from git note
    // NOTES_SYNC_CONFLICT,          // Conflict between local and remote git notes
    // NOTES_RELATIONSHIP_MISMATCH,  // Mismatch between reflog and notes-based relationships
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
    // TODO: Add git notes support when creating new slices
    // When a new slice is created, automatically add a git note to preserve the parent relationship
    // This will ensure slice relationships survive rebasing/squashing operations
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
    // TODO: Consider preserving git notes during update operations
    // If update involves rebasing/squashing, ensure slice parent notes are preserved
    // and updated to reflect new commit IDs after the update
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
        const stdout = std.io.getStdOut().writer();
        try stdout.print("⚠️  A rebase is currently in progress.\n", .{});
        try stdout.print("Please resolve any conflicts and run:\n", .{});
        try stdout.print("  git rebase --continue\n", .{});
        try stdout.print("Then run:\n", .{});
        try stdout.print("  sparse update --continue\n", .{});
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
                const stdout = std.io.getStdOut().writer();
                try stdout.print("❌ Unable to detect current sparse feature.\n", .{});
                try stdout.print("Make sure you're on a sparse feature branch before running update.\n", .{});
                return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
            }
            if (!state.inProgress()) {
                try state.delete();
                const stdout = std.io.getStdOut().writer();
                try stdout.print("❌ No update in progress to continue.\n", .{});
                try stdout.print("Run 'sparse update' without --continue to start a new update.\n", .{});
                return Error.NO_UPDATE_IN_PROGRESS;
            }
            log.err("update:: already in progress", .{});
            try handleUpdateInProgress(o.alloc, &state);
        }
    }
}

/// Displays comprehensive status information for the currently active sparse feature.
///
/// This function provides a detailed overview of the current feature's state, including:
/// - Active feature identification
/// - Slice structure analysis (orphan and forked slice counts)
/// - Visual slice relationship graph
/// - Individual slice merge status against the target branch
///
/// ## Behavior
/// 1. Checks for an active sparse feature using `Feature.activeFeature()`
/// 2. If no active feature exists, displays "No active feature" and returns
/// 3. For active features, performs structural analysis via `Slice.constructLinks()`
/// 4. Displays warnings if slice structure is non-ideal (orphan_count != 1 or forked_count != 0)
/// 5. Shows the feature's target branch using `Feature.target()`
/// 6. Renders a visual graph of slice relationships via `Slice.printSliceGraph()`
/// 7. Lists merge status of each slice against the target using `Slice.isMerged()`
///
/// ## Ideal Feature Structure
/// - Exactly 1 orphan slice (root of the feature)
/// - 0 forked slices (no branching within the feature)
///
/// ## Output
/// All user-facing information is written to stdout for proper shell integration.
/// Debug information is logged using the sparse logger.
///
/// ## Memory Management
/// All allocations are properly managed with defer statements. The function is safe
/// against memory leaks even in error conditions.
///
/// ## Errors
/// Returns error if Git operations fail or if LibGit2 initialization fails.
pub fn status(o: struct {
    alloc: std.mem.Allocator,
}) !void {
    // TODO: Enhance status command to show slice relationships from git notes
    // Current implementation relies on reflog which is unreliable after rebasing/squashing.
    // Should display:
    // 1. Current slice and its parent (from git notes if available)
    // 2. Full dependency chain using notes-based analysis
    // 3. Warning if reflog and notes show different relationships
    // 4. Instructions for pushing/fetching notes for team collaboration
    try LibGit.init();
    defer LibGit.shutdown() catch @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");

    const stdout = std.io.getStdOut().writer();
    log.debug("status:: checking for active feature", .{});

    // Check if we are currently on an active feature
    const active_feature = try Feature.activeFeature(.{ .alloc = o.alloc });

    if (active_feature == null) {
        try stdout.print("\n🚫 \x1b[33mNo active sparse feature detected\x1b[0m\n", .{});
        try stdout.print("   Use `sparse feature <name>` to create or switch to a feature\n\n", .{});
        return;
    }

    var current_feature = active_feature.?;
    defer current_feature.free(o.alloc);

    log.debug("status:: found active feature: {s}", .{current_feature.name});
    try stdout.print("\n┌─ \x1b[1;36mSparse Feature Status\x1b[0m\n", .{});
    try stdout.print("│\n", .{});
    try stdout.print("├─ 🎯 \x1b[1;32mActive Feature:\x1b[0m \x1b[1m{s}\x1b[0m\n", .{current_feature.name});

    // Check if we have slices
    if (current_feature.slices == null) {
        try stdout.print("│\n", .{});
        try stdout.print("└─ \x1b[33m⚠ Feature has no slices\x1b[0m\n\n", .{});
        return;
    }

    const slices = current_feature.slices.?.items;

    // Do sanity checks for orphan and forked slices using constructLinks
    // This function analyzes the slice relationships and returns counts
    const orphan_count, const forked_count = try Slice.constructLinks(o.alloc, slices);

    log.debug("status:: slice analysis - orphan_count: {d}, forked_count: {d}", .{ orphan_count, forked_count });
    try stdout.print("│\n", .{});
    try stdout.print("├─ 📊 \x1b[1;34mSlice Analysis:\x1b[0m\n", .{});

    const orphan_status = if (orphan_count == 1) "\x1b[32m✓\x1b[0m" else "\x1b[33m⚠\x1b[0m";
    const forked_status = if (forked_count == 0) "\x1b[32m✓\x1b[0m" else "\x1b[31m✗\x1b[0m";

    try stdout.print("│  {s} Orphan slices: \x1b[1m{d}\x1b[0m \x1b[2m(ideal: 1)\x1b[0m\n", .{ orphan_status, orphan_count });
    try stdout.print("│  {s} Forked slices: \x1b[1m{d}\x1b[0m \x1b[2m(ideal: 0)\x1b[0m\n", .{ forked_status, forked_count });

    // Warn if we don't have the ideal slice structure
    if (orphan_count != 1) {
        log.warn("status:: unexpected orphan slice count: {d}", .{orphan_count});
        try stdout.print("│  \x1b[33m⚠ Warning:\x1b[0m Expected exactly 1 orphan slice, found \x1b[1m{d}\x1b[0m\n", .{orphan_count});
    }
    if (forked_count != 0) {
        log.warn("status:: unexpected forked slice count: {d}", .{forked_count});
        try stdout.print("│  \x1b[33m⚠ Warning:\x1b[0m Expected 0 forked slices, found \x1b[1m{d}\x1b[0m\n", .{forked_count});
    }

    // Get the target of the feature
    const target_ref = try current_feature.target(o.alloc);
    if (target_ref) |target| {
        defer target.free();
        try fetchTarget(.{ .alloc = o.alloc, .target = target });

        log.debug("status:: feature target: {s}", .{target.name()});
        try stdout.print("│\n", .{});
        const clean_target_name = if (std.mem.startsWith(u8, target.name(), "refs/heads/"))
            target.name()["refs/heads/".len..]
        else
            target.name();
        try stdout.print("├─ 🎯 \x1b[1;35mTarget Branch:\x1b[0m \x1b[1m{s}\x1b[0m\n", .{clean_target_name});

        // Print slice graph showing the relationship between slices
        try stdout.print("│\n", .{});
        try stdout.print("├─ 🌳 \x1b[1;36mSlice Graph:\x1b[0m\n", .{});
        try stdout.print("│\n", .{});
        try Slice.printSliceGraph(stdout, slices);

        // List merge status of each slice in the feature
        try stdout.print("│\n", .{});
        try stdout.print("├─ 🔄 \x1b[1;34mMerge Status:\x1b[0m\n", .{});
        for (slices) |*slice_item| {
            const is_merged = try slice_item.isMerged(.{ .alloc = o.alloc, .into = target });
            const status_symbol = if (is_merged) "\x1b[32m✓\x1b[0m" else "\x1b[31m✗\x1b[0m";
            const status_text = if (is_merged) "\x1b[32mmerged\x1b[0m" else "\x1b[31mnot merged\x1b[0m";
            log.debug("status:: slice {s} merge status: {}", .{ slice_item.name(), is_merged });
            try stdout.print("│  {s} \x1b[1m{s}:\x1b[0m {s}\n", .{ status_symbol, slice_item.name(), status_text });
        }

        // Display git notes information
        try stdout.print("│\n", .{});
        try stdout.print("├─ 📝 \x1b[1;36mGit Notes Status:\x1b[0m\n", .{});
        try displayGitNotesInfo(o.alloc, stdout, slices);

        // Add summary statistics
        const total_slices = slices.len;
        const merged_count = blk: {
            var count: usize = 0;
            for (slices) |*slice_item| {
                const is_merged = slice_item.isMerged(.{ .alloc = o.alloc, .into = target }) catch false;
                if (is_merged) count += 1;
            }
            break :blk count;
        };

        try stdout.print("│\n", .{});
        try stdout.print("├─ 📈 \x1b[1;34mSummary:\x1b[0m\n", .{});
        try stdout.print("│  📊 Total slices: \x1b[1m{d}\x1b[0m\n", .{total_slices});
        try stdout.print("│  ✅ Merged: \x1b[1;32m{d}\x1b[0m / \x1b[1m{d}\x1b[0m\n", .{ merged_count, total_slices });
        try stdout.print("│  🔄 Pending: \x1b[1;33m{d}\x1b[0m\n", .{total_slices - merged_count});
    } else {
        log.debug("status:: feature has no target", .{});
        try stdout.print("│\n", .{});
        try stdout.print("├─ \x1b[33m⚠ Feature has no target branch\x1b[0m\n", .{});

        // Still print slice graph even without target
        try stdout.print("│\n", .{});
        try stdout.print("├─ 🌳 \x1b[1;36mSlice Graph:\x1b[0m\n", .{});
        try stdout.print("│\n", .{});
        try Slice.printSliceGraph(stdout, slices);

        try stdout.print("│\n", .{});
        try stdout.print("├─ 📈 \x1b[1;34mSummary:\x1b[0m\n", .{});
        try stdout.print("│  📊 Total slices: \x1b[1m{d}\x1b[0m\n", .{slices.len});
        try stdout.print("│\n", .{});
        try stdout.print("└─ \x1b[2mℹ Note: Cannot check merge status without a target reference\x1b[0m\n\n", .{});
        return;
    }

    // Close the status box
    try stdout.print("│\n", .{});
    try stdout.print("└─ \x1b[2m✨ Status complete\x1b[0m\n\n", .{});
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

fn fetchTarget(o: struct {
    alloc: std.mem.Allocator,
    target: GitReference,
}) !void {
    const target_branch = try o.target.branchName();
    const target_branch_refspec = try std.fmt.allocPrint(o.alloc, "{s}:{s}", .{ target_branch, target_branch });
    defer o.alloc.free(target_branch_refspec);
    const rr_fetch = try Git.fetch(.{
        .allocator = o.alloc,
        .args = &.{
            // TODO: get the remote from config
            "origin",
            target_branch_refspec,
        },
    });
    defer o.alloc.free(rr_fetch.stderr);
    defer o.alloc.free(rr_fetch.stdout);
}

fn updateGoodWeather(o: struct {
    alloc: std.mem.Allocator,
    feature: *Feature,
    state: *State.Update,
}) !void {
    const target = try o.feature.target(o.alloc);
    o.state.free(o.alloc);

    // Print update information
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Updating feature '{s}' from target '{s}'\n", .{ o.feature.name, target.?.name() });

    try fetchTarget(.{ .alloc = o.alloc, .target = target.? });
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

        // Show what commits will be updated
        try stdout.print("Found unmerged changes. Showing commits to be updated:\n\n", .{});

        // Get the range of commits to show: upstream..tip_of_feature
        const tip_slice_name = leaves[0].ref.name();
        const upstream_name = upstream.name();

        // Build the git log command to show commits
        const log_range = try std.fmt.allocPrint(o.alloc, "{s}..{s}", .{ upstream_name, tip_slice_name });
        defer o.alloc.free(log_range);

        const log_result = Git.log(.{
            .allocator = o.alloc,
            .args = &.{ "--oneline", "--decorate", "--graph", log_range },
        }) catch |err| {
            try stdout.print("Unable to show commit log: {}\n", .{err});
            return err;
        };
        defer o.alloc.free(log_result.stdout);
        defer o.alloc.free(log_result.stderr);

        if (log_result.stdout.len > 0) {
            try stdout.print("{s}\n", .{log_result.stdout});
        } else {
            try stdout.print("No commits to show in range {s}\n\n", .{log_range});
        }

        try stdout.print("Rebasing unmerged slices onto updated target...\n", .{});

        // save state of the sparse update we need this information
        // in case there is a conflict or error during the rebase process
        // so that we can resume the update from where it left off
        o.state._data.last_operation = .Reparent;
        o.state._data.last_unmerged_slice = try o.alloc.dupe(u8, lu.ref.name());
        try o.state.save();

        // jump to tip
        try jump(.{ .allocator = o.alloc, .to = o.feature });
        try updateRefs(.{ .alloc = o.alloc, .target_ref = target.? });

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

        // Show success message
        try stdout.print("✓ Successfully updated feature '{s}' - all slices rebased and pushed\n", .{o.feature.name});

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
        try stdout.print("✓ Feature '{s}' is already up to date - no changes needed\n", .{o.feature.name});
        try o.state.delete();
    }
}

fn handleUpdateInProgress(alloc: std.mem.Allocator, state: *State.Update) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("🔄 Continuing update for feature '{s}'...\n", .{state._data.feature.?});

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
            try stdout.print("Retrying analysis and update...\n", .{});
            if (feature_updated) |*f| {
                try jump(.{
                    .allocator = alloc,
                    .to = f,
                });
                try updateGoodWeather(.{ .alloc = alloc, .feature = f, .state = state });
            } else {
                try stdout.print("❌ Unable to find feature to continue update\n", .{});
                return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
            }
            return Error.UNABLE_TO_DETECT_CURRENT_FEATURE;
        },
        .Reparent => {
            log.debug("update:: failed when reparent command is called before", .{});
            try stdout.print("Continuing to push remaining unmerged slices...\n", .{});
            if (feature_updated) |*f| {
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
                try stdout.print("✓ Successfully completed update for feature '{s}'\n", .{f.name});
            } else {
                try stdout.print("❌ Unable to find feature to continue update\n", .{});
            }
        },
        .Complete => {
            log.debug("update:: failed when complete command is called before, no need to continue updating", .{});
            try stdout.print("✓ Update already completed - nothing to continue\n", .{});
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
    // TODO: When creating new slices (o.create == true), add git notes to preserve relationships
    // After successful slice creation, add note: "slice-parent: <start_point_or_main>"
    // This ensures slice relationships are preserved even after rebasing/squashing
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

// Helper function to display git notes information for slices
fn displayGitNotesInfo(alloc: std.mem.Allocator, writer: anytype, slices: []Slice) !void {

    // Track if any notes were found
    var notes_found = false;
    var notes_with_parents: usize = 0;
    var notes_without_parents: usize = 0;

    // Check each slice for git notes
    for (slices) |slice_item| {
        // Get the commit ID for this slice
        const slice_ref = slice_item.ref;
        const maybe_commit_oid = slice_ref.target();

        if (maybe_commit_oid == null) continue;

        // Try to read the note for this slice using Slice method
        if (slice_item.getParentFromNotes(alloc)) |maybe_parent_info| {
            if (maybe_parent_info) |parent_info| {
                defer alloc.free(parent_info);
                notes_found = true;
                notes_with_parents += 1;
                
                const slice_name = slice_item.name();
                try writer.print("│  📝 \x1b[1m{s}:\x1b[0m parent → \x1b[32m{s}\x1b[0m\n", .{ slice_name, parent_info });
            } else {
                // No note exists for this slice
                notes_without_parents += 1;
            }
        } else |_| {
            // Failed to read note
            notes_without_parents += 1;
        }
    }

    // Show summary of notes status
    if (notes_found) {
        try writer.print("│  ✅ Slices with parent notes: \x1b[1;32m{d}\x1b[0m\n", .{notes_with_parents});
        if (notes_without_parents > 0) {
            try writer.print("│  ⚠️  Slices without parent notes: \x1b[1;33m{d}\x1b[0m\n", .{notes_without_parents});
        }
    } else {
        try writer.print("│  📄 No git notes found for slice relationships\n", .{});
        try writer.print("│  💡 \x1b[2mTip: Use git notes to preserve relationships after rebasing\x1b[0m\n", .{});
    }

    // Show instructions for team collaboration if notes exist
    if (notes_found) {
        try writer.print("│  \x1b[2m💡 Team tip: Push notes with 'git push origin refs/notes/commits'\x1b[0m\n", .{});
    }
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
