const std = @import("std");

pub fn combine(
    comptime T: type,
    allocator: std.mem.Allocator,
    arr1: []const T,
    arr2: []const T,
) ![]T {
    var all = try allocator.alloc(T, arr1.len + arr2.len);
    @memcpy(all[0..arr1.len], arr1);
    @memcpy(all[arr1.len..], arr2);
    return all;
}

pub fn trimString(slice: []const u8, o: struct {
    values_to_strip: []const u8 = "\r\n\t ",
}) []const u8 {
    return std.mem.trim(u8, slice, o.values_to_strip);
}
