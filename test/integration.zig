const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.integration);
const sparse = @import("sparse");
const build_options = @import("build_options");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    log.debug(
        "main:: args={s} build_options={s} output_dir={s}",
        .{
            args,
            build_options.sparse_exe_path,
            build_options.output_dir,
        },
    );
    const repo_dir = try std.fs.path.join(allocator, &.{ build_options.output_dir, "sparse_test_repo" });
    defer allocator.free(repo_dir);
    {
        const rr = try system.system(.{
            .allocator = allocator,
            .args = &.{
                "mkdir",
                "-p",
                repo_dir,
            },
        });
        defer allocator.free(rr.stdout);
        defer allocator.free(rr.stderr);
    }
    {
        const rr = try system.git(.{
            .allocator = allocator,
            .args = &.{ "init", "." },
            .cwd = repo_dir,
        });
        defer allocator.free(rr.stdout);
        defer allocator.free(rr.stderr);
    }
    {
        const rr = try system.system(.{
            .allocator = allocator,
            .args = &.{
                "rm",
                "-r",
                repo_dir,
            },
        });
        defer allocator.free(rr.stdout);
        defer allocator.free(rr.stderr);
    }
}

const system = @import("system.zig");
