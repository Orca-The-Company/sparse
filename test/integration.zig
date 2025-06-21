const builtin = @import("builtin");
const std = @import("std");
const RunResult = std.process.Child.RunResult;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.integration);
const build_options = @import("build_options");
pub const IntegrationTestError = error{
    UNEXPECTED_ERROR,
};

pub const IntegrationTest = union(enum) {
    feature: SparseFeatureTest,
    pub fn setup(
        self: IntegrationTest,
        alloc: Allocator,
        comptime T: anytype,
    ) !T {
        switch (self) {
            inline else => |integration_test| return try integration_test.setup(
                alloc,
            ),
        }
    }

    pub fn teardown(
        self: IntegrationTest,
        alloc: Allocator,
        data: anytype,
    ) !void {
        switch (self) {
            inline else => |integration_test| return integration_test.teardown(
                alloc,
                data,
            ),
        }
    }
    pub fn run(
        self: IntegrationTest,
        alloc: Allocator,
        comptime T: anytype,
        data: T,
        comptime func: fn (Allocator, T) bool,
    ) IntegrationTestError!bool {
        switch (self) {
            inline else => |integration_test| return try integration_test.run(
                alloc,
                T,
                data,
                func,
            ),
        }
    }
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.testing.log_level = .debug;
    // log.debug(
    //     "main:: args={s} build_options={s} output_dir={s}",
    //     .{
    //         args,
    //         build_options.sparse_exe_path,
    //         build_options.output_dir,
    //     },
    // );
    const repo_dir = try std.fs.path.join(allocator, &.{ build_options.output_dir, "sparse_test_repo" });
    defer allocator.free(repo_dir);
}

// Good Wheater
test "Create Sparse Feature to default target with only feature name" {
    if (true) {
        return error.SkipZigTest;
    }
    const test_allocator = std.testing.allocator;
    const args = try std.process.argsAlloc(test_allocator);
    defer std.process.argsFree(test_allocator, args);

    const integration: IntegrationTest = undefined;
    const feature_integration = @field(
        integration,
        "feature",
    );
    const data: SparseFeatureTestData = try feature_integration.setup(
        test_allocator,
        SparseFeatureTestData,
    );
    defer data.free(test_allocator);
    _ = try feature_integration.run(
        test_allocator,
        SparseFeatureTestData,
        data,
        sparse_feature_test.createFeature,
    );
    //try feature_integration.teardown(test_allocator, data);
    try std.testing.expect(false);
}
test "Create Sparse Feature with only feature name" {
    const test_allocator = std.testing.allocator;
    const args = try std.process.argsAlloc(test_allocator);
    defer std.process.argsFree(test_allocator, args);

    const integration: IntegrationTest = undefined;
    const feature_integration = @field(
        integration,
        "feature",
    );
    const data: SparseFeatureTestData = try feature_integration.setup(
        test_allocator,
        SparseFeatureTestData,
    );
    defer data.free(test_allocator);
    _ = try feature_integration.run(
        test_allocator,
        SparseFeatureTestData,
        data,
        sparse_feature_test.createCommitOnTarget,
    );
    _ = try feature_integration.run(
        test_allocator,
        SparseFeatureTestData,
        data,
        sparse_feature_test.createFeature,
    );
    //try feature_integration.teardown(test_allocator, data);
    try std.testing.expect(true);
}

test "Hello Integration2" {
    try std.testing.expect(true);
}

const system = @import("system.zig");
const SparseFeatureTest = @import("sparse_feature_test.zig").SparseFeatureTest;
const sparse_feature_test = @import("sparse_feature_test.zig");
const SparseFeatureTestData = @import("sparse_feature_test.zig").TestData;
