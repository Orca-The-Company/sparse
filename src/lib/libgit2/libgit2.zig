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
pub const GitBuf = @import("types.zig").GitBuf;
pub const GitOID = @import("types.zig").GitOID;
pub const GitString = @import("types.zig").GitString;
pub const GitRepository = @import("repository.zig").GitRepository;
pub const GitReference = @import("reference.zig").GitReference;
pub const GitReferenceIterator = @import("reference.zig").GitReferenceIterator;
pub const GitWorktree = @import("worktree.zig").GitWorktree;

// TODO: Create note.zig module to wrap libgit2 notes functionality
// This should include:
// - GitNote struct with methods for creating, reading, updating, deleting notes
// - GitNoteIterator for iterating through notes
// - Functions: git_note_create, git_note_read, git_note_remove, git_note_iterator_new
// - Support for reading/writing slice parent relationships in notes
// - Error handling for note operations
pub const GitWorktreeAddOptions = @import("worktree.zig").GitWorktreeAddOptions;
pub const GitBranchType = @import("branch.zig").GitBranchType;
pub const GitBranch = @import("branch.zig").GitBranch;
pub const GitRevSpec = @import("revspec.zig").GitRevSpec;
pub const GitReflog = @import("reflog.zig").GitReflog;
pub const GitReflogEntry = @import("reflog.zig").GitReflogEntry;
pub const GitSignature = @import("signature.zig").GitSignature;
// TODO: Add git notes support for preserving slice relationships
// pub const GitNote = @import("note.zig").GitNote;
// pub const GitNoteIterator = @import("note.zig").GitNoteIterator;
pub const GitConfig = @import("config.zig").GitConfig;
pub const GitConfigEntry = @import("config.zig").GitConfigEntry;
pub const GitMerge = @import("merge.zig").GitMerge;
