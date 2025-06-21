const std = @import("std");
const log = std.log.scoped(.sparse_config);

pub const SparseConfig = struct {
    /// Returns the `sparse.user.id` git config value if it exists otherwise
    /// it fallbacks to try and get `user.email` git config value and checks if
    /// the config value we got is valid branch name or not since we are using
    /// this value to create branches
    pub fn userId(alloc: std.mem.Allocator, repo: GitRepository) !GitString {
        log.debug("userId::", .{});
        const config = try GitConfig.repositoryConfig(repo);
        defer config.free();
        const sparse_user_id = config.getEntry("sparse.user.id") catch res: {
            log.warn("userId:: falling back to 'user.email'", .{});
            const val = config.getEntry("user.email") catch {
                log.err("userId:: couldnt get config 'user.email'", .{});
                return GitError.UNEXPECTED_ERROR;
            };
            break :res val;
        };
        defer sparse_user_id.free();
        const valid = try GitBranch.isNameValid(cStringToGitString(sparse_user_id.value.?.value));
        log.debug("userId:: sparse_user_id:{s} is_valid:{any}", .{ sparse_user_id.value.?.value, valid });
        if (!valid) {
            log.err("userId:: invalid 'sparse.user.id' or 'user.email' ('{s}'). See git-check-ref-format for valid options.", .{sparse_user_id.value.?.value});
            return GitError.UNEXPECTED_ERROR;
        }
        return try alloc.dupe(
            u8,
            cStringToGitString(sparse_user_id.value.?.value),
        );
    }
    pub fn setUserId(repo: GitRepository, value: GitString) void {
        _ = repo;
        _ = value;
        // TODO: people can set the `sparse.user.id` using git config command `git config sparse.user.id talhaHavadar`
    }
};

const cStringToGitString = @import("libgit2/types.zig").cStringToGitString;
const GitString = @import("libgit2/types.zig").GitString;
const GitConfig = @import("libgit2/libgit2.zig").GitConfig;
const GitRepository = @import("libgit2/libgit2.zig").GitRepository;
const GitBranch = @import("libgit2/libgit2.zig").GitBranch;
const GitError = @import("libgit2/error.zig").GitError;
