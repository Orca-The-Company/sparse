const c = @import("c.zig").c;

pub const GitWorktreeAddOptions = struct {
    value: ?c.git_worktree_add_options = null,

    // version: c_uint = @import("std").mem.zeroes(c_uint),
    // lock: c_int = @import("std").mem.zeroes(c_int),
    // checkout_existing: c_int = @import("std").mem.zeroes(c_int),
    // ref: ?*git_reference = @import("std").mem.zeroes(?*git_reference),
    // checkout_options: git_checkout_options = @import("std").mem.zeroes(git_checkout_options),
    pub fn create(options: struct {
        lock: bool = false,
        checkout_existing: bool = false,
        ref: ?GitReference = null,
    }) !GitWorktreeAddOptions {
        var add_options: GitWorktreeAddOptions = .{ .value = .{} };
        const res: c_int = c.git_worktree_add_options_init(&add_options.value.?, c.GIT_WORKTREE_ADD_OPTIONS_VERSION);
        if (res == 0) {
            add_options.value.?.lock = if (options.lock) 1 else 0;
            add_options.value.?.checkout_existing = if (options.checkout_existing) 1 else 0;
            if (options.ref) |ref| {
                add_options.value.?.ref = ref.value;
            }
            return add_options;
        }
        return GitError.UNEXPECTED_ERROR;
    }
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

    pub fn lookup(repo: GitRepository, name_to_look: GitString) !GitWorktree {
        var worktree: GitWorktree = .{};
        const res: c_int = c.git_worktree_lookup(&worktree.value, repo.value, @ptrCast(name_to_look));
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

    pub fn add(repo: GitRepository, name_to_add: GitString, path_to_add: GitString) !GitWorktree {
        var worktree: GitWorktree = .{};
        const res: c_int = c.git_worktree_add(
            &worktree.value,
            repo.value,
            @ptrCast(name_to_add),
            @ptrCast(path_to_add),
            null,
        );

        if (res != 0) {
            @import("std").debug.print("addWithOptions: res: {any}\n", .{res});
            return GitError.UNEXPECTED_ERROR;
        }

        return worktree;
    }

    pub fn addWithOptions(
        repo: GitRepository,
        name_to_add: GitString,
        path_to_add: GitString,
        options: GitWorktreeAddOptions,
    ) !GitWorktree {
        var worktree: GitWorktree = .{};

        const res: c_int = c.git_worktree_add(
            &worktree.value,
            repo.value,
            @ptrCast(name_to_add),
            @ptrCast(path_to_add),
            if (options.value != null) &options.value.? else null,
        );

        if (res != 0) {
            @import("std").debug.print("addWithOptions: res: {any}\n", .{res});
            return GitError.UNEXPECTED_ERROR;
        }

        return worktree;
    }

    pub fn free(self: GitWorktree) void {
        c.git_worktree_free(self.value);
    }

    pub fn name(self: GitWorktree) GitString {
        return cStringToGitString(c.git_worktree_name(self.value));
    }

    pub fn path(self: GitWorktree) GitString {
        return cStringToGitString(c.git_worktree_path(self.value));
    }

    pub fn lock(self: GitWorktree, reason: GitString) bool {
        const res: c_int = c.git_worktree_lock(self.value, @ptrCast(reason));
        return res == 0;
    }

    pub fn unlock(self: GitWorktree) bool {
        const res: c_int = c.git_worktree_unlock(self.value);
        return res == 0;
    }

    pub fn validate(self: GitWorktree) bool {
        const res: c_int = c.git_worktree_validate(self.value);
        return res == 0;
    }
};

const GitString = @import("types.zig").GitString;
const cStringToGitString = @import("types.zig").cStringToGitString;
const GitStrArray = @import("types.zig").GitStrArray;
const GitRepository = @import("repository.zig").GitRepository;
const GitReference = @import("reference.zig").GitReference;
const GitError = @import("error.zig").GitError;
