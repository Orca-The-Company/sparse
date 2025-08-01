const c = @import("c.zig").c;
const log = @import("std").log.scoped(.branch);

pub const GitBranchType = enum(c_uint) {
    git_branch_local = 1,
    git_branch_remote = 2,
    git_branch_all = 3,
};

///
/// https://libgit2.org/docs/reference/main/branch/index.html
pub const GitBranch = struct {
    _ref: GitReference = undefined,

    pub fn lookup(repo: GitRepository, branch_name: GitString, branch_type: GitBranchType) !GitBranch {
        log.debug("lookup:: branch_name:{s} branch_type:{}", .{ branch_name, branch_type });
        var branch: GitBranch = .{
            ._ref = .{},
        };
        const res: c_int = c.git_branch_lookup(&branch._ref.value, repo.value, @ptrCast(branch_name), @intFromEnum(branch_type));
        if (res == c.GIT_ENOTFOUND) {
            log.err("lookup:: GIT_ENOTFOUND error occured", .{});
            return GitError.GIT_ENOTFOUND;
        } else if (res == c.GIT_EINVALIDSPEC) {
            log.err("lookup:: GIT_EINVALIDSPEC error occured", .{});
            return GitError.GIT_EINVALIDSPEC;
        } else if (res < 0) {
            log.err("lookup:: UNEXPECTED_ERROR error occured", .{});
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

    /// Takes `GitReference` ref, and returns the merge base for the given ref
    /// if we can identify it using `git_branch_upstream_merge` otherwise returns
    /// null. For details see: https://libgit2.org/docs/reference/main/branch/git_branch_upstream_merge.html
    pub fn mergeBaseRefOf(ref: GitReference) ?GitReference {
        const branch_name = ref.name();
        log.debug("mergeBaseRefOf:: branch_name:{s}", .{branch_name});
        const buf: GitBuf = .{};
        defer buf.dispose();

        const res: c_int = c.git_branch_upstream_merge(
            buf.value,
            ref._repo.value,
            @ptrCast(branch_name),
        );

        if (res != 0) {
            log.err(
                "mergeBaseRefOf:: couldn't find merge base for '{s}' res: {d}",
                .{
                    branch_name,
                    res,
                },
            );
            return null;
        }
        if (buf.value) |bval| {
            return GitReference.lookup(
                ref._repo,
                cStringToGitString(bval.ptr),
            ) catch return null;
        } else {
            return null;
        }
    }

    ///
    /// Get the branch name
    ///
    /// Given a reference object, this will check that it really is a branch
    /// (ie. it lives under "refs/heads/" or "refs/remotes/"), and return the
    /// branch part of it.
    ///
    pub fn name(self: GitBranch) !GitString {
        return try self._ref.branchName();
    }

    /// Get the upstream of a branch
    ///
    /// Given a reference, this will return a new reference object corresponding
    /// to its remote tracking branch. The reference must be a local branch.
    /// If not able to determine the remote ref by the ref object only then it
    /// tries to get it using ref_name.
    ///
    /// https://libgit2.org/docs/reference/main/branch/git_branch_upstream.html
    ///
    pub fn upstream(self: GitBranch, repo: GitRepository) !GitReference {
        return try self._ref.upstream(repo);
    }

    pub fn mergeBase(self: GitBranch) !GitBuf {
        log.debug("mergeBase:: ref.name:{s}", .{self._ref.name()});
        const buf: GitBuf = .{};

        const res: c_int = c.git_branch_upstream_merge(
            buf.value,
            self._ref._repo.value,
            @ptrCast(self._ref.name()),
        );

        if (res != 0) {
            log.err(
                "mergeBase:: unexpected error occured (res:{d})",
                .{
                    res,
                },
            );
            return GitError.UNEXPECTED_ERROR;
        }

        return buf;
    }

    pub fn free(self: GitBranch) void {
        self._ref.free();
    }
};

const GitString = @import("types.zig").GitString;
const GitBuf = @import("types.zig").GitBuf;
const cStringToGitString = @import("types.zig").cStringToGitString;
const GitError = @import("error.zig").GitError;
const GitReference = @import("reference.zig").GitReference;
const GitRepository = @import("repository.zig").GitRepository;
