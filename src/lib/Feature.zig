const Allocator = @import("std").mem.Allocator;
const RunResult = @import("std").process.Child.RunResult;
const std = @import("std");
const log = std.log.scoped(.Feature);

const Feature = @This();

name: GitString,
ref_name: GitString,
slices: ?std.ArrayList(Slice) = null,

pub fn new(o: struct {
    alloc: std.mem.Allocator,
    name: GitString,
    ref_name: ?GitString = null,
    slices: ?[]Slice = null,
}) !Feature {
    const dup = try o.alloc.dupe(u8, o.name);
    var f = Feature{
        .name = dup,
        .ref_name = if (o.ref_name) |r| try o.alloc.dupe(u8, r) else try asFeatureRefName(o.alloc, dup),
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
    allocator.free(self.ref_name);
    if (self.slices) |s| {
        for (s.items) |*i| i.free(allocator);
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
    alloc: Allocator,
}) !?Feature {
    log.debug("activeFeature::", .{});
    const head_ref = Git.getHeadRef(.{ .allocator = o.alloc }) catch |err| switch (err) {
        error.BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH => return null,
        else => return err,
    };
    defer head_ref.free(o.alloc);

    log.debug(
        "activeFeature:: head_ref:refname={s} head_ref:objectname:{s}",
        .{
            head_ref.refname,
            head_ref.objectname,
        },
    );

    // now we can search for sparse refs
    const slice_array = try Slice.getAllSlicesWith(.{
        .alloc = o.alloc,
    });
    defer {
        for (slice_array) |*s| s.free(o.alloc);
        o.alloc.free(slice_array);
    }

    for (slice_array) |slice| {
        // we are in sparse feature
        if (std.mem.eql(u8, slice.ref.name(), head_ref.refname)) {
            const our_slices = try Slice.getAllSlicesWith(.{
                .alloc = o.alloc,
                .in_feature = refNameToFeatureName(slice.ref.name()),
            });
            defer o.alloc.free(our_slices);
            const orphan_count, const forked_count = try Slice.constructLinks(
                o.alloc,
                our_slices,
            );
            if (orphan_count > 1) {
                log.warn(
                    "activeFeature:: detected more than 1 orphan slices. (orphan_count:{d})",
                    .{orphan_count},
                );
            }
            if (forked_count > 0) {
                log.warn(
                    "activeFeature:: detected more than 0 forked slices. (forked_count:{d})",
                    .{forked_count},
                );
            }

            return try Feature.new(.{
                .alloc = o.alloc,
                .name = refNameToFeatureName(slice.ref.name()),
                .slices = our_slices,
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
    // Do not free each slice since they will be freed when feature is freed
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

    const orphan_count, const forked_count = try Slice.constructLinks(
        o.alloc,
        slice_array,
    );
    if (orphan_count > 1) {
        log.warn(
            "findFeatureByName:: detected more than 1 orphan slices. (orphan_count:{d})",
            .{orphan_count},
        );
    }
    if (forked_count > 0) {
        log.warn(
            "findFeatureByName:: detected more than 0 forked slices. (forked_count:{d})",
            .{forked_count},
        );
    }
    const leaves = try Slice.leafNodes(.{ .alloc = o.alloc, .slice_pool = slice_array });
    defer o.alloc.free(leaves);
    if (leaves.len == 0) {
        log.err(
            "findFeatureByName:: couldn't find leaf slice for feature ('{s}')",
            .{o.feature_name},
        );
        return SparseError.CORRUPTED_FEATURE;
    }

    return try Feature.new(.{
        .alloc = o.alloc,
        .name = refNameToFeatureName(leaves[0].ref.name()),
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
    start_point: ?[]const u8,
}) !void {
    log.debug(
        "activate:: o:create={any} o:slice_name={s}",
        .{
            o.create,
            o.slice_name,
        },
    );

    var slice_name: []u8 = undefined;
    defer o.allocator.free(slice_name);

    if (std.mem.eql(u8, o.slice_name, constants.LAST_SLICE_NAME_POINTER)) {
        if (self.slices) |slice_array| {
            if (o.create) {
                slice_name = try std.fmt.allocPrint(
                    o.allocator,
                    "{s}/slice/{d}",
                    .{ self.ref_name, slice_array.items.len + 1 },
                );
            } else {
                if (slice_array.items.len > 0) {
                    slice_name = try std.fmt.allocPrint(
                        o.allocator,
                        "{s}",
                        .{slice_array.getLast().ref.name()},
                    );
                } else {
                    slice_name = try std.fmt.allocPrint(o.allocator, "{s}/slice/1", .{self.ref_name});
                }
            }
        } else {
            slice_name = try std.fmt.allocPrint(o.allocator, "{s}/slice/1", .{self.ref_name});
        }
    } else {
        slice_name = try std.fmt.allocPrint(o.allocator, "{s}/slice/{s}", .{ self.ref_name, o.slice_name });
    }

    log.debug("activate:: switching branch_name={s}", .{slice_name});

    var switch_args: []const []const u8 = undefined;

    if (o.create) {
        if (o.start_point) |start_point| {
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

fn asFeatureRefName(alloc: Allocator, name: []const u8) ![]const u8 {
    const result = sliceRefToFeatureRef(name);
    if (std.mem.startsWith(u8, result, "refs/heads/sparse/")) {
        // already a sparse feature name it seems
        return std.fmt.allocPrint(alloc, "{s}", .{result});
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

fn sliceRefToFeatureRef(slice_name: []const u8) []const u8 {
    log.debug("sliceRefToFeatureRef:: slice_name:{s}", .{slice_name});
    const until = std.mem.indexOf(u8, slice_name, "/slice/") orelse slice_name.len;
    return slice_name[0..until];
}

fn refNameToFeatureName(ref_name: []const u8) []const u8 {
    const ref_prefix = "refs/heads/sparse/";
    var prefix_upto = ref_prefix.len;
    log.debug("refNameToFeatureName:: ref_name:{s}", .{ref_name});

    const until = std.mem.indexOf(u8, ref_name, "/slice/") orelse ref_name.len;
    const from = std.mem.lastIndexOf(u8, ref_name, ref_prefix) orelse 0;

    if (ref_name.len < prefix_upto) {
        prefix_upto = 0;
    }

    const may_contain_userid = ref_name[(from + prefix_upto)..until];
    var slash_idx = std.mem.indexOf(u8, may_contain_userid, "/");
    if (slash_idx == null) {
        slash_idx = 0;
    } else {
        slash_idx.? += 1;
    }

    return may_contain_userid[slash_idx.?..];
}

test "asFeatureRefName" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const allocator = std.testing.allocator;
    {
        const res = try asFeatureRefName(allocator, "refs/heads/sparse/talhaHavadar/test/slice/1");
        defer allocator.free(res);
        try expectEqualStrings("refs/heads/sparse/talhaHavadar/test", res);
    }
    {
        const res = try asFeatureRefName(allocator, "test");
        defer allocator.free(res);
        try expectEqualStrings("refs/heads/sparse/talhaHavadar/test", res);
    }
}

test "sliceRefToFeatureRef" {
    const expectEqualStrings = std.testing.expectEqualStrings;

    // Standard case with userid and feature name
    {
        const res = sliceRefToFeatureRef("refs/heads/sparse/user1/featureA/slice/3");
        try expectEqualStrings("refs/heads/sparse/user1/featureA", res);
    }
    // Case with no /slice/ (should return the whole string)
    {
        const res = sliceRefToFeatureRef("refs/heads/sparse/user1/featureA");
        try expectEqualStrings("refs/heads/sparse/user1/featureA", res);
    }
    // Case with only feature name, no userid
    {
        const res = sliceRefToFeatureRef("refs/heads/sparse/featureB/slice/1");
        try expectEqualStrings("refs/heads/sparse/featureB", res);
    }
    // Case with only feature name, no /slice/
    {
        const res = sliceRefToFeatureRef("refs/heads/sparse/featureB");
        try expectEqualStrings("refs/heads/sparse/featureB", res);
    }
    // Case with just a feature name (not a full ref)
    {
        const res = sliceRefToFeatureRef("featureC/slice/2");
        try expectEqualStrings("featureC", res);
    }
    // Case with just a feature name, no /slice/
    {
        const res = sliceRefToFeatureRef("featureC");
        try expectEqualStrings("featureC", res);
    }
}

test "fuzz sliceRefToFeatureRef" {
    const expect = std.testing.expect;

    const Fuzz = struct {
        pub fn fuzzWrapper(context: @This(), input: []const u8) !void {
            _ = context;
            // The function should never crash or panic
            const result = sliceRefToFeatureRef(input);
            // Optionally, add some invariants:
            // - result should always be a slice of input or empty
            // - result.len <= input.len
            try expect(result.len <= input.len);
            // - result should not contain "/slice/" if input did
            if (std.mem.indexOf(u8, input, "/slice/")) |_| {
                try expect(std.mem.indexOf(u8, result, "/slice/") == null);
            }
        }
    };

    try std.testing.fuzz(Fuzz{}, Fuzz.fuzzWrapper, .{});
}

test "refNameToFeatureName" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    {
        const res = refNameToFeatureName("refs/heads/sparse/talhaHavadar/test/slice/");
        try expectEqualStrings("test", res);
    }
    {
        const res = refNameToFeatureName("refs/heads/sparse/test/slice/");
        try expectEqualStrings("test", res);
    }
    {
        const res = refNameToFeatureName("refs/heads/sparse/test");
        try expectEqualStrings("test", res);
    }
    {
        const res = refNameToFeatureName("refs/heads/sparse/talhaHavadar/test");
        try expectEqualStrings("test", res);
    }
    {
        const res = refNameToFeatureName("test");
        try expectEqualStrings("test", res);
    }
}

test {
    std.testing.refAllDecls(@This());
}

const constants = @import("constants.zig");
const Git = @import("system/Git.zig");
const GitString = @import("libgit2/types.zig").GitString;
const GitBranch = @import("libgit2/branch.zig").GitBranch;
const GitBranchType = @import("libgit2/branch.zig").GitBranchType;
const cStringToGitString = @import("libgit2/types.zig").cStringToGitString;
const utils = @import("utils.zig");
const Slice = @import("slice.zig").Slice;
const SparseError = @import("sparse.zig").Error;
