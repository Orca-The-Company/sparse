const std = @import("std");

pub fn combine(
    comptime T: type,
    allocator: std.mem.Allocator,
    arr1: []const T,
    arr2: []const T,
) ![]T {
    var arr_list: std.ArrayListUnmanaged(T) = try std.ArrayListUnmanaged(T).initCapacity(allocator, arr1.len + arr2.len);
    for (arr1) |item| {
        try arr_list.append(allocator, item);
    }
    for (arr2) |item| {
        try arr_list.append(allocator, item);
    }
    return try arr_list.toOwnedSlice(allocator);
}

pub fn trimString(slice: []const u8, o: struct {
    values_to_strip: []const u8 = "\r\n\t ",
}) []const u8 {
    return std.mem.trim(u8, slice, o.values_to_strip);
}
