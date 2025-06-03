const std = @import("std");
const Allocator = std.mem.Allocator;
const CheckCommand = @import("check_command.zig").CheckCommand;
const NewCommand = @import("new_command.zig").NewCommand;

pub const CString = [*:0]const u8;
pub const StringSentinel = [:0]const u8;

pub const Error = error{
    // More than 1 command detected only one command in one run is supported
    MultipleCommand,
    // Unknown command has been detected
    UnknownCommand,
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

pub fn parseArgs(
    comptime T: type,
    alloc: Allocator,
    dst: *T,
    iter: anytype,
) !void {
    _ = alloc;
    // eger adam -- ya da - ile baslayan bir arguman gondermisse
    // optionlarin field ve declerationlarina bakmamiz gerekir
    // eger declaration ile match olursak calistir ve cik
    // field ile match olursak kullanicinin gonderdigi value you set et
    // ve argumanlarda donmeye devam et
    while (iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {

            // so this command has help capability
            if (@hasDecl(@TypeOf(dst.options), "help")) {
                if (std.mem.eql(u8, arg, "--help")) {
                    std.debug.print("{s}\n", .{try dst.options.help()});
                    return;
                }
            }
        } else {}
    }
    // inline for (@typeInfo(T).@"struct".fields) |field| {
    //     if (!std.mem.eql(u8, @ptrCast(field.name), "options")) {
    //         @field(T, "orphan") = "hello";
    //     }
    // }
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
    try parseArgs(Args, allocator, &args, @constCast(&iter));
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
