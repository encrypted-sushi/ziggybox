const std = @import("std");
const constants = @import("constants_raw.zig");
const common = @import("common_raw.zig");
const applets = @import("applets_raw.zig");

pub fn main(init: std.process.Init.Minimal) void {
    const argv0 = std.mem.span(init.args.vector[0]);
    const bn_slice = std.fs.path.basename(argv0);
    const bn: [:0]const u8 = argv0[argv0.len - bn_slice.len .. argv0.len :0];
    const as_ziggybox = std.mem.eql(u8, bn, constants.BIN_NAME);

    if (as_ziggybox and init.args.vector.len < 2) {
        common.stderr("usage: ziggybox <applet>\n");
        std.process.exit(1);
    }

    const applet_name: [:0]const u8 = if (as_ziggybox) std.mem.span(init.args.vector[1]) else bn;
    const applet_args = if (as_ziggybox) init.args.vector[2..] else init.args.vector[1..];

    const applet = std.meta.stringToEnum(applets.Applet, applet_name) orelse {
        common.stderr("unknown applet\n");
        std.process.exit(1);
    };

    applets.dispatch[@intFromEnum(applet)](.{
        .args = applet_args,
        .environ = init.environ,
    });
}

// const applet_name: [:0]const u8 = if (as_ziggybox) init.args[1] else bn;
// if args[1] not in array print error
// else call run() for that applet by passing args
// }

//     var parser = ArgParser.init(init.args);
//     parser.index = 1;
//
//     while (parser.next("t")) |arg| {
//         switch (arg) {
//             // .long => |s| {
//             //     _ = linux.write(1, "long: ", 6);
//             //     _ = linux.write(1, s.ptr, s.len);
//             //     _ = linux.write(1, "\n", 1);
//             // },
//             .short => |c| {
//                 _ = linux.write(1, "short: ", 7);
//                 _ = linux.write(1, &[_]u8{c}, 1);
//                 _ = linux.write(1, "\n", 1);
//             },
//             .short_with_value => |sv| {
//                 _ = linux.write(1, "short+val: ", 11);
//                 _ = linux.write(1, &[_]u8{sv.flag}, 1);
//                 _ = linux.write(1, "=", 1);
//                 _ = linux.write(1, sv.value.ptr, sv.value.len);
//                 _ = linux.write(1, "\n", 1);
//             },
//             .positionals => |p| {
//                 for (p) |s| {
//                     const str = std.mem.span(s);
//                     _ = linux.write(1, "positional: ", 12);
//                     _ = linux.write(1, str.ptr, str.len);
//                     _ = linux.write(1, "\n", 1);
//                 }
//             },
//             // .positionals => |p| {
//             //     _ = linux.write(1, "positionals: ", 13);
//             //     _ = linux.write(1, &std.mem.toBytes(p.len), 1);
//             //     _ = linux.write(1, "\n", 1);
//             // },
//             // .end_of_opts => {
//             //     _ = linux.write(1, "end_of_opts\n", 12);
//             // },
//         }
//     }
// }
