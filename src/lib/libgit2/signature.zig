const c = @import("c.zig").c;
const std = @import("std");

pub const GitSignature = struct {
    value: ?*c.git_signature = null,

    // Creates signature using git config (user.name and user.email)
    pub fn default(repo: GitRepository) !GitSignature {
        var signature: ?*c.git_signature = null;
        
        const res = c.git_signature_default(&signature, repo.value);
        
        if (res < 0) {
            return GitError.SIGNATURE_DEFAULT_FAILED;
        }
        
        return GitSignature{ .value = signature };
    }

    // Creates signature with current timestamp
    pub fn now(name: []const u8, email: []const u8) !GitSignature {
        var signature: ?*c.git_signature = null;
        
        const res = c.git_signature_now(&signature, name.ptr, email.ptr);
        
        if (res < 0) {
            return GitError.SIGNATURE_CREATE_FAILED;
        }
        
        return GitSignature{ .value = signature };
    }

    // Creates signature with explicit timestamp
    pub fn new(name: []const u8, email: []const u8, time: i64, offset: c_int) !GitSignature {
        var signature: ?*c.git_signature = null;
        
        const res = c.git_signature_new(&signature, name.ptr, email.ptr, time, offset);
        
        if (res < 0) {
            return GitError.SIGNATURE_CREATE_FAILED;
        }
        
        return GitSignature{ .value = signature };
    }

    pub fn free(self: GitSignature) void {
        if (self.value) |sig| {
            c.git_signature_free(sig);
        }
    }
};

const GitError = @import("error.zig").GitError;
const GitRepository = @import("repository.zig").GitRepository;
const GitString = @import("types.zig").GitString;
