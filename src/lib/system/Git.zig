const std = @import("std");
const logger = @import("std").log.scoped(.Git);
const RunResult = std.process.Child.RunResult;

pub const Ref = struct {
    objectname: []const u8,
    refname: []const u8,
    pub fn new(o: struct {
        alloc: std.mem.Allocator,
        oname: []const u8,
        rname: []const u8,
    }) !Ref {
        logger.debug("Ref::new:: objectname:{s} refname:{s}", .{ o.oname, o.rname });

        // duping strings since we got them from RunResult which we free before returning
        const oname = try o.alloc.dupe(u8, o.oname);
        const rname = try o.alloc.dupe(u8, o.rname);

        return .{
            .objectname = oname,
            .refname = rname,
        };
    }

    pub fn free(self: Ref, alloc: std.mem.Allocator) void {
        logger.debug("Ref::free::", .{});
        alloc.free(self.objectname);
        alloc.free(self.refname);
    }
};

/// Simple wrapper around `ArrayListUnmanaged` to handle freeing easily
/// It holds the list of `Ref`
pub const Refs = struct {
    list: std.ArrayListUnmanaged(Ref),

    pub fn new(alloc: std.mem.Allocator) !Refs {
        logger.debug("Refs::new::", .{});
        return .{
            .list = try std.ArrayListUnmanaged(Ref).initCapacity(alloc, 4),
        };
    }

    pub fn free(self: *Refs, alloc: std.mem.Allocator) void {
        logger.debug("Refs::free::", .{});
        for (self.list.items) |ref| {
            ref.free(alloc);
        }
        self.list.deinit(alloc);
    }
};

pub fn getHeadRef(o: struct {
    allocator: std.mem.Allocator,
}) !Ref {
    const rr_refname = try @"rev-parse"(.{
        .allocator = o.allocator,
        .args = &.{
            "--symbolic-full-name",
            "HEAD",
        },
    });
    defer o.allocator.free(rr_refname.stderr);
    defer o.allocator.free(rr_refname.stdout);

    const rr_objectname = try @"rev-parse"(.{
        .allocator = o.allocator,
        .args = &.{
            "HEAD",
        },
    });
    defer o.allocator.free(rr_objectname.stderr);
    defer o.allocator.free(rr_objectname.stdout);

    if (rr_refname.term.Exited != 0 or rr_objectname.term.Exited != 0) {
        logger.debug("getHeadRef:: unable to determine current branch", .{});
        return SparseError.BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH;
    }

    // <objectname> <refname> # is the expected format
    const objectname = utils.trimString(rr_objectname.stdout, .{});
    const refname = utils.trimString(rr_refname.stdout, .{});
    return Ref.new(.{
        .alloc = o.allocator,
        .oname = objectname,
        .rname = refname,
    });
}

pub fn getBranchRefs(o: struct {
    alloc: std.mem.Allocator,
    withHead: bool = true,
}) !Refs {
    const refs_result = try @"show-ref"(.{
        .allocator = o.alloc,
        .args = &.{ "--branches", (if (o.withHead) "--head" else "") },
    });
    defer o.alloc.free(refs_result.stdout);
    defer o.alloc.free(refs_result.stderr);

    if (refs_result.term.Exited == 0) {
        var lines = std.mem.splitScalar(u8, refs_result.stdout, '\n');
        var refs = try Refs.new(o.alloc);
        while (lines.next()) |l| {
            const line = utils.trimString(l, .{});
            if (line.len > 0) {
                // <objectname> <refname>
                var vals = std.mem.splitScalar(u8, line, ' ');
                const ref = try Ref.new(.{
                    .alloc = o.alloc,
                    .oname = vals.first(),
                    .rname = vals.rest(),
                });
                try refs.list.append(o.alloc, ref);
            }
        }
        return refs;
    }

    logger.debug("getBranchRefs:: unable to get refs returning empty", .{});

    return try Refs.new(o.alloc);
}

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
    logger.debug("getSparseRefs:: unable to get refs", .{});
    return SparseError.BACKEND_UNABLE_TO_GET_REFS;
}
pub fn getFeatureSliceRefs(o: struct {
    alloc: std.mem.Allocator,
    feature_name: []const u8,
}) !Refs {
    const sparse_prefix = try utils.sparseBranchRefPrefix(.{
        .alloc = o.alloc,
    });
    defer o.alloc.free(sparse_prefix);
    const pattern = try std.fmt.allocPrint(
        o.alloc,
        "{s}/{s}/slice/",
        .{
            sparse_prefix,
            o.feature_name,
        },
    );
    defer o.alloc.free(pattern);

    // refs/heads/sparse/<username>/<feature_name>/slice/
    const rr = try @"for-each-ref"(.{
        .allocator = o.alloc,
        .args = &.{ "--sort=-committerdate", pattern, "--format=%(objectname) %(refname)" },
    });
    defer o.alloc.free(rr.stderr);
    defer o.alloc.free(rr.stdout);

    if (rr.term.Exited == 0) {
        var rr_iter = std.mem.splitScalar(u8, rr.stdout, '\n');
        var refs: Refs = try Refs.new(o.alloc);
        while (rr_iter.next()) |ref_line| {
            var line_iter = std.mem.splitScalar(u8, ref_line, ' ');
            const objectname = line_iter.first();
            const refname = line_iter.rest();
            try refs.list.append(o.alloc, try Ref.new(.{
                .alloc = o.alloc,
                .rname = refname,
                .oname = objectname,
            }));
        }
        return refs;
    }
    return SparseError.BACKEND_UNABLE_TO_GET_REFS;
}

pub fn branch(options: struct {
    allocator: std.mem.Allocator,
}) !RunResult {
    logger.debug("branch::", .{});
    const run_result: RunResult = try std.process.Child.run(.{
        .allocator = options.allocator,
        .argv = &.{ "git", "branch", "-vva" },
    });
    return run_result;
}

fn @"for-each-ref"(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8 = &.{},
}) !RunResult {
    logger.debug("for-each-ref:: args:{s}", .{o.args});
    const command: []const []const u8 = &.{
        "git",
        "for-each-ref",
    };

    const argv = try utils.combine([]const u8, o.allocator, command, o.args);
    defer o.allocator.free(argv);

    const run_result: RunResult = try std.process.Child.run(.{
        .allocator = o.allocator,
        .argv = argv,
    });
    return run_result;
}

fn @"show-ref"(options: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8 = &.{},
}) !RunResult {
    logger.debug("show-ref:: args:{s}", .{options.args});
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

pub fn @"rev-parse"(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
}) !RunResult {
    logger.debug("rev-parse:: args:{s}", .{o.args});
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
    logger.debug("switch:: args:{s}", .{o.args});
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

pub fn log(o: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
}) !RunResult {
    logger.debug("log:: args:{s}", .{o.args});
    const command: []const []const u8 = &.{
        "git",
        "log",
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
