const std = @import("std");
const log = std.log.scoped(.slice);
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

pub const Slice = struct {
    repo: GitRepository,
    ref: GitReference,
    target: ?*Slice = null,
    children: ArrayListUnmanaged(*Slice) = ArrayListUnmanaged(*Slice).empty,
    /// cache to hold already calculated isMerged calls
    _is_merge_into_map: StringHashMap(bool),

    /// This function takes the list of slices and loop through all of them and
    /// tries to create target, children relationship between each. In an ideal
    /// world, we should only have 1 orphan and 0 forked slices for a sane feature
    /// But anything may happen user may change things without our control so
    /// this function also returns this information discovered during construction
    /// which may help recovery or provide more helpful information to end user
    ///
    /// Returns: tuple of { orphan_count, forked_count }
    ///
    pub fn constructLinks(alloc: Allocator, slices: []Slice) !struct {
        usize,
        usize,
    } {
        log.debug("constructLinks::", .{});
        var orphan_count: usize = 0;
        var forked_count: usize = 0;

        // TODO: investigate better ways to construct links between given slices
        // Current implementation uses reflog via createdFrom() which fails after rebasing/squashing.
        // Should be enhanced to:
        // 1. First try reading slice parent relationships from git notes
        // 2. Fall back to reflog analysis if notes are not available
        // 3. Provide a hybrid approach that combines both methods for accuracy
        for (slices) |*s| {
            // TODO: Replace this reflog-based approach with git notes reading
            // Current createdFrom() uses reflog which is unreliable after rebasing/squashing
            // Should implement: s.getParentFromNotes() that reads "slice-parent: <parent>" notes
            // and falls back to createdFrom() if notes are not available
            const created_from = s.ref.createdFrom(s.repo);
            if (created_from) |c| {
                defer c.free();
                s.target = null;
                for (slices) |*s_other| {
                    if (std.mem.eql(u8, c.name(), s_other.ref.name())) {
                        s.target = s_other;
                        try s_other.children.append(alloc, s);
                    }
                }
            } else {
                s.target = null;
            }
            if (s.target == null) {
                orphan_count += 1;
            }
            if (s.children.items.len > 1) {
                forked_count += 1;
            }
        }

        log.debug(
            "constructLinks:: orphan_count:{d} forked_count:{d}",
            .{ orphan_count, forked_count },
        );

        return .{
            orphan_count,
            forked_count,
        };
    }

    /// Given pool of slices in `slice_pool` finds the leaf nodes and returns
    /// the pointer of them as array. Returns slices as owned so it is up to
    /// caller to free the memory.
    pub fn leafNodes(o: struct {
        alloc: Allocator,
        slice_pool: []Slice,
    }) ![]*Slice {
        var leaves = ArrayListUnmanaged(*Slice).empty;
        defer leaves.deinit(o.alloc);

        for (o.slice_pool) |*s| {
            if (s.children.items.len == 0) {
                try leaves.append(o.alloc, s);
            }
        }
        return try leaves.toOwnedSlice(o.alloc);
    }

    pub fn printSliceGraph(writer: anytype, slice_pool: []Slice) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer std.debug.assert(gpa.deinit() == .ok);
        const allocator = gpa.allocator();

        // find leaf nodes
        const leaves = try Slice.leafNodes(
            .{
                .alloc = allocator,
                .slice_pool = slice_pool,
            },
        );
        defer allocator.free(leaves);

        for (leaves, 0..) |l, leaf_index| {
            var slice_chain = std.ArrayList(*Slice).init(allocator);
            defer slice_chain.deinit();

            // Build the chain from leaf to root
            var current_slice: ?*Slice = l;
            while (current_slice != null) {
                try slice_chain.append(current_slice.?);
                current_slice = current_slice.?.target;
            }

            // Print the chain from leaf to root (tip to base)
            for (slice_chain.items, 0..) |slice, chain_index| {
                const is_leaf = (chain_index == 0); // First item is the leaf (tip)
                const is_root = (chain_index == slice_chain.items.len - 1); // Last item is the root

                // Add tree structure indentation
                if (leaf_index > 0 and chain_index == slice_chain.items.len - 1) {
                    try writer.writeAll("│\n");
                }

                try writer.writeAll("│  ");

                if (is_root) {
                    try writer.writeAll("└─ ");
                } else {
                    try writer.writeAll("├─ ");
                }

                // Color and format slice names
                if (is_leaf) {
                    // Leaf slice (current working slice) - green
                    try writer.writeAll("\x1b[1;32m🍃 ");
                    try writer.writeAll(slice.name());
                    try writer.writeAll("\x1b[0m");
                } else if (is_root) {
                    // Root slice - blue
                    try writer.writeAll("\x1b[1;34m🌱 ");
                    try writer.writeAll(slice.name());
                    try writer.writeAll("\x1b[0m");
                } else {
                    // Intermediate slice - yellow
                    try writer.writeAll("\x1b[1;33m🔸 ");
                    try writer.writeAll(slice.name());
                    try writer.writeAll("\x1b[0m");
                }

                // Add flow indicators
                if (is_root) {
                    // Show connection to external target
                    const created_from = slice.ref.createdFrom(slice.repo);
                    if (created_from) |c| {
                        defer c.free();
                        const clean_target_name = if (std.mem.startsWith(u8, c.name(), "refs/heads/"))
                            c.name()["refs/heads/".len..]
                        else
                            c.name();
                        try writer.writeAll(" \x1b[2m→\x1b[0m \x1b[1;36m");
                        try writer.writeAll(clean_target_name);
                        try writer.writeAll("\x1b[0m");
                    }
                } else {
                    // Show connection to next slice in chain
                    if (slice.target) |target_slice| {
                        try writer.writeAll(" \x1b[2m↓\x1b[0m \x1b[2m");
                        try writer.writeAll(target_slice.name());
                        try writer.writeAll("\x1b[0m");
                    }
                }

                try writer.writeAll("\n");
            }
        }
    }

    /// Returns the name of a slice from its reference name.
    /// Assumes that the reference name is in following format
    /// "refs/heads/sparse/<user_id>/<feature_name>/slice/<slice_name>"
    ///
    pub fn name(self: Slice) []const u8 {
        return sliceNameFromRefName(self.ref.name());
    }

    /// Returns the name of a slice from its reference name.
    /// Assumes that the reference name is in following format
    /// "refs/heads/sparse/<user_id>/<feature_name>/slice/<slice_name>"
    ///
    fn sliceNameFromRefName(ref_name: []const u8) []const u8 {
        // Find the last '/' in the refname
        const last_slash_index = std.mem.lastIndexOfScalar(u8, ref_name, '/') orelse 0;
        // The slice name is the substring after the last '/'
        if (last_slash_index + 1 < ref_name.len) {
            return ref_name[last_slash_index + 1 ..];
        } else {
            return ref_name;
        }
    }

    ///
    /// Returns all slices available with given constraints.
    ///
    /// options:
    /// .in_feature(?[]const u8): feature to search slices in, if it is null
    ///  function returns all slices ignoring which feature they are in.
    pub fn getAllSlicesWith(o: struct {
        alloc: Allocator,
        in_feature: ?[]const u8 = null,
    }) ![]Slice {
        // TODO: Consider enhancing this function to also populate slice parent relationships
        // from git notes during slice creation, rather than doing it later in constructLinks()
        // This could improve performance and reliability of relationship detection
        log.debug("getAllSlicesWith::", .{});
        const repo = try GitRepository.open();
        defer repo.free();

        const sparse_ref_prefix = try utils.sparseBranchRefPrefix(.{
            .alloc = o.alloc,
            .repo = repo,
        });
        defer o.alloc.free(sparse_ref_prefix);

        var glob: []const u8 = undefined;
        if (o.in_feature) |f| {
            glob = try std.fmt.allocPrint(
                o.alloc,
                "{s}/{s}/slice/*",
                .{ sparse_ref_prefix, f },
            );
        } else {
            glob = try std.fmt.allocPrint(
                o.alloc,
                "{s}/*",
                .{
                    sparse_ref_prefix,
                },
            );
        }
        defer o.alloc.free(glob);
        log.debug("getAllSlicesWith:: glob:{s}", .{glob});

        var ref_iter = try GitReferenceIterator.fromGlob(glob, repo);
        defer ref_iter.free();
        var slices = std.ArrayListUnmanaged(Slice).empty;

        while (try ref_iter.next()) |ref| {
            const slice_repo = try GitRepository.open();
            try slices.append(o.alloc, .{
                .ref = ref,
                .repo = slice_repo,
                ._is_merge_into_map = StringHashMap(bool).init(o.alloc),
            });
        }

        return try slices.toOwnedSlice(o.alloc);
    }

    // TODO: Add function to read slice parent from git notes
    // pub fn getParentFromNotes(self: *Slice, alloc: Allocator) !?[]const u8 {
    //     // Read git note with format "slice-parent: <parent_branch_name>"
    //     // Return parent branch name or null if no note exists
    //     // Use libgit2 git_note_read() or system Git wrapper
    // }

    // TODO: Add function to set slice parent in git notes
    // pub fn setParentInNotes(self: *Slice, alloc: Allocator, parent: []const u8) !void {
    //     // Create git note with format "slice-parent: <parent_branch_name>"
    //     // Use libgit2 git_note_create() or system Git wrapper
    // }

    pub fn isMerged(self: *Slice, o: struct { alloc: Allocator, into: GitReference }) !bool {
        log.debug("isMerged:: self.name:{s}", .{self.ref.name()});
        log.debug("isMerged:: o.into.name:{s}", .{o.into.name()});
        if (self._is_merge_into_map.contains(o.into.name())) {
            return self._is_merge_into_map.get(o.into.name()).?;
        }
        // object ids should be different otherwise no need to check if it is
        // merged or not just return false, maybe there is no commit in branch?
        if (std.mem.eql(u8, &self.ref.target().?.id(), &o.into.target().?.id())) {
            return false;
        }

        // TODO: replace this with libgit2 version
        const merge_base = res: {
            const rr_merge_base = try Git.@"merge-base"(.{
                .allocator = o.alloc,
                .args = &.{
                    o.into.name(),
                    self.ref.name(),
                },
            });
            defer o.alloc.free(rr_merge_base.stderr);
            defer o.alloc.free(rr_merge_base.stdout);
            const trimmed_stdout = utils.trimString(rr_merge_base.stdout, .{});
            log.debug("isMerged:: merge_base:{s}", .{trimmed_stdout});
            break :res try o.alloc.dupe(u8, trimmed_stdout);
        };
        defer o.alloc.free(merge_base);

        const merge_base_query = try std.fmt.allocPrint(
            o.alloc,
            "{s}^{{tree}}",
            .{merge_base},
        );
        defer o.alloc.free(merge_base_query);
        const rr_base_tree = try Git.@"rev-parse"(.{
            .allocator = o.alloc,
            .args = &.{
                merge_base_query,
            },
        });
        defer o.alloc.free(rr_base_tree.stderr);
        defer o.alloc.free(rr_base_tree.stdout);
        log.debug("isMerged:: base_tree:{s}", .{rr_base_tree.stdout});

        const slice_tree_query = try std.fmt.allocPrint(
            o.alloc,
            "{s}^{{tree}}",
            .{self.ref.name()},
        );
        defer o.alloc.free(slice_tree_query);
        const rr_slice_tree = try Git.@"rev-parse"(.{
            .allocator = o.alloc,
            .args = &.{
                slice_tree_query,
            },
        });
        defer o.alloc.free(rr_slice_tree.stderr);
        defer o.alloc.free(rr_slice_tree.stdout);
        log.debug("isMerged:: slice_tree:{s}", .{rr_slice_tree.stdout});

        const log_tree_query = try std.fmt.allocPrint(
            o.alloc,
            "{s}..{s}",
            .{ merge_base, o.into.name() },
        );
        defer o.alloc.free(log_tree_query);
        const rr_log = try Git.log(.{
            .allocator = o.alloc,
            .args = &.{
                "--format=%T",
                log_tree_query,
            },
        });
        defer o.alloc.free(rr_log.stderr);
        defer o.alloc.free(rr_log.stdout);
        log.debug("isMerged:: log:{s}", .{rr_log.stdout});

        // check the logs we got and see if our tree is already merged
        var log_lines = std.mem.splitScalar(u8, rr_log.stdout, '\n');
        const trimmed_slice_tree = utils.trimString(rr_slice_tree.stdout, .{});
        while (log_lines.next()) |line| {
            const trimmed_log = utils.trimString(line, .{});

            if (std.mem.eql(u8, trimmed_log, trimmed_slice_tree)) {
                log.debug("isMerged:: slice:{s} is already merged", .{self.ref.name()});
                try self._is_merge_into_map.put(o.into.name(), true);
                return true;
            }
        }
        log.debug("isMerged:: slice:{s} is not merged", .{self.ref.name()});
        try self._is_merge_into_map.put(o.into.name(), false);

        return false;
    }

    pub fn activate(self: Slice, alloc: Allocator) !void {
        const rr_switch = try Git.@"switch"(
            .{
                .allocator = alloc,
                .args = &.{
                    try self.ref.branchName(),
                },
            },
        );
        defer alloc.free(rr_switch.stderr);
        defer alloc.free(rr_switch.stdout);
        if (rr_switch.term.Exited != 0) {
            log.debug("activate:: switch stderr: {s}", .{rr_switch.stderr});
            log.err(
                "activate:: switch failed with exit code {d}",
                .{rr_switch.term.Exited},
            );
            return SparseError.UNABLE_TO_SWITCH_BRANCHES;
        }
    }

    pub fn push(self: Slice, alloc: Allocator) !void {
        const rr_push = try Git.push(.{
            .allocator = alloc,
            .args = &.{
                "--force-with-lease",
                // TODO: use proper remote here
                "origin",
                try self.ref.branchName(),
            },
        });
        defer alloc.free(rr_push.stderr);
        defer alloc.free(rr_push.stdout);
        if (rr_push.term.Exited != 0) {
            log.debug("push:: push stderr: {s}", .{rr_push.stderr});
            log.err(
                "push:: push failed with exit code {d}",
                .{rr_push.term.Exited},
            );
            return SparseError.UNABLE_TO_PUSH_SLICE;
        }
    }

    pub fn free(self: *Slice, alloc: Allocator) void {
        self.ref.free();
        self.repo.free();
        self.children.deinit(alloc);
        self._is_merge_into_map.deinit();
    }
};

const utils = @import("utils.zig");
const LibGit = @import("libgit2/libgit2.zig");
const GitConfig = LibGit.GitConfig;
const GitBranch = LibGit.GitBranch;
const GitBranchType = LibGit.GitBranchType;
const GitReference = LibGit.GitReference;
const GitReferenceIterator = LibGit.GitReferenceIterator;
const GitRepository = LibGit.GitRepository;
const GitMerge = LibGit.GitMerge;
const constants = @import("constants.zig");
const SparseConfig = @import("config.zig").SparseConfig;
const SparseError = @import("sparse.zig").Error;
const Git = @import("system/Git.zig");
