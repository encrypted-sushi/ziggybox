const std = @import("std");
const Io = std.Io;

pub const ReverseWriter = struct {
    downstream: *Io.Writer,
    allocator: std.mem.Allocator,
    line_buf: std.ArrayList(u8),
    interface: Io.Writer,

    pub fn init(downstream: *Io.Writer, allocator: std.mem.Allocator, buffer: []u8) ReverseWriter {
        return .{
            .downstream = downstream,
            .allocator = allocator,
            .line_buf = .empty,
            .interface = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = buffer,
            },
        };
    }

    pub fn deinit(self: *ReverseWriter) void {
        self.line_buf.deinit(self.allocator);
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *ReverseWriter = @alignCast(@fieldParentPtr("interface", w));
        _ = splat;

        // First process whatever is already in w.buffer
        for (w.buffer[0..w.end]) |byte| {
            if (byte == '\n') {
                std.mem.reverse(u8, self.line_buf.items);
                self.downstream.writeAll(self.line_buf.items) catch return error.WriteFailed;
                self.downstream.writeByte('\n') catch return error.WriteFailed;
                self.line_buf.clearRetainingCapacity();
            } else {
                self.line_buf.append(self.allocator, byte) catch return error.WriteFailed;
            }
        }
        w.end = 0; // empty the buffer — this is what defaultFlush needs

        // Then process the incoming data slices
        var total: usize = 0;
        for (data) |chunk| {
            for (chunk) |byte| {
                if (byte == '\n') {
                    std.mem.reverse(u8, self.line_buf.items);
                    self.downstream.writeAll(self.line_buf.items) catch return error.WriteFailed;
                    self.downstream.writeByte('\n') catch return error.WriteFailed;
                    self.line_buf.clearRetainingCapacity();
                } else {
                    self.line_buf.append(self.allocator, byte) catch return error.WriteFailed;
                }
                total += 1;
            }
        }
        return total;
    }

    // This flush() needs to be implemented, because:
    // Example: if test.txt contains hello with no trailing newline, drain
    // will accumulate hello into line_buf but never see a \n to trigger
    // the reverse-and-write. flush() is what writes that final buffered
    // content out.
    pub fn flush(self: *ReverseWriter) !void {
        if (self.line_buf.items.len == 0) return;

        std.mem.reverse(u8, self.line_buf.items);
        try self.downstream.writeAll(self.line_buf.items);
        self.line_buf.clearRetainingCapacity();
    }
};
