const std = @import("std");
const log = std.log.scoped(.sparse_feature_test);
const debug = std.debug.print;
const Allocator = std.mem.Allocator;
const RunResult = std.process.Child.RunResult;

const mystruct = @This();
pub const TestData = struct {
    repo_dir: ?[]const u8 = null,
    pub fn free(self: TestData, alloc: Allocator) void {
        if (self.repo_dir) |repo_dir| {
            alloc.free(repo_dir);
        }
    }
};

pub const SparseFeatureTest = struct {
    pub fn setup(
        self: SparseFeatureTest,
        alloc: Allocator,
        comptime T: anytype,
    ) !T {
        _ = self;
        var data: TestData = .{};
        //_ = alloc;
        //_ = repo_dir;
        //

        const rr_temp_dir = try system.system(.{
            .allocator = alloc,
            .args = &.{
                "mktemp",
                "-d",
            },
        });
        defer alloc.free(rr_temp_dir.stdout);
        defer alloc.free(rr_temp_dir.stderr);

        try std.testing.expect(rr_temp_dir.term.Exited == 0);
        try std.testing.expect(std.mem.eql(u8, rr_temp_dir.stderr, ""));
        try std.testing.expect(!std.mem.eql(u8, rr_temp_dir.stdout, ""));

        data.repo_dir = try alloc.dupe(u8, std.mem.trim(u8, rr_temp_dir.stdout, "\n\t \r"));
        const rr_git_init = try system.git(.{
            .allocator = alloc,
            .args = &.{ "init", "." },
            .cwd = data.repo_dir.?,
        });
        defer alloc.free(rr_git_init.stdout);
        defer alloc.free(rr_git_init.stderr);

        try std.testing.expect(rr_git_init.term.Exited == 0);
        try std.testing.expect(std.mem.eql(u8, rr_git_init.stderr, ""));
        try std.testing.expect(!std.mem.eql(u8, rr_git_init.stdout, ""));
        return @as(T, data);
    }

    pub fn teardown(
        self: SparseFeatureTest,
        alloc: Allocator,
        data: anytype,
    ) !void {
        _ = self;

        const test_data: TestData = @as(TestData, data);
        defer test_data.free(alloc);
        std.testing.log_level = .debug;
        log.info("repo_dir {s}\n", .{test_data.repo_dir.?});
        const rr_temp_dir = try system.system(.{
            .allocator = alloc,
            .args = &.{
                "rm",
                "-r",
                test_data.repo_dir.?,
            },
        });
        defer alloc.free(rr_temp_dir.stdout);
        defer alloc.free(rr_temp_dir.stderr);
    }
    // pub fn run(self: SparseFeatureTest, alloc: Allocator) !u8 {
    //     _ = self;
    //     _ = alloc;
    // }
};

const sparse = @import("sparse");
const system = @import("system.zig");
const integration_test = @import("integration.zig");
