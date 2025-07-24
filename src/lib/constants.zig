pub const BRANCH_REFS_PREFIX: []const u8 = "refs/heads/sparse/";
pub const LAST_SLICE_NAME_POINTER: []const u8 = "-1";

// TODO: Add constants for git notes functionality to preserve slice relationships
// These constants will be used for creating and reading git notes that store slice parent information
// pub const SLICE_PARENT_NOTE_PREFIX: []const u8 = "slice-parent: ";
// pub const NOTES_REF_NAMESPACE: []const u8 = "refs/notes/commits";
// pub const NOTES_PUSH_REFSPEC: []const u8 = "refs/notes/commits";
// pub const NOTES_FETCH_REFSPEC: []const u8 = "refs/notes/*:refs/notes/*";
// pub const DEFAULT_NOTES_MESSAGE_FORMAT: []const u8 = "slice-parent: {s}";
