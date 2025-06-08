const std = @import("std");
const debug = std.debug.print;
const Allocator = std.mem.Allocator;
const CheckCommand = @import("check_command.zig").CheckCommand;
const NewCommand = @import("new_command.zig").NewCommand;

pub const CString = [*:0]const u8;
pub const ArgString = [:0]u8;
pub const StringSentinel = [:0]const u8;

pub const Error = error{
    // More than 1 command detected only one command in one run is supported
    MultipleCommand,
    // Unknown command has been detected
    UnknownCommand,
    MissingArgument,
    UnexpectedArgument,
};

pub const ArgType = enum {
    Boolean,
    NonBoolean,
    Unsupported,
};

pub const Command = union(enum) {
    check: CheckCommand,
    new: NewCommand,

    pub fn run(self: Command, alloc: Allocator) !u8 {
        switch (self) {
            inline else => |command| return command.run(alloc),
        }
    }
};
pub inline fn getFields(comptime T: type) []std.builtin.Type.StructField {
    comptime var fields: []std.builtin.Type.StructField = undefined;
    fields = @constCast(@typeInfo(T).@"struct".fields);
    return fields;
}

const ArgDeserializer = struct {
    args: [][:0]u8,
    argIndex: usize,

    fn readInt(self: *ArgDeserializer, comptime T: anytype) !T {
        if (self.args.len <= self.argIndex) {
            return Error.MissingArgument;
        }
        const arg: []const u8 = self.args[self.argIndex];
        self.argIndex += 1;
        return std.fmt.parseInt(T, arg, 10) catch Error.UnexpectedArgument;
    }

    fn readPointer(self: *ArgDeserializer, comptime T: anytype) !T {
        const dupe = self.args[self.argIndex..];
        self.argIndex = self.args.len;
        return dupe;
    }

    fn readArray(self: *ArgDeserializer, comptime T: anytype) !T {
        const arrayLength = @typeInfo(T).array.len;
        if (self.argIndex + arrayLength > self.args.len) {
            return Error.MissingArgument;
        }
        const to = self.argIndex + arrayLength;
        var dupe: T = undefined;
        var dupeIndex: usize = 0;
        while (self.argIndex < to) : ({
            self.argIndex += 1;
            dupeIndex += 1;
        }) {
            dupe[dupeIndex] = self.args[self.argIndex];
        }
        return dupe;
    }

    fn readBool(self: *ArgDeserializer, comptime T: anytype) !T {
        if (self.args.len <= self.argIndex) {
            return Error.MissingArgument;
        }

        self.argIndex += 1;
        return true;
    }

    fn readOptional(self: *ArgDeserializer, comptime T: anytype) !T {
        if (self.argIndex < self.args.len) {
            const child = @typeInfo(@typeInfo(T).optional.child);
            return switch (child) {
                else => try self.read(@typeInfo(T).optional.child),
            };
        }
        return Error.MissingArgument;
    }

    fn readStruct(self: *ArgDeserializer, comptime T: anytype) !T {
        const fields = @typeInfo(T).@"struct".fields;

        var item: T = undefined;
        inline for (fields) |field| {
            @field(item, field.name) = self.read(field.type) catch |err| val: {
                if (field.defaultValue()) |default| {
                    break :val default;
                }
                return err;
            };
        }
        return item;
    }

    pub fn read(self: *ArgDeserializer, comptime T: anytype) !T {
        return switch (@typeInfo(T)) {
            .int => try self.readInt(T),
            .@"struct" => self.readStruct(T),
            .bool => try self.readBool(T),
            .pointer => self.readPointer(T),
            .array => self.readArray(T),
            .optional => self.readOptional(T),
            else => |case| @compileLog("unsupported type", case),
        };
    }
};
//pub fn getFieldByName(alloc: Allocator, comptime T: anytype, field_name: []const u8) ?struct { [:0]const u8, type } {
//    var fields_list: std.ArrayListUnmanaged(std.builtin.Type.StructField) = .empty;
//    const fields = @typeInfo(T).@"struct".fields;
//    for (fields) |field| {
//        fields_list.append(alloc, field);
//        //if (std.mem.eql(u8, field_name, field.name)) {
//        //  return .{ field.name, field.type };
//        // }
//
//    }
//    for (fields_list) |elem| {
//        if (std.mem.eql(u8, elem.name, field_name)) {
//            std.debug.print("did it work field name equal to my name {s}", field_name);
//            return .{ elem.name, elem.type };
//        }
//    }
//    //arg is not in positionals nor options
//    return null;
//}
pub fn getFieldByName(opt_fields: []std.builtin.Type.StructField, arg: []u8) struct { bool, ArgType } {
    inline for (opt_fields) |field| {
        if (std.mem.eql(u8, field.name, arg)) {
            return .{ true, switch (@typeInfo(field.type)) {
                .bool => ArgType.Boolean,
                else => ArgType.NonBoolean,
            } };
        }
    }
    return .{ false, ArgType.Unsupported };
}

pub fn splitArgs(alloc: Allocator, cli_args: [][:0]u8, opt_fields: []std.builtin.Type.StructField) !struct { std.ArrayListUnmanaged([]u8), std.ArrayListUnmanaged([]u8) } {
    var positionals: std.ArrayListUnmanaged([]u8) = .empty;
    var options: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer {
        positionals.deinit(alloc);
        options.deinit(alloc);
    }
    var index: usize = 2;
    while (index < cli_args.len) : (index += 1) {
        if (std.mem.startsWith(u8, cli_args[index], "--")) {
            const exists, const argType = getFieldByName(opt_fields, cli_args[index]);
            if (exists) {
                if (argType == ArgType.Boolean) {
                    try options.append(alloc, cli_args[index]);
                } else if (argType == ArgType.NonBoolean) {
                    try options.append(alloc, cli_args[index]);
                    if (index + 1 >= cli_args.len) {
                        return Error.MissingArgument;
                    }
                    index += 1;
                    try options.append(alloc, cli_args[index]);
                }
            }
        }
        try positionals.append(alloc, cli_args[index]);
        debug("\n{s} {d}\n", .{ cli_args[index], index });
    }
    return .{ options, positionals };
}

pub fn parsePositionals(
    comptime T: type,
    alloc: Allocator,
    dst: *T,
    args: [][:0]u8,
) !void {
    _ = alloc;
    var deserializer = ArgDeserializer{ .args = args, .argIndex = 2 };
    const result = try deserializer.read(T);
    std.debug.print("Positionals: {any}\n", .{result});
    dst.* = result;
}

test "parseArgs example options and args" {
    const expectEqual = std.testing.expectEqual;
    const ArrayList = std.ArrayList;
    const allocator = std.testing.allocator;
    const Options = struct {
        @"--target": CString = "main",
        @"--f": bool = false,
        @"-a": bool = true,

        pub fn help(self: @This()) ![]u8 {
            _ = self;
            return @constCast("Hello Moto!");
        }
    };
    const Args = struct {
        options: Options = .{},
        start: bool = false,
        after: ?bool = undefined,
        new: ?struct {
            files: ?ArrayList(CString) = undefined,
        } = undefined,
    };
    var args: Args = .{};
    const cli_args = "--f start --target dev after new a b c ddd";
    const iter = std.mem.splitAny(u8, cli_args, " ");
    try parsePositionals(Args, allocator, &args, @constCast(&iter));
    try expectEqual(true, args.start);
    try expectEqual(true, args.after);
    try expectEqual(true, args.options.@"--f");
    try expectEqual(true, args.options.@"-a");
    try expectEqual("dev", args.options.@"--target");
    try expectEqual(4, args.new.?.files.?.items.len);
    try expectEqual("ddd", args.new.?.files.?.items[3]);
    try expectEqual("b", args.new.?.files.?.items[1]);
    try expectEqual("c", args.new.?.files.?.items[2]);
    try expectEqual("a", args.new.?.files.?.items[0]);
}
