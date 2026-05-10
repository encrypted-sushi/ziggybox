const std = @import("std");

pub const AppletInit = struct {
    args: []const [*:0]const u8,
    environ: std.process.Environ,
};

pub fn stdout(msg: []const u8) void {
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

pub fn stderr(msg: []const u8) void {
    _ = std.os.linux.write(2, msg.ptr, msg.len);
}

// return type of "noreturn" tells Zig this function never returns
// so you can use it without unreachable after it.
pub fn die(msg: []const u8) noreturn {
    stderr(msg);
    std.process.exit(1);
}

// Used to print u64 as int
pub fn printInt(value: u64) void {
    if (value == 0) {
        stdout("0");
        return;
    }
    var buf: [20]u8 = undefined; // u64 max is 18446744073709551615, 20 digits
    var i: usize = 20;
    var v = value;
    while (v > 0) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    stdout(buf[i..]);
}

// Used to print u64 as hex (zero-padded to 16 digits, no "0x" prefix)
pub fn printHex(value: u64) void {
    const digits = "0123456789abcdef";
    var buf: [16]u8 = undefined;
    var i: usize = 16;
    var v = value;
    while (i > 0) {
        i -= 1;
        buf[i] = digits[v & 0xf];
        v >>= 4;
    }
    stdout(&buf);
}
