const std = @import("std");

pub const Error = error{
    BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH,
    BACKEND_UNABLE_TO_GET_REFS,
    CORRUPTED_FEATURE,
};

const Slice = struct {
    name: [1]GitString,
};

pub fn feature(args: struct {
    feature: Feature,
    slice: ?Slice = null,
    _options: ?struct {
        @"--to": ?Feature = .{ .name = .{"main"} },
    } = .{},
}) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print("\n===sparse-feature===\n\n", .{});
    std.debug.print("opts: feature:name:{s} slice:{any} --to:{s}\n", .{ args.feature.name, args.slice, args._options.?.@"--to".?.name });
    // once sparse branchinde olup olmadigimizi kontrol edelim
    // git show-ref --branches --head # butun branchleri ve suan ki HEAD i gormemizi
    // sagliyor
    const maybe_active_feature = try Feature.activeFeature(.{
        .allocator = allocator,
    });
    const maybe_existing_feature = try Feature.findFeatureByName(.{
        .allocator = allocator,
        .feature_name = args.feature.name[0],
    });

    if (maybe_active_feature) |active_feature| {
        defer active_feature.free(allocator);

        // I am already an active sparse feature and I want to go to a feature
        // right so lets check if it is necessary
        if (maybe_existing_feature) |feature_to_go| {
            defer feature_to_go.free(allocator);

            if (std.mem.eql(u8, feature_to_go.ref.?, active_feature.ref.?)) {
                // returning no need to do anything fancy
                return;
            } else {
                return jump(.{ .to = feature_to_go });
            }
        } else {
            const to = try Feature.new(.{
                .alloc = allocator,
                .name = args.feature.name[0],
            });
            defer to.free(allocator);
            return jump(.{
                .from = active_feature,
                .to = to,
                .create = true,
            });
        }
    } else {
        const to = try Feature.new(.{
            .alloc = allocator,
            .name = args.feature.name[0],
        });
        defer to.free(allocator);
        return jump(.{
            .to = to,
            .create = true,
        });
    }

    std.debug.print("\n====================\n", .{});
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
    from: ?Feature = null,
    to: Feature,
    create: bool = false,
}) void {
    std.debug.print("jumping from:{s} to:{s} create:{any}", .{ if (o.from) |f| f.name[0] else "null", o.to.name, o.create });
}

const GitString = @import("libgit2/types.zig").GitString;
const Feature = @import("Feature.zig");
