const std = @import("std");

pub const Error = error{
    BACKEND_UNABLE_TO_DETERMINE_CURRENT_BRANCH,
    BACKEND_UNABLE_TO_GET_REFS,
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
    const f = try Feature.activeFeature(.{
        .allocator = allocator,
    });
    defer {
        if (f) |_f| {
            _f.deinit(allocator);
        }
    }

    std.debug.print("Feature:: name: {s} ref: {s}", .{ f.?.name[0], f.?.ref });

    // butun sparse sembolik refler: git rev-parse --symbolic-full-name --glob="refs/sparse/*"
    // ilk olarak hali hazirda bir sparse feature branchinde miyim kontrolu yap
    // bunun icin
    // eger feature zaten varsa o feature da bulunan son slice a zipla
    // eger feature yok ise yeni branch olustur <feature_name>/slice/<slice_name>
    //  core.notesRef and notes.displayRef
    //  git symbolic-ref -m sparse::feature:hello:slice:1:: refs/sparse/feature/hello/slice/1 refs/heads/sparse/hello/slice/1
    // get branches

    // first check all notes in git notes --ref refs/notes/sparse list
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

const GitString = @import("libgit2/types.zig").GitString;
const Feature = @import("Feature.zig");
