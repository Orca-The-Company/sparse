const std = @import("std");

// Global log level based on environment variable
var runtime_log_level: ?std.log.Level = null; // Default to no logs

pub const std_options: std.Options = .{
    .logFn = logFn,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // Only log if runtime_log_level is set and level meets threshold
    if (runtime_log_level) |log_level| {
        // In Zig: err=0, warn=1, info=2, debug=3
        // Lower number = higher priority, so we show messages with level <= threshold
        if (@intFromEnum(level) <= @intFromEnum(log_level)) {
            std.log.defaultLog(level, scope, format, args);
        }
    }
    // If runtime_log_level is null, no logging happens
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    // Set log level from environment variable (only if set)
    if (std.process.getEnvVarOwned(allocator, "SPARSE_LOG_LEVEL")) |log_level_str| {
        defer allocator.free(log_level_str);
        runtime_log_level = parseLogLevel(log_level_str);
    } else |_| {
        // Default to null (no logging) if env var not set
        runtime_log_level = null;
    }

    try cli.run(allocator);
}

fn parseLogLevel(level_str: []const u8) std.log.Level {
    if (std.mem.eql(u8, level_str, "debug")) return .debug;
    if (std.mem.eql(u8, level_str, "info")) return .info;
    if (std.mem.eql(u8, level_str, "warn")) return .warn;
    if (std.mem.eql(u8, level_str, "err")) return .err;
    return .err; // Default fallback
}

test {
    std.testing.refAllDecls(@This());
}

const cli = @import("cli.zig");
