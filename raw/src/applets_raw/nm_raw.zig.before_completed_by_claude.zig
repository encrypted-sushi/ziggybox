// applets_raw/nm_raw.zig
const std = @import("std");
const linux = std.os.linux;
const common = @import("../common_raw.zig");

pub fn run(init: common.AppletInit) void {
    if (init.args.len == 0) common.die("nm: no input files\n");

    // Create the file descriptor to the file
    const path = init.args[0];
    const fd = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (fd > std.math.maxInt(i32)) common.die("nm: cannot open file\n");
    // const fd = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    // if (fd < 0) common.die("nm: cannot open file\n");

    // Bytes 0-3: Read the first 4 bytes of the file to see if it is an ELF file
    // ELF => 7f 45 4c 46 (0x7f, 'E', 'L', 'F')
    var magic: [4]u8 = undefined;
    _ = linux.read(@intCast(fd), &magic, 4);
    if (magic[0] != 0x7f or magic[1] != 'E' or magic[2] != 'L' or magic[3] != 'F')
        common.die("nm: not an ELF file\n");
    common.stdout("ELF magic OK\n");

    // Byte 4: class (1 = 32-bit, 2 = 64-bit)
    var class: [1]u8 = undefined;
    _ = linux.read(@intCast(fd), &class, 1);
    if (class[0] != 2) common.die("nm: only 64-bit ELF supported\n");
    common.stdout("64-bit ELF OK\n");

    // Byte 5: endianness (1 = little, 2 = big)
    // How multibyte integers are stored
    var endian: [1]u8 = undefined;
    _ = linux.read(@intCast(fd), &endian, 1);
    if (endian[0] != 1) common.die("nm: only little-endian ELF supported\n");
    common.stdout("little-endian OK\n");

    // Seek to e_shoff (byte 40) and read it
    // Where the Section Header starts
    _ = linux.lseek(@intCast(fd), 40, linux.SEEK.SET);
    var e_shoff: u64 = undefined;
    _ = linux.read(@intCast(fd), std.mem.asBytes(&e_shoff), 8);

    // e_shentsize is at byte 58, e_shnum at byte 60 — read both together
    // The size of each Section Headers
    // The number of Section Headers entires
    _ = linux.lseek(@intCast(fd), 58, linux.SEEK.SET);
    var e_shentsize: u16 = undefined;
    var e_shnum: u16 = undefined;
    _ = linux.read(@intCast(fd), std.mem.asBytes(&e_shentsize), 2);
    _ = linux.read(@intCast(fd), std.mem.asBytes(&e_shnum), 2);

    common.stdout("shoff: ");
    common.printInt(e_shoff);
    common.stdout("\n");
    common.stdout("shentsize: ");
    common.printInt(e_shentsize);
    common.stdout("\n");
    common.stdout("shnum: ");
    common.printInt(e_shnum);
    common.stdout("\n");

    // Now that we know:
    //  - Where the section headers start
    //  - The size of each section header
    //  - and how many there are
    // we can create a loop to read what we want.
    //
    // Layout of ELF Sections
    // Offset  Bytes    Size  Name          Type
    // 0x00    0-3      4     sh_name       u32      # Section name (index into string table)
    // 0x04    4-7      4     sh_type       u32      # Section type
    // 0x08    8-15     8     sh_flags      u64      # Section attributes/flags
    // 0x10    16-23    8     sh_addr       u64      # Virtual address in memory (for loaded sections)
    // 0x18    24-31    8     sh_offset     u64      # Offset in file
    // 0x20    32-39    8     sh_size       u64      # Size of section in bytes
    // 0x28    40-43    4     sh_link       u32      # Link to another section (depends on type)
    // 0x2C    44-47    4     sh_info       u32      # Extra section-specific information
    // 0x30    48-55    8     sh_addralign  u64      # Alignment requirement
    // 0x38    56-63    8     sh_entsize    u64      # Size of entries, if section holds a table
    //
    // For each section header at index i:
    //  - seek to shoff + i * shentsize + 4
    //  - read 4 bytes → sh_type
    //  - if sh_type == 2 → this is the SYMTAB
    // We need to get to the Symbol Table
    var i: u64 = 0;
    while (i < e_shnum) : (i += 1) {
        _ = linux.lseek(@intCast(fd), @intCast(e_shoff + i * e_shentsize + 4), linux.SEEK.SET);
        var sh_type: u32 = undefined;
        _ = linux.read(@intCast(fd), std.mem.asBytes(&sh_type), 4);
        if (sh_type == 2) {
            common.stdout("found SYMTAB at index ");
            common.printInt(i);
            common.stdout("\n");
            parseSectionHeader(fd, i, e_shoff, e_shentsize) catch |err| {
                common.stderr(@errorName(err));
                common.die("Failed to parse.\n");
            };
        }
    }
}

fn printSectionHeader(section_number: usize, sh_offset: u64, sh_size: u64, sh_link: u32, sh_entsize: u64) void {
    common.stdout("Section: ");
    common.printInt(section_number);
    common.stdout("    sh_offset: ");
    common.printInt(sh_offset);
    common.stdout("    sh_size: ");
    common.printInt(sh_size);
    common.stdout("    sh_link: ");
    common.printInt(sh_link);
    common.stdout("    sh_entsize: ");
    common.printInt(sh_entsize);
    common.stdout("\n");
}

fn parseSectionHeader(fd: usize, section_number: u64, e_shoff: u64, e_shentsize: u64) !void {
    // read() result variable
    var r: usize = 0;

    // Calculate base offset
    const shdr_base = e_shoff + section_number * e_shentsize;

    // Seek to sh_offset (ELF64: offset 24)
    // Offset  Bytes    Size  Name          Type
    // -------------------------------------------------------------------------
    // 0x18    24-31    8     sh_offset     u64      # Offset in file
    // 0x20    32-39    8     sh_size       u64      # Size of section in bytes
    _ = linux.lseek(@intCast(fd), @intCast(shdr_base + 24), linux.SEEK.SET);
    // Read sh_offset and sh_size consecutively, since they are next to eachother
    var sh_offset: u64 = undefined;
    var sh_size: u64 = undefined;
    r = linux.read(@intCast(fd), std.mem.asBytes(&sh_offset), 8);
    if (r != 8) return error.ReadFailed;
    r = linux.read(@intCast(fd), std.mem.asBytes(&sh_size), 8);
    if (r != 8) return error.ReadFailed;

    // Seek to sh_link (ELF64: offset 40)
    // Offset  Bytes    Size  Name          Type
    // -------------------------------------------------------------------------
    // 0x28    40-43    4     sh_link       u32      # Link to another section (depends on type)
    _ = linux.lseek(@intCast(fd), @intCast(shdr_base + 40), linux.SEEK.SET);
    // And read the data
    var sh_link: u32 = undefined;
    r = linux.read(@intCast(fd), std.mem.asBytes(&sh_link), 4);
    if (r != 4) return error.ReadFailed;

    // Seek to sh_entsize (ELF64: offset 56)
    // Offset  Bytes    Size  Name          Type
    // -------------------------------------------------------------------------
    // 0x38    56-63    8     sh_entsize    u64      # Size of entries, if section holds a table
    _ = linux.lseek(@intCast(fd), @intCast(shdr_base + 56), linux.SEEK.SET);
    // And read the data
    var sh_entsize: u64 = undefined;
    r = linux.read(@intCast(fd), std.mem.asBytes(&sh_entsize), 8);
    if (r != 8) return error.ReadFailed;

    // Print what we found
    printSectionHeader(section_number, sh_offset, sh_size, sh_link, sh_entsize);

    // Read STRTAB section header at index sh_link — we only need sh_offset
    const strtab_base = e_shoff + @as(u64, sh_link) * e_shentsize;
    _ = linux.lseek(@intCast(fd), @intCast(strtab_base + 24), linux.SEEK.SET);
    var strtab_offset: u64 = undefined;
    r = linux.read(@intCast(fd), std.mem.asBytes(&strtab_offset), 8);
    if (r != 8) return error.ReadFailed;

    // Iterate symbol entries — each is sh_entsize bytes (24 for ELF64)
    // Elf64_Sym layout:
    // 0x00  4   st_name   u32   offset into STRTAB
    // 0x04  1   st_info   u8    binding (high 4) + type (low 4)
    // 0x05  1   st_other  u8    visibility
    // 0x06  2   st_shndx  u16   section index
    // 0x08  8   st_value  u64   symbol value
    // 0x10  8   st_size   u64   symbol size
    const sym_count = sh_size / sh_entsize;
    var sym_i: u64 = 0;
    while (sym_i < sym_count) : (sym_i += 1) {
        const sym_base = sh_offset + sym_i * sh_entsize;

        // Read st_name
        _ = linux.lseek(@intCast(fd), @intCast(sym_base), linux.SEEK.SET);
        var st_name: u32 = undefined;
        r = linux.read(@intCast(fd), std.mem.asBytes(&st_name), 4);
        if (r != 4) return error.ReadFailed;

        // Read st_info
        var st_info: u8 = undefined;
        r = linux.read(@intCast(fd), std.mem.asBytes(&st_info), 1);
        if (r != 1) return error.ReadFailed;

        // Skip st_other + st_shndx, seek to st_value
        _ = linux.lseek(@intCast(fd), @intCast(sym_base + 8), linux.SEEK.SET);
        var st_value: u64 = undefined;
        r = linux.read(@intCast(fd), std.mem.asBytes(&st_value), 8);
        if (r != 8) return error.ReadFailed;

        // Skip null symbol (index 0 always has empty name)
        if (st_name == 0 and sym_i == 0) continue;

        // Read the name: seek to STRTAB + st_name, read until \0
        _ = linux.lseek(@intCast(fd), @intCast(strtab_offset + st_name), linux.SEEK.SET);
        var name_buf: [256]u8 = undefined;
        var name_len: usize = 0;
        while (name_len < name_buf.len) {
            r = linux.read(@intCast(fd), name_buf[name_len..][0..1], 1);
            if (r != 1) break;
            if (name_buf[name_len] == 0) break;
            name_len += 1;
        }
        const name = name_buf[0..name_len];
        if (name_len == 0) continue;

        // Derive type letter from st_info
        const sym_bind = st_info >> 4;
        const sym_type_raw = st_info & 0xf;
        const type_letter: u8 = switch (sym_type_raw) {
            std.elf.STT_FUNC => if (sym_bind == std.elf.STB_GLOBAL) 'T' else 't',
            std.elf.STT_OBJECT => if (sym_bind == std.elf.STB_GLOBAL) 'D' else 'd',
            std.elf.STT_SECTION => if (sym_bind == std.elf.STB_GLOBAL) 'B' else 'b',
            std.elf.STT_FILE => 'f',
            else => '?',
        };

        // Print: <value> <type> <name>
        common.printHex(st_value);
        common.stdout(" ");
        common.stdout(&[_]u8{type_letter});
        common.stdout(" ");
        common.stdout(name);
        common.stdout("\n");
    }
}
