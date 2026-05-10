const std = @import("std");
const Io = std.Io;

pub const SortWriter = struct {
    downstream: *Io.Writer,
    allocator: std.mem.Allocator,
    field: usize, // 0-based index of whitespace-separated field to sort on; 0 = whole line
    lines: std.ArrayList([]const u8),
    line_buf: std.ArrayList(u8),
    interface: Io.Writer,

    pub fn init(downstream: *Io.Writer, allocator: std.mem.Allocator, buffer: []u8, field: usize) SortWriter {
        return .{
            .downstream = downstream,
            .allocator = allocator,
            .field = field,
            .lines = .empty,
            .line_buf = .empty,
            .interface = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = buffer,
            },
        };
    }

    pub fn deinit(self: *SortWriter) void {
        for (self.lines.items) |line| self.allocator.free(line);
        self.lines.deinit(self.allocator);
        self.line_buf.deinit(self.allocator);
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *SortWriter = @alignCast(@fieldParentPtr("interface", w));
        _ = splat;

        // Process w.buffer first
        for (w.buffer[0..w.end]) |byte| {
            try self.accumulateByte(byte);
        }
        w.end = 0;

        // Then process incoming data slices
        var total: usize = 0;
        for (data) |chunk| {
            for (chunk) |byte| {
                try self.accumulateByte(byte);
                total += 1;
            }
        }
        return total;
    }

    fn accumulateByte(self: *SortWriter, byte: u8) Io.Writer.Error!void {
        if (byte == '\n') {
            // Dupe the completed line into owned memory and store it
            const line = self.allocator.dupe(u8, self.line_buf.items) catch return error.WriteFailed;
            self.lines.append(self.allocator, line) catch return error.WriteFailed;
            self.line_buf.clearRetainingCapacity();
        } else {
            self.line_buf.append(self.allocator, byte) catch return error.WriteFailed;
        }
    }

    // Sort and flush all buffered lines to downstream
    pub fn flush(self: *SortWriter) !void {
        // Handle any remaining content without a trailing newline
        if (self.line_buf.items.len > 0) {
            const line = try self.allocator.dupe(u8, self.line_buf.items);
            try self.lines.append(self.allocator, line);
            self.line_buf.clearRetainingCapacity();
        }

        // Sort by the specified field
        const ctx = SortCtx{ .field = self.field };
        std.mem.sort([]const u8, self.lines.items, ctx, SortCtx.lessThan);

        // Write all lines downstream
        for (self.lines.items) |line| {
            self.downstream.writeAll(line) catch return error.WriteFailed;
            self.downstream.writeByte('\n') catch return error.WriteFailed;
        }

        // Clean up
        for (self.lines.items) |line| self.allocator.free(line);
        self.lines.clearRetainingCapacity();
    }

    const SortCtx = struct {
        field: usize,

        fn lessThan(ctx: SortCtx, a: []const u8, b: []const u8) bool {
            const a_field = getField(a, ctx.field);
            const b_field = getField(b, ctx.field);
            return std.mem.order(u8, a_field, b_field) == .lt;
        }

        // Extract the Nth whitespace-separated field from a line.
        // If field == 0 or the field index exceeds available fields, return the whole line.
        fn getField(line: []const u8, field: usize) []const u8 {
            if (field == 0) return line;
            var it = std.mem.tokenizeAny(u8, line, " \t");
            var i: usize = 0;
            while (it.next()) |token| {
                i += 1;
                if (i == field) return token;
            }
            return line; // field index out of range — fall back to whole line
        }
    };
};
