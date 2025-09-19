const std = @import("std");
const build_options = @import("build_options");
const log = std.log.scoped(.sparse_feature_test);
const Allocator = std.mem.Allocator;
const RunResult = std.process.Child.RunResult;
const TEST_SPARSE_USER_ID: []const u8 = "exampleUser";

pub const TestData = struct {
    repo_dir: ?[]const u8 = null,
    feature_name: ?[]const u8 = null,
    feature_to: ?[]const u8 = null,
    pub fn free(self: TestData, alloc: Allocator) void {
        if (self.repo_dir) |repo_dir| {
            alloc.free(repo_dir);
        }
    }
};
pub const TestResult = struct {
    error_context: ?struct {
        err: ?IntegrationTestError = null,
        err_msg: ?[]const u8 = "",
    } = null,
    // output: ?struct {
    //     feature_name: ?[]const u8 = null,
    //     feature_prefix: []const u8 = "refs/heads/sparse/",
    //     target: ?[]const u8 = null,
    //     user_config: ?[]const u8 = null,
    //     slice_prefix: []const u8 = "/slice/",
    //     slice_name: ?[]const u8 = null,
    // } = null,
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
        {
            const rr = try system.git(.{
                .allocator = alloc,
                .args = &.{ "init", "." },
                .cwd = data.repo_dir.?,
            });
            defer alloc.free(rr.stdout);
            defer alloc.free(rr.stderr);
            try std.testing.expect(rr.term.Exited == 0);
        }
        {
            const rr = try system.git(.{
                .allocator = alloc,
                .args = &.{ "config", "sparse.user.id", TEST_SPARSE_USER_ID },
                .cwd = data.repo_dir.?,
            });
            defer alloc.free(rr.stdout);
            defer alloc.free(rr.stderr);
        }

        log.debug(
            "sparse::feature::test:: repo_dir {s}",
            .{data.repo_dir.?},
        );

        return @as(T, data);
    }

    pub fn teardown(
        self: SparseFeatureTest,
        alloc: Allocator,
        data: TestData,
    ) !void {
        _ = self;

        std.testing.log_level = .debug;
        log.info("repo_dir {s}\n", .{data.repo_dir.?});
        const rr_temp_dir = try system.system(.{
            .allocator = alloc,
            .args = &.{
                "rm",
                "-r",
                data.repo_dir.?,
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

pub fn createFeatureStep(alloc: Allocator, data: TestData) IntegrationTestResult {
    std.testing.log_level = .debug;
    var test_result: IntegrationTestResult = .{
        .feature = .{
            .exit_code = 1,
            .error_context = .{
                .err = null,
                .err_msg = null,
            },
        },
    };
    createCommitOnTarget(alloc, data) catch {
        test_result.feature.error_context.?.err = IntegrationTestError.TERM_EXIT_FAILED;
        return test_result;
    };
    // run sparse feature [feature_name] --to = null
    const rr_sparse_feature = system.system(.{
        .allocator = alloc,
        .args = &.{
            build_options.sparse_exe_path,
            "feature",
            data.feature_name.?,
        },
        .cwd = data.repo_dir.?,
    }) catch {
        test_result.feature.error_context.?.err = IntegrationTestError.TERM_EXIT_FAILED;
        return test_result;
    };
    defer alloc.free(rr_sparse_feature.stdout);
    defer alloc.free(rr_sparse_feature.stderr);
    const rr_git_show_ref = system.git(
        .{
            .allocator = alloc,
            .args = &.{"show-ref"},
            .cwd = data.repo_dir.?,
        },
    ) catch {
        test_result.feature.error_context.?.err = IntegrationTestError.TERM_EXIT_FAILED;
        test_result.feature.error_context.?.err_msg = "git show-ref command failed";
        return test_result;
    };
    log.debug(
        "sparse::feature::test:: git show ref stderr:{s}\n",
        .{rr_git_show_ref.stdout},
    );
    defer alloc.free(rr_git_show_ref.stdout);
    defer alloc.free(rr_git_show_ref.stderr);

    // Parsing git-show-ref
    const sparce_slice = parseGitShowRefResult(
        alloc,
        rr_git_show_ref.stdout,
        data.feature_name.?,
        TEST_SPARSE_USER_ID,
    ) catch |res| {
        switch (res) {
            IntegrationTestError.SPARSE_FEATURE_NOT_FOUND => test_result.feature.error_context.?.err = IntegrationTestError.SPARSE_FEATURE_NOT_FOUND,
            IntegrationTestError.SPARSE_FEATURE_EMPTY_REF => test_result.feature.error_context.?.err = IntegrationTestError.SPARSE_FEATURE_EMPTY_REF,
            else => test_result.feature.error_context.?.err = IntegrationTestError.UNEXPECTED_ERROR,
        }

        return test_result;
    };

    log.debug(":: My Sparse Slice {s}\n", .{sparce_slice});
    if (test_result.feature.error_context.?.err == null) {
        test_result.feature.exit_code = 0;
    }
    return test_result;
}

//test facility functions (TODO: move another module later maybe?)
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

    const rr_git_add = try system.git(
        .{
            .allocator = alloc,
            .args = &.{ "add", "." },
            .cwd = data.repo_dir.?,
        },
    );
    defer alloc.free(rr_git_add.stdout);
    defer alloc.free(rr_git_add.stderr);

    const rr_git_commit = try system.git(.{
        .allocator = alloc,
        .args = &.{ "commit", "-m", "first commit" },
        .cwd = data.repo_dir.?,
    });
    defer alloc.free(rr_git_commit.stdout);
    defer alloc.free(rr_git_commit.stderr);
}

/// Attention!: this function will not be responsible to free stdout,
/// it should be done in caller side
fn parseGitShowRefResult(
    alloc: Allocator,
    stdout: []u8,
    feature_name: []const u8,
    user_config: []const u8,
) IntegrationTestError![]const u8 {
    std.testing.log_level = .debug;
    const ref_result = std.mem.trim(u8, stdout, "\n\t \r");

    const expected_sparse_slice = std.fmt.allocPrint(
        alloc,
        "refs/heads/sparse/{s}/{s}/slice/",
        .{ user_config, feature_name },
    ) catch return IntegrationTestError.SPARSE_FEATURE_NOT_FOUND;
    defer alloc.free(expected_sparse_slice);
    if (ref_result.len != 0) {
        var split_ref_result = std.mem.tokenizeAny(
            u8,
            stdout,
            " \n",
        );
        while (split_ref_result.next()) |iter| {
            log.debug("ref iter {s}\n ", .{iter});
            if (std.mem.startsWith(u8, iter, expected_sparse_slice)) {
                return iter;
            }
        }
    }
    return IntegrationTestError.SPARSE_FEATURE_NOT_FOUND;
}

const sparse = @import("sparse");
const system = @import("system.zig");
const integration_test = @import("integration.zig");
const IntegrationTestResult = integration_test.IntegrationTestResult;
const IntegrationTestError = integration_test.IntegrationTestError;
