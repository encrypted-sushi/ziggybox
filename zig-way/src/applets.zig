const std = @import("std");
const bin_true = @import("applets/true.zig");
const bin_false = @import("applets/false.zig");
const echo = @import("applets/echo.zig");
const pwd = @import("applets/pwd.zig");
const cat = @import("applets/cat.zig");
const rev = @import("applets/rev.zig");
const nm = @import("applets/nm.zig");

// The Applet Enum
// This will be the name to array index lookup for the dispatcher.
// I.e., Applet Name => Enum's Int value => fns[Enum's Int]
pub const Applet = enum {
    true,
    false,
    echo,
    pwd,
    cat,
    rev,
    nm,
};

// The Array of Applet Function Pointers
//
pub const fns = [_]*const fn (std.process.Init, []const [:0]const u8) void{
    bin_true.run,
    bin_false.run,
    echo.run,
    pwd.run,
    cat.run,
    rev.run,
    nm.run,
};
