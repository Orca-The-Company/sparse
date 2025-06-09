const c = @import("c.zig").c;

pub const GitRepositoryState = enum(c_int) {
    git_repository_state_none = 0,
    git_repository_state_merge,
    git_repository_state_revert,
    git_repository_state_revert_sequence,
    git_repository_state_cherrypick,
    git_repository_state_cherrypick_sequence,
    git_repository_state_bisect,
    git_repository_state_rebase,
    git_repository_state_rebase_interactive,
    git_repository_state_rebase_merge,
    git_repository_state_apply_mailbox,
    git_repository_state_apply_mailbox_or_rebase,
};

pub const GitRepository = struct {
    value: ?*c.git_repository = null,

    pub fn open() !GitRepository {
        var repository: GitRepository = .{};
        const res: c_int = c.git_repository_open_ext(&repository.value, ".", c.GIT_REPOSITORY_OPEN_FROM_ENV, null);

        if (res < 0) {
            return GitError.REPOSITORY_NOT_OPEN;
        }

        return repository;
    }

    pub fn free(self: GitRepository) void {
        if (self.value) |val| {
            c.git_repository_free(val);
        }
    }

    pub fn isEmpty(self: GitRepository) !bool {
        const res: c_int = c.git_repository_is_empty(self.value);
        if (res < 0) {
            return GitError.REPOSITORY_CORRUPTED;
        } else if (res == 0) {
            return false;
        } else {
            return true;
        }
    }

    pub fn isBare(self: GitRepository) !bool {
        const res: c_int = c.git_repository_is_bare(self.value);
        return res == 1;
    }

    pub fn isWorktree(self: GitRepository) !bool {
        const res: c_int = c.git_repository_is_worktree(self.value);
        return res == 1;
    }

    pub fn path(self: GitRepository) GitString {
        return c.git_repository_path(self.value);
    }

    /// Get the path of the shared common directory for this repository.
    /// If the repository is bare, it is the root directory for the repository. If the repository is a worktree, it is the parent repo's gitdir. Otherwise, it is the gitdir.
    /// Use commondir if you want to work with .git and you are using worktrees
    pub fn commondir(self: GitRepository) GitString {
        return c.git_repository_commondir(self.value);
    }

    pub fn stateCleanup(self: GitRepository) !void {
        const res: c_int = c.git_repository_state_cleanup(self.value);
        if (res != 0) {
            return GitError.REPOSITORY_STATE_CLEANUP;
        }
    }
    pub fn state(self: GitRepository) GitRepositoryState {
        return @enumFromInt(c.git_repository_state(self.value));
    }
};

const GitError = @import("error.zig").GitError;
const GitString = @import("types.zig").GitString;
