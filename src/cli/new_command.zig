const std = @import("std");
const command = @import("command.zig");
const Allocator = @import("std").mem.Allocator;
const log = @import("std").log.scoped(".new_command");

pub const Options = struct {
    orphan: bool = false,
    pub fn help(self: Options) ![]u8 {
        return self._help();
    }
    pub fn h(self: Options) ![]u8 {
        return self._help();
    }
    fn _help(self: Options) ![]u8 {
        _ = self;
        return @constCast("Hello Moto!");
    }
};

pub const Args = struct {
    options: Options = .{},
    dev: ?[]u8 = undefined,
    target: []u8 = @constCast("main"),
};

pub const NewCommand = struct {

    // sparse new [options] [<dev> [<target:-main>]]
    // options:
    //  -h, --help
    pub fn run(self: NewCommand, alloc: Allocator) !u8 {
        _ = self;
        var args: Args = Args{};

        var iterator = try std.process.argsWithAllocator(alloc);
        defer iterator.deinit();
        try command.parseArgs(Args, alloc, &args, &iterator);
        return 0;
    }
};
