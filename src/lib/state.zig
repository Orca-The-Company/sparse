//! Module that manages the state of the sparse commands
const std = @import("std");
const Allocator = std.mem.Allocator;
const State = @This();
const state_dir_name = "sparse";

pub const Error = error{
    UnableToLoad,
};

pub const Update = struct {
    const file_name = "update-state";
    const Operation = enum {
        Created,
        Analyzed,
        Reparented,
        Completed,
        Failed,
    };
    const UpdateData = struct {
        feature: ?[]const u8,
        target: ?[]const u8,
        last_unmerged_slice: ?[]const u8,
        last_operation: Operation,
    };
    _data: UpdateData,
    _repo: GitRepository,

    /// Indicates whether the update is in progress
    pub fn inProgress(self: Update) bool {
        _ = self;
        // TODO: Implement update progress tracking
        // check the existence of the update in progress
        // we can use .git/sparse/update-state file to determine if
        // an update is in progress
        @panic("Not implemented");
    }

    pub fn save(self: Update) !void {
        var state_dir = try Update.stateDir(self._repo);
        defer state_dir.close();

        const file = try state_dir.createFile(file_name, .{});
        defer file.close();
        try std.zon.stringify.serialize(self._data, .{}, file.writer());
    }

    pub fn load(alloc: Allocator, repo: GitRepository) !Update {
        var state_dir = try Update.stateDir(repo);
        defer state_dir.close();
        const file = state_dir.openFile(
            file_name,
            .{ .mode = .read_only },
        ) catch |err| {
            if (err == error.FileNotFound) {
                return Update{
                    ._repo = repo,
                    ._data = UpdateData{
                        .feature = null,
                        .target = null,
                        .last_unmerged_slice = null,
                        .last_operation = .Created,
                    },
                };
            }
            return err;
        };
        defer file.close();
        const content = try file.readToEndAlloc(alloc, 4096);
        defer alloc.free(content);
        const data = try std.zon.parse.fromSlice(
            UpdateData,
            alloc,
            @ptrCast(content),
            null,
            .{},
        );
        return .{
            ._repo = repo,
            ._data = data,
        };
    }

    pub fn free(self: Update, alloc: Allocator) void {
        if (self._data.feature) |feature| {
            alloc.free(feature);
        }
        if (self._data.target) |target| {
            alloc.free(target);
        }
        if (self._data.last_unmerged_slice) |slice| {
            alloc.free(slice);
        }
    }

    fn stateDir(repo: GitRepository) !std.fs.Dir {
        var git_dir = try std.fs.openDirAbsolute(repo.commondir(), .{});
        defer git_dir.close();
        return try git_dir.makeOpenPath(state_dir_name, .{});
    }
};

const GitRepository = @import("libgit2/libgit2.zig").GitRepository;
