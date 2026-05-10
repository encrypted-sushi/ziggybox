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
const SortWriter = @import("../writers/SortWriter.zig").SortWriter;

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

// Resolved numeric base after considering -o, -x, -t flags
const NumBase = enum { hex, dec, oct };

// Default output field layout (1-based, whitespace-separated):
// field 1 = value, field 2 = type, field 3 = name
// -P portable layout:
// field 1 = name, field 2 = type, field 3 = value, field 4 = size
const SORT_FIELD_NAME: usize = 3;
const SORT_FIELD_VALUE: usize = 1;
const SORT_FIELD_NAME_PORTABLE: usize = 1;
const SORT_FIELD_VALUE_PORTABLE: usize = 3;

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

    // Resolve numeric base: -o and -x are aliases for -t o and -t x
    const base: NumBase = blk: {
        if (opts.octal) break :blk .oct;
        if (opts.hexadecimal) break :blk .hex;
        if (opts.numeric_format) |fmt| {
            if (fmt.len > 0) switch (fmt[0]) {
                'd' => break :blk .dec,
                'o' => break :blk .oct,
                'x' => break :blk .hex,
                else => {
                    stderr.print("{s}: invalid format '{s}'\n", .{ applet_name, fmt }) catch {};
                    stderr.flush() catch {};
                    std.process.exit(1);
                },
            };
        }
        break :blk .dec; // POSIX XSI default
    };

    // Resolve sort field based on -v and -P
    const sort_field: usize = if (opts.sort_value)
        if (opts.portable) SORT_FIELD_VALUE_PORTABLE else SORT_FIELD_VALUE
    else if (opts.portable) SORT_FIELD_NAME_PORTABLE else SORT_FIELD_NAME;

    // Wrap stdout in a SortWriter — always sort, field depends on flags
    var sort_buf: [constants.WRITE_BUF_SIZE]u8 = undefined;
    // var sorter = SortWriter.init(stdout, init.arena.allocator(), &sort_buf, sort_field);
    var sorter = SortWriter.init(stdout, init.gpa, &sort_buf, sort_field);
    sorter.deinit();

    const multi_file = opts.positionals.len > 1;

    for (opts.positionals) |path| {
        processFile(init, path, opts, base, multi_file, &sorter.interface, stderr);
    }

    sorter.flush() catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    stdout.flush() catch {};
}

fn processFile(
    init: std.process.Init,
    path: [:0]const u8,
    opts: anytype,
    base: NumBase,
    multi_file: bool,
    out: *Io.Writer,
    stderr: *Io.Writer,
) void {
    // Print filename header when processing multiple files
    if (multi_file) {
        out.print("\n{s}:\n", .{path}) catch {};
    }

    // Create a file reader
    const file_handle = Io.Dir.cwd().openFile(init.io, path, .{}) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    var file_reader_buf: [constants.READ_BUF_SIZE]u8 = undefined;
    var file_reader = file_handle.reader(init.io, &file_reader_buf);
    const file = &file_reader.interface;

    // Read ELF header
    const header = std.elf.Header.read(file) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };

    // Iterate section headers, find SYMTAB (sh_type == 2)
    var it = header.iterateSectionHeaders(&file_reader);
    var symtab_shdr: ?std.elf.Elf64_Shdr = null;
    while (it.next() catch null) |shdr| {
        if (shdr.sh_type == 2) {
            symtab_shdr = shdr;
        }
    }

    if (symtab_shdr == null) {
        stderr.print("nm: {s}: no symbols\n", .{path}) catch {};
        stderr.flush() catch {};
        return;
    }

    // Find associated STRTAB via sh_link
    const strtab_shdr_offset = header.shoff + @as(u64, symtab_shdr.?.sh_link) * @as(u64, header.shentsize);
    file_reader.seekTo(strtab_shdr_offset) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    const strtab_shdr = std.elf.takeSectionHeader(&file_reader.interface, header.is_64, header.endian) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };

    // Read the whole string table into arena memory
    file_reader.seekTo(strtab_shdr.sh_offset) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    var strtab_list = std.ArrayList(u8).empty;
    file.appendExact(init.arena.allocator(), &strtab_list, strtab_shdr.sh_size) catch |err| {
        common.handleError(err, stderr);
        unreachable;
    };
    const strtab = strtab_list.items;

    // Seek to symbol table and iterate
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
        const name = std.mem.sliceTo(strtab[sym.st_name..], 0);
        if (name.len == 0) continue;

        const sym_bind = sym.st_info >> 4;
        const sym_type_raw = sym.st_info & 0xf;

        // Apply filters
        if (opts.undefined and sym.st_shndx != 0) continue;
        if (opts.global_only and sym_bind != std.elf.STB_GLOBAL) continue;
        if (opts.external) {
            const is_global = sym_bind == std.elf.STB_GLOBAL;
            const is_static = sym_bind == std.elf.STB_LOCAL and
                (sym_type_raw == std.elf.STT_OBJECT or sym_type_raw == std.elf.STT_FUNC);
            if (!is_global and !is_static) continue;
        }

        const sym_type: u8 = switch (sym_type_raw) {
            std.elf.STT_FUNC => if (sym_bind == std.elf.STB_GLOBAL) 'T' else 't',
            std.elf.STT_OBJECT => if (sym_bind == std.elf.STB_GLOBAL) 'D' else 'd',
            std.elf.STT_SECTION => if (sym_bind == std.elf.STB_GLOBAL) 'B' else 'b',
            std.elf.STT_FILE => 'f',
            else => if (sym.st_shndx == 0) 'U' else if (sym.st_shndx == @as(u16, std.elf.SHN_ABS)) 'A' else if (sym.st_info == 0) 'a' else '?',
        };

        // -A: prepend filename
        if (opts.all) {
            out.print("{s}:", .{path}) catch {};
        }

        if (opts.portable) {
            // POSIX portable format: <name> <type> <value> <size>
            out.print("{s} {c} ", .{ name, sym_type }) catch {};
            printNum(sym.st_value, base, out);
            out.print(" ", .{}) catch {};
            printNum(sym.st_size, base, out);
            out.print("\n", .{}) catch {};
        } else {
            // Default format: <value> <type> <name>
            if (sym_type == 'U') {
                out.print("                 {c} {s}\n", .{ sym_type, name }) catch {};
            } else {
                printNum(sym.st_value, base, out);
                out.print(" {c} {s}\n", .{ sym_type, name }) catch {};
            }
        }
    }
}

fn printNum(value: u64, base: NumBase, out: *Io.Writer) void {
    switch (base) {
        .hex => out.print("{x:0>16}", .{value}) catch {},
        .dec => out.print("{d:0>16}", .{value}) catch {},
        .oct => out.print("{o:0>16}", .{value}) catch {},
    }
}
