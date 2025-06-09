const c = @import("c.zig").c;

pub const GitObjectType = enum(c_int) {
    /// Object can be any of the following
    GIT_OBJECT_ANY = -2,
    /// Object is invalid.
    GIT_OBJECT_INVALID = -1,
    /// A commit object.
    GIT_OBJECT_COMMIT = 1,
    /// A tree (directory listing) object.
    GIT_OBJECT_TREE = 2,
    /// A file revision object.
    GIT_OBJECT_BLOB = 3,
    /// An annotated tag object.
    GIT_OBJECT_TAG = 4,
};

pub const GitObject = struct {
    value: ?*c.git_object = null,

    ///
    /// https://libgit2.org/docs/reference/main/object/git_object_lookup.html
    /// Lookup a reference to one of the objects in a repository.
    ///
    /// The generated reference is owned by the repository and should be closed
    /// with the git_object_free method instead of free'd manually.
    ///
    /// The 'type' parameter must match the type of the object in the odb; the
    /// method will fail otherwise. The special value 'GIT_OBJECT_ANY' may be
    /// passed to let the method guess the object's type.
    //
    pub fn lookup(repo: GitRepository, lookup_id: GitOID, object_type: GitObjectType) !GitObject {
        var object = .{};

        const res: c_int = c.git_object_lookup(&object.value, repo.value, lookup_id.value, @intFromEnum(object_type));
        if (res != 0) {
            return GitError.UNEXPECTED_ERROR;
        }

        return object;
    }

    ///
    /// Close an open object
    ///
    /// This method instructs the library to close an existing object; note that
    /// git_objects are owned and cached by the repository so the object may or
    /// may not be freed after this library call, depending on how aggressive is
    /// the caching mechanism used by the repository.
    ///
    /// IMPORTANT: It is necessary to call this method when you stop using an
    /// object. Failure to do so will cause a memory leak.
    ///
    pub fn free(self: GitObject) void {
        c.git_object_free(self.value);
    }

    pub fn id(self: GitObject) ?GitOID {
        if (self.value) |val| {
            var oid: GitOID = .{ .value = .{} };
            oid.value.? = c.git_object_id(val).*;
            return oid;
        }
        return null;
    }
};

const GitError = @import("error.zig").GitError;
const GitOID = @import("types.zig").GitOID;
const GitRepository = @import("repository.zig").GitRepository;
