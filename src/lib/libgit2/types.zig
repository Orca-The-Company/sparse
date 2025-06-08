const c = @import("c.zig").c;
const std = @import("std");

pub const GitStrArray = struct {
    value: ?c.git_strarray = null,

    pub fn dispose(self: *GitStrArray) void {
        if (self.value) |*value| {
            c.git_strarray_dispose(value);
        }
    }
    pub fn items(self: GitStrArray, alloc: std.mem.Allocator) [][*:0]const u8 {
        _ = alloc;
        if (self.value) |value| {
            return @ptrCast(value.strings[0..value.count]);
        }

        return &.{};
    }
};
