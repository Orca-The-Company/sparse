const c = @import("c.zig").c;
const log = @import("std").log.scoped(.merge);

pub const GitMerge = struct {
    pub fn base(repo: GitRepository, one: GitOID, two: GitOID) !?GitOID {
        var out = GitOID{ .value = c.git_oid{} };
        log.debug("base:: one:{s} two:{s}", .{ one.str(), two.str() });

        const res: c_int = c.git_merge_base(&out.value.?, repo.value, &one.value.?, &two.value.?);

        if (res == c.GIT_ENOTFOUND) {
            return null;
        } else if (res != 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return out;
    }
};

const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
const GitOID = @import("types.zig").GitOID;
