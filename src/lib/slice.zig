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
        allocator: Allocator,
        in_feature: ?[]const u8 = null,
    }) ![]Slice {
        const repo = try GitRepository.open();
        defer repo.free();

        var glob: []u8 = undefined;
        if (o.in_feature) |f| {
            glob = try std.fmt.allocPrint(
                o.allocator,
                "{s}havadartalha@gmail.com/{s}/slice/*",
                .{ constants.BRANCH_REFS_PREFIX, f },
            );
        } else {
            glob = try std.fmt.allocPrint(
                o.allocator,
                "{s}havadartalha@gmail.com/*",
                .{
                    constants.BRANCH_REFS_PREFIX,
                },
            );
        }
        defer o.allocator.free(glob);

        var ref_iter = try GitReferenceIterator.fromGlob(glob, repo);
        defer ref_iter.free();
        var refs = std.ArrayListUnmanaged(GitReference).empty;
        defer refs.deinit(o.allocator);
        var slices = std.ArrayListUnmanaged(Slice).empty;
        defer slices.deinit(o.allocator);

        while (try ref_iter.next()) |ref| {
            try refs.append(o.allocator, ref);
        }
        std.mem.sort(GitReference, refs.items, {}, GitReference.lessThanFn);
        for (refs.items) |ref| {
            try slices.append(o.allocator, .{ .ref = ref });
        }

        return try slices.toOwnedSlice(o.allocator);
    }
};

const LibGit = @import("libgit2/libgit2.zig");
const GitReference = LibGit.GitReference;
const GitReferenceIterator = LibGit.GitReferenceIterator;
const GitRepository = LibGit.GitRepository;
const constants = @import("constants.zig");
