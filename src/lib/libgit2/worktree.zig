const c = @import("c.zig").c;

pub const GitWorktreeAddOptions = struct {
    value: ?c.git_worktree_add_options = null,
};
pub const GitWorktreePruneOptions = struct {
    value: ?c.git_worktree_prune_options = null,
};

pub const GitWorktree = struct {
    value: ?*c.git_worktree = null,

    pub fn list(repo: GitRepository) !GitStrArray {
        var str_array = GitStrArray{ .value = c.git_strarray{} };

        const res: c_int = c.git_worktree_list(&str_array.value.?, repo.value);
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return str_array;
    }

    pub fn lookup(repo: GitRepository, name_to_look: [*:0]const u8) !GitWorktree {
        var worktree: GitWorktree = .{};
        const res: c_int = c.git_worktree_lookup(&worktree.value, repo.value, name_to_look);
        if (res == 0) {
            return worktree;
        } else if (res == c.GIT_ENOTFOUND) {
            return GitError.GIT_ENOTFOUND;
        } else if (res == c.GIT_EINVALIDSPEC) {
            return GitError.GIT_EINVALIDSPEC;
        } else {
            return GitError.UNEXPECTED_ERROR;
        }
    }

    pub fn name(self: GitWorktree) [*:0]const u8 {
        return c.git_worktree_name(self.value);
    }

    pub fn path(self: GitWorktree) [*:0]const u8 {
        return c.git_worktree_path(self.value);
    }
};

const GitStrArray = @import("types.zig").GitStrArray;
const GitRepository = @import("repository.zig").GitRepository;
const GitError = @import("error.zig").GitError;
