const std = @import("std");
const Allocator = std.mem.Allocator;
const CheckCommand = @import("check_command.zig").CheckCommand;
const NewCommand = @import("new_command.zig").NewCommand;

pub const Error = error{
    // More than 1 command detected only one command in one run is supported
    MultipleCommand,
    // Unknown command has been detected
    UnknownCommand,
};

pub const Command = union(enum) {
    check: CheckCommand,
    new: NewCommand,

    pub fn run(self: Command, alloc: Allocator) !u8 {
        switch (self) {
            inline else => |command| return command.run(alloc),
        }
    }
};

pub fn parseArgs(
    comptime T: type,
    alloc: Allocator,
    dst: *T,
    iter: anytype,
) !void {
    _ = alloc;
    _ = dst;
    _ = iter;
}
