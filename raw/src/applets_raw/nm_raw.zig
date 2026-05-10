// applets_raw/nm_raw.zig
const std = @import("std");
const linux = std.os.linux;
const common = @import("../common_raw.zig");
const ArgParser = @import("../ArgParser_raw.zig");

// Maximum bytes per output line:
// 16 (value) + 1 (space) + 1 (type) + 1 (space) + 256 (name) + 1 (newline) = 276
const MAX_LINE = 276;

const Flags = struct {
    undefined_only: bool = false,
    global_only: bool = false,
    prepend_filename: bool = false,
    portable: bool = false,
    sort_by_value: bool = false,
    external_only: bool = false,
    full_output: bool = false,
    base: enum { dec, oct, hex } = .dec,
};

const ElfInfo = struct {
    fd: usize,
    section_number: u64,
    e_shoff: u64,
    e_shentsize: u64,
};

pub fn run(init: common.AppletInit) void {
    var flags = Flags{};
    var parser = ArgParser{ .vector = init.args };
    var files: []const [*:0]const u8 = &.{};

    while (parser.next("t")) |arg| {
        switch (arg) {
            .short => |c| switch (c) {
                'u' => {
                    flags.undefined_only = true;
                    flags.global_only = false;
                },
                'g' => {
                    flags.global_only = true;
                    flags.undefined_only = false;
                },
                'A' => flags.prepend_filename = true,
                'P' => flags.portable = true,
                'v' => flags.sort_by_value = true,
                'e' => flags.external_only = true,
                'f' => flags.full_output = true,
                'o' => flags.base = .oct,
                'x' => flags.base = .hex,
                else => common.die("nm: unknown flag\n"),
            },
            .short_with_value => |sv| switch (sv.flag) {
                't' => flags.base = switch (sv.value[0]) {
                    'd' => .dec,
                    'o' => .oct,
                    'x' => .hex,
                    else => common.die("nm: invalid -t format\n"),
                },
                else => common.die("nm: unknown flag\n"),
            },
            .positionals => |p| {
                files = p;
                break;
            },
        }
    }

    if (files.len == 0) common.die("nm: no input files\n");

    // -P implies -t x unless -t was explicitly given
    if (flags.portable and flags.base == .dec) flags.base = .hex;

    const multi_file = files.len > 1;
    for (files) |path| {
        processFile(path, flags, multi_file);
    }
}

fn processFile(path: [*:0]const u8, flags: Flags, multi_file: bool) void {
    // Print header if multi_file
    if (multi_file) {
        common.stdout(std.mem.span(path));
        common.stdout(":\n");
    }
    const fd = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (fd > std.math.maxInt(i32)) common.die("nm: cannot open file\n");

    // Bytes 0-3: ELF magic
    var magic: [4]u8 = undefined;
    _ = linux.read(@intCast(fd), &magic, 4);
    if (magic[0] != 0x7f or magic[1] != 'E' or magic[2] != 'L' or magic[3] != 'F')
        common.die("nm: not an ELF file\n");

    // Byte 4: class (2 = 64-bit)
    var class: [1]u8 = undefined;
    _ = linux.read(@intCast(fd), &class, 1);
    if (class[0] != 2) common.die("nm: only 64-bit ELF supported\n");

    // Byte 5: endianness (1 = little)
    var endian: [1]u8 = undefined;
    _ = linux.read(@intCast(fd), &endian, 1);
    if (endian[0] != 1) common.die("nm: only little-endian ELF supported\n");

    // e_shoff at byte 40
    _ = linux.lseek(@intCast(fd), 40, linux.SEEK.SET);
    var e_shoff: u64 = undefined;
    _ = linux.read(@intCast(fd), std.mem.asBytes(&e_shoff), 8);

    // e_shentsize at byte 58, e_shnum at byte 60
    _ = linux.lseek(@intCast(fd), 58, linux.SEEK.SET);
    var e_shentsize: u16 = undefined;
    var e_shnum: u16 = undefined;
    _ = linux.read(@intCast(fd), std.mem.asBytes(&e_shentsize), 2);
    _ = linux.read(@intCast(fd), std.mem.asBytes(&e_shnum), 2);

    // Find SYMTAB (sh_type == 2)
    var symtab_index: ?u64 = null;
    var i: u64 = 0;
    while (i < e_shnum) : (i += 1) {
        _ = linux.lseek(@intCast(fd), @intCast(e_shoff + i * e_shentsize + 4), linux.SEEK.SET);
        var sh_type: u32 = undefined;
        _ = linux.read(@intCast(fd), std.mem.asBytes(&sh_type), 4);
        if (sh_type == 2) {
            symtab_index = i;
            break; // ELF files have at most one SYMTAB
        }
    }

    if (symtab_index == null) common.die("nm: no symbol table found\n");

    // processSymtab(flags, fd, symtab_index.?, e_shoff, e_shentsize) catch |err| {
    processSymtab(path, .{
        .fd = fd,
        .section_number = symtab_index.?,
        .e_shoff = e_shoff,
        .e_shentsize = e_shentsize,
    }, flags) catch |err| {
        common.stderr(@errorName(err));
        common.die("\n");
    };

    _ = linux.close(@intCast(fd));
}

// fn processSymtab(flags: Flags, fd: usize, section_number: u64, e_shoff: u64, e_shentsize: u64) !void {
fn processSymtab(path: [*:0]const u8, elf: ElfInfo, flags: Flags) !void {
    var r: usize = 0;
    const shdr_base = elf.e_shoff + elf.section_number * elf.e_shentsize;

    // Read sh_offset and sh_size (at offsets 24 and 32 within the section header)
    _ = linux.lseek(@intCast(elf.fd), @intCast(shdr_base + 24), linux.SEEK.SET);
    var sh_offset: u64 = undefined;
    var sh_size: u64 = undefined;
    r = linux.read(@intCast(elf.fd), std.mem.asBytes(&sh_offset), 8);
    if (r != 8) return error.ReadFailed;
    r = linux.read(@intCast(elf.fd), std.mem.asBytes(&sh_size), 8);
    if (r != 8) return error.ReadFailed;

    // Read sh_link (at offset 40 within the section header)
    _ = linux.lseek(@intCast(elf.fd), @intCast(shdr_base + 40), linux.SEEK.SET);
    var sh_link: u32 = undefined;
    r = linux.read(@intCast(elf.fd), std.mem.asBytes(&sh_link), 4);
    if (r != 4) return error.ReadFailed;

    // Read sh_entsize (at offset 56 within the section header)
    _ = linux.lseek(@intCast(elf.fd), @intCast(shdr_base + 56), linux.SEEK.SET);
    var sh_entsize: u64 = undefined;
    r = linux.read(@intCast(elf.fd), std.mem.asBytes(&sh_entsize), 8);
    if (r != 8) return error.ReadFailed;

    // Read STRTAB sh_offset via sh_link
    const strtab_base = elf.e_shoff + @as(u64, sh_link) * elf.e_shentsize;
    _ = linux.lseek(@intCast(elf.fd), @intCast(strtab_base + 24), linux.SEEK.SET);
    var strtab_offset: u64 = undefined;
    r = linux.read(@intCast(elf.fd), std.mem.asBytes(&strtab_offset), 8);
    if (r != 8) return error.ReadFailed;

    // mmap an anonymous buffer sized for worst-case output
    const sym_count = sh_size / sh_entsize;
    const buf_size = sym_count * MAX_LINE;
    const buf_ptr = linux.mmap(
        null,
        buf_size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    );
    if (buf_ptr == std.math.maxInt(usize)) return error.MmapFailed;
    const buf: [*]u8 = @ptrFromInt(buf_ptr);
    var buf_end: usize = 0; // how many bytes written so far

    // Iterate symbol entries
    var sym_i: u64 = 0;
    while (sym_i < sym_count) : (sym_i += 1) {
        const sym_base = sh_offset + sym_i * sh_entsize;

        // Read st_name (u32) and st_info (u8) — they are consecutive at offset 0 and 4
        _ = linux.lseek(@intCast(elf.fd), @intCast(sym_base), linux.SEEK.SET);
        var st_name: u32 = undefined;
        r = linux.read(@intCast(elf.fd), std.mem.asBytes(&st_name), 4);
        if (r != 4) return error.ReadFailed;
        var st_info: u8 = undefined;
        r = linux.read(@intCast(elf.fd), std.mem.asBytes(&st_info), 1);
        if (r != 1) return error.ReadFailed;

        // st_shndx is at offset 6 within the symbol entry
        _ = linux.lseek(@intCast(elf.fd), @intCast(sym_base + 6), linux.SEEK.SET);
        var st_shndx: u16 = undefined;
        r = linux.read(@intCast(elf.fd), std.mem.asBytes(&st_shndx), 2);
        if (r != 2) return error.ReadFailed;

        // st_value is at offset 8 within the symbol entry
        _ = linux.lseek(@intCast(elf.fd), @intCast(sym_base + 8), linux.SEEK.SET);
        var st_value: u64 = undefined;
        r = linux.read(@intCast(elf.fd), std.mem.asBytes(&st_value), 8);
        if (r != 8) return error.ReadFailed;

        // Skip null symbol (index 0, empty name)
        if (sym_i == 0 and st_name == 0) continue;

        // Read name from STRTAB
        _ = linux.lseek(@intCast(elf.fd), @intCast(strtab_offset + st_name), linux.SEEK.SET);
        var name_buf: [256]u8 = undefined;
        var name_len: usize = 0;
        while (name_len < name_buf.len) {
            r = linux.read(@intCast(elf.fd), name_buf[name_len..][0..1], 1);
            if (r != 1) break;
            if (name_buf[name_len] == 0) break;
            name_len += 1;
        }
        if (name_len == 0) continue;
        const name = name_buf[0..name_len];

        // Derive type letter
        const sym_bind = st_info >> 4;
        const sym_type_raw = st_info & 0xf;
        const is_global = sym_bind == std.elf.STB_GLOBAL;
        const type_letter: u8 = if (st_shndx == 0)
            'U'
        else switch (sym_type_raw) {
            std.elf.STT_FUNC => if (is_global) 'T' else 't',
            std.elf.STT_OBJECT => if (is_global) 'D' else 'd',
            std.elf.STT_SECTION => if (is_global) 'B' else 'b',
            std.elf.STT_FILE => 'f',
            else => if (st_shndx == std.elf.SHN_ABS) (if (is_global) 'A' else 'a') else '?',
        };

        // ================{ OUTPUT FILTERING }==================
        // This is where Flags are used to determine what to print

        // Undefined Only (-u)
        if (flags.undefined_only and type_letter != 'U') continue;

        // Global Only (-g)
        if (flags.global_only and !is_global) continue;

        // External AND Static (-e)
        //   => IF External...
        if (flags.external_only) {
            // => AND Static...
            const is_static = !is_global and
                (sym_type_raw == std.elf.STT_OBJECT or sym_type_raw == std.elf.STT_FUNC);
            if (!is_global and !is_static) continue;
        }

        // Write line into mmap buffer: "<value> <type> <name>\n"
        // Undefined symbols get blank value per convention
        if (type_letter == 'U') {
            buf[buf_end..][0..17].* = "                 ".*;
            buf_end += 17;
        } else {
            writeHex(buf[buf_end..][0..16], st_value);
            buf_end += 16;
            buf[buf_end] = ' ';
            buf_end += 1;
        }
        buf[buf_end] = type_letter;
        buf_end += 1;
        buf[buf_end] = ' ';
        buf_end += 1;
        @memcpy(buf[buf_end..][0..name_len], name);
        buf_end += name_len;
        buf[buf_end] = '\n';
        buf_end += 1;
    }

    // Sort lines in mmap buffer by name (field 3, after two space-separated fields)
    sortLines(buf[0..buf_end], path, flags);

    // Write sorted output
    // _ = linux.write(1, buf, buf_end);

    _ = linux.munmap(@ptrFromInt(buf_ptr), buf_size);
}

// Write a u64 as exactly 16 lowercase hex digits into dest[0..16]
fn writeHex(dest: *[16]u8, value: u64) void {
    const digits = "0123456789abcdef";
    var v = value;
    var i: usize = 16;
    while (i > 0) {
        i -= 1;
        dest[i] = digits[v & 0xf];
        v >>= 4;
    }
}

fn writeDec(dest: *[20]u8, value: u64) void {
    var v = value;
    var i: usize = 20;
    while (i > 0) {
        i -= 1;
        dest[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
}

fn writeOct(dest: *[22]u8, value: u64) void {
    var v = value;
    var i: usize = 22;
    while (i > 0) {
        i -= 1;
        dest[i] = '0' + @as(u8, @intCast(v & 0x7));
        v >>= 3;
    }
}

// Default nm output format: "<16-hex> <type> <name>\n" or "                 <type> <name>\n"
// Name starts at byte offset 18 in every line.
fn sortLines(buf: []u8, path: [*:0]const u8, flags: Flags) void {
    // Build a slice of line slices (each points into buf, includes the \n)
    // We use a fixed stack array — sym_count * MAX_LINE is already mmap'd,
    // but we need pointers. Use a second mmap for the pointer array.
    // Each pointer is 8 bytes; worst case sym_count = buf.len / 18 (shortest possible line)
    const max_lines = buf.len / 18 + 1;
    const ptr_buf_size = max_lines * @sizeOf([]u8);
    const ptr_buf_raw = linux.mmap(
        null,
        ptr_buf_size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    );
    if (ptr_buf_raw == std.math.maxInt(usize)) return; // can't sort, just output unsorted
    const lines: [*][]u8 = @ptrFromInt(ptr_buf_raw);
    var line_count: usize = 0;

    // Slice the buffer into lines
    var start: usize = 0;
    for (buf, 0..) |byte, idx| {
        if (byte == '\n') {
            lines[line_count] = buf[start .. idx + 1];
            line_count += 1;
            start = idx + 1;
        }
    }

    // Insertion sort — simple, no allocator needed, fine for typical nm output
    var j: usize = 1;
    while (j < line_count) : (j += 1) {
        const key = lines[j];
        const key_name = nameField(key);
        var k: usize = j;
        while (k > 0 and std.mem.order(u8, nameField(lines[k - 1]), key_name) == .gt) : (k -= 1) {
            lines[k] = lines[k - 1];
        }
        lines[k] = key;
    }

    // Write sorted lines back into buf in-place
    // Since we're reordering existing slices back into the same buffer we need a temp.
    // Simplest: just write directly to stdout in order instead of back to buf.
    // Caller already does the write, so we reconstruct buf in sorted order.
    // var pos: usize = 0;
    // for (lines[0..line_count]) |line| {
    //     @memcpy(buf[pos..][0..line.len], line);
    //     pos += line.len;
    // }
    // Write sorted lines directly to stdout
    for (lines[0..line_count]) |line| {
        // FLAGS: FOR PREPEND_FILENAME (-A)
        if (flags.prepend_filename) {
            common.stdout(std.mem.span(path));
            common.stdout(":");
        }
        _ = linux.write(1, line.ptr, line.len);
    }

    _ = linux.munmap(@ptrFromInt(ptr_buf_raw), ptr_buf_size);
}

// Extract the name field from a line.
// Format: "xxxxxxxxxxxxxxxx t name\n"  (18 bytes before name)
//      or "                 t name\n"  (18 bytes before name)
// So name always starts at index 18.
fn nameField(line: []u8) []u8 {
    if (line.len <= 18) return line;
    const end = if (line[line.len - 1] == '\n') line.len - 1 else line.len;
    return line[18..end];
}
