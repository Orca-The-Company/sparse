const builtin = @import("builtin");
const std = @import("std");
const RunResult = std.process.Child.RunResult;
const Allocator = std.mem.Allocator;
const assert = @import("std").debug.assert;
const log = std.log.scoped(.integration);
const sparse = @import("sparse");
const build_options = @import("build_options");

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
    // pub fn run(self: IntegrationTest, alloc: Allocator) !u8 {
    //     switch (self) {
    //         inline else => |integration_test| return integration_test.run(alloc),
    //     }
    // }
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.testing.log_level = .debug;
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

    //const sparse_test: IntegrationTest = undefined;
    //sparse_test.setup(allocator, repo_dir);
    //sparse_test.run(allocator);
    //sparse_test.teardown(allocator, repo_dir);
    // {
    //     const rr = try system.system(.{
    //         .allocator = allocator,
    //         .args = &.{
    //             "mkdir",
    //             "-p",
    //             repo_dir,
    //         },
    //     });
    //     defer allocator.free(rr.stdout);
    //     defer allocator.free(rr.stderr);
    // }
    // {
    //     const rr = try system.git(.{
    //         .allocator = allocator,
    //         .args = &.{ "init", "." },
    //         .cwd = repo_dir,
    //     });
    //     defer allocator.free(rr.stdout);
    //     defer allocator.free(rr.stderr);
    // }
    // {
    //     const rr = try system.system(.{
    //         .allocator = allocator,
    //         .args = &.{
    //             "rm",
    //             "-r",
    //             repo_dir,
    //         },
    //     });
    //     defer allocator.free(rr.stdout);
    //     defer allocator.free(rr.stderr);
    // }
}

test "Hello Integration" {
    const test_alloc = std.testing.allocator;
    const args = try std.process.argsAlloc(test_alloc);
    defer std.process.argsFree(test_alloc, args);

    const integration: IntegrationTest = undefined;
    const sparse_feature_test = @field(
        integration,
        "feature",
    );
    const data = try sparse_feature_test.setup(test_alloc, SparseFeatureTestData);
    try std.testing.expect(data.repo_dir != null);
    try sparse_feature_test.teardown(test_alloc, data);
    try std.testing.expect(true);
}

test "Hello Integration2" {
    try std.testing.expect(true);
}

const system = @import("system.zig");
const SparseFeatureTest = @import("sparse_feature_test.zig").SparseFeatureTest;
const SparseFeatureTestData = @import("sparse_feature_test.zig").TestData;
