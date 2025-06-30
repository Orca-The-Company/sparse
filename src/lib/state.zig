//! Module that manages the state of the sparse commands
const std = @import("std");
const State = @This();
const state_dir_name = "sparse";

pub const Error = error{
    UnableToLoad,
};

pub const Update = struct {
    const file_name = "update-state";
    const UpdateData = struct {
        feature: []const u8,
        target: []const u8,
        last_unmerged_slice: []const u8,
    };
    data: UpdateData,
    _repo: GitRepository,

    /// Indicates whether the update is in progress
    pub fn inProgress(self: Update) bool {
        _ = self;
        // TODO: Implement update progress tracking
        // check the existence of the update in progress
        // we can use .git/sparse/update-state file to determine if
        // an update is in progress
        @panic("Not implemented");
        return false;
    }

    pub fn save(self: Update) !void {
        _ = self;
        @panic("Not implemented");
    }

    pub fn load(alloc: std.mem.Allocator, repo: GitRepository) !Update {
        const update_state_file = try std.fs.path.join(alloc, &.{
            repo.commondir(),
            state_dir_name,
            file_name,
        });
        const file = try std.fs.openFileAbsolute(
            update_state_file,
            .{ .mode = .read_only },
        );
        const content = try file.readToEndAlloc(alloc, 4096);
        const data = try std.zon.parse.fromSlice(
            UpdateData,
            alloc,
            content,
            null,
            .{},
        );
        return .{
            ._repo = repo,
            .data = data,
        };
    }
};

const GitRepository = @import("libgit2/libgit2.zig").GitRepository;
