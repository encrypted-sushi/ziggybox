// applets_raw/echo_raw.zig
const std = @import("std");
const common = @import("../common_raw.zig");

pub fn run(init: common.AppletInit) void {
    var i: usize = 0;

    while (i < init.args.len) : (i += 1) {
        const s = std.mem.span(init.args[i]);
        common.stdout(s);
        if (i + 1 < init.args.len) _ = common.stdout(" ");
    }
    common.stdout("\n");
}
