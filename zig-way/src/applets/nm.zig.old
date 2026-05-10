// applets/nm.zig
//
// nm — write the name list of an object file (DEVELOPMENT)
//
// POSIX Issue 8 Specification
// https://pubs.opengroup.org/onlinepubs/9799919799/utilities/nm.html#tag_20_88
//
const applet_name = "nm";
const std = @import("std");
const Io = std.Io;
const constants = @import("../constants.zig");
const common = @import("../common.zig");
const DeclArgs = @import("../DeclArgs.zig");

const nm_args = [_]DeclArgs.Argument{
    .{
        .name = "help",
        .shortopt = 'h',
        .longopt = "help",
        .description = "Prints this help message.",
    },
    .{
        .name = "all",
        .shortopt = 'A',
        .description = "Write the full pathname or library name of an object on each line.",
    },
    .{
        .name = "external",
        .shortopt = 'e',
        .description = "Write only external (global) and static symbol information.",
    },
    .{
        .name = "full_output",
        .shortopt = 'f',
        .description = "Produce full output.",
    },
    .{
        .name = "global_only",
        .shortopt = 'g',
        .description = "Write only external (global) symbol information",
    },
    .{
        .name = "octal",
        .shortopt = 'o',
        .description = "Numeric values in octal",
    },
    .{
        .name = "portable",
        .shortopt = 'P',
        .description = "Portable format",
    },
    .{
        .name = "numeric_format",
        .shortopt = 't',
        .arity = .one,
        .value_hint = "FORMAT",
        .description = "Numeric in (d)ecimal, (o)ctal, (h)exadecimal format",
    },
    .{
        .name = "undefined",
        .shortopt = 'u',
        .description = "Only undefined symbols.",
    },
    .{
        .name = "sort_value",
        .shortopt = 'v',
        .description = "Sort by value",
    },
    .{
        .name = "hexadecimal",
        .shortopt = 'x',
        .description = "Numeric values in hexadecimal",
    },
};

pub fn run(init: std.process.Init, args: []const [:0]const u8) void {
    // Prepare stderr writer
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(init.io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    // Create parser
    const Parser = DeclArgs.Parser(&nm_args);
    const opts = Parser.parse(args) catch {
        Parser.usage(applet_name, stderr) catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    };

    // Check if positionals were provided
    if (opts.positionals.len <= 0) {
        stderr.print("{s}: no input files\n", .{opts.command}) catch {};
        Parser.usage(applet_name, stderr) catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    }

    // Create stdout writer and handle if help was requested
    var stdout_buf: [constants.WRITE_BUF_SIZE]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    if (common.handleHelp(Parser, opts, stdout) catch false) {
        stdout.flush() catch {};
        std.process.exit(0);
    }

    for (opts.positionals) |path| {
        processFile(init, path, opts, stdout, stderr);
    }

    stdout.flush() catch {};
}

fn processFile(init: std.process.Init, path: [:0]const u8, opts: anytype, stdout: *Io.Writer, stderr: *Io.Writer) void {
    // Create a file reader
    const file_handle = Io.Dir.cwd().openFile(init.io, path, .{}) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    var file_reader_buf: [constants.READ_BUF_SIZE]u8 = undefined;
    var file_reader = file_handle.reader(init.io, &file_reader_buf);
    const file = &file_reader.interface;

    // Read the binary file, and obtain ELF header
    // this is, essentially, a "table of contents"
    const header = std.elf.Header.read(file) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };

    // Obtain an iterator for Section Headers
    var it = header.iterateSectionHeaders(&file_reader);
    // Iterate over then, and find the STRTAB (String Table?: sh_type == 2)
    var symtab_shdr: ?std.elf.Elf64_Shdr = null;
    while (it.next() catch null) |shdr| {
        if (shdr.sh_type == 2) {
            symtab_shdr = shdr;
        }
    }
    stdout.flush() catch {};

    // First, check if symbol table even exist (might be stripped?)
    if (symtab_shdr == null) {
        stderr.print("nm: {s}: no symbols\n", .{path}) catch {};
        stderr.flush() catch {};
        return;
    }
    // Calculate the file offset of STRTAB in the file
    // sh_link (location) * shentsize (section header entry size)
    const strtab_shdr_offset = header.shoff + @as(u64, symtab_shdr.?.sh_link) * @as(u64, header.shentsize);

    // Move the file reader to that position
    file_reader.seekTo(strtab_shdr_offset) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };

    // Read the Section Header
    const strtab_shdr = std.elf.takeSectionHeader(&file_reader.interface, header.is_64, header.endian) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };

    // Now seek to the actual string table data
    file_reader.seekTo(strtab_shdr.sh_offset) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };

    // Read the whole string table into memory
    var strtab_list = std.ArrayList(u8).empty;
    file.appendExact(init.arena.allocator(), &strtab_list, strtab_shdr.sh_size) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    const strtab = strtab_list.items;

    file_reader.seekTo(symtab_shdr.?.sh_offset) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    const sym_count = symtab_shdr.?.sh_size / symtab_shdr.?.sh_entsize;
    var i: u64 = 0;
    while (i < sym_count) : (i += 1) {
        var sym: std.elf.Elf64_Sym = undefined;
        file_reader.interface.readSliceAll(std.mem.asBytes(&sym)) catch |err| {
            common.handleError(err, stderr);
            unreachable;
        };
        const name_offset = sym.st_name;
        const name = std.mem.sliceTo(strtab[name_offset..], 0);

        // First line is has an empty name, the null symbol
        // always at the start of a ELF symbol table.  Ignore.
        if (name.len == 0) continue;

        // In -u was selected, ignore anything not "undefined"
        if (opts.undefined and sym.st_shndx != 0) continue;

        const value = sym.st_value;
        const sym_bind = sym.st_info >> 4;
        if (i < 50) stdout.print("DEBUG sym_bind={d} STB_GLOBAL={d}\n", .{ sym_bind, std.elf.STB_GLOBAL }) catch {};

        if (std.mem.eql(u8, name, "_DYNAMIC")) stdout.print("DEBUG {any}\n", .{sym}) catch {};
        if (opts.global_only and sym_bind != std.elf.STB_GLOBAL) continue;

        const sym_type: u8 = switch (sym.st_info & 0xf) {
            std.elf.STT_FUNC => if (sym_bind == std.elf.STB_GLOBAL) 'T' else 't',
            std.elf.STT_OBJECT => if (sym_bind == std.elf.STB_GLOBAL) 'D' else 'd',
            std.elf.STT_SECTION => if (sym_bind == std.elf.STB_GLOBAL) 'B' else 'b',
            std.elf.STT_FILE => 'f',
            else => if (sym.st_shndx == 0) 'U' else if (sym.st_shndx == @as(u16, std.elf.SHN_ABS)) 'A' else if (sym.st_info == 0) 'a' else '?',
        };
        // if (value == 0 and sym.st_shndx == 0) {
        //     stdout.print("                 {c} {s}\n", .{ sym_type, name }) catch {};
        // } else {
        //     stdout.print("{x:0>16} {c} {s}\n", .{ value, sym_type, name }) catch {};
        // }
        stdout.print("{x:0>16} {c} {s} ({d} bytes)\n", .{ value, sym_type, name, sym.st_size }) catch {};
    }
    // everything that was here before
}
