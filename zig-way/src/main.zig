const std = @import("std");
const applets = @import("applets.zig");

const BIN_NAME = "ziggybox";

pub fn main(init: std.process.Init) !void {
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const bn = std.fs.path.basename(args[0]);
    const as_ziggybox = std.mem.eql(u8, bn, BIN_NAME);

    if (as_ziggybox and args.len < 2) {
        try stderr.print("{s}: applet not specified\n", .{BIN_NAME});
        try stderr.flush();
        std.process.exit(1);
    }

    const applet_name = if (as_ziggybox) args[1] else bn;
    const applet_args = if (as_ziggybox) args[1..] else args;

    const applet = std.meta.stringToEnum(applets.Applet, applet_name) orelse {
        try stderr.print("{s}: unknown applet '{s}'\n", .{ BIN_NAME, applet_name });
        try stderr.flush();
        std.process.exit(1);
    };
    // _ = try stderr.print("Calling {s} as {s}\n", .{ applet_name, applet_args[0] });
    // _ = try stderr.print("args:", .{});
    // for (applet_args) |arg| {
    //     _ = try stderr.print(" {s}", .{arg});
    // }
    // try stderr.print("\n", .{});
    try stderr.flush();

    applets.fns[@intFromEnum(applet)](init, applet_args);
}
