const std = @import("std");

/// refs/heads/sparse/<sparse.user.id>
pub fn sparseBranchRefPrefix(
    o: struct {
        alloc: std.mem.Allocator,
        repo: ?GitRepository = null,
    },
) ![]const u8 {
    var user_id: []const u8 = undefined;
    defer o.alloc.free(user_id);

    if (o.repo == null) {
        try LibGit.init();
        defer LibGit.shutdown() catch @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");
        const repo = try GitRepository.open();
        defer repo.free();
        user_id = try SparseConfig.userId(o.alloc, repo);
    } else {
        user_id = try SparseConfig.userId(o.alloc, o.repo.?);
    }

    return try std.fmt.allocPrint(
        o.alloc,
        "{s}{s}",
        .{ constants.BRANCH_REFS_PREFIX, user_id },
    );
}

pub fn combine(
    comptime T: type,
    alloc: std.mem.Allocator,
    arr1: []const T,
    arr2: []const T,
) ![]T {
    var arr_list: std.ArrayListUnmanaged(T) = try std.ArrayListUnmanaged(T).initCapacity(alloc, arr1.len + arr2.len);
    for (arr1) |item| {
        try arr_list.append(alloc, item);
    }
    for (arr2) |item| {
        try arr_list.append(alloc, item);
    }
    return try arr_list.toOwnedSlice(alloc);
}

pub fn trimString(slice: []const u8, o: struct {
    values_to_strip: []const u8 = "\r\n\t ",
}) []const u8 {
    return std.mem.trim(u8, slice, o.values_to_strip);
}

const constants = @import("constants.zig");
const SparseConfig = @import("config.zig").SparseConfig;
const LibGit = @import("libgit2/libgit2.zig");
const GitRepository = LibGit.GitRepository;
