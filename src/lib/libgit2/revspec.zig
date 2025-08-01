const c = @import("c.zig").c;

/// https://libgit2.org/docs/reference/main/revparse/git_revspec.html
///
pub const GitRevSpec = struct {
    value: ?c.git_revspec = null,

    ///
    /// Parse a revision string for from, to, and intent.
    ///
    /// See man gitrevisions or
    /// http://git-scm.com/docs/git-rev-parse.html#_specifying_revisions for
    /// information on the syntax accepted.
    ///
    pub fn revparse(repo: GitRepository, spec: GitString) !GitRevSpec {
        var revspec: GitRevSpec = .{ .value = .{} };
        const res: c_int = c.git_revparse(&revspec.value.?, repo.value, @ptrCast(spec));
        if (res == c.GIT_EINVALIDSPEC) {
            return GitError.GIT_EINVALIDSPEC;
        } else if (res == c.GIT_EAMBIGUOUS) {
            return GitError.GIT_EAMBIGUOUS;
        } else if (res == c.GIT_ENOTFOUND) {
            return GitError.GIT_ENOTFOUND;
        } else if (res != 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return revspec;
    }

    // TODO: git_revparse_single
    ///
    /// Get the left hand side of a range.
    ///
    /// The left element of the revspec; must be freed by the user
    /// Call `GitRevSpec.free` to free the objects
    ///
    pub fn from(self: GitRevSpec) ?GitObject {
        if (self.value) |val| {
            if (val.from) |val_from| {
                return GitObject{ .value = val_from };
            }
        }
        return null;
    }

    ///
    /// Get the right hand side of a range.
    ///
    /// The right element of the revspec; must be freed by the user
    /// Call `GitRevSpec.free` to free the objects
    ///
    pub fn to(self: GitRevSpec) ?GitObject {
        if (self.value) |val| {
            if (val.to) |val_to| {
                return GitObject{ .value = val_to };
            }
        }
        return null;
    }

    pub fn free(self: GitRevSpec) void {
        if (self.value) |_| {
            if (self.from()) |self_from| self_from.free();
            if (self.to()) |self_to| self_to.free();
        }
    }
};

const GitString = @import("types.zig").GitString;
const GitObject = @import("object.zig").GitObject;
const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
