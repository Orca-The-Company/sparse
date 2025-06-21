const std = @import("std");
const log = std.log.scoped(.slice);
const Allocator = std.mem.Allocator;

pub const Slice = struct {
    ref: GitReference,
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
        var refs = std.ArrayListUnmanaged(GitReference).empty;
        defer refs.deinit(o.alloc);
        var slices = std.ArrayListUnmanaged(Slice).empty;
        defer slices.deinit(o.alloc);

        while (try ref_iter.next()) |ref| {
            try refs.append(o.alloc, ref);
        }
        std.mem.sort(GitReference, refs.items, {}, GitReference.lessThanFn);
        for (refs.items) |ref| {
            try slices.append(o.alloc, .{ .ref = ref });
        }

        return try slices.toOwnedSlice(o.alloc);
    }
};

const utils = @import("utils.zig");
const LibGit = @import("libgit2/libgit2.zig");
const GitConfig = LibGit.GitConfig;
const GitBranch = LibGit.GitBranch;
const GitReference = LibGit.GitReference;
const GitReferenceIterator = LibGit.GitReferenceIterator;
const GitRepository = LibGit.GitRepository;
const constants = @import("constants.zig");
const SparseConfig = @import("config.zig").SparseConfig;
