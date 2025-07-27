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

        // Hybrid approach: Try git notes first, fall back to reflog
        // This provides reliability for repositories that have been rebased/squashed
        for (slices) |*s| {
            s.target = null;

            // 1. First try reading slice parent relationships from git notes
            var parent_found = false;
            if (s.getParentFromNotes(alloc)) |maybe_parent_branch_name| {
                if (maybe_parent_branch_name) |parent_branch_name| {
                    defer alloc.free(parent_branch_name);
                    log.debug("Found parent from git notes for slice {s}: {s}", .{ s.name(), parent_branch_name });

                    // Look for the parent slice in our slice list
                    for (slices) |*s_other| {
                        const other_branch_name = s_other.ref.branchName() catch continue;
                        if (std.mem.eql(u8, parent_branch_name, other_branch_name)) {
                            s.target = s_other;
                            try s_other.children.append(alloc, s);
                            parent_found = true;
                            log.debug("Linked slice {s} to parent {s} via git notes", .{ s.name(), s_other.name() });
                            break;
                        }
                    }

                    if (!parent_found) {
                        log.debug("Parent {s} from git notes not found in current slice list for {s}", .{ parent_branch_name, s.name() });
                    }
                } else {
                    log.debug("No parent note found for slice {s}", .{s.name()});
                }
            } else |err| {
                log.debug("Failed to get parent from git notes for slice {s}: {}", .{ s.name(), err });
            }

            // 2. Fall back to reflog analysis if notes are not available
            if (!parent_found) {
                log.debug("Falling back to reflog analysis for slice {s}", .{s.name()});
                const created_from = s.ref.createdFrom(s.repo);
                if (created_from) |c| {
                    defer c.free();
                    for (slices) |*s_other| {
                        if (std.mem.eql(u8, c.name(), s_other.ref.name())) {
                            s.target = s_other;
                            try s_other.children.append(alloc, s);
                            log.debug("Linked slice {s} to parent {s} via reflog", .{ s.name(), s_other.name() });
                            break;
                        }
                    }
                } else {
                    log.debug("No parent found via reflog for slice {s}", .{s.name()});
                }
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

    /// Pushes git notes to remote repository to share slice relationships with team
    /// Syncs all slice-specific note namespaces
    pub fn pushNotes(self: Slice, alloc: Allocator) !void {
        _ = self; // We push all notes, not just for this slice
        
        // Get all slice-specific note namespaces to push
        const note_namespaces = try getAllSliceNoteNamespaces(alloc);
        defer {
            for (note_namespaces) |namespace| {
                alloc.free(namespace);
            }
            alloc.free(note_namespaces);
        }
        
        // Push each slice-specific note namespace with conflict resolution
        var success_count: usize = 0;
        var failure_count: usize = 0;
        
        for (note_namespaces) |namespace| {
            const refspec = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ namespace, namespace });
            defer alloc.free(refspec);
            
            const rr_push_slice_notes = try Git.push(.{
                .allocator = alloc,
                .args = &.{
                    // TODO: use proper remote here
                    "origin",
                    refspec,
                },
            });
            defer alloc.free(rr_push_slice_notes.stderr);
            defer alloc.free(rr_push_slice_notes.stdout);
            
            if (rr_push_slice_notes.term.Exited != 0) {
                failure_count += 1;
                
                // Check for specific error types and provide helpful messages
                if (std.mem.indexOf(u8, rr_push_slice_notes.stderr, "non-fast-forward") != null) {
                    log.warn("pushNotes:: Non-fast-forward update for {s}. Remote has newer notes. Consider fetching first.", .{namespace});
                } else if (std.mem.indexOf(u8, rr_push_slice_notes.stderr, "remote ref does not exist") != null) {
                    log.debug("pushNotes:: Creating new remote notes namespace: {s}", .{namespace});
                    // This is expected for new note namespaces, continue
                } else {
                    log.err("pushNotes:: Failed to push {s}: {s}", .{ namespace, rr_push_slice_notes.stderr });
                }
                continue;
            }
            
            success_count += 1;
            log.debug("Successfully pushed slice notes for namespace: {s}", .{namespace});
        }
        
        if (failure_count > 0) {
            log.warn("pushNotes:: {d} note namespaces failed to push, {d} succeeded", .{ failure_count, success_count });
        }
        
        log.info("Successfully pushed git notes to remote ({d} slice namespaces)", .{note_namespaces.len});
    }

    /// Fetches git notes from remote repository to get latest slice relationships
    /// Syncs all slice-specific note namespaces
    pub fn fetchNotes(self: Slice, alloc: Allocator) !void {
        _ = self; // We fetch all notes, not just for this slice
        
        // Fetch all slice-specific note namespaces using wildcard pattern
        // This is more efficient than fetching each namespace individually
        const sparse_notes_pattern = try getSparseNotesPattern(alloc);
        defer alloc.free(sparse_notes_pattern);
        
        const rr_fetch_slice_notes = try Git.fetch(.{
            .allocator = alloc,
            .args = &.{
                // TODO: use proper remote here
                "origin",
                sparse_notes_pattern,
            },
        });
        defer alloc.free(rr_fetch_slice_notes.stderr);
        defer alloc.free(rr_fetch_slice_notes.stdout);
        
        var slice_notes_fetched = false;
        if (rr_fetch_slice_notes.term.Exited != 0) {
            // Check for specific error types
            if (std.mem.indexOf(u8, rr_fetch_slice_notes.stderr, "couldn't find remote ref") != null) {
                log.debug("fetchNotes:: No remote slice notes found (this is normal for new repositories)");
            } else if (std.mem.indexOf(u8, rr_fetch_slice_notes.stderr, "Connection refused") != null or 
                       std.mem.indexOf(u8, rr_fetch_slice_notes.stderr, "Could not resolve hostname") != null) {
                log.warn("fetchNotes:: Network error while fetching slice notes: {s}", .{rr_fetch_slice_notes.stderr});
            } else {
                log.debug("fetchNotes:: fetch slice notes stderr: {s}", .{rr_fetch_slice_notes.stderr});
            }
        } else {
            slice_notes_fetched = true;
            log.debug("Successfully fetched slice-specific notes");
        }
        
        if (slice_notes_fetched) {
            log.info("Successfully fetched git notes from remote (slice namespaces)");
        } else {
            log.info("Failed to fetch git notes from remote (slice notes unavailable)");
        }
    }

    /// Force pushes git notes to remote, overwriting any conflicts
    /// Use with caution - this will overwrite remote notes
    pub fn forcePushNotes(self: Slice, alloc: Allocator) !void {
        _ = self; // We push all notes, not just for this slice
        
        log.warn("Force pushing notes - this will overwrite remote notes!");
        
        // Get and force push all slice-specific note namespaces
        const note_namespaces = try getAllSliceNoteNamespaces(alloc);
        defer {
            for (note_namespaces) |namespace| {
                alloc.free(namespace);
            }
            alloc.free(note_namespaces);
        }
        
        for (note_namespaces) |namespace| {
            const refspec = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ namespace, namespace });
            defer alloc.free(refspec);
            
            const rr_force_push = try Git.push(.{
                .allocator = alloc,
                .args = &.{
                    "--force",
                    // TODO: use proper remote here
                    "origin",
                    refspec,
                },
            });
            defer alloc.free(rr_force_push.stderr);
            defer alloc.free(rr_force_push.stdout);
            
            if (rr_force_push.term.Exited != 0) {
                log.err("forcePushNotes:: Failed to force push {s}: {s}", .{ namespace, rr_force_push.stderr });
            } else {
                log.debug("Force pushed slice notes for namespace: {s}", .{namespace});
            }
        }
        
        log.info("Force pushed git notes to remote");
    }

    // Git notes methods for preserving slice parent relationships

    /// Converts a slice branch name to its corresponding git notes namespace
    /// Example: refs/heads/sparse/user/feature/slice/1 -> refs/notes/sparse/user/feature/slice/1
    fn sliceBranchToNotesNamespace(self: Slice, alloc: Allocator) ![]u8 {
        const branch_name = self.ref.name();
        
        // Convert refs/heads/sparse/... to refs/notes/sparse/...
        if (std.mem.startsWith(u8, branch_name, "refs/heads/sparse/")) {
            return try std.fmt.allocPrint(alloc, "refs/notes/{s}", .{branch_name["refs/heads/".len..]});
        }
        
        // Fallback to default namespace if not a sparse branch
        return try alloc.dupe(u8, "refs/notes/commits");
    }

    /// Creates a git note recording the parent relationship for this slice
    /// Uses slice-specific namespace to avoid conflicts between slices
    pub fn createParentNote(self: *Slice, parent_branch: []const u8, alloc: Allocator) !void {
        const commit_oid = self.ref.target() orelse return SparseError.BACKEND_UNABLE_TO_GET_REFS;

        const signature = LibGit.GitSignature.default(self.repo) catch |err| {
            log.err("Failed to create signature for note: {}", .{err});
            return err;
        };
        defer signature.free();

        // Get the slice-specific notes namespace
        const notes_namespace = try self.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Format note content
        const note_content = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.SLICE_PARENT_NOTE_PREFIX, parent_branch });
        defer alloc.free(note_content);

        _ = LibGit.GitNote.create(self.repo, commit_oid, note_content, signature, notes_namespace) catch |err| {
            log.err("Failed to create parent note for slice {s}: {}", .{ self.name(), err });
            return err;
        };

        log.info("Created parent note for slice {s} with parent: {s}", .{ self.name(), parent_branch });
    }

    /// Reads the parent branch from git notes for this slice
    /// Uses slice-specific namespace to avoid conflicts between slices
    pub fn getParentFromNotes(self: *const Slice, alloc: Allocator) !?[]const u8 {
        const commit_oid = self.ref.target() orelse return null;

        // Get the slice-specific notes namespace
        const notes_namespace = try self.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(notes_namespace);

        const note = LibGit.GitNote.read(self.repo, commit_oid, notes_namespace) catch |err| {
            log.debug("Failed to read note for slice {s}: {}", .{ self.name(), err });
            return null;
        };

        if (note == null) {
            return null; // No note exists
        }

        defer note.?.free();

        const note_content = note.?.content();
        return parseSliceParentNote(note_content, alloc);
    }

    /// Updates the parent note for this slice
    pub fn updateParentNote(self: *Slice, new_parent_branch: []const u8, alloc: Allocator) !void {
        const commit_oid = self.ref.target() orelse return SparseError.BACKEND_UNABLE_TO_GET_REFS;

        const signature = LibGit.GitSignature.default(self.repo) catch |err| {
            log.err("Failed to create signature for note update: {}", .{err});
            return err;
        };
        defer signature.free();

        // Get the slice-specific notes namespace
        const notes_namespace = try self.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Format note content
        const note_content = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.SLICE_PARENT_NOTE_PREFIX, new_parent_branch });
        defer alloc.free(note_content);

        _ = LibGit.GitNote.update(self.repo, commit_oid, note_content, signature, notes_namespace) catch |err| {
            log.err("Failed to update parent note for slice {s}: {}", .{ self.name(), err });
            return err;
        };

        log.info("Updated parent note for slice {s} with new parent: {s}", .{ self.name(), new_parent_branch });
    }

    /// Removes the parent note for this slice
    pub fn removeParentNote(self: *Slice, alloc: Allocator) !void {
        const commit_oid = self.ref.target() orelse return SparseError.BACKEND_UNABLE_TO_GET_REFS;

        const signature = LibGit.GitSignature.default(self.repo) catch |err| {
            log.err("Failed to create signature for note removal: {}", .{err});
            return err;
        };
        defer signature.free();

        // Get the slice-specific notes namespace
        const notes_namespace = try self.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(notes_namespace);

        LibGit.GitNote.remove(self.repo, commit_oid, signature, notes_namespace) catch |err| {
            log.debug("Failed to remove parent note for slice {s}: {}", .{ self.name(), err });
            return err;
        };

        log.info("Removed parent note for slice {s}", .{self.name()});
    }

    pub fn free(self: *Slice, alloc: Allocator) void {
        self.ref.free();
        self.repo.free();
        self.children.deinit(alloc);
        self._is_merge_into_map.deinit();
    }
};

// Helper functions for remote notes sync

/// Gets all slice-specific note namespaces that exist in the current repository
/// Returns array of namespace strings that caller must free
fn getAllSliceNoteNamespaces(alloc: Allocator) ![][]u8 {
    const repo = try GitRepository.open();
    defer repo.free();
    
    // Get all slice branches
    const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
    defer {
        for (all_slices) |*slice| {
            slice.free(alloc);
        }
        alloc.free(all_slices);
    }
    
    var namespaces = std.ArrayList([]u8).init(alloc);
    errdefer {
        for (namespaces.items) |namespace| {
            alloc.free(namespace);
        }
        namespaces.deinit();
    }
    
    // Convert each slice to its note namespace
    for (all_slices) |slice| {
        const namespace = try slice.sliceBranchToNotesNamespace(alloc);
        
        // Only add if it's a slice-specific namespace (not default)
        if (!std.mem.eql(u8, namespace, "refs/notes/commits")) {
            try namespaces.append(namespace);
        } else {
            alloc.free(namespace);
        }
    }
    
    return namespaces.toOwnedSlice();
}

/// Gets the refspec pattern for fetching all sparse note namespaces
/// Returns pattern like "refs/notes/sparse/*:refs/notes/sparse/*"
fn getSparseNotesPattern(alloc: Allocator) ![]u8 {
    const repo = try GitRepository.open();
    defer repo.free();
    
    const user_id = try SparseConfig.userId(alloc, repo);
    defer alloc.free(user_id);
    
    // Create pattern to fetch all notes for this user's slices
    return try std.fmt.allocPrint(alloc, "refs/notes/sparse/{s}/*:refs/notes/sparse/{s}/*", .{ user_id, user_id });
}

// Helper functions for slice parent notes

/// Parses slice parent note content and extracts parent branch name
fn parseSliceParentNote(note_content: []const u8, alloc: Allocator) !?[]const u8 {
    // Look for "slice-parent: " prefix
    if (!std.mem.startsWith(u8, note_content, constants.SLICE_PARENT_NOTE_PREFIX)) {
        return null; // Not a valid slice parent note
    }

    const parent_name = note_content[constants.SLICE_PARENT_NOTE_PREFIX.len..];

    // Trim whitespace and validate
    const trimmed = std.mem.trim(u8, parent_name, " \t\n\r");
    if (trimmed.len == 0) {
        return null; // Empty parent name
    }

    return try alloc.dupe(u8, trimmed);
}

/// Finds all slices that have parent notes in the repository
pub fn findSlicesWithParentNotes(repo: GitRepository, alloc: Allocator) ![]LibGit.GitOID {
    var iterator = LibGit.GitNoteIterator.init(repo, null) catch |err| {
        log.err("Failed to create note iterator: {}", .{err});
        return err;
    };
    defer iterator.free();

    var slice_commits = std.ArrayList(LibGit.GitOID).init(alloc);
    errdefer slice_commits.deinit();

    while (iterator.next() catch |err| {
        log.err("Failed to iterate notes: {}", .{err});
        return err;
    }) |note_info| {
        // Read the note to check if it's a slice parent note
        if (LibGit.GitNote.read(repo, note_info.annotated_id) catch null) |note| {
            defer note.free();

            const note_content = note.content();
            if (std.mem.startsWith(u8, note_content, constants.SLICE_PARENT_NOTE_PREFIX)) {
                try slice_commits.append(note_info.annotated_id);
                log.debug("Found slice parent note for commit: {s}", .{note_info.annotated_id.str()});
            }
        }
    }

    log.info("Found {d} commits with slice parent notes", .{slice_commits.items.len});
    return slice_commits.toOwnedSlice();
}

test "parseSliceParentNote" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;

    // Test valid slice parent note
    {
        const note_content = "slice-parent: main";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result != null);
        defer allocator.free(result.?);
        try expectEqualStrings("main", result.?);
    }

    // Test valid slice parent note with feature branch
    {
        const note_content = "slice-parent: sparse/user/feature/slice/1";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result != null);
        defer allocator.free(result.?);
        try expectEqualStrings("sparse/user/feature/slice/1", result.?);
    }

    // Test note with whitespace around parent name
    {
        const note_content = "slice-parent:   feature-branch  \t\n";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result != null);
        defer allocator.free(result.?);
        try expectEqualStrings("feature-branch", result.?);
    }

    // Test invalid note without correct prefix
    {
        const note_content = "some other note content";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test note with prefix but empty parent name
    {
        const note_content = "slice-parent:   \t\n";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test note with partial prefix
    {
        const note_content = "slice-pare: main";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }
}

const utils = @import("utils.zig");
const LibGit = @import("libgit2/libgit2.zig");
const GitConfig = LibGit.GitConfig;
const GitBranch = LibGit.GitBranch;
const GitBranchType = LibGit.GitBranchType;
const GitReference = LibGit.GitReference;
const GitReferenceIterator = LibGit.GitReferenceIterator;
const GitRepository = LibGit.GitRepository;
const GitMerge = LibGit.GitMerge;
const SparseConfig = @import("config.zig").SparseConfig;
const SparseError = @import("sparse.zig").Error;
const Git = @import("system/Git.zig");
const constants = @import("constants.zig");
