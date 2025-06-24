const std = @import("std");
const Tag = std.zig.Token.Tag;
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    try genCommands(alloc, stdout);
}

fn genCommands(alloc: std.mem.Allocator, writer: anytype) !void {
    try extractFileIntoHelp(alloc, writer, "feature_command.zig", "sparse_feature");
    try extractFileIntoHelp(alloc, writer, "slice_command.zig", "sparse_slice");
    try extractFileIntoHelp(alloc, writer, "update_command.zig", "sparse_update");
}

fn extractFileIntoHelp(alloc: Allocator, writer: anytype, comptime zig_file: []const u8, comptime const_name: []const u8) !void {
    var ast = try Ast.parse(alloc, @embedFile(zig_file), .zig);
    defer ast.deinit(alloc);
    const tokens = ast.tokens.items(.tag);
    const maybe_params_struct = findToken(ast, tokens, isParams);
    if (maybe_params_struct) |params_struct| {
        const header = try extractDocComments(alloc, ast, @intCast(params_struct.@"0" - 3), tokens);
        const content = try extractNextStruct(alloc, ast, params_struct.@"0" + 1);
        try writer.print("pub const {s} =\n", .{const_name});
        {
            var raw_lines = std.mem.splitScalar(u8, header, '\n');
            while (raw_lines.next()) |line| {
                try writer.writeAll("\\\\");
                try writer.writeAll(line);
                try writer.writeAll("\n");
            }
        }
        {
            var raw_lines = std.mem.splitScalar(u8, content, '\n');
            while (raw_lines.next()) |line| {
                try writer.writeAll("\\\\");
                try writer.writeAll(line);
                try writer.writeAll("\n");
            }
        }
        try writer.writeAll(";\n");
    }
}

/// Searches the token with given predicate function and returns index of the
/// first occurrence for the given predicate
fn findToken(ast: Ast, tokens: []Tag, predicate: *const fn ([]Tag, usize, Ast) bool) ?struct { usize } {
    for (tokens, 0..) |_, i| {
        if (!predicate(tokens, i, ast)) continue;
        return .{i};
    }
    return null;
}

fn isParams(tt: []Tag, current_index: usize, a: Ast) bool {
    if (current_index < 2) return false;
    const params_id = std.mem.eql(u8, a.tokenSlice(@intCast(current_index - 2)), "Params");
    return params_id and (tt[current_index] == .keyword_struct) and (tt[current_index - 2] == .identifier);
}

/// First token must be .l_brace
fn extractNextStruct(alloc: Allocator, ast: Ast, start_idx: usize) ![]const u8 {
    var stack = std.ArrayList(Tag).init(alloc);
    defer stack.deinit();
    var lines = std.ArrayList([]const u8).init(alloc);
    defer lines.deinit();

    const tokens = ast.tokens.items(.tag);
    for (tokens[start_idx..], start_idx..) |token, i| {
        //std.debug.print("Found {} name: {s}\n", .{ token, ast.tokenSlice(@intCast(i)) });
        if (token == .l_brace) _ = try stack.append(token);
        if (token == .r_brace) _ = stack.pop();
        if (stack.items.len == 0) break;

        // We only care about identifiers that are preceded by doc comments.
        if (token != .identifier) continue;
        if (tokens[i - 2] != .doc_comment and tokens[i - 1] != .doc_comment) continue;
        const extracted = try extractDocComments(alloc, ast, @intCast(i), tokens);
        try lines.append(extracted);
    }

    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();
    for (lines.items) |line| {
        try buffer.writer().print("{s}", .{line});
    }
    return buffer.toOwnedSlice();
}

fn extractDocComments(
    alloc: std.mem.Allocator,
    ast: std.zig.Ast,
    index: std.zig.Ast.TokenIndex,
    tokens: []std.zig.Token.Tag,
) ![]const u8 {
    // Find the first index of the doc comments. The doc comments are
    // always stacked on top of each other so we can just go backwards.
    const start_idx: usize = start_idx: for (0..index) |i| {
        const reverse_i = index - i - 1;
        const token = tokens[reverse_i];
        if (token != .doc_comment) break :start_idx reverse_i + 1;
    } else unreachable;

    // Go through and build up the lines.
    var lines = std.ArrayList([]const u8).init(alloc);
    defer lines.deinit();
    for (start_idx..index + 1) |i| {
        const token = tokens[i];
        if (token != .doc_comment) break;
        try lines.append(ast.tokenSlice(@intCast(i))[3..]);
    }

    // Convert the lines to a multiline string.
    var buffer = std.ArrayList(u8).init(alloc);
    const writer = buffer.writer();
    const prefix = findCommonPrefix(lines);
    for (lines.items) |line| {
        try writer.writeAll(line[@min(prefix, line.len)..]);
        try writer.writeAll("\n");
    }

    return buffer.toOwnedSlice();
}

fn findCommonPrefix(lines: std.ArrayList([]const u8)) usize {
    var m: usize = std.math.maxInt(usize);
    for (lines.items) |line| {
        var n: usize = std.math.maxInt(usize);
        for (line, 0..) |c, i| {
            if (c != ' ') {
                n = i;
                break;
            }
        }
        m = @min(m, n);
    }
    return m;
}
