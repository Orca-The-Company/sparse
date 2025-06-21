const c = @import("c.zig").c;
const log = @import("std").log.scoped(.config);

pub const GitConfigEntry = struct {
    value: ?*c.git_config_entry = null,

    pub fn free(self: GitConfigEntry) void {
        if (self.value) |val| {
            c.git_config_entry_free(val);
        }
    }
};
/// https://libgit2.org/docs/reference/main/config/index.html
pub const GitConfig = struct {
    value: ?*c.git_config = null,
    _repo: ?GitRepository = null,

    pub fn repositoryConfig(repo: GitRepository) GitError!GitConfig {
        var config = GitConfig{};
        const res: c_int = c.git_repository_config(&config.value, repo.value);
        if (res == 0) {
            config._repo = repo;
            return config;
        }
        return GitError.UNEXPECTED_ERROR;
    }

    pub fn getEntry(self: GitConfig, name: GitString) GitError!GitConfigEntry {
        log.debug("getEntry:: name:{s}", .{name});
        var entry: GitConfigEntry = .{};
        const res: c_int = c.git_config_get_entry(&entry.value, self.value, @ptrCast(name));
        if (res == 0) {
            return entry;
        }
        return GitError.UNEXPECTED_ERROR;
    }

    pub fn free(self: GitConfig) void {
        c.git_config_free(self.value);
    }
};

const GitRepository = @import("repository.zig").GitRepository;
const GitString = @import("types.zig").GitString;
const GitError = @import("error.zig").GitError;
