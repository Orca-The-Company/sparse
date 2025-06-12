const Allocator = @import("std").mem.Allocator;
const RunResult = @import("std").process.Child.RunResult;
const std = @import("std");

const Feature = @This();

name: [1]GitString,
ref: GitString = undefined,

pub fn deinit(self: Feature, allocator: Allocator) void {
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
        var head_objectname: []const u8 = undefined;
        var lines = std.mem.splitScalar(u8, run_result.stdout, '\n');
        const head_line = utils.trimString(lines.first(), .{});

        var iter = std.mem.splitScalar(u8, head_line, ' ');
        // <objectname> <refname> # is the expected format
        const objectname = iter.first();
        const refname = iter.rest();
        if (std.mem.eql(u8, refname, "HEAD")) {
            head_objectname = objectname;
            std.debug.print("found head ref: {s}\n", .{head_objectname});
        } else {
            return SparseError.BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH;
        }

        // now we can search for sparse refs

        var sparse_refs: std.ArrayListUnmanaged([]const u8) = try Git.getSparseRefs(.{
            .allocator = o.allocator,
        });
        defer {
            for (sparse_refs.items) |i| {
                o.allocator.free(i);
            }
            sparse_refs.deinit(o.allocator);
        }

        std.debug.print("sparse refs:\n", .{});
        for (sparse_refs.items) |ref| {
            var r_iter = std.mem.splitScalar(u8, ref, ' ');
            // <objectname> <refname> # is the expected format
            const ref_objectname = r_iter.first();
            const ref_name = r_iter.rest();
            std.debug.print("head: {s} ref: {s}\n", .{ head_objectname, ref_objectname });

            // we are in sparse feature
            if (std.mem.eql(u8, ref_objectname, head_objectname)) {
                const dup = try o.allocator.dupe(u8, ref_name);
                return Feature{
                    .name = .{dup},
                    .ref = try o.allocator.dupe(u8, ref_objectname),
                };
            }
        }

        // while (lines.next()) |l| {
        //     const line = utils.trimString(l, .{});

        //     var iter = std.mem.splitScalar(u8, line, ' ');
        //     // <objectname> <refname> # is the expected format
        //     const objectname = iter.first();
        //     const refname = iter.rest();
        //     if (std.mem.eql(u8, refname, "HEAD")) {

        //     }

        //     std.debug.print("objectname: {s} - refname: {s}\n", .{ objectname, refname });
        // }
    }

    return null;
}

const Git = @import("system/Git.zig");
const GitString = @import("libgit2/types.zig").GitString;
const utils = @import("utils.zig");
const SparseError = @import("sparse.zig").Error;
