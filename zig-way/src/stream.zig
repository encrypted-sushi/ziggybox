const std = @import("std");

pub fn loop(reader: *std.Io.Reader, writer: *std.Io.Writer, flush_each: bool) !void {
    while (true) {
        const chunk = reader.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        try writer.writeAll(chunk);
        reader.toss(chunk.len);
        if (flush_each) try writer.flush();
    }
    try writer.flush();
}
