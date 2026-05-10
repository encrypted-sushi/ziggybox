// ArgParser.zig
const std = @import("std");
const ArgParser = @This();

vector: []const [*:0]const u8,
index: usize = 0,
current_token: []const u8 = "",
current_sflag: ?u8 = null,
short_index: usize = 0,

pub const Arg = union(enum) {
    short: u8,
    short_with_value: struct {
        flag: u8,
        value: [:0]const u8,
    },
    positionals: []const [*:0]const u8,
};

pub fn init(args: std.process.Args) ArgParser {
    return .{ .vector = args.vector };
}

pub fn next(self: *ArgParser, value_flags: []const u8) ?Arg {
    const State = enum { start, short, svalue, positional };
    parse: switch (State.start) {
        .start => {
            // If we've reached the end, return a null to signify
            if (self.index >= self.vector.len) return null;

            // If we have a "current_token" set, process short
            if (self.current_token.len > 0) continue :parse .short;

            // "Take" the token slice from vector
            const token = std.mem.span(self.vector[self.index]);
            self.index += 1;

            // bare "--": drop and proceed to positional
            if (std.mem.eql(u8, token, "--")) {
                const msg = "DEBUG: bare \"--\"\n";
                _ = std.os.linux.write(2, msg, msg.len);
                self.index += 1;
                continue :parse .positional;
            }

            // bare "-": means stdin, so move to positional
            if (std.mem.eql(u8, token, "-")) continue :parse .positional;

            // short "-abcd"
            if (token[0] == '-' and token.len > 1) {
                self.current_token = token[1..];
                self.short_index = 0;
                continue :parse .short;
            }

            // Otherwise, it's a positional
            continue :parse .positional;
        },
        .short => {
            // if we've end of short cluster, reset and return to start
            if (self.short_index >= self.current_token.len) {
                self.short_index = 0;
                self.current_token = "";
                self.current_sflag = null;
                continue :parse .start;
            }

            // "Take" flag from current_token
            self.current_sflag = self.current_token[self.short_index];
            self.short_index += 1;

            // If this is in "value_flags", must get value
            if (std.mem.find(u8, value_flags, &.{self.current_sflag.?}) != null)
                continue :parse .svalue;

            return .{ .short = self.current_sflag.? };
        },
        .svalue => {
            // First, take the short flag from state
            const current_sflag = self.current_sflag.?;
            self.current_sflag = null;

            // If we are at the end of the current token, take next token
            if (self.short_index >= self.current_token.len) {
                // get the current sflag
                // "Take" the next token
                const token = std.mem.span(self.vector[self.index]);
                self.index += 1;
                // Reset short state
                self.short_index = 0;
                self.current_token = "";
                // return
                return .{ .short_with_value = .{
                    .flag = current_sflag,
                    .value = token,
                } };
            }

            // If no tokens are left, return with a blank value
            if (self.index >= self.vector.len) {
                return .{ .short_with_value = .{
                    .flag = current_sflag,
                    .value = "",
                } };
            }

            // Otherwise, reset short state, and return remaining
            // e.g.,  -oflags.txt
            // Get remaing in token
            const value = self.current_token[self.short_index..self.current_token.len :0];
            // Reset short state
            self.short_index = 0;
            self.current_token = "";
            // and return
            return .{ .short_with_value = .{
                .flag = current_sflag,
                .value = value,
            } };
        },
        .positional => {
            const rest = self.vector[self.index - 1 ..];
            self.index = self.vector.len;
            return .{ .positionals = rest };
        },
    }
}
