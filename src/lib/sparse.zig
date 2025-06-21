const std = @import("std");
const log = std.log.scoped(.sparse);

pub const Error = error{
    BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH,
    BACKEND_UNABLE_TO_GET_REFS,
    UNABLE_TO_SWITCH_BRANCHES,
    CORRUPTED_FEATURE,
};

pub fn feature(
    feature_name: []const u8,
    slice_name: ?[]const u8,
    target: []const u8,
) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    try LibGit.init();
    defer LibGit.shutdown() catch @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");

    log.debug("feature:: feature_name:{s} slice_name:{s} target:{s}", .{
        feature_name,
        if (slice_name) |s| s else "null",
        target,
    });

    const _slice = if (slice_name) |s| s else constants.LAST_SLICE_NAME_POINTER;

    // once sparse branchinde olup olmadigimizi kontrol edelim
    // git show-ref --branches --head # butun branchleri ve suan ki HEAD i gormemizi
    // sagliyor
    var maybe_active_feature = try Feature.activeFeature(.{
        .allocator = allocator,
    });
    defer {
        if (maybe_active_feature) |*f| {
            f.free(allocator);
        }
    }

    var maybe_existing_feature = try Feature.findFeatureByName(.{
        .alloc = allocator,
        .feature_name = feature_name,
    });
    defer {
        if (maybe_existing_feature) |*f| {
            f.free(allocator);
        }
    }

    if (maybe_active_feature) |*active_feature| {
        log.debug(
            "feature:: active_feature:name={s}",
            .{
                active_feature.name,
            },
        );

        // I am already an active sparse feature and I want to go to a feature
        // right so lets check if it is necessary
        if (maybe_existing_feature) |*feature_to_go| {
            log.debug(
                "feature:: feature_to_go:name={s}",
                .{
                    feature_to_go.name,
                },
            );

            if (std.mem.eql(u8, feature_to_go.name, active_feature.name)) {
                // returning no need to do anything fancy
                log.info("feature:: already in same feature({s})", .{active_feature.name});
                return;
            } else {
                return try jump(.{
                    .allocator = allocator,
                    .from = active_feature.*,
                    .to = feature_to_go,
                    .slice = _slice,
                });
            }
        } else {
            var to = try Feature.new(.{
                .alloc = allocator,
                .name = feature_name,
                .start_point = target,
            });
            defer to.free(allocator);
            return try jump(.{
                .allocator = allocator,
                .from = active_feature.*,
                .to = &to,
                .create = true,
                .slice = _slice,
            });
        }
    } else {
        if (maybe_existing_feature) |*feature_to_go| {
            return try jump(.{
                .allocator = allocator,
                .to = feature_to_go,
                .slice = _slice,
            });
        } else {
            var to = try Feature.new(.{
                .alloc = allocator,
                .name = feature_name,
                .start_point = target,
            });
            defer to.free(allocator);
            return try jump(.{
                .allocator = allocator,
                .to = &to,
                .create = true,
                .slice = _slice,
            });
        }
    }
}

pub fn slice(opts: struct {}) !void {
    _ = opts;
    std.debug.print("\n===sparse-slice===\n\n", .{});
    std.debug.print("\n====================\n", .{});
}

pub fn submit(opts: struct {}) !void {
    _ = opts;
    std.debug.print("\n===sparse-submit===\n\n", .{});
    std.debug.print("\n====================\n", .{});
}

fn jump(o: struct {
    allocator: std.mem.Allocator,
    from: ?Feature = null,
    to: *Feature,
    create: bool = false,
    slice: []const u8 = constants.LAST_SLICE_NAME_POINTER,
}) !void {
    log.debug(
        "jump:: from:{s} to:{s} slice:{s} to:start_point:{s} create:{any}",
        .{
            if (o.from) |f| f.name else "null",
            o.to.name,
            o.slice,
            if (o.to.start_point) |s| s else "null",
            o.create,
        },
    );
    try LibGit.init();
    defer LibGit.shutdown() catch {
        @panic("Oops: couldn't shutdown libgit2, something weird is cooking...");
    };
    const repo = try LibGit.GitRepository.open();
    defer repo.free();

    // TODO: handle gracefully saving things for current feature (`from`)
    // TODO: test if it is possible to use start_point as remote branch

    if (o.to.start_point) |start_point| {
        // check if start_point of `to` is valid
        const branch = GitBranch.lookup(
            repo,
            start_point,
            GitBranchType.git_branch_all,
        ) catch |err| res: {
            switch (err) {
                LibGit.GitError.GIT_ENOTFOUND => {
                    o.allocator.free(start_point);
                    o.to.start_point = null;
                    break :res GitBranch{ .ref = .{} };
                },
                else => return err,
            }
        };
        defer branch.free();
    }

    try o.to.activate(.{
        .allocator = o.allocator,
        .create = o.create,
        .slice_name = o.slice,
    });
}

const constants = @import("constants.zig");
const LibGit = @import("libgit2/libgit2.zig");
const GitString = LibGit.GitString;
const GitBranch = LibGit.GitBranch;
const GitBranchType = LibGit.GitBranchType;
const Git = @import("system/Git.zig");
const Feature = @import("Feature.zig");
const Slice = @import("slice.zig");
