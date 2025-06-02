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
