const std = @import("std");
const log = @import("std").log.scoped(.Git);
const RunResult = std.process.Child.RunResult;

pub const Ref = struct {
    objectname: []const u8,
    refname: []const u8,
    pub fn new(o: struct {
        alloc: std.mem.Allocator,
        oname: []const u8,
        rname: []const u8,
    }) !Ref {
        log.debug("Ref::new:: objectname:{s} refname:{s}", .{ o.oname, o.rname });

        // duping strings since we got them from RunResult which we free before returning
        const oname = try o.alloc.dupe(u8, o.oname);
        const rname = try o.alloc.dupe(u8, o.rname);

        return .{
            .objectname = oname,
            .refname = rname,
        };
    }

    pub fn free(self: Ref, alloc: std.mem.Allocator) void {
        log.debug("Ref::free::", .{});
        alloc.free(self.objectname);
        alloc.free(self.refname);
    }
};

/// Simple wrapper around `ArrayListUnmanaged` to handle freeing easily
/// It holds the list of `Ref`
pub const Refs = struct {
    list: std.ArrayListUnmanaged(Ref),

    pub fn new(alloc: std.mem.Allocator) !Refs {
        log.debug("Refs::new::", .{});
        return .{
            .list = try std.ArrayListUnmanaged(Ref).initCapacity(alloc, 4),
        };
    }

    pub fn free(self: *Refs, alloc: std.mem.Allocator) void {
        log.debug("Refs::free::", .{});
        for (self.list.items) |ref| {
            ref.free(alloc);
        }
        self.list.deinit(alloc);
    }
};

pub fn getHeadRef(o: struct {
    allocator: std.mem.Allocator,
}) !Ref {
    var branch_refs = try getBranchRefs(.{
        .allocator = o.allocator,
    });
    defer branch_refs.free(o.allocator);
    if (branch_refs.list.items.len == 0) {
        log.debug("getHeadRef:: unable to determine current branch", .{});
        return SparseError.BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH;
    }

    // <objectname> <refname> # is the expected format
    const objectname = branch_refs.list.items[0].objectname;
    const refname = branch_refs.list.items[0].refname;
    if (std.mem.eql(u8, refname, "HEAD")) {
        return Ref.new(.{
            .alloc = o.allocator,
            .oname = objectname,
            .rname = refname,
        });
    } else {
        log.debug("getHeadRef:: unable to determine current branch", .{});
        return SparseError.BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH;
    }
}

pub fn getBranchRefs(o: struct {
    allocator: std.mem.Allocator,
    withHead: bool = true,
}) !Refs {
    const refs_result = try @"show-ref"(.{
        .allocator = o.allocator,
        .args = &.{ "--branches", (if (o.withHead) "--head" else "") },
    });
    defer o.allocator.free(refs_result.stdout);
    defer o.allocator.free(refs_result.stderr);

    if (refs_result.term.Exited == 0) {
        var lines = std.mem.splitScalar(u8, refs_result.stdout, '\n');
        var refs = try Refs.new(o.allocator);
        while (lines.next()) |l| {
            const line = utils.trimString(l, .{});
            if (line.len > 0) {
                // <objectname> <refname>
                var vals = std.mem.splitScalar(u8, line, ' ');
                const ref = try Ref.new(.{
                    .alloc = o.allocator,
                    .oname = vals.first(),
                    .rname = vals.rest(),
                });
                try refs.list.append(o.allocator, ref);
            }
        }
        return refs;
    }

    log.debug("getBranchRefs:: unable to get refs", .{});
    return SparseError.BACKEND_UNABLE_TO_GET_REFS;
}

/// git rev-parse --symbolic-full-name --glob="refs/sparse/*"
pub fn getSparseRefs(o: struct {
    allocator: std.mem.Allocator,
}) !Refs {
    const refs_result = try @"show-ref"(.{
        .allocator = o.allocator,
    });
    defer o.allocator.free(refs_result.stdout);
    defer o.allocator.free(refs_result.stderr);

    if (refs_result.term.Exited == 0) {
        var lines = std.mem.splitScalar(u8, refs_result.stdout, '\n');
        var refs = try Refs.new(o.allocator);
        while (lines.next()) |l| {
            const line = utils.trimString(l, .{});
            // ref format: refs/heads/sparse/<username>/<feature_name>/slice/<slice_name>
            if (std.mem.count(
                u8,
                line,
                constants.BRANCH_REFS_PREFIX,
            ) > 0) {
                // <objectname> <refname>
                var vals = std.mem.splitScalar(u8, line, ' ');
                try refs.list.append(o.allocator, try Ref.new(.{
                    .alloc = o.allocator,
                    .oname = vals.first(),
                    .rname = vals.rest(),
                }));
            }
        }
        return refs;
    }
    log.debug("getSparseRefs:: unable to get refs", .{});
    return SparseError.BACKEND_UNABLE_TO_GET_REFS;
}

pub fn branch(options: struct {
    allocator: std.mem.Allocator,
}) !RunResult {
    log.debug("branch::", .{});
    const run_result: RunResult = try std.process.Child.run(.{
        .allocator = options.allocator,
        .argv = &.{ "git", "branch", "-vva" },
    });
    return run_result;
}

fn @"show-ref"(options: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8 = &.{},
}) !RunResult {
    log.debug("show-ref:: args:{s}", .{options.args});
    const command: []const []const u8 = &.{
        "git",
        "show-ref",
    };

    const argv = try utils.combine([]const u8, options.allocator, command, options.args);
    defer options.allocator.free(argv);

    const run_result: RunResult = try std.process.Child.run(.{
        .allocator = options.allocator,
        .argv = argv,
    });
    return run_result;
}

fn @"rev-parse"(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
}) !RunResult {
    log.debug("rev-parse:: args:{s}", .{o.args});
    const command: []const []const u8 = &.{
        "git",
        "rev-parse",
    };
    const argv = try utils.combine([]const u8, o.allocator, command, o.args);
    defer o.allocator.free(argv);

    return try std.process.Child.run(.{
        .allocator = o.allocator,
        .argv = argv,
    });
}

pub fn @"switch"(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
}) !RunResult {
    log.debug("switch:: args:{s}", .{o.args});
    const command: []const []const u8 = &.{
        "git",
        "switch",
    };
    const argv = try utils.combine([]const u8, o.allocator, command, o.args);
    defer o.allocator.free(argv);

    return try std.process.Child.run(.{
        .allocator = o.allocator,
        .argv = argv,
    });
}

const constants = @import("../constants.zig");
const utils = @import("../utils.zig");
const SparseError = @import("../sparse.zig").Error;
