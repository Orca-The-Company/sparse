const c = @import("c.zig").c;

pub const GitSignature = struct {
    value: ?c.git_signature = null,

    pub fn free(self: GitSignature) void {
        c.git_signature_free(self.value);
    }
};

const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
const GitString = @import("types.zig").GitString;
