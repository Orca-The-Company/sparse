const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Command = @import("cli/command.zig").Command;
const CommandError = @import("cli/command.zig").Error;

fn parse(args: [][:0]u8) !Command {
    const my_commands = @typeInfo(Command).@"union".fields;

    if (args.len < 2) {
        return CommandError.UnknownCommand;
    }

    inline for (my_commands) |c| {
        if (std.mem.eql(u8, args[1], c.name)) {
            return @field(Command, c.name);
        }
    }
    return CommandError.UnknownCommand;
}

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const command = try parse(args);
    const return_code = try command.run(allocator);
    std.process.exit(return_code);
}

test "parse a non existent command" {
    const expectEqual = std.testing.expectEqual;
    const args: [2][:0]const u8 = .{ "sparse", "boo" };
    const command = parse(@constCast(@ptrCast(&args))) catch |e| e;
    try expectEqual(CommandError.UnknownCommand, command);
}
