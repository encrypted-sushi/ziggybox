// applets/pwd.zig
//
// pwd — return working directory name
//
// POSIX Issue 8 Specification
// https://pubs.opengroup.org/onlinepubs/9799919799/utilities/pwd.html#tag_20_99
//
const std = @import("std");
const Io = std.Io;
const constants = @import("../constants.zig");
const common = @import("../common.zig");
const DeclArgs = @import("../DeclArgs.zig");

pub fn run(init: std.process.Init, args: []const [:0]const u8) void {
    const pwd_args = [_]DeclArgs.Argument{
        .{
            .name = "help",
            .shortopt = 'h',
            .longopt = "help",
            .description = "Prints this help message.",
        },
        .{
            .name = "from_env",
            .shortopt = 'L',
            .description = "Gets PWD environment variable is the value is POSIX Issue 8 compliant",
        },
        .{
            .name = "default",
            .shortopt = 'P',
            .description = "Write the pathname of the current directory, resolving all symlinks.",
        },
    };

    var stderr_buf: [constants.WRITE_BUF_SIZE]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buf);
    const stderr = &stderr_file_writer.interface;

    const Parser = DeclArgs.Parser(&pwd_args);
    const opts = Parser.parse(args) catch {
        Parser.usage("pwd", stderr) catch {};
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

    const pwd_env = init.environ_map.get("PWD");
    if (pwd_env) |p|
        _ = stdout.print("{s}\n", .{p}) catch {};
    stdout.flush() catch {};
}
