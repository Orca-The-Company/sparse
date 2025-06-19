const std = @import("std");
const log = std.log.scoped(.slice);
const Allocator = std.mem.Allocator;

///
/// Returns all slices available with given constraints.
///
/// options:
/// .inFeature(?[]const u8): feature to search slices in, if it is null
///  function returns all slices ignoring which feature they are in.
pub fn getAllSlicesWith(o: struct {
    allocator: Allocator,
    repo: LibGit.GitRepository,
    inFeature: ?[]const u8 = null,
}) !void {
    var glob: []u8 = undefined;
    if (o.inFeature) |f| {
        glob = try std.fmt.allocPrint(
            o.allocator,
            "refs/heads/sparse/havadartalha@gmail.com/{s}/*",
            .{f},
        );
    } else {
        glob = try std.fmt.allocPrint(
            o.allocator,
            "refs/heads/sparse/havadartalha@gmail.com/*",
            .{},
        );
    }
    defer o.allocator.free(glob);

    //std.fmt.allocPrint(o.allocator, comptime fmt: []const u8, args: anytype)
    var ref_iter = try LibGit.GitReferenceIterator.fromGlob(glob, o.repo);
    defer ref_iter.free();
    while (try ref_iter.next()) |ref| {
        const reflog = try LibGit.GitReflog.read(o.repo, ref.name());
        defer reflog.free();
        const last_entry = reflog.entryByIndex(reflog.entrycount() - 1).?;
        const committer = last_entry.committer().value.?;
        log.debug(
            "getAllSlicesWith:: ref.name: {s} entrycount: {d} committer:{s} time:{d}",
            .{ ref.name(), reflog.entrycount(), committer.email, committer.when.time },
        );
    }
}
const Slice = struct {};

const LibGit = @import("libgit2/libgit2.zig");
