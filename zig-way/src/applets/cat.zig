// applets/cat.zig
//
// cat — concatenate and print files
//
// POSIX Issue 8 Specification
// https://pubs.opengroup.org/onlinepubs/9799919799/utilities/cat.html#tag_20_13
//
const std = @import("std");
const Io = std.Io;
const constants = @import("../constants.zig");
const common = @import("../common.zig");
const DeclArgs = @import("../DeclArgs.zig");
const Stream = @import("../stream.zig");

const cat_args = [_]DeclArgs.Argument{
    .{
        .name = "help",
        .shortopt = 'h',
        .longopt = "help",
        .description = "Prints this help message.",
    },
    .{
        .name = "unbuffered",
        .shortopt = 'u',
        .description = "Disable output buffering",
    },
};

pub fn run(init: std.process.Init, args: []const [:0]const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(init.io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    const Parser = DeclArgs.Parser(&cat_args);
    const opts = Parser.parse(args) catch {
        Parser.usage("cat", stderr) catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    };

    var stdout_buf: [constants.WRITE_BUF_SIZE]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    if (common.handleHelp(Parser, opts, stdout) catch false) {
        stdout.flush() catch {};
        std.process.exit(0);
    }

    var exit_code: u1 = 0;

    if (opts.positionals.len == 0) {
        process(init.io, "-", stdout, opts.unbuffered, stderr) catch {
            exit_code = 1;
        };
    } else {
        for (opts.positionals) |path| {
            process(init.io, path, stdout, opts.unbuffered, stderr) catch {
                exit_code = 1;
            };
        }
    }
    std.process.exit(exit_code);
}

fn process(io: Io, path: []const u8, w: *Io.Writer, flush_each: bool, stderr: *Io.Writer) !void {
    const is_stdin = std.mem.eql(u8, path, "-");
    const source = if (is_stdin)
        Io.File.stdin()
    else
        Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
            stderr.print("cat: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
            stderr.flush() catch {};
            return err;
        };
    defer if (!is_stdin) source.close(io);

    var file_reader_buf: [constants.READ_BUF_SIZE]u8 = undefined;
    var file_reader = source.reader(io, &file_reader_buf);
    const file = &file_reader.interface;

    Stream.loop(file, w, flush_each) catch |err| {
        stderr.print("cat: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        stderr.flush() catch {};
        return err;
    };
}
