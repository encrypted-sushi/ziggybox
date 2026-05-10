// applets_raw/false_raw.zig
const std = @import("std");
const common = @import("../common_raw.zig");

pub fn run(_: common.AppletInit) void {
    std.process.exit(1);
}
