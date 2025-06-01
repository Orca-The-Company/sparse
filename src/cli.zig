const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Command = @import("cli/command.zig").Command;
const CommandError = @import("cli/command.zig").Error;

fn parse(alloc: Allocator) !Command {
    //_ = alloc;
    const my_commands = @typeInfo(Command).@"union".fields;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 2) {
        return CommandError.UnknownCommand;
    }
    std.debug.print("{any}", .{@TypeOf(args[1])});
    inline for (my_commands) |c| {
        //if (std.mem.eql([:0]u8, command, c.name)) {
        std.debug.print("{s}\n", .{c.name});
        //}
    }
    return .{ .new = .{} };
}

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    const command = try parse(allocator);
    const return_code = try command.run(allocator);
    std.debug.print("return_code: {d}\n", .{return_code});
}
