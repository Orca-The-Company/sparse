const std = @import("std");
const build_options = @import("build_options");
const log = std.log.scoped(.sparse_feature_test);
const Allocator = std.mem.Allocator;
const RunResult = std.process.Child.RunResult;
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
        err: IntegrationTestError,
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
pub fn createFeatureStep(alloc: Allocator, data: TestData) IntegrationTestResult {
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
            data.feature_name.?,
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
    // log.debug(
    //     "sparse::feature::test:: createFeature stderr:{s}\n",
    //     .{rr_temp_dir.stderr},
    // );
    const rr_git_show_ref = system.git(
        .{
            .allocator = alloc,
            .args = &.{"show-ref"},
            .cwd = data.repo_dir.?,
        },
    ) catch return .{
        .feature = .{
            .exit_code = 1,
            .error_context = .{
                .err = IntegrationTestError.TERM_EXIT_FAILED,
                .err_msg = "git show-ref command failed.",
            },
        },
    };
    const ref_target, const sparce_slice = parseGitShowRefResult(
        alloc,
        rr_git_show_ref.stdout,
    ) catch |res| switch (res) {
        IntegrationTestError.SPARSE_FEATURE_NOT_FOUND => return .{
            .feature = .{
                .exit_code = 1,
                .error_context = .{
                    .err = IntegrationTestError.SPARSE_FEATURE_NOT_FOUND,
                },
            },
        },
        IntegrationTestError.SPARSE_FEATURE_EMPTY_REF => return .{
            .feature = .{
                .exit_code = 1,
                .error_context = .{
                    .err = IntegrationTestError.SPARSE_FEATURE_EMPTY_REF,
                },
            },
        },
        else => return .{
            .feature = .{
                .exit_code = 1,
                .error_context = .{
                    .err = IntegrationTestError.UNEXPECTED_ERROR,
                },
            },
        },
    };
    _ = ref_target;
    _ = sparce_slice;
    defer alloc.free(rr_git_show_ref.stdout);
    defer alloc.free(rr_git_show_ref.stderr);
    return .{ .feature = .{ .exit_code = 0 } };
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
fn parseGitShowRefResult(alloc: Allocator, stdout: []u8) IntegrationTestError!struct { []const u8, []const u8 } {
    // Attention!: this function will not be responsible to free stdout,
    // it should be done in caller side
    _ = alloc;

    // log.debug(
    //     "SparseFeatureTest::createFeature stderr:{s}\n",
    //     .{stdout},
    // );

    const ref_result = std.mem.trim(u8, stdout, "\n\t \r");

    // log.debug(
    //     "::parseGitShowRefResult :{s}\n",
    //     .{ref_result},
    // );
    var ref_target: ?[]const u8 = null;
    var sparse_slice: ?[]const u8 = null;
    if (ref_result.len != 0) {
        var split_ref_result = std.mem.tokenizeAny(
            u8,
            stdout,
            " \n",
        );
        while (split_ref_result.next()) |iter| {
            if (ref_target != null and sparse_slice != null) {
                break;
            }
            if (std.mem.startsWith(u8, iter, "refs/heads/")) {
                if (std.mem.containsAtLeast(u8, iter, 1, "sparse")) {
                    sparse_slice = iter;
                } else {
                    ref_target = iter;
                }
            }
        }
        // else {
        //     ref_target = null;
        //     sparse_slice = null;
        //     return IntegrationTestError.SPARSE_FEATURE_EMPTY_REF_ERROR;
        // }

        return .{ ref_target.?, sparse_slice.? };
    }
    if (ref_target == null) {
        return IntegrationTestError.SPARSE_FEATURE_EMPTY_REF;
    }
    if (sparse_slice == null) {
        return IntegrationTestError.SPARSE_FEATURE_NOT_FOUND;
    }
    // split_ref_result.reset();
    // while (split_ref_result.index < split_ref_result.buffer.len) : (split_ref_result.index += 1) {

    //     _ = split_ref_result.next().?;
    //     const ref_target = split_ref_result.next().?;
    //     _ = split_ref_result.next().?;
    //     const sparse_slice = split_ref_result.next().?;
    //     log.debug(
    //         "SparseFeatureTest::createFeature stderr: target:{s}\n slice: {s}\n",
    //         .{ ref_target, sparse_slice },
    //     );
    // }
    // }
    return IntegrationTestError.SPARSE_FEATURE_NOT_FOUND;
}
const sparse = @import("sparse");
const system = @import("system.zig");
const integration_test = @import("integration.zig");
const IntegrationTestResult = integration_test.IntegrationTestResult;
const IntegrationTestError = integration_test.IntegrationTestError;
