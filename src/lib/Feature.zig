const Allocator = @import("std").mem.Allocator;
const RunResult = @import("std").process.Child.RunResult;
const std = @import("std");

const Feature = @This();

name: [1]GitString,
ref: ?GitString = null,
start_point: ?GitString = null,

pub fn new(o: struct {
    alloc: std.mem.Allocator,
    name: GitString,
    ref: ?GitString = null,
    start_point: ?GitString = null,
}) !Feature {
    const dup = try o.alloc.dupe(u8, o.name);

    return Feature{
        .name = .{dup},
        .ref = if (o.ref) |r| try o.alloc.dupe(u8, r) else null,
        .start_point = if (o.start_point) |s| try o.alloc.dupe(u8, s) else null,
    };
}

pub fn free(self: Feature, allocator: Allocator) void {
    if (self.ref) |r| {
        allocator.free(r);
    }
    if (self.start_point) |s| {
        allocator.free(s);
    }
    allocator.free(self.name[0]);
}

/// Looks for sparse feature in git repository by searching through refs
/// and if it finds the feature that is same as the HEAD then it returns
/// the `Feature` otherwise it returns Null.
///
/// During this search if any error occurs it returns the error.
pub fn activeFeature(o: struct {
    allocator: Allocator,
}) !?Feature {
    const head_ref = try Git.getHeadRef(.{ .allocator = o.allocator });
    defer head_ref.free(o.allocator);

    // now we can search for sparse refs
    var sparse_refs = try Git.getSparseRefs(.{
        .allocator = o.allocator,
    });
    defer sparse_refs.free(o.allocator);

    for (sparse_refs.list.items) |ref| {
        // we are in sparse feature
        if (std.mem.eql(u8, ref.objectname, head_ref.objectname)) {
            return try Feature.new(.{
                .alloc = o.allocator,
                .name = ref.refname,
                .ref = ref.objectname,
            });
        }
    }

    return null;
}

pub fn findFeatureByName(o: struct {
    allocator: Allocator,
    feature_name: []const u8,
}) !?Feature {
    // get all branch refs using git
    var branch_refs = try Git.getBranchRefs(.{
        .allocator = o.allocator,
    });
    defer branch_refs.free(o.allocator);

    // ref format: refs/heads/sparse/<username>/<feature_name>/slice/<slice_name>
    //
    const with_slice = try std.fmt.allocPrint(o.allocator, "refs/heads/sparse/{s}/{s}/slice/", .{ "havadartalha@gmail.com", o.feature_name });
    defer o.allocator.free(with_slice);
    const without_slice = try std.fmt.allocPrint(o.allocator, "refs/heads/sparse/{s}/{s}", .{ "havadartalha@gmail.com", o.feature_name });
    defer o.allocator.free(without_slice);

    for (branch_refs.list.items) |ref| {
        if (std.mem.eql(u8, ref.refname, without_slice)) {
            // found an existing branch check if it has slices
            if (std.mem.eql(u8, ref.refname, with_slice)) {
                return try Feature.new(.{
                    .alloc = o.allocator,
                    .name = ref.refname,
                    .ref = ref.objectname,
                });
            } else {
                // this is weird.
                // lets return an error for now we can think about recovery later
                return try recoverFeatureWithName();
            }
        }
    }

    return null;
}

pub fn recoverFeatureWithName() !Feature {
    // TODO: implement recovery logic
    return SparseError.CORRUPTED_FEATURE;
}

pub fn save(self: Feature) !void {
    _ = self;
}

const Git = @import("system/Git.zig");
const GitString = @import("libgit2/types.zig").GitString;
const utils = @import("utils.zig");
const SparseError = @import("sparse.zig").Error;
