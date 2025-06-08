const c = @import("c.zig").c;
const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
const GitStrArray = @import("types.zig").GitStrArray;

pub const GitReferenceIterator = struct {
    value: ?*c.git_reference_iterator = null,

    pub fn create(repo: GitRepository) !GitReferenceIterator {
        var iterator: GitReferenceIterator = .{};

        const res: c_int = c.git_reference_iterator_new(&iterator.value, repo.value);
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return iterator;
    }

    pub fn fromGlob(glob: []const u8, repo: GitRepository) !GitReferenceIterator {
        var iterator: GitReferenceIterator = .{};

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
        var ref: GitReference = .{};

        const res: c_int = c.git_reference_next(&ref.value, self.value);
        if (res == c.GIT_ITEROVER) {
            return null;
        } else if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        } else {
            return ref;
        }
    }
};

pub const GitReference = struct {
    value: ?*c.git_reference = null,

    pub fn lookup(repo: GitRepository, name_to_look: [*:0]const u8) !GitReference {
        var ref: GitReference = .{};
        const res: c_int = c.git_reference_lookup(&ref.value, repo.value, name_to_look);
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

    pub fn list(repo: GitRepository) !GitStrArray {
        var str_array = GitStrArray{ .value = c.git_strarray{} };

        const res: c_int = c.git_reference_list(&str_array.value.?, repo.value);
        if (res < 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return str_array;
    }

    pub fn free(self: GitReference) void {
        if (self.value) |val| {
            c.git_reference_free(val);
        }
    }
    pub fn name(self: GitReference) [*:0]const u8 {
        return c.git_reference_name(self.value);
    }
};
