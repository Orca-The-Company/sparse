const c = @import("c.zig").c;
pub const GitBranchType = enum(c_uint) {
    git_branch_local = 1,
    git_branch_remote = 2,
    git_branch_all = 3,
};

pub const GitBranch = struct {
    ref: GitReference = undefined,

    pub fn lookup(repo: GitRepository, branch_name: GitString, branch_type: GitBranchType) !GitBranch {
        var branch: GitBranch = .{
            .ref = .{},
        };
        const res: c_int = c.git_branch_lookup(&branch.ref.value, repo.value, @ptrCast(branch_name), @intFromEnum(branch_type));
        if (res == c.GIT_ENOTFOUND) {
            return GitError.GIT_ENOTFOUND;
        } else if (res == c.GIT_EINVALIDSPEC) {
            return GitError.GIT_EINVALIDSPEC;
        } else if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }
        return branch;
    }

    pub fn isNameValid(check_name: []const u8) !bool {
        var is_valid: c_int = undefined;

        const res: c_int = c.git_branch_name_is_valid(&is_valid, @ptrCast(check_name));
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }
        return is_valid == 1;
    }
};

const GitString = @import("types.zig").GitString;
const GitError = @import("error.zig").GitError;
const GitReference = @import("reference.zig").GitReference;
const GitRepository = @import("repository.zig").GitRepository;
