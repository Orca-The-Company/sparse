const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Command = @import("cli/command.zig").Command;
const CommandError = @import("cli/command.zig").Error;

fn showHelp() void {
    const help_message =
        \\Sparse - A CLI tool for stacked pull request workflows
        \\
        \\USAGE:
        \\    sparse <command> [options]
        \\
        \\COMMANDS:
        \\    feature     Manage feature branches and stacked workflows
        \\    slice       Create and manage feature slices
        \\    status      Show status information for current feature
        \\    update      Update and synchronize feature branches
        \\
        \\OPTIONS:
        \\    --help      Show this help message
        \\
        \\For command-specific help, use:
        \\    sparse <command> --help
        \\
        \\Examples:
        \\    sparse status
        \\    sparse feature --help
        \\    sparse slice my-slice
        \\
    ;
    std.io.getStdOut().writer().print(help_message, .{}) catch return;
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
            std.log.err("unknown command. Try 'sparse --help' for available commands.", .{});
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
