const c = @import("c.zig").c;
const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;

pub const GitReference = struct {
    value: ?*c.git_reference = null,

    pub fn lookup(repo: GitRepository, name: [*:0]const u8) !GitReference {
        var ref: GitReference = .{};
        const res: c_int = c.git_reference_lookup(&ref.value, repo.value, name);
        if (res == 0) {
            return ref;
        } else if (res == c.GIT_ENOTFOUND) {
            return GitError.GIT_ENOTFOUND;
        } else if (res == c.GIT_EINVALIDSPEC) {
            return GitError.GIT_EINVALIDSPEC;
        } else {
            return GitError.UNEXPECTED_ERROR;
        }
    }
};
