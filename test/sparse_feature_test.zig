const std = @import("std");
const build_options = @import("build_options");
const log = std.log.scoped(.sparse_feature_test);
const Allocator = std.mem.Allocator;
const RunResult = std.process.Child.RunResult;
pub const TestData = struct {
    repo_dir: ?[]const u8 = null,
    feature_name: ?[]const u8 = null,
    pub fn free(self: TestData, alloc: Allocator) void {
        if (self.repo_dir) |repo_dir| {
            alloc.free(repo_dir);
        }
    }
};
pub const TestResult = struct {
    error_context: ?struct {
        err: IntegrationTestError,
        err_msg: ?[]const u8 = "",
    } = null,
    exit_code: u8 = 1,

    pub fn status(self: TestResult) bool {
        return self.exit_code == 0;
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

        std.testing.log_level = .debug;
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
        log.debug(
            "sparse::feature::test:: repo_dir {s}",
            .{data.repo_dir.?},
        );
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
        log.info("stdout {s}\n", .{rr_temp_dir.stdout});
        defer alloc.free(rr_temp_dir.stdout);
        defer alloc.free(rr_temp_dir.stderr);

        try std.testing.expect(rr_temp_dir.term.Exited == 0);
        try std.testing.expect(std.mem.eql(u8, rr_temp_dir.stderr, ""));
        try std.testing.expect(std.mem.eql(u8, rr_temp_dir.stdout, ""));
    }
    pub fn run(
        self: SparseFeatureTest,
        alloc: Allocator,
        comptime T: anytype,
        data: T,
        comptime func: fn (Allocator, T) IntegrationTestResult,
    ) IntegrationTestResult {
        _ = self;
        return func(alloc, data);
    }
};
pub fn createFeature(alloc: Allocator, data: TestData) IntegrationTestResult {
    std.testing.log_level = .debug;
    createCommitOnTarget(alloc, data) catch return .{
        .feature = .{
            .exit_code = 1,
            .error_context = .{
                .err = IntegrationTestError.TERM_EXIT_FAILED,
            },
        },
    };
    const rr_temp_dir = system.system(.{
        .allocator = alloc,
        .args = &.{
            build_options.sparse_exe_path,
            "feature",
            "myNewFeature",
        },
        .cwd = data.repo_dir.?,
    }) catch return .{
        .feature = .{
            .exit_code = 1,
            .error_context = .{ .err = IntegrationTestError.TERM_EXIT_FAILED },
        },
    };
    defer alloc.free(rr_temp_dir.stdout);
    defer alloc.free(rr_temp_dir.stderr);
    //_ = rr_temp_dir;
    log.debug(
        "sparse::feature::test:: createFeature stdout: {s}\n stderr:{s}\n",
        .{ rr_temp_dir.stdout, rr_temp_dir.stderr },
    );
    return .{ .feature = .{ .exit_code = 0 } };
}
fn createCommitOnTarget(alloc: Allocator, data: TestData) !void {
    std.testing.log_level = .debug;
    const rr_new_file = try system.system(.{
        .allocator = alloc,
        .args = &.{
            "touch",
            "test.txt",
        },
        .cwd = data.repo_dir.?,
    });

    defer alloc.free(rr_new_file.stdout);
    defer alloc.free(rr_new_file.stderr);

    //try std.testing.expect(rr_new_file.term.Exited == 0);

    const rr_git_add = try system.git(
        .{
            .allocator = alloc,
            .args = &.{ "add", "." },
            .cwd = data.repo_dir.?,
        },
    );
    defer alloc.free(rr_git_add.stdout);
    defer alloc.free(rr_git_add.stderr);

    //try std.testing.expect(rr_git_add.term.Exited == 0);
    const rr_git_commit = try system.git(.{
        .allocator = alloc,
        .args = &.{ "commit", "-m", "first commit" },
        .cwd = data.repo_dir.?,
    });
    defer alloc.free(rr_git_commit.stdout);
    defer alloc.free(rr_git_commit.stderr);

    // return .{ .feature = .{ .exit_code = 0 } };
}
const sparse = @import("sparse");
const system = @import("system.zig");
const integration_test = @import("integration.zig");
const IntegrationTestResult = integration_test.IntegrationTestResult;
const IntegrationTestError = integration_test.IntegrationTestError;
