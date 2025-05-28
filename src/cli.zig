const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Command = @import("cli/command.zig").Command;
const CommandError = @import("cli/command.zig").Error;

fn parse(alloc: Allocator) !Command {
    _ = alloc;
    return .{ .check = .{} };
}

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    const command = try parse(allocator);
    const return_code = try command.run(allocator);
    std.debug.print("return_code: {d}\n", .{return_code});
}
