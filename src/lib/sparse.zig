const std = @import("std");
const log = std.log.scoped(.sparse);

pub const Error = error{
    BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH,
    BACKEND_UNABLE_TO_GET_REFS,
    UNABLE_TO_SWITCH_BRANCHES,
    CORRUPTED_FEATURE,
};

const Slice = struct {
    name: [1]GitString,
};

pub fn feature(
    feature_name: []const u8,
    slice_name: ?[]const u8,
    target: []const u8,
) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    log.debug("feature:: feature_name:{s} slice_name:{s} target:{s}", .{
        feature_name,
        if (slice_name) |s| s else "null",
        target,
    });

    const _slice = if (slice_name) |s| s else "-1";

    // once sparse branchinde olup olmadigimizi kontrol edelim
    // git show-ref --branches --head # butun branchleri ve suan ki HEAD i gormemizi
    // sagliyor
    var maybe_active_feature = try Feature.activeFeature(.{
        .allocator = allocator,
    });
    var maybe_existing_feature = try Feature.findFeatureByName(.{
        .allocator = allocator,
        .feature_name = feature_name,
    });

    if (maybe_active_feature) |*active_feature| {
        defer active_feature.free(allocator);
        log.debug(
            "feature:: active_feature:name={s}",
            .{
                active_feature.name,
            },
        );

        // I am already an active sparse feature and I want to go to a feature
        // right so lets check if it is necessary
        if (maybe_existing_feature) |*feature_to_go| {
            defer feature_to_go.free(allocator);
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
                    .to = feature_to_go.*,
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
                .to = to,
                .create = true,
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
            .to = to,
            .create = true,
            .slice = _slice,
        });
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
    to: Feature,
    create: bool = false,
    slice: []const u8 = "-1",
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
    // TODO: handle gracefully saving things for current feature (`from`)

    try o.to.save();
    // const run_result = try Git.@"switch"(.{
    //     .allocator = o.allocator,
    //     .args = &.{
    //         if (o.create) "-c" else "",
    //         o.to.name[0],
    //         if (o.to.start_point) |s| s else "",
    //     },
    // });
    // defer o.allocator.free(run_result.stderr);
    // defer o.allocator.free(run_result.stdout);

    // if (run_result.term.Exited != 0) {
    //     return Error.UNABLE_TO_SWITCH_BRANCHES;
    // }
}

const GitString = @import("libgit2/types.zig").GitString;
const Git = @import("system/Git.zig");
const Feature = @import("Feature.zig");
