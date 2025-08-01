// Implement git notes functionality for preserving slice parent relationships
// This module wraps libgit2's git notes API to provide slice relationship persistence
// that survives rebasing/squashing operations, unlike reflog-based approaches.

const std = @import("std");
const log = std.log.scoped(.git_note);
const c = @import("c.zig").c;

// Import required types from other libgit2 modules
const GitRepository = @import("repository.zig").GitRepository;
const GitString = @import("types.zig").GitString;
const GitError = @import("error.zig").GitError;
const GitOID = @import("types.zig").GitOID;
const GitSignature = @import("signature.zig").GitSignature;

// Define constants for git notes
pub const NOTES_DEFAULT_REF: []const u8 = "refs/notes/commits";

// GitNote struct to wrap libgit2 git_note operations
pub const GitNote = struct {
    value: ?*c.git_note = null,

    // Creates a git note with the provided content
    pub fn create(
        repo: GitRepository,
        commit_id: GitOID,
        note_content: []const u8,
        signature: GitSignature,
    ) !GitOID {
        var note_oid = GitOID{};

        const res = c.git_note_create(
            &note_oid.value,
            repo.value,
            signature.value,
            signature.value,
            NOTES_DEFAULT_REF.ptr,
            &commit_id.value.?,
            note_content.ptr,
            0, // allow_updates = false initially
        );

        if (res < 0) {
            if (res == c.GIT_EEXISTS) {
                // Note already exists, update it instead
                return update(repo, commit_id, note_content, signature);
            }
            log.err("Failed to create note with error code: {d}", .{res});
            return GitError.NOTE_CREATE_FAILED;
        }

        log.debug("Created note for commit {s}", .{commit_id.str()});
        return note_oid;
    }

    // Reads existing git note for a commit
    pub fn read(repo: GitRepository, commit_id: GitOID) !?GitNote {
        var note: ?*c.git_note = null;

        const res = c.git_note_read(&note, repo.value, NOTES_DEFAULT_REF.ptr, &commit_id.value.?);

        if (res < 0) {
            if (res == c.GIT_ENOTFOUND) {
                return null; // No note exists, not an error
            }
            log.err("Failed to read note with error code: {d}", .{res});
            return GitError.NOTE_READ_FAILED;
        }

        return GitNote{
            .value = note,
        };
    }

    // Updates existing note with new content
    pub fn update(
        repo: GitRepository,
        commit_id: GitOID,
        note_content: []const u8,
        signature: GitSignature,
    ) !GitOID {
        var note_oid = GitOID{};

        const res = c.git_note_create(
            &note_oid.value,
            repo.value,
            signature.value,
            signature.value,
            NOTES_DEFAULT_REF.ptr,
            &commit_id.value.?,
            note_content.ptr,
            1, // allow_updates = true
        );

        if (res < 0) {
            log.err("Failed to update note with error code: {d}", .{res});
            return GitError.NOTE_UPDATE_FAILED;
        }

        log.debug("Updated note for commit {s}", .{commit_id.str()});
        return note_oid;
    }

    // Removes git note for a commit
    pub fn remove(repo: GitRepository, commit_id: GitOID, signature: GitSignature) !void {
        const res = c.git_note_remove(
            repo.value,
            NOTES_DEFAULT_REF.ptr,
            signature.value,
            signature.value,
            &commit_id.value.?,
        );

        if (res < 0) {
            if (res == c.GIT_ENOTFOUND) {
                return; // Note doesn't exist, not an error
            }
            log.err("Failed to remove note with error code: {d}", .{res});
            return GitError.NOTE_DELETE_FAILED;
        }

        log.debug("Removed note for commit {s}", .{commit_id.str()});
    }

    // Returns the raw content of the git note
    pub fn content(self: GitNote) []const u8 {
        if (self.value) |note| {
            const c_message = c.git_note_message(note);
            return std.mem.span(c_message);
        }
        return "";
    }

    // Cleanup libgit2 resources
    pub fn free(self: GitNote) void {
        if (self.value) |note| {
            c.git_note_free(note);
        }
    }
};

// GitNoteIterator for iterating through notes
pub const GitNoteIterator = struct {
    value: ?*c.git_note_iterator = null,

    pub const NoteInfo = struct {
        note_id: GitOID,
        annotated_id: GitOID,
    };

    // Creates iterator for all notes in a repository
    pub fn init(repo: GitRepository, notes_ref: ?[]const u8) !GitNoteIterator {
        var iterator: ?*c.git_note_iterator = null;
        const ref_name = notes_ref orelse NOTES_DEFAULT_REF;

        const res = c.git_note_iterator_new(&iterator, repo.value, ref_name.ptr);

        if (res < 0) {
            log.err("Failed to create note iterator with error code: {d}", .{res});
            return GitError.NOTE_ITERATOR_FAILED;
        }

        return GitNoteIterator{
            .value = iterator,
        };
    }

    // Returns next note in iteration
    pub fn next(self: *GitNoteIterator) !?NoteInfo {
        if (self.value == null) {
            return null;
        }

        var note_id = GitOID{};
        var annotated_id = GitOID{};

        const res = c.git_note_next(&note_id.value, &annotated_id.value, self.value);

        if (res < 0) {
            if (res == c.GIT_ITEROVER) {
                return null; // End of iteration
            }
            log.err("Failed to get next note with error code: {d}", .{res});
            return GitError.NOTE_ITERATOR_FAILED;
        }

        return NoteInfo{
            .note_id = note_id,
            .annotated_id = annotated_id,
        };
    }

    // Cleanup resources
    pub fn free(self: GitNoteIterator) void {
        if (self.value) |iterator| {
            c.git_note_iterator_free(iterator);
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}
