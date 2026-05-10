// applets/rev.zig
//
// false — return false value
//
// NOT POSIX
// Implemented to be like busybox
//
const std = @import("std");
const Io = std.Io;
const constants = @import("../constants.zig");
const stream = @import("../stream.zig");
const ReverseWriter = @import("../writers/reverse.zig").ReverseWriter;

pub fn run(init: std.process.Init, args: []const [:0]const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), init.io, &stderr_buf);
    const stderr = &stderr_file_writer.interface;

    var stdout_buf: [constants.WRITE_BUF_SIZE]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buf);
    const stdout = &stdout_file_writer.interface;

    var reverse_buf: [constants.READ_BUF_SIZE]u8 = undefined;
    var reverse = ReverseWriter.init(stdout, init.gpa, &reverse_buf);
    defer reverse.deinit();
    const writer = &reverse.interface;

    const positionals = args[1..];
    var exit_code: u8 = 0;

    if (positionals.len == 0) {
        _ = stderr.print("Why am I here?\n", .{}) catch {};
        // var read_buf: [READ_BUF_SIZE]u8 = undefined;
        // var file_reader: Io.File.Reader = .init(.stdin(), init.io, &read_buf);
        // while (true) {
        //     _ = file_reader.interface.stream(writer, .unlimited) catch |err| switch (err) {
        //         error.EndOfStream => break,
        //         else => {
        //             exit_code = 1;
        //             break;
        //         },
        //     };
        // }
    } else {
        for (positionals) |path| {
            const is_stdin = std.mem.eql(u8, path, "-");
            const file = if (is_stdin)
                Io.File.stdin()
            else
                Io.Dir.cwd().openFile(init.io, path, .{}) catch |err| {
                    stderr.print("rev: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
                    exit_code = 1;
                    continue;
                };
            defer if (!is_stdin) file.close(init.io);
            var read_buf: [constants.READ_BUF_SIZE]u8 = undefined;
            // var file_reader: Io.File.Reader = .init(file, init.io, &read_buf);
            var file_reader = file.reader(init.io, &read_buf);
            stream.loop(&file_reader.interface, writer, false) catch |err| {
                stderr.print("rev: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
                exit_code = 1;
            };
            // while (true) {
            //     _ = file_reader.interface.stream(writer, .unlimited) catch |err| switch (err) {
            //         error.EndOfStream => break,
            //         else => {
            //             stderr.print("rev: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
            //             exit_code = 1;
            //             break;
            //         },
            //     };
            // }
        }
    }

    // writer.flush() catch {};
    reverse.flush() catch {};
    stdout.flush() catch {};
    stderr.flush() catch {};
    std.process.exit(exit_code);
}
