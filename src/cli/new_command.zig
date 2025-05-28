const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(".new_command");

pub const Options = struct {
    pub fn help() ![]u8 {
        return "Hello Moto!";
    }
};

pub const Args = struct {
    var options: Options = .{};
    var dev: ?[]u8 = undefined;
    var target: ?[]u8 = "main";
};

pub const NewCommand = struct {

    // sparse new [options] [<dev> [<target:-main>]]
    // options:
    //  -h, --help
    pub fn run(self: NewCommand, alloc: Allocator) !u8 {
        _ = self;
        var args: Args = .{};
        var iterator = try std.process.argsWithAllocator(alloc);
        defer iterator.deinit();
        try command.parseArgs(Args, alloc, &args, iterator);
        return 0;
    }
};
