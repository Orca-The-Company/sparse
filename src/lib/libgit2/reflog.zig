const c = @import("c.zig").c;
pub const GitReflogEntry = struct {
    value: ?*c.git_reflog_entry = null,

    pub fn committer(self: GitReflogEntry) GitSignature {
        var signature: GitSignature = .{ .value = .{} };
        const _committer = c.git_reflog_entry_committer(self.value);
        if (_committer) |_c| {
            signature.value = _c.*;
        } else {
            signature.value = null;
        }

        return signature;
    }
};

pub const GitReflog = struct {
    value: ?*c.git_reflog = null,

    pub fn read(repo: GitRepository, name: GitString) !GitReflog {
        var reflog = GitReflog{};

        const res: c_int = c.git_reflog_read(&reflog.value, repo.value, @ptrCast(name));
        if (res != 0) {
            return GitError.UNEXPECTED_ERROR;
        }
        return reflog;
    }

    pub fn entrycount(self: GitReflog) usize {
        return c.git_reflog_entrycount(self.value);
    }

    /// https://libgit2.org/docs/reference/main/reflog/git_reflog_entry_byindex.html
    pub fn entryByIndex(self: GitReflog, index: usize) ?GitReflogEntry {
        const reflog_entry = GitReflogEntry{
            .value = @constCast(c.git_reflog_entry_byindex(self.value, index)),
        };

        if (reflog_entry.value) |_| {
            return reflog_entry;
        }

        return null;
    }

    pub fn free(self: GitReflog) void {
        c.git_reflog_free(self.value);
    }
};

const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
const GitString = @import("types.zig").GitString;
const GitSignature = @import("signature.zig").GitSignature;
