// applets/echo.zig
//
// echo — write arguments to standard output
//
// POSIX Issue 8 Specification
// https://pubs.opengroup.org/onlinepubs/9799919799/utilities/echo.html#tag_20_37
//
const std = @import("std");
const Io = std.Io;
const constants = @import("../constants.zig");

pub fn run(init: std.process.Init, args: []const [:0]const u8) void {
    var stdout_buf: [constants.WRITE_BUF_SIZE]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    // ignore the command name
    for (args[1..], 1..) |arg, i| {
        if (args[1..].len > i) {
            _ = stdout.print("{s} ", .{arg}) catch {};
        } else {
            _ = stdout.print("{s}", .{arg}) catch {};
        }
    }
    stdout.writeByte('\n') catch {};
    stdout.flush() catch {};
}
