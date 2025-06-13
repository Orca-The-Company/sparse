const Allocator = @import("std").mem.Allocator;
const RunResult = @import("std").process.Child.RunResult;
const std = @import("std");

const Feature = @This();

name: [1]GitString,
ref: GitString = undefined,

pub fn new(o: struct {
    alloc: std.mem.Allocator,
    name: GitString,
    ref: GitString = undefined,
}) !Feature {
    const dup = try o.alloc.dupe(u8, o.name);

    return Feature{
        .name = .{dup},
        .ref = try o.alloc.dupe(u8, o.ref),
    };
}

pub fn free(self: Feature, allocator: Allocator) void {
    allocator.free(self.ref);
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
    // get all refs using git
    const run_result: RunResult = try Git.getBranchRefs(.{
        .allocator = o.allocator,
    });
    defer o.allocator.free(run_result.stdout);
    defer o.allocator.free(run_result.stderr);

    // exited successfully
    if (run_result.term.Exited == 0) {
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
    }

    return null;
}

const Git = @import("system/Git.zig");
const GitString = @import("libgit2/types.zig").GitString;
const utils = @import("utils.zig");
const SparseError = @import("sparse.zig").Error;
