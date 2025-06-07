const c = @import("c.zig").c;
const GitError = @import("error.zig").GitError;

pub const GitRepositoryState = enum(c_int) {
    git_repository_state_none,
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
        c.git_repository_free(self.value);
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
    pub fn path(self: GitRepository) [*:0]const u8 {
        return c.git_repository_path(self.value);
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
