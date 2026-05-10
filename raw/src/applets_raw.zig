const std = @import("std");
const common = @import("common_raw.zig");
const bin_true = @import("applets_raw/true_raw.zig");
const bin_false = @import("applets_raw/false_raw.zig");
const echo = @import("applets_raw/echo_raw.zig");
const nm = @import("applets_raw/nm_raw.zig");

pub const Applet = enum {
    true,
    false,
    echo,
    nm,
};

pub const dispatch = [@typeInfo(Applet).@"enum".fields.len]*const fn (common.AppletInit) void{
    bin_true.run,
    bin_false.run,
    echo.run,
    nm.run,
};
