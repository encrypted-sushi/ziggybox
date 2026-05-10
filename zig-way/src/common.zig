const std = @import("std");
const Io = std.Io;

pub fn handleHelp(comptime Parser: type, opts: anytype, stdout: *Io.Writer) !bool {
    if (!opts.help) return false;
    try Parser.usage(opts.command, stdout);
    return true;
}

pub fn handleError(err: anyerror, stderr: *Io.Writer) void {
    stderr.print("{s}\n", .{@errorName(err)}) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}
