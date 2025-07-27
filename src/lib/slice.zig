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
        // Get the slice-specific notes namespace
        const notes_namespace = try self.notesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Create refspec for pushing slice-specific notes
        const refspec = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ notes_namespace, notes_namespace });
        defer alloc.free(refspec);

        // TODO: Migrate to libgit2 implementation for better error handling and consistency
        const rr_push_notes = try Git.push(.{
            .allocator = alloc,
            .args = &.{
                // TODO: use proper remote here
                "origin",
                refspec,
            },
        });
        defer alloc.free(rr_push_notes.stderr);
        defer alloc.free(rr_push_notes.stdout);

        if (rr_push_notes.term.Exited != 0) {
            log.debug("pushNotes:: push notes stderr: {s}", .{rr_push_notes.stderr});
            log.err(
                "pushNotes:: push notes failed with exit code {d}",
                .{rr_push_notes.term.Exited},
            );
            return SparseError.UNABLE_TO_PUSH_SLICE;
        }

        log.info("[pushNotes]:: Successfully pushed git notes to remote", .{});
    }

    /// Fetches git notes from remote repository to get latest slice relationships
    pub fn fetchNotes(self: Slice, alloc: Allocator) !void {
        // Get the slice-specific notes namespace
        const notes_namespace = try self.notesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Create refspec for fetching slice-specific notes
        const refspec = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ notes_namespace, notes_namespace });
        defer alloc.free(refspec);

        const rr_fetch_notes = try Git.fetch(.{
            .allocator = alloc,
            .args = &.{
                // TODO: use proper remote here
                "origin",
                refspec,
            },
        });
        defer alloc.free(rr_fetch_notes.stderr);
        defer alloc.free(rr_fetch_notes.stdout);

        if (rr_fetch_notes.term.Exited != 0) {
            log.debug("fetchNotes:: fetch notes stderr: {s}", .{rr_fetch_notes.stderr});
            log.err(
                "fetchNotes:: fetch notes failed with exit code {d}",
                .{rr_fetch_notes.term.Exited},
            );
            return SparseError.UNABLE_TO_PUSH_SLICE; // Reusing error for fetch
        }
        log.info("[fetchNotes]:: Successfully fetched git notes from remote", .{});
    }

    /// Converts a slice branch name to its corresponding git notes namespace
    /// Example: refs/heads/sparse/user/feature/slice/1 -> refs/notes/sparse/user/feature/slice/1
    fn notesNamespace(self: Slice, alloc: Allocator) ![]u8 {
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
        const notes_namespace = try self.notesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Format note content
        const note_content = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.SLICE_PARENT_NOTE_PREFIX, parent_branch });
        defer alloc.free(note_content);

        _ = LibGit.GitNote.create(self.repo, commit_oid, note_content, signature, notes_namespace) catch |err| {
            log.err("[createParentNote]:: Failed to create parent note for slice {s}: {}", .{ self.name(), err });
            return err;
        };

        log.info("[createParentNote]:: Created parent note for slice {s} with parent: {s}", .{ self.name(), parent_branch });
    }

    /// Reads the parent branch from git notes for this slice
    /// Searches through all notes in the slice namespace to find the most recent parent note
    pub fn getParentFromNotes(self: *const Slice, alloc: Allocator) !?[]const u8 {
        // Get the slice-specific notes namespace
        const notes_namespace = try self.notesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Create iterator for notes in this slice's namespace
        var notes_iter = LibGit.GitNoteIterator.init(self.repo, notes_namespace) catch |err| {
            log.debug("[getParentFromNotes]:: Failed to create notes iterator for slice {s}: {}", .{ self.name(), err });
            return null;
        };
        defer notes_iter.free();

        var latest_parent: ?[]const u8 = null;

        // Iterate through all notes in the namespace to find parent notes
        // Note: We iterate through all notes and keep overwriting latest_parent,
        // effectively getting the most recent parent note as the final result
        while (try notes_iter.next()) |note_info| {
            const note = LibGit.GitNote.read(self.repo, note_info.annotated_id, notes_namespace) catch {
                continue; // Skip notes we can't read
            };

            if (note) |n| {
                defer n.free();
                const note_content = n.content();

                // Check if this is a parent note and parse it
                if (parseSliceParentNote(note_content, alloc)) |parent| {
                    // Free previous parent if we found a more recent one
                    if (latest_parent) |prev| {
                        alloc.free(prev);
                    }
                    latest_parent = parent;
                } else |_| {
                    // Not a parent note, continue
                    continue;
                }
            }
        }

        return latest_parent;
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
        const notes_namespace = try self.notesNamespace(alloc);
        defer alloc.free(notes_namespace);

        // Format note content
        const note_content = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.SLICE_PARENT_NOTE_PREFIX, new_parent_branch });
        defer alloc.free(note_content);

        _ = LibGit.GitNote.update(self.repo, commit_oid, note_content, signature, notes_namespace) catch |err| {
            log.err("Failed to update parent note for slice {s}: {}", .{ self.name(), err });
            return err;
        };

        log.info("[updateParentNote]:: Updated parent note for slice {s} with new parent: {s}", .{ self.name(), new_parent_branch });
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
        const notes_namespace = try self.notesNamespace(alloc);
        defer alloc.free(notes_namespace);

        LibGit.GitNote.remove(self.repo, commit_oid, signature, notes_namespace) catch |err| {
            log.debug("Failed to remove parent note for slice {s}: {}", .{ self.name(), err });
            return err;
        };

        log.info("[removeParentNote]:: Removed parent note for slice {s}", .{self.name()});
    }

    pub fn free(self: *Slice, alloc: Allocator) void {
        self.ref.free();
        self.repo.free();
        self.children.deinit(alloc);
        self._is_merge_into_map.deinit();
    }
};

// Helper functions for slice parent notes

/// Enhanced note validation errors
const NoteValidationError = error{
    InvalidNoteFormat,
    EmptyParentName,
    InvalidBranchName,
    NoteTooLong,
    InvalidCharacters,
};

/// Validates and parses slice parent note content with comprehensive error checking
fn parseSliceParentNote(note_content: []const u8, alloc: Allocator) !?[]const u8 {
    return parseSliceParentNoteWithValidation(note_content, alloc, true) catch |err| switch (err) {
        NoteValidationError.InvalidNoteFormat,
        NoteValidationError.EmptyParentName,
        NoteValidationError.InvalidBranchName,
        NoteValidationError.NoteTooLong,
        NoteValidationError.InvalidCharacters => {
            log.warn("Note validation failed: {}", .{err});
            return null;
        },
        else => return err,
    };
}

/// Validates and parses slice parent note with detailed validation
fn parseSliceParentNoteWithValidation(note_content: []const u8, alloc: Allocator, strict: bool) !?[]const u8 {
    // Check note length limits (prevent extremely long notes)
    if (note_content.len > 1024) {
        if (strict) return NoteValidationError.NoteTooLong;
        log.warn("Note content is suspiciously long ({d} chars), truncating", .{note_content.len});
    }

    // Look for "slice-parent: " prefix
    if (!std.mem.startsWith(u8, note_content, constants.SLICE_PARENT_NOTE_PREFIX)) {
        if (strict) return NoteValidationError.InvalidNoteFormat;
        return null; // Not a valid slice parent note
    }

    const parent_name = note_content[constants.SLICE_PARENT_NOTE_PREFIX.len..];

    // Trim whitespace and validate
    const trimmed = std.mem.trim(u8, parent_name, " \t\n\r");
    if (trimmed.len == 0) {
        if (strict) return NoteValidationError.EmptyParentName;
        return null; // Empty parent name
    }

    // Validate parent branch name format
    if (!isValidBranchReference(trimmed)) {
        if (strict) return NoteValidationError.InvalidBranchName;
        log.warn("Parent branch name contains invalid characters: {s}", .{trimmed});
        return null;
    }

    return try alloc.dupe(u8, trimmed);
}

/// Validates if a string is a valid branch reference name
fn isValidBranchReference(branch_name: []const u8) bool {
    if (branch_name.len == 0) return false;
    
    // Check for valid branch name patterns
    // Allow: main, feature/slice, sparse/user/feature/slice/name, refs/heads/...
    
    // Check for obviously invalid characters
    for (branch_name) |c| {
        switch (c) {
            // Invalid characters for git branch names
            ' ', '~', '^', ':', '?', '*', '[', '\\' => return false,
            // Control characters (includes \t, \n, \r)
            0...31, 127 => return false,
            else => {},
        }
    }
    
    // Check for invalid patterns
    if (std.mem.indexOf(u8, branch_name, "..") != null) return false; // No double dots
    if (std.mem.startsWith(u8, branch_name, ".") or std.mem.endsWith(u8, branch_name, ".")) return false; // No leading/trailing dots
    if (std.mem.endsWith(u8, branch_name, "/") or std.mem.startsWith(u8, branch_name, "/")) return false; // No leading/trailing slashes
    if (std.mem.indexOf(u8, branch_name, "//") != null) return false; // No double slashes
    
    return true;
}

/// Note consistency check results
const NoteConsistencyReport = struct {
    total_notes_checked: usize,
    corrupted_notes: usize,
    orphaned_notes: usize,  // Notes pointing to non-existent branches
    circular_references: usize,
    repaired_notes: usize,
    
    pub fn hasIssues(self: NoteConsistencyReport) bool {
        return self.corrupted_notes > 0 or self.orphaned_notes > 0 or self.circular_references > 0;
    }
};

/// Performs comprehensive note consistency checks across all slice namespaces
pub fn checkNoteConsistency(alloc: Allocator) !NoteConsistencyReport {
    log.info("Starting note consistency check...");
    
    const repo = try GitRepository.open();
    defer repo.free();
    
    var report = NoteConsistencyReport{
        .total_notes_checked = 0,
        .corrupted_notes = 0,
        .orphaned_notes = 0,
        .circular_references = 0,
        .repaired_notes = 0,
    };
    
    // Get all slice branches to build valid reference map
    const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
    defer {
        for (all_slices) |*slice| {
            slice.free(alloc);
        }
        alloc.free(all_slices);
    }
    
    // Build set of valid branch names for orphan detection
    var valid_branches = std.StringHashMap(void).init(alloc);
    defer valid_branches.deinit();
    
    try valid_branches.put("main", {});
    for (all_slices) |slice| {
        const branch_name = slice.ref.branchName() catch continue;
        try valid_branches.put(branch_name, {});
    }
    
    // Check notes in each slice's namespace
    for (all_slices) |slice| {
        const namespace = try slice.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(namespace);
        
        // Skip default namespace as we're not using it anymore
        if (std.mem.eql(u8, namespace, "refs/notes/commits")) continue;
        
        try checkSliceNotes(&report, repo, slice, namespace, &valid_branches, alloc);
    }
    
    log.info("Note consistency check complete: {d} notes checked, {d} issues found", 
        .{ report.total_notes_checked, report.corrupted_notes + report.orphaned_notes + report.circular_references });
    
    return report;
}

/// Checks notes for a specific slice namespace
fn checkSliceNotes(
    report: *NoteConsistencyReport, 
    repo: GitRepository, 
    slice: Slice, 
    namespace: []const u8,
    valid_branches: *std.StringHashMap(void),
    alloc: Allocator
) !void {
    // Try to read the note for this slice
    const commit_oid = slice.ref.target() orelse return;
    
    const note = LibGit.GitNote.read(repo, commit_oid, namespace) catch |err| switch (err) {
        LibGit.GitError.NOTE_READ_FAILED => return, // No note exists, not an error
        else => return err,
    };
    
    if (note == null) return; // No note for this slice
    defer note.?.free();
    
    report.total_notes_checked += 1;
    
    const note_content = note.?.content();
    
    // Validate note content
    const parent_branch = parseSliceParentNoteWithValidation(note_content, alloc, false) catch |err| switch (err) {
        NoteValidationError.InvalidNoteFormat,
        NoteValidationError.EmptyParentName,
        NoteValidationError.InvalidBranchName,
        NoteValidationError.NoteTooLong,
        NoteValidationError.InvalidCharacters => {
            log.warn("Corrupted note found for slice {s}: {}", .{ slice.name(), err });
            report.corrupted_notes += 1;
            return;
        },
        else => return err,
    };
    
    if (parent_branch == null) {
        log.debug("Note for slice {s} is not a parent note, skipping", .{slice.name()});
        return;
    }
    defer alloc.free(parent_branch.?);
    
    // Check if parent branch exists
    if (!valid_branches.contains(parent_branch.?)) {
        log.warn("Orphaned note found: slice {s} points to non-existent parent {s}", .{ slice.name(), parent_branch.? });
        report.orphaned_notes += 1;
    }
    
    // TODO: Add circular reference detection by building dependency graph
}

/// Attempts to repair corrupted or inconsistent notes
pub fn repairNotes(alloc: Allocator, dry_run: bool) !NoteConsistencyReport {
    log.info("Starting note repair process (dry_run: {})...", .{dry_run});
    
    var report = try checkNoteConsistency(alloc);
    
    if (!report.hasIssues()) {
        log.info("No note issues found, nothing to repair");
        return report;
    }
    
    const repo = try GitRepository.open();
    defer repo.free();
    
    // Get all slices for repair operations
    const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
    defer {
        for (all_slices) |*slice| {
            slice.free(alloc);
        }
        alloc.free(all_slices);
    }
    
    // Attempt to repair orphaned notes by falling back to reflog analysis
    for (all_slices) |*slice| {
        const namespace = try slice.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(namespace);
        
        if (std.mem.eql(u8, namespace, "refs/notes/commits")) continue;
        
        try repairSliceNote(&report, repo, slice, namespace, alloc, dry_run);
    }
    
    if (dry_run) {
        log.info("Dry run complete: {d} notes could be repaired", .{report.repaired_notes});
    } else {
        log.info("Repair complete: {d} notes repaired", .{report.repaired_notes});
    }
    
    return report;
}

/// Attempts to repair a single slice's note
fn repairSliceNote(
    report: *NoteConsistencyReport,
    repo: GitRepository,
    slice: *Slice,
    namespace: []const u8,
    alloc: Allocator,
    dry_run: bool
) !void {
    const commit_oid = slice.ref.target() orelse return;
    
    // Check if note exists and is valid
    const note = LibGit.GitNote.read(repo, commit_oid, namespace) catch return;
    if (note == null) return;
    defer note.?.free();
    
    const note_content = note.?.content();
    const parent_branch = parseSliceParentNoteWithValidation(note_content, alloc, false) catch {
        // Note is corrupted, try to repair using reflog
        log.info("Attempting to repair corrupted note for slice {s} using reflog", .{slice.name()});
        
        if (!dry_run) {
            try repairNoteFromReflog(slice, alloc);
            report.repaired_notes += 1;
        } else {
            report.repaired_notes += 1;
        }
        return;
    };
    
    if (parent_branch) |parent| {
        defer alloc.free(parent);
        // Note is valid, no repair needed
    }
}

/// Repairs a note by extracting parent information from reflog
fn repairNoteFromReflog(slice: *Slice, alloc: Allocator) !void {
    const created_from = slice.ref.createdFrom(slice.repo);
    if (created_from) |parent_ref| {
        defer parent_ref.free();
        
        const parent_branch = try parent_ref.branchName();
        log.info("Repairing note for slice {s} with parent from reflog: {s}", .{ slice.name(), parent_branch });
        
        try slice.createParentNote(parent_branch, alloc);
    } else {
        log.warn("Cannot repair note for slice {s}: no reflog information available", .{slice.name()});
    }
}

/// Error recovery scenarios and handlers
const RecoveryScenario = enum {
    MissingNotes,           // Slices exist but have no notes
    CorruptedNotes,         // Notes exist but are malformed
    OrphanedNotes,          // Notes point to non-existent parents
    CircularReferences,     // Notes form circular dependencies
    NamespaceMismatch,      // Notes in wrong namespace
    DuplicateNotes,         // Multiple notes for same slice
};

/// Comprehensive error recovery for slice notes
pub fn recoverFromNoteErrors(alloc: Allocator, scenarios: []const RecoveryScenario, dry_run: bool) !NoteConsistencyReport {
    log.info("Starting comprehensive note error recovery (dry_run: {})...", .{dry_run});
    
    var report = NoteConsistencyReport{
        .total_notes_checked = 0,
        .corrupted_notes = 0,
        .orphaned_notes = 0,
        .circular_references = 0,
        .repaired_notes = 0,
    };
    
    for (scenarios) |scenario| {
        log.info("Recovering from scenario: {}", .{scenario});
        
        switch (scenario) {
            .MissingNotes => {
                const recovered = try recoverMissingNotes(alloc, dry_run);
                report.repaired_notes += recovered;
            },
            .CorruptedNotes => {
                const recovered = try recoverCorruptedNotes(alloc, dry_run);
                report.repaired_notes += recovered;
            },
            .OrphanedNotes => {
                const recovered = try recoverOrphanedNotes(alloc, dry_run);
                report.repaired_notes += recovered;
            },
            .NamespaceMismatch => {
                const recovered = try recoverNamespaceMismatches(alloc, dry_run);
                report.repaired_notes += recovered;
            },
            .CircularReferences, .DuplicateNotes => {
                log.warn("Recovery for {} not yet implemented", .{scenario});
            },
        }
    }
    
    log.info("Comprehensive recovery complete: {d} notes recovered", .{report.repaired_notes});
    return report;
}

/// Recovers slices that are missing notes by creating them from reflog
fn recoverMissingNotes(alloc: Allocator, dry_run: bool) !usize {
    const repo = try GitRepository.open();
    defer repo.free();
    
    const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
    defer {
        for (all_slices) |*slice| {
            slice.free(alloc);
        }
        alloc.free(all_slices);
    }
    
    var recovered: usize = 0;
    
    for (all_slices) |*slice| {
        const namespace = try slice.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(namespace);
        
        if (std.mem.eql(u8, namespace, "refs/notes/commits")) continue;
        
        const commit_oid = slice.ref.target() orelse continue;
        
        // Check if note exists
        const note = LibGit.GitNote.read(repo, commit_oid, namespace) catch null;
        if (note != null) {
            note.?.free();
            continue; // Note exists, no recovery needed
        }
        
        // Note is missing, try to recover from reflog
        log.info("Recovering missing note for slice {s}", .{slice.name()});
        
        if (!dry_run) {
            repairNoteFromReflog(slice, alloc) catch |err| {
                log.warn("Failed to recover note for slice {s}: {}", .{ slice.name(), err });
                continue;
            };
        }
        
        recovered += 1;
    }
    
    return recovered;
}

/// Recovers corrupted notes by replacing them with reflog data
fn recoverCorruptedNotes(alloc: Allocator, dry_run: bool) !usize {
    const repo = try GitRepository.open();
    defer repo.free();
    
    const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
    defer {
        for (all_slices) |*slice| {
            slice.free(alloc);
        }
        alloc.free(all_slices);
    }
    
    var recovered: usize = 0;
    
    for (all_slices) |*slice| {
        const namespace = try slice.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(namespace);
        
        if (std.mem.eql(u8, namespace, "refs/notes/commits")) continue;
        
        const commit_oid = slice.ref.target() orelse continue;
        
        // Check if note exists and is corrupted
        const note = LibGit.GitNote.read(repo, commit_oid, namespace) catch continue;
        if (note == null) continue;
        defer note.?.free();
        
        const note_content = note.?.content();
        
        // Try to parse the note - if it fails, it's corrupted
        const is_corrupted = parseSliceParentNoteWithValidation(note_content, alloc, true) catch true;
        if (is_corrupted != true) {
            // Note is valid, no recovery needed
            if (is_corrupted) |parent| {
                alloc.free(parent);
            }
            continue;
        }
        
        log.info("Recovering corrupted note for slice {s}", .{slice.name()});
        
        if (!dry_run) {
            // Remove corrupted note and recreate from reflog
            const signature = LibGit.GitSignature.default(slice.repo) catch continue;
            defer signature.free();
            
            LibGit.GitNote.remove(repo, commit_oid, signature, namespace) catch {};
            repairNoteFromReflog(slice, alloc) catch |err| {
                log.warn("Failed to recover corrupted note for slice {s}: {}", .{ slice.name(), err });
                continue;
            };
        }
        
        recovered += 1;
    }
    
    return recovered;
}

/// Recovers orphaned notes (pointing to non-existent parents) by updating them
fn recoverOrphanedNotes(alloc: Allocator, dry_run: bool) !usize {
    const repo = try GitRepository.open();
    defer repo.free();
    
    const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
    defer {
        for (all_slices) |*slice| {
            slice.free(alloc);
        }
        alloc.free(all_slices);
    }
    
    // Build set of valid branch names
    var valid_branches = std.StringHashMap(void).init(alloc);
    defer valid_branches.deinit();
    
    try valid_branches.put("main", {});
    for (all_slices) |slice| {
        const branch_name = slice.ref.branchName() catch continue;
        try valid_branches.put(branch_name, {});
    }
    
    var recovered: usize = 0;
    
    for (all_slices) |*slice| {
        const namespace = try slice.sliceBranchToNotesNamespace(alloc);
        defer alloc.free(namespace);
        
        if (std.mem.eql(u8, namespace, "refs/notes/commits")) continue;
        
        const commit_oid = slice.ref.target() orelse continue;
        
        // Check if note exists
        const note = LibGit.GitNote.read(repo, commit_oid, namespace) catch continue;
        if (note == null) continue;
        defer note.?.free();
        
        const note_content = note.?.content();
        const parent_branch = parseSliceParentNoteWithValidation(note_content, alloc, false) catch continue;
        if (parent_branch == null) continue;
        defer alloc.free(parent_branch.?);
        
        // Check if parent exists
        if (valid_branches.contains(parent_branch.?)) continue; // Parent exists, no recovery needed
        
        log.info("Recovering orphaned note for slice {s} (missing parent: {s})", .{ slice.name(), parent_branch.? });
        
        if (!dry_run) {
            // Try to find correct parent from reflog
            repairNoteFromReflog(slice, alloc) catch |err| {
                log.warn("Failed to recover orphaned note for slice {s}: {}", .{ slice.name(), err });
                continue;
            };
        }
        
        recovered += 1;
    }
    
    return recovered;
}

/// Recovers notes that are in the wrong namespace
fn recoverNamespaceMismatches(alloc: Allocator, dry_run: bool) !usize {
    const repo = try GitRepository.open();
    defer repo.free();
    
    var recovered: usize = 0;
    
    // Check for notes in the old default namespace that should be moved
    var iterator = LibGit.GitNoteIterator.init(repo, "refs/notes/commits") catch return 0;
    defer iterator.free();
    
    while (iterator.next() catch null) |note_info| {
        const note = LibGit.GitNote.read(repo, note_info.annotated_id, "refs/notes/commits") catch continue;
        if (note == null) continue;
        defer note.?.free();
        
        const note_content = note.?.content();
        
        // Check if this is a slice parent note
        if (!std.mem.startsWith(u8, note_content, constants.SLICE_PARENT_NOTE_PREFIX)) continue;
        
        // Try to find the slice this note belongs to
        const all_slices = try Slice.getAllSlicesWith(.{ .alloc = alloc });
        defer {
            for (all_slices) |*s| {
                s.free(alloc);
            }
            alloc.free(all_slices);
        }
        
        for (all_slices) |*slice| {
            const slice_commit = slice.ref.target() orelse continue;
            
            // Check if this note belongs to this slice
            if (!std.mem.eql(u8, &note_info.annotated_id.value.?, &slice_commit.value.?)) continue;
            
            // Found the slice, move note to correct namespace
            const correct_namespace = try slice.sliceBranchToNotesNamespace(alloc);
            defer alloc.free(correct_namespace);
            
            if (std.mem.eql(u8, correct_namespace, "refs/notes/commits")) continue; // Already in correct namespace
            
            log.info("Moving note for slice {s} to correct namespace: {s}", .{ slice.name(), correct_namespace });
            
            if (!dry_run) {
                // Create note in correct namespace
                const signature = LibGit.GitSignature.default(slice.repo) catch continue;
                defer signature.free();
                
                _ = LibGit.GitNote.create(repo, slice_commit, note_content, signature, correct_namespace) catch continue;
                
                // Remove from old namespace
                LibGit.GitNote.remove(repo, slice_commit, signature, "refs/notes/commits") catch {};
            }
            
            recovered += 1;
            break;
        }
    }
    
    return recovered;
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

test "parseSliceParentNoteValidation" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;

    // Test invalid branch names are rejected
    {
        const note_content = "slice-parent: invalid~branch";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test branch name with invalid characters
    {
        const note_content = "slice-parent: branch with spaces";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test double dots in branch name
    {
        const note_content = "slice-parent: feature..branch";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test leading slash
    {
        const note_content = "slice-parent: /invalid/branch";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test trailing slash
    {
        const note_content = "slice-parent: invalid/branch/";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result == null);
    }

    // Test valid refs/heads/ format
    {
        const note_content = "slice-parent: refs/heads/main";
        const result = try parseSliceParentNote(note_content, allocator);
        try expect(result != null);
        defer allocator.free(result.?);
    }
}

test "isValidBranchReference" {
    const expect = std.testing.expect;

    // Valid branch names
    try expect(isValidBranchReference("main"));
    try expect(isValidBranchReference("feature/branch"));
    try expect(isValidBranchReference("sparse/user/feature/slice/1"));
    try expect(isValidBranchReference("refs/heads/main"));
    try expect(isValidBranchReference("feature-branch"));
    try expect(isValidBranchReference("123-feature"));

    // Invalid branch names
    try expect(!isValidBranchReference(""));
    try expect(!isValidBranchReference("branch with spaces"));
    try expect(!isValidBranchReference("branch~name"));
    try expect(!isValidBranchReference("branch^name"));
    try expect(!isValidBranchReference("branch:name"));
    try expect(!isValidBranchReference("branch?name"));
    try expect(!isValidBranchReference("branch*name"));
    try expect(!isValidBranchReference("branch[name"));
    try expect(!isValidBranchReference("branch\\name"));
    try expect(!isValidBranchReference("feature..branch"));
    try expect(!isValidBranchReference(".feature"));
    try expect(!isValidBranchReference("feature."));
    try expect(!isValidBranchReference("/feature"));
    try expect(!isValidBranchReference("feature/"));
    try expect(!isValidBranchReference("feature//branch"));
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
