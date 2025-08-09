const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Command = @import("cli/command.zig").Command;
const CommandError = @import("cli/command.zig").Error;

fn getCommandDescription(command_name: []const u8) []const u8 {
    if (std.mem.eql(u8, command_name, "feature")) return "Manage feature branches and stacked workflows";
    if (std.mem.eql(u8, command_name, "slice")) return "Create and manage feature slices";
    if (std.mem.eql(u8, command_name, "status")) return "Show status information for current feature";
    if (std.mem.eql(u8, command_name, "update")) return "Update and synchronize feature branches";
    return "Unknown command";
}

fn showHelp() void {
    const writer = std.io.getStdOut().writer();

    writer.print("Sparse - A CLI tool for stacked pull request workflows\n\n", .{}) catch return;
    writer.print("USAGE:\n    sparse <command> [options]\n\n", .{}) catch return;
    writer.print("COMMANDS:\n", .{}) catch return;

    const my_commands = @typeInfo(Command).@"union".fields;
    inline for (my_commands) |c| {
        const description = getCommandDescription(c.name);
        writer.print("    {s:<12}{s}\n", .{ c.name, description }) catch return;
    }

    writer.print("\nOPTIONS:\n", .{}) catch return;
    writer.print("    --help      Show this help message\n\n", .{}) catch return;
    writer.print("For command-specific help, use:\n", .{}) catch return;
    writer.print("    sparse <command> --help\n\n", .{}) catch return;
    writer.print("Examples:\n", .{}) catch return;
    writer.print("    sparse status\n", .{}) catch return;
    writer.print("    sparse feature --help\n", .{}) catch return;
    writer.print("    sparse slice my-slice\n\n", .{}) catch return;
}

fn parse(args: [][:0]u8) !Command {
    const my_commands = @typeInfo(Command).@"union".fields;

    if (args.len < 2) {
        return CommandError.UnknownCommand;
    }

    // Check for global --help flag
    if (std.mem.eql(u8, args[1], "--help")) {
        showHelp();
        std.process.exit(0);
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

    const command = parse(args) catch |err| switch (err) {
        CommandError.UnknownCommand => {
            const stdout = std.io.getStdOut().writer();
            if (args.len >= 2) {
                stdout.print("'{s}' is not a sparse command.\n\n", .{args[1]}) catch {};
            } else {
                stdout.print("No command specified.\n\n", .{}) catch {};
            }
            stdout.print("Available commands: ", .{}) catch {};

            const my_commands = @typeInfo(Command).@"union".fields;
            inline for (my_commands, 0..) |c, i| {
                if (i > 0) stdout.print(", ", .{}) catch {};
                stdout.print("{s}", .{c.name}) catch {};
            }
            stdout.print("\n\nFor more help: sparse --help\n", .{}) catch {};
            std.process.exit(1);
        },
        else => return err,
    };
    const return_code = try command.run(allocator);
    std.process.exit(return_code);
}

test "parse a non existent command" {
    const expectEqual = std.testing.expectEqual;
    const args: [2][:0]const u8 = .{ "sparse", "boo" };
    const command = parse(@constCast(@ptrCast(&args))) catch |e| e;
    try expectEqual(CommandError.UnknownCommand, command);
}
