const std = @import("std");
const log = std.log.scoped(.command);
const debug = std.debug.print;
const Allocator = std.mem.Allocator;

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
    UnknownOption,
    OptionHandledAlready,
};

pub const ArgType = enum {
    Boolean,
    NonBoolean,
    Unsupported,
};

pub const Command = union(enum) {
    feature: FeatureCommand,
    slice: SliceCommand,
    update: UpdateCommand,
    status: StatusCommand,

    pub fn run(self: Command, alloc: Allocator) !u8 {
        switch (self) {
            inline else => |command| return command.run(alloc),
        }
    }
};

const ArgDeserializer = struct {
    args: [][]u8,
    argIndex: usize,
    parsing_options: bool = false,

    fn readInt(self: *ArgDeserializer, comptime T: anytype) !T {
        if (self.args.len <= self.argIndex) {
            return Error.MissingArgument;
        }
        if (self.parsing_options) {
            self.argIndex += 1;
        }
        const arg: []const u8 = self.args[self.argIndex];
        self.argIndex += 1;
        return std.fmt.parseInt(T, arg, 10) catch Error.UnexpectedArgument;
    }

    fn readPointer(self: *ArgDeserializer, comptime T: anytype) !T {
        const dupe = self.args[self.argIndex..];
        self.argIndex = self.args.len;
        return @ptrCast(dupe);
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
            if (std.mem.eql(u8, field.name, "_options") == false) {
                @field(item, field.name) = self.read(field.type) catch |err| val: {
                    if (field.defaultValue()) |default| {
                        break :val default;
                    }
                    return err;
                };
            }
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

pub fn parseOptions(
    comptime T: type,
    alloc: Allocator,
    dst: *T,
    args: [][:0]u8,
) ![][]u8 {
    const fields = @typeInfo(T).@"struct".fields;
    var positionals: std.ArrayListUnmanaged([]u8) = .empty;
    defer positionals.deinit(alloc);

    var item: T = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (std.mem.startsWith(u8, args[index], "-")) {
            var option_handled: bool = false;
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, args[index])) {
                    option_handled = true;
                    switch (@typeInfo(field.type)) {
                        .bool => {
                            @field(item, field.name) = !field.defaultValue().?;
                        },
                        .pointer => |parent| {
                            switch (@typeInfo(parent.child)) {
                                .@"fn" => {
                                    @field(item, field.name)();
                                    return Error.OptionHandledAlready;
                                },
                                else => {
                                    if (index + 1 >= args.len) {
                                        std.log.err("missing argument for '{s}'", .{args[index]});
                                        return Error.MissingArgument;
                                    }
                                    index += 1;
                                    @field(item, field.name) = args[index];
                                },
                            }
                        },
                        else => {
                            if (index + 1 >= args.len) {
                                std.log.err("missing argument for '{s}'", .{args[index]});
                                return Error.MissingArgument;
                            }
                            index += 1;
                            @field(item, field.name) = args[index];
                        },
                    }
                }
            }
            if (!option_handled) {
                log.err("unknown option '{s}'", .{args[index]});
                return Error.UnknownOption;
            }
        } else {
            try positionals.append(alloc, args[index]);
        }
    }

    dst.* = item;
    return positionals.toOwnedSlice(alloc);
}

pub fn parsePositionals(
    comptime T: type,
    alloc: Allocator,
    dst: *T,
    args: [][]u8,
) !void {
    _ = alloc;
    const options = dst.*._options;
    var deserializer = ArgDeserializer{ .args = args, .argIndex = 2 };
    const result = try deserializer.read(T);
    dst.* = result;
    dst.*._options = options;
}

const FeatureCommand = @import("feature_command.zig").FeatureCommand;
const SliceCommand = @import("slice_command.zig").SliceCommand;
const UpdateCommand = @import("update_command.zig").UpdateCommand;
const StatusCommand = @import("status_command.zig").StatusCommand;
