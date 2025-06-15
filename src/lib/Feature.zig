const Allocator = @import("std").mem.Allocator;
const RunResult = @import("std").process.Child.RunResult;
const std = @import("std");
const log = std.log.scoped(.Feature);

const Feature = @This();

name: GitString,
ref: ?GitString = null,
start_point: ?GitString = null,
slices: ?Git.Refs = null,

pub fn new(o: struct {
    alloc: std.mem.Allocator,
    name: GitString,
    ref: ?GitString = null,
    start_point: ?GitString = null,
    slices: ?Git.Refs = null,
}) !Feature {
    const dup = try o.alloc.dupe(u8, o.name);

    return Feature{
        .name = dup,
        .ref = if (o.ref) |r| try o.alloc.dupe(u8, r) else null,
        .start_point = if (o.start_point) |s| try o.alloc.dupe(u8, s) else null,
        .slices = if (o.slices) |s| s else null,
    };
}

pub fn free(self: *Feature, allocator: Allocator) void {
    if (self.ref) |r| {
        allocator.free(r);
    }
    if (self.start_point) |s| {
        allocator.free(s);
    }
    if (self.slices) |*s| {
        s.free(allocator);
    }
    allocator.free(self.name);
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

    log.debug(
        "activeFeature:: head_ref:refname={s} head_ref:objectname:{s}",
        .{
            head_ref.refname,
            head_ref.objectname,
        },
    );

    // now we can search for sparse refs
    var sparse_refs = try Git.getSparseRefs(.{
        .allocator = o.allocator,
    });
    defer sparse_refs.free(o.allocator);

    for (sparse_refs.list.items) |ref| {
        // we are in sparse feature
        if (std.mem.eql(u8, ref.refname, head_ref.refname)) {
            return try Feature.new(.{
                .alloc = o.allocator,
                .name = sliceNameToFeatureName(ref.refname),
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
    const with_slice = try std.fmt.allocPrint(
        o.allocator,
        "{s}{s}/{s}/slice/",
        .{
            constants.BRANCH_REFS_PREFIX,
            "havadartalha@gmail.com",
            o.feature_name,
        },
    );
    defer o.allocator.free(with_slice);
    const without_slice = try std.fmt.allocPrint(
        o.allocator,
        "{s}{s}/{s}",
        .{
            constants.BRANCH_REFS_PREFIX,
            "havadartalha@gmail.com",
            o.feature_name,
        },
    );
    defer o.allocator.free(without_slice);

    for (branch_refs.list.items) |ref| {
        if (std.mem.startsWith(u8, ref.refname, without_slice)) {
            // found an existing branch check if it has slices
            if (std.mem.startsWith(u8, ref.refname, with_slice)) {
                // refs/heads/sparse/<username>/<feature_name>/slice/
                const refs = try Git.getFeatureSliceRefs(.{
                    .allocator = o.allocator,
                    .feature_name = o.feature_name,
                });

                return try Feature.new(.{
                    .alloc = o.allocator,
                    .name = without_slice,
                    .ref = ref.objectname,
                    .slices = refs,
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

pub fn activate(self: *Feature, o: struct {
    allocator: std.mem.Allocator,
    create: bool = false,
    slice_name: []const u8,
}) !void {
    log.debug(
        "activate:: o:create={any} o:slice_name={s}",
        .{
            o.create,
            o.slice_name,
        },
    );

    const sparse_name = try asFeatureName(o.allocator, self.name);
    o.allocator.free(self.name);
    self.name = sparse_name;

    var slice_name: []u8 = undefined;
    defer o.allocator.free(slice_name);

    if (std.mem.eql(u8, o.slice_name, constants.LAST_SLICE_NAME_POINTER)) {
        if (self.slices) |slice_refs| {
            if (o.create) {
                slice_name = try std.fmt.allocPrint(
                    o.allocator,
                    "{s}/{d}",
                    .{ self.name, slice_refs.list.items.len + 1 },
                );
            } else {
                if (slice_refs.list.items.len > 0) {
                    slice_name = try std.fmt.allocPrint(
                        o.allocator,
                        "{s}",
                        .{slice_refs.list.items[0].refname},
                    );
                } else {
                    slice_name = try std.fmt.allocPrint(o.allocator, "{s}/slice/1", .{self.name});
                }
            }
        } else {
            slice_name = try std.fmt.allocPrint(o.allocator, "{s}/slice/1", .{self.name});
        }
    } else {
        slice_name = try std.fmt.allocPrint(o.allocator, "{s}/slice/{s}", .{ self.name, o.slice_name });
    }

    log.debug("activate:: switching branch_name={s}", .{slice_name});

    var switch_args: []const []const u8 = undefined;

    if (o.create) {
        if (self.start_point) |start_point| {
            switch_args = &.{
                "-c",
                slice_name["refs/heads/".len..],
                start_point,
            };
        } else {
            switch_args = &.{
                "-c",
                slice_name["refs/heads/".len..],
            };
        }
    } else {
        switch_args = &.{
            slice_name["refs/heads/".len..],
        };
    }
    const rr = try Git.@"switch"(.{
        .allocator = o.allocator,
        .args = switch_args,
    });
    defer o.allocator.free(rr.stdout);
    defer o.allocator.free(rr.stderr);

    log.debug("switch result: stdout:{s} stderr:{s}", .{ rr.stdout, rr.stderr });
}

fn asFeatureName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, name, "refs/heads/sparse/")) {
        // already a sparse feature name it seems
        return std.fmt.allocPrint(allocator, "{s}", .{name});
    }
    // refs/heads/sparse/<usermail>/<feature_name>
    //
    return try std.fmt.allocPrint(allocator, "{s}{s}/{s}", .{
        constants.BRANCH_REFS_PREFIX,
        "havadartalha@gmail.com",
        name,
    });
}

fn sliceNameToFeatureName(slice_name: []const u8) []const u8 {
    log.debug("sliceNameToFeatureName:: slice_name:{s}", .{slice_name});
    const until = std.mem.indexOf(u8, slice_name, "/slice/") orelse slice_name.len;
    return slice_name[0..until];
}

const constants = @import("constants.zig");
const Git = @import("system/Git.zig");
const GitString = @import("libgit2/types.zig").GitString;
const utils = @import("utils.zig");
const SparseError = @import("sparse.zig").Error;
