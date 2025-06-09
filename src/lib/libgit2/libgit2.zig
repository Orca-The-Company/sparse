const c = @import("c.zig").c;

pub fn init() !void {
    const res: c_int = c.git_libgit2_init();
    if (res < 0) {
        return GitError.LIBGIT2_NOT_INITIALIZED;
    }
}

pub fn shutdown() !void {
    const res: c_int = c.git_libgit2_shutdown();
    if (res < 0) {
        return GitError.LIBGIT2_NOT_SHUTDOWN;
    }
}

pub const GitError = @import("error.zig").GitError;
pub const GitStrArray = @import("types.zig").GitStrArray;
pub const GitOID = @import("types.zig").GitOID;
pub const GitRepository = @import("repository.zig").GitRepository;
pub const GitReference = @import("reference.zig").GitReference;
pub const GitReferenceIterator = @import("reference.zig").GitReferenceIterator;
pub const GitWorktree = @import("worktree.zig").GitWorktree;
pub const GitWorktreeAddOptions = @import("worktree.zig").GitWorktreeAddOptions;
