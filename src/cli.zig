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

fn showHelp() !void {
    //const writer = std.fs.File.stdout().writer(stdout)
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const writer = &stdout_writer.interface;
    //TODO: add error log to flush
    defer {
        writer.flush() catch {};
    }
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
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const writer = &stdout_writer.interface;
    // TODO: add err log to defer
    defer {
        writer.flush() catch {};
    }
    const my_commands = @typeInfo(Command).@"union".fields;

    if (args.len < 2) {
        return CommandError.UnknownCommand;
    }

    // Check for global --help flag
    if (std.mem.eql(u8, args[1], "--help")) {
        try showHelp();
        std.process.exit(0);
    }

    inline for (my_commands) |c| {
        if (std.mem.eql(u8, args[1], c.name)) {
            return @field(Command, c.name);
        }
    }
    return CommandError.UnknownCommand;
}

pub fn run(alloc: Allocator) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    var writer = &stdout_writer.interface;
    //TODO: add error log to flush
    defer {
        writer.flush() catch {};
    }
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const command = parse(args) catch |err| switch (err) {
        CommandError.UnknownCommand => {
            //const stdout = std.io.getStdOut().writer();
            if (args.len >= 2) {
                writer.print("'{s}' is not a sparse command.\n\n", .{args[1]}) catch {};
            } else {
                writer.print("No command specified.\n\n", .{}) catch {};
            }
            writer.print("Available commands: ", .{}) catch {};

            const my_commands = @typeInfo(Command).@"union".fields;
            inline for (my_commands, 0..) |c, i| {
                if (i > 0) writer.print(", ", .{}) catch {};
                writer.print("{s}", .{c.name}) catch {};
            }
            writer.print("\n\nFor more help: sparse --help\n", .{}) catch {};
            std.process.exit(1);
        },
        else => return err,
    };
    const return_code = try command.run(alloc);
    std.process.exit(return_code);
}
// TODO: add tests about writer
test "parse a non existent command" {
    const expectEqual = std.testing.expectEqual;
    const args: [2][:0]const u8 = .{ "sparse", "boo" };
    const command = parse(@ptrCast(@constCast(&args))) catch |e| e;
    try expectEqual(CommandError.UnknownCommand, command);
}
