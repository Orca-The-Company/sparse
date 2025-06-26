const c = @import("c.zig").c;
const std = @import("std");

pub fn cStringToGitString(c_string: [*c]const u8) GitString {
    return std.mem.span(c_string);
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

const GitError = @import("error.zig").GitError;
