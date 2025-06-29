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
        for (slices) |*s| {
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

        for (leaves) |l| {
            var leaf_slice: ?*Slice = l;
            while (leaf_slice != null) : (leaf_slice = leaf_slice.?.target) {
                try writer.writeAll(leaf_slice.?.ref.name());
                if (leaf_slice.?.target != null) {
                    try writer.writeAll(" ==> ");
                } else {
                    const created_from = leaf_slice.?.ref.createdFrom(
                        leaf_slice.?.repo,
                    );
                    if (created_from) |c| {
                        defer c.free();
                        try writer.writeAll(" ==> ");
                        try writer.writeAll(c.name());
                    }
                }
            }
            try writer.writeAll("\n");
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
        const merge_base = GitMerge.base(
            self.repo,
            o.into.target().?,
            self.ref.target().?,
        ) catch {
            // TODO: return more appropriate error
            return SparseError.CORRUPTED_FEATURE;
        };

        const merge_base_query = try std.fmt.allocPrint(
            o.alloc,
            "{s}^{{tree}}",
            .{merge_base.?.str()},
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
            .{ merge_base.?.str(), o.into.name() },
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
