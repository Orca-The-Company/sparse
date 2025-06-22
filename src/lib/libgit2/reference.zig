const c = @import("c.zig").c;
const std = @import("std");
const log = std.log.scoped(.reference);

pub const GitReferenceIterator = struct {
    value: ?*c.git_reference_iterator = null,
    _repo: GitRepository = undefined,

    pub fn create(repo: GitRepository) !GitReferenceIterator {
        var iterator: GitReferenceIterator = .{};

        const res: c_int = c.git_reference_iterator_new(&iterator.value, repo.value);
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return iterator;
    }

    pub fn fromGlob(glob: []const u8, repo: GitRepository) !GitReferenceIterator {
        var iterator: GitReferenceIterator = .{
            ._repo = repo,
        };

        const res: c_int = c.git_reference_iterator_glob_new(&iterator.value, repo.value, @ptrCast(glob));
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return iterator;
    }

    pub fn free(self: GitReferenceIterator) void {
        c.git_reference_iterator_free(self.value);
    }

    pub fn next(self: *GitReferenceIterator) !?GitReference {
        var ref: GitReference = .{
            ._repo = self._repo,
        };

        const res: c_int = c.git_reference_next(&ref.value, self.value);
        if (res == c.GIT_ITEROVER) {
            return null;
        } else if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        } else {
            ref._reflog = try GitReflog.read(self._repo, ref.name());
            return ref;
        }
    }
};

pub const GitReference = struct {
    value: ?*c.git_reference = null,
    _repo: GitRepository = undefined,
    _reflog: GitReflog = undefined,

    /// This function is a comparison function which compares lhs' first reflog entry creation time
    /// with rhs'. When used resulting slice of `GitReference` will have earlier ref as first item.
    pub fn lessThanFn(context: void, lhs: GitReference, rhs: GitReference) bool {
        _ = context;
        const lhs_reflog_entry = lhs.reflog().entryByIndex(lhs.reflog().entrycount() - 1);
        const lhs_committer = lhs_reflog_entry.?.committer();
        const rhs_reflog_entry = rhs.reflog().entryByIndex(rhs.reflog().entrycount() - 1);
        const rhs_committer = rhs_reflog_entry.?.committer();

        return lhs_committer.value.?.when.time < rhs_committer.value.?.when.time;
    }

    pub fn lookup(repo: GitRepository, name_to_look: GitString) !GitReference {
        var ref: GitReference = .{ ._repo = repo };
        const res: c_int = c.git_reference_lookup(&ref.value, repo.value, @ptrCast(name_to_look));
        if (res == 0) {
            ref._reflog = try GitReflog.read(repo, name_to_look);
            return ref;
        } else if (res == c.GIT_ENOTFOUND) {
            return GitError.GIT_ENOTFOUND;
        } else if (res == c.GIT_EINVALIDSPEC) {
            return GitError.GIT_EINVALIDSPEC;
        } else {
            return GitError.UNEXPECTED_ERROR;
        }
    }

    pub fn list(repo: GitRepository) !GitStrArray {
        var str_array = GitStrArray{ .value = c.git_strarray{} };

        const res: c_int = c.git_reference_list(&str_array.value.?, repo.value);
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return str_array;
    }

    pub fn reflog(self: GitReference) GitReflog {
        return self._reflog;
    }

    ///Ensure the reference name is well-formed.
    ///
    ///Valid reference names must follow one of two patterns:
    ///
    ///1- Top-level names must contain only capital letters and underscores, and must begin and end with a letter. (e.g. "HEAD", "ORIG_HEAD").
    ///2- Names prefixed with "refs/" can be almost anything. You must avoid the characters '~', '^', ':', '
    ///    ', '?', '[', and '*', and the sequences ".." and "@{" which have special meaning to revparse.
    ///
    pub fn isNameValid(check_name: []const u8) !bool {
        var is_valid: c_int = undefined;

        const res: c_int = c.git_reference_name_is_valid(&is_valid, @ptrCast(check_name));
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }
        return is_valid == 1;
    }

    /// Ref: https://libgit2.org/docs/reference/main/refs/git_reference_name_to_id.html
    /// Lookup a reference by name and resolve immediately to OID.
    ///
    /// This function provides a quick way to resolve a reference name straight
    /// through to the object id that it refers to. This avoids having to allocate
    /// or free any git_reference objects for simple situations.
    ///
    /// The name will be checked for validity. See git_reference_symbolic_create()
    /// for rules about valid names.
    ///
    pub fn nameToID(repo: GitRepository, check_name: []const u8) !?GitOID {
        var oid: GitOID = .{ .value = .{} };
        const res: c_int = c.git_reference_name_to_id(&oid.value.?, repo.value, @ptrCast(check_name));
        if (res == c.GIT_ENOTFOUND) {
            return null;
        } else if (res == c.GIT_EINVALIDSPEC) {
            return GitError.GIT_EINVALIDSPEC;
        } else if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }
        return oid;
    }

    /// Ref: https://libgit2.org/docs/reference/main/refs/git_reference_target.html
    /// Get the OID pointed to by a direct reference.
    ///
    /// Only available if the reference is direct (i.e. an object id reference,
    /// not a symbolic one).
    ///
    /// To find the OID of a symbolic ref, call git_reference_resolve() and then
    /// this function (or maybe use git_reference_name_to_id() to directly resolve
    /// a reference name all the way through to an OID).
    ///
    pub fn target(self: GitReference) ?GitOID {
        const oid = c.git_reference_target(self.value);

        if (oid == null) {
            return null;
        }

        return .{ .value = oid.* };
    }

    pub fn resolve(self: GitReference) !GitReference {
        var ref: GitReference = .{};

        const res: c_int = c.git_reference_resolve(&ref.value, self.value);
        if (res != 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return ref;
    }

    pub fn free(self: GitReference) void {
        if (self.value) |val| {
            c.git_reference_free(val);
        }
    }

    pub fn name(self: GitReference) GitString {
        return cStringToGitString(c.git_reference_name(self.value));
    }

    pub fn createdFrom(self: GitReference) ?GitReference {
        log.debug("createdFrom::", .{});
        const rlog = self.reflog();
        const first_entry = rlog.entryByIndex(rlog.entrycount() - 1);
        if (first_entry == null) {
            return null;
        }
        log.debug(
            "createdFrom:: first_entry.message:{s}",
            .{first_entry.?.message()},
        );
        var iter = std.mem.splitBackwardsScalar(u8, first_entry.?.message(), ' ');
        const from = iter.first();
        // last entry can be HEAD so check for valid references
        // GitReference.lookup(self._repo, from);
        if (std.mem.eql(u8, "HEAD", from)) {
            log.err("createdFrom:: detected HEAD as source, returning null", .{});
            return null;
        }

        const branch = GitBranch.lookup(self._repo, from, GitBranchType.git_branch_all) catch {
            log.err("createdFrom:: couldn't find the branch with ref:{s}", .{from});
            return null;
        };
        return branch.ref;
    }
};

const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
const GitReflog = @import("reflog.zig").GitReflog;
const GitBranch = @import("branch.zig").GitBranch;
const GitBranchType = @import("branch.zig").GitBranchType;
const GitStrArray = @import("types.zig").GitStrArray;
const GitString = @import("types.zig").GitString;
const cStringToGitString = @import("types.zig").cStringToGitString;
const GitOID = @import("types.zig").GitOID;
