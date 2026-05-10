// applets/true.zig
//
// true — return true value
//
// POSIX Issue 8 Specification
// https://pubs.opengroup.org/onlinepubs/9799919799/utilities/true.html#tag_20_127
//
const std = @import("std");

pub fn run(init: std.process.Init, args: []const [:0]const u8) void {
    _ = init;
    _ = args;
    std.process.exit(0);
}
