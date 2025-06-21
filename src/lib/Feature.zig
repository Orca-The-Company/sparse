const Allocator = @import("std").mem.Allocator;
const RunResult = @import("std").process.Child.RunResult;
const std = @import("std");
const log = std.log.scoped(.Feature);

const Feature = @This();

name: GitString,
ref: ?GitString = null,
start_point: ?GitString = null,
slices: ?std.ArrayList(Slice) = null,

pub fn new(o: struct {
    alloc: std.mem.Allocator,
    name: GitString,
    ref: ?GitString = null,
    start_point: ?GitString = null,
    slices: ?[]Slice = null,
}) !Feature {
    const dup = try o.alloc.dupe(u8, o.name);
    var f = Feature{
        .name = dup,
        .ref = if (o.ref) |r| try o.alloc.dupe(u8, r) else null,
        .start_point = if (o.start_point) |s| try o.alloc.dupe(u8, s) else null,
    };
    if (o.slices) |s| {
        if (f.slices) |*fs| {
            try fs.appendSlice(s);
        } else {
            f.slices = try std.ArrayList(Slice).initCapacity(o.alloc, s.len);
            try f.slices.?.appendSlice(s);
        }
    }
    return f;
}

pub fn free(self: *Feature, allocator: Allocator) void {
    if (self.ref) |r| {
        allocator.free(r);
    }
    if (self.start_point) |s| {
        allocator.free(s);
    }
    if (self.slices) |s| {
        s.deinit();
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
    log.debug("activeFeature::", .{});
    const head_ref = Git.getHeadRef(.{ .allocator = o.allocator }) catch |err| switch (err) {
        error.BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH => return null,
        else => return err,
    };
    defer head_ref.free(o.allocator);

    log.debug(
        "activeFeature:: head_ref:refname={s} head_ref:objectname:{s}",
        .{
            head_ref.refname,
            head_ref.objectname,
        },
    );

    // now we can search for sparse refs
    const slice_array = try Slice.getAllSlicesWith(.{
        .alloc = o.allocator,
    });
    defer o.allocator.free(slice_array);

    for (slice_array) |slice| {
        // we are in sparse feature
        if (std.mem.eql(u8, slice.ref.name(), head_ref.refname)) {
            return try Feature.new(.{
                .alloc = o.allocator,
                .name = sliceNameToFeatureName(slice.ref.name()),
                .ref = cStringToGitString(slice.ref.target().?.str()),
            });
        }
    }

    return null;
}

pub fn findFeatureByName(o: struct {
    alloc: Allocator,
    feature_name: []const u8,
}) !?Feature {
    log.debug("findFeatureByName::", .{});
    // get all branch refs using git
    const slice_array = try Slice.getAllSlicesWith(.{
        .alloc = o.alloc,
        .in_feature = o.feature_name,
    });
    defer o.alloc.free(slice_array);

    // ref format: refs/heads/sparse/<username>/<feature_name>/slice/<slice_name>
    //
    if (slice_array.len == 0) {
        return null;
        // TODO: check if we have something with feature name but dont have slices
        // this is weird.
        // lets return an error for now we can think about recovery later
        //return try recoverFeatureWithName();
    }

    return try Feature.new(.{
        .alloc = o.alloc,
        .name = sliceNameToFeatureName(slice_array[0].ref.name()),
        .ref = cStringToGitString(slice_array[0].ref.target().?.str()),
        .slices = slice_array,
    });
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
        if (self.slices) |slice_array| {
            if (o.create) {
                slice_name = try std.fmt.allocPrint(
                    o.allocator,
                    "{s}/{d}",
                    .{ self.name, slice_array.items.len + 1 },
                );
            } else {
                if (slice_array.items.len > 0) {
                    slice_name = try std.fmt.allocPrint(
                        o.allocator,
                        "{s}",
                        .{slice_array.getLast().ref.name()},
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

fn asFeatureName(alloc: Allocator, name: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, name, "refs/heads/sparse/")) {
        // already a sparse feature name it seems
        return std.fmt.allocPrint(alloc, "{s}", .{name});
    }
    const sparse_prefix = try utils.sparseBranchRefPrefix(.{
        .alloc = alloc,
    });
    defer alloc.free(sparse_prefix);
    return try std.fmt.allocPrint(alloc, "{s}/{s}", .{
        sparse_prefix,
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
const cStringToGitString = @import("libgit2/types.zig").cStringToGitString;
const utils = @import("utils.zig");
const Slice = @import("slice.zig").Slice;
const SparseError = @import("sparse.zig").Error;
