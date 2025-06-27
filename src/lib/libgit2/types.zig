const c = @import("c.zig").c;
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn cStringToGitString(c_string: [*c]const u8) GitString {
    return std.mem.span(c_string);
}

/// Takes `branch_ref_name` which can be in following format `refs/heads/main`
/// and converts it into `refs/remotes/<remote_name>/main`
pub fn branchRefNameToRemote(
    alloc: Allocator,
    branch_ref_name: GitString,
    remote_name: GitString,
) !GitString {
    const local_branch_prefix = "refs/heads/";
    if (!std.mem.startsWith(u8, branch_ref_name, local_branch_prefix)) {
        return alloc.dupe(u8, branch_ref_name);
    }

    const remote_prefix = "refs/remotes";
    return try std.fmt.allocPrint(
        alloc,
        "{s}/{s}/{s}",
        .{
            remote_prefix,
            remote_name,
            branch_ref_name[local_branch_prefix.len..],
        },
    );
}

pub const GitString = []const u8;

/// https://libgit2.org/docs/reference/main/buffer/git_buf.html
pub const GitBuf = struct {
    value: ?*c.git_buf = null,

    pub fn dispose(self: GitBuf) void {
        c.git_buf_dispose(self.value);
    }
};

pub const GitStrArray = struct {
    value: ?c.git_strarray = null,

    pub fn dispose(self: *GitStrArray) void {
        if (self.value) |*value| {
            c.git_strarray_dispose(value);
        }
    }
    pub fn items(self: GitStrArray, alloc: std.mem.Allocator) [][*:0]const u8 {
        _ = alloc;
        if (self.value) |value| {
            if (value.count > 0) {
                return @ptrCast(value.strings[0..value.count]);
            }
        }

        return &.{};
    }
};

pub const GitOID = struct {
    value: ?c.git_oid = null,

    pub fn id(self: GitOID) [20]u8 {
        if (self.value) |value| {
            return value.id;
        }
        return std.mem.zeroes([20]u8);
    }

    pub fn str(self: GitOID) [*:0]const u8 {
        if (self.value) |val| {
            return c.git_oid_tostr_s(&val);
        }
        return c.git_oid_tostr_s(null);
    }
};

test "branchRefNameToRemote: converts refs/heads/main to refs/remotes/origin/main" {
    const testing = std.testing;
    var allocator = testing.allocator;
    const input = "refs/heads/main";
    const remote = "origin";
    const expected = "refs/remotes/origin/main";
    const result = try branchRefNameToRemote(allocator, input, remote);
    defer allocator.free(result);
    try testing.expectEqualStrings(expected, result);
}

test "branchRefNameToRemote: handles branch names with slashes" {
    const testing = std.testing;
    var allocator = testing.allocator;
    const input = "refs/heads/feature/xyz";
    const remote = "upstream";
    const expected = "refs/remotes/upstream/feature/xyz";
    const result = try branchRefNameToRemote(allocator, input, remote);
    defer allocator.free(result);
    try testing.expectEqualStrings(expected, result);
}

test "branchRefNameToRemote: returns unchanged if not refs/heads/" {
    const testing = std.testing;
    var allocator = testing.allocator;
    const input = "refs/tags/v1.0";
    const remote = "origin";
    const expected = "refs/tags/v1.0";
    const result = try branchRefNameToRemote(allocator, input, remote);
    defer allocator.free(result);
    try testing.expectEqualStrings(expected, result);
}

test "branchRefNameToRemote: empty branch name" {
    const testing = std.testing;
    var allocator = testing.allocator;
    const input = "";
    const remote = "origin";
    const expected = "";
    const result = try branchRefNameToRemote(allocator, input, remote);
    defer allocator.free(result);
    try testing.expectEqualStrings(expected, result);
}

test "branchRefNameToRemote: empty remote name" {
    const testing = std.testing;
    var allocator = testing.allocator;
    const input = "refs/heads/main";
    const remote = "";
    const expected = "refs/remotes//main";
    const result = try branchRefNameToRemote(allocator, input, remote);
    defer allocator.free(result);
    try testing.expectEqualStrings(expected, result);
}

test {
    std.testing.refAllDecls(@This());
}

const GitError = @import("error.zig").GitError;
