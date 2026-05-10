// ===============================================================
// File: DeclArgs.zig
// Description: An argument parser library for Zig programs
// ===============================================================
//
// Guiding Principles: https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap12.html#tag_12_02
//  + optional long options
//

const std = @import("std");

//> {{{ DeclArgs
pub const DeclArgs = @This();

//>> {{{ Structs
//>>> {{{ ArgInfo
// Used by long/short option maps
const ArgInfo = struct {
    name: [:0]const u8,
    arity: Arity,
};
//<<< }}}
//>>> {{{ Arity
pub const Arity = union(enum) {
    none,
    one,
    accumulate: usize, // the max
};
//<<< }}}
//>>> {{{ Argument
// Used to declare a command line argument
pub const Argument = struct {
    // name:         Name of the option        (NOTE: sentinel-terminated for enum field names)
    // longopt:      Long Option string        (NOTE: Do not include '--' prefix.  e.g. unbuffered)
    // shortopt:     Short Option character    (NOTE: Do not include '-' prefix.   e.g. -u)
    // description:  Used to generate "Usage"
    // arity:        Does the option take (none|one|accumulate) additional parameters?
    // value_hint:   What type of values does it take (e.g. PATH, ADDR:PORT, etc.)
    name: [:0]const u8,
    longopt: ?[]const u8 = null,
    shortopt: u8,
    description: []const u8,
    arity: Arity = .none,
    value_hint: ?[]const u8 = null,
};
//<<< }}}
//<< }}}
//>> {{{ Parser() The Main Public Interface
// Comptime Parser Builder
pub fn Parser(comptime args: []const Argument) type {
    // Validate Arguments passed
    if (validateArgs(args)) |msg| @compileError(msg);

    // Parser calls buildCmdOpts
    const GeneratedCmdOpts = buildCmdOpts(args);

    // then defines GeneratedParser which contains Opts, parse(), and usage()
    //>>> {{{ Returning Struct
    const GeneratedParser = struct {
        // Type information for caller to cite if needed
        pub const CmdOpts = GeneratedCmdOpts;

        // Argument mappings for O(1) Lookup of options -> ArgInfo
        const long_map = buildLongMap(args);
        const short_map = buildShortMap(args);

        // the "GeneratedParser" struct shall have a parse() function
        //>>>> {{{ parse()
        pub fn parse(argv: []const [:0]const u8) !CmdOpts {
            // States for the parsing state machine
            const State = enum { start, longopt, shortopt, positional };

            // Start with a CmdOpts with command name and default values for the rest
            var result: CmdOpts = .{
                .command = argv[0],
            };

            // Use index of 1 as starting point (0 was command above)
            var i: usize = 1;

            // switch (State.start) tells this labelled switch where to START
            parse: switch (State.start) {
                .start => {
                    // If we've read the end of the tokens, return the parsed result
                    if (i >= argv.len) return result;
                    // "Peek" the next token
                    const token = argv[i];
                    // If this token is a bare "--", advance (ignore it) and go to positinal
                    if (std.mem.eql(u8, token, "--")) {
                        i += 1;
                        continue :parse .positional;
                    }
                    // If this token is a bare "-", and go to positinal (stdin)
                    if (std.mem.eql(u8, token, "-")) {
                        continue :parse .positional;
                    }
                    // LongOpt
                    if (std.mem.startsWith(u8, token, "--")) continue :parse .longopt;
                    // ShortOpt
                    if (std.mem.startsWith(u8, token, "-")) continue :parse .shortopt;
                    // Start of Positionals
                    continue :parse .positional;
                },
                .longopt => {
                    // "Take" the next Token (without the leading "--")
                    const token = argv[i][2..];
                    i += 1;
                    // Lookup the option to see if this is a valid longopt
                    const arg_info = long_map.get(token) orelse return error.InvalidLongOpt;
                    // Act according to the flag
                    switch (arg_info.arity) {
                        // Binary flag
                        .none => setNone(args, &result, arg_info.name),
                        // One value flag
                        .one => {
                            if (i >= argv.len) return error.MissingValue;
                            setOne(args, &result, arg_info.name, argv[i]);
                            i += 1;
                        },
                        // Accumulating flag
                        .accumulate => {
                            if (i >= argv.len) return error.MissingValue;
                            try setAccum(args, &result, arg_info.name, argv[i]);
                            i += 1;
                        },
                    }
                    continue :parse .start;
                },
                .shortopt => {
                    // "Take" the next Token (without the leading "-")
                    // also, cast it to include the sentinel, to make sure we're working on a sentinel-terminated slice
                    const token = argv[i][1..argv[i].len :0];
                    i += 1;
                    // Look at each individual characters
                    var j: usize = 0;
                    while (true) {
                        // "Peek" next flag to see if it exists
                        if (j >= token.len) continue :parse .start;
                        // "Take" next flag
                        const flag = token[j];
                        j += 1;
                        // Check validity of flag
                        const arg_info = short_map[@as(usize, flag)] orelse return error.InvalidShortOpt;
                        // Act according to the flag
                        switch (arg_info.arity) {
                            // Binary flag
                            .none => setNone(args, &result, arg_info.name),
                            // One value flag
                            .one => {
                                // initialize "value" variable for assignment
                                var value: [:0]const u8 = "";
                                // if flag is at end of token string
                                if (j >= token.len) {
                                    // if next token does not exist, error
                                    if (i >= argv.len) return error.MissingValue;
                                    // otherwise, "Take" next token as value
                                    value = argv[i];
                                    i += 1;
                                } else {
                                    // otherwise, the rest of token IS the value
                                    value = token[j..];
                                }
                                setOne(args, &result, arg_info.name, value);
                                continue :parse .start;
                            },
                            .accumulate => {
                                // initialize "value" variable for assignment
                                var value: [:0]const u8 = "";
                                // if flag is at end of token string
                                if (j >= token.len) {
                                    // if next token does not exist, error
                                    if (i >= argv.len) return error.MissingValue;
                                    // otherwise, "Take" next token as value
                                    value = argv[i];
                                    i += 1;
                                } else {
                                    // otherwise, use the rest of token as value
                                    value = token[j..];
                                }
                                try setAccum(args, &result, arg_info.name, value);
                                continue :parse .start;
                            },
                        }
                    }
                },
                .positional => {
                    result.positionals = argv[i..];
                    return result;
                },
            }
        }
        //<<<< }}}

        //>>>> {{{ usage()
        pub fn usage(command: []const u8, writer: *std.Io.Writer) !void {
            // Step 1: Build the grouped .none token
            // Count .none flags first
            comptime var none_count = 0;
            inline for (args) |arg| {
                if (arg.arity == .none) none_count += 1;
            }

            // Build [-abc] string at comptime
            comptime var none_token: []const u8 = "";
            if (none_count > 0) {
                none_token = "[-";
                inline for (args) |arg| {
                    if (arg.arity == .none)
                        none_token = none_token ++ .{arg.shortopt};
                }
                none_token = none_token ++ "]";
            }

            // Step 2: Build the synopsis parts that are available at comptime
            comptime var options_synopsis: []const u8 = "";
            if (none_count > 0)
                options_synopsis = options_synopsis ++ none_token ++ " ";
            inline for (args) |arg| {
                switch (arg.arity) {
                    .one => options_synopsis = options_synopsis ++ "[-" ++ .{arg.shortopt} ++ " " ++ arg.value_hint.? ++ "] ",
                    .accumulate => options_synopsis = options_synopsis ++ "[-" ++ .{arg.shortopt} ++ " " ++ arg.value_hint.? ++ "]... ",
                    .none => {},
                }
            }
            options_synopsis = options_synopsis ++ "[operand...]";

            // Step 3: Check length and print (runtime)
            const name = std.fs.path.basename(command);
            if (name.len + 1 + options_synopsis.len <= 76) {
                try writer.print("Usage: {s} {s}\n", .{ name, options_synopsis });
            } else {
                try writer.print("Usage: {s} [options] [operands]\n", .{name});
            }

            // Step 4: Calculate left column widths at comptime
            comptime var max_left: usize = 0;
            inline for (args) |arg| {
                // Short options will always look like this: "  -u" = 4 always
                comptime var entry_len: usize = 4;
                // Long Option, if present, will be displayed like this: ", --longopt"
                if (arg.longopt) |long|
                    entry_len += 4 + long.len; // ", --" ++ longopt
                // " HINT" for .one and .accumulate
                switch (arg.arity) {
                    .one, .accumulate => entry_len += 1 + arg.value_hint.?.len, // " " ++ hint
                    .none => {},
                }
                if (entry_len > max_left)
                    max_left = entry_len;
            }

            // Step 5: Print options section
            try writer.print("Options:\n", .{});
            inline for (args) |arg| {
                // Build left column
                comptime var left: []const u8 = "  -" ++ .{arg.shortopt};
                if (arg.longopt) |long|
                    left = left ++ ", --" ++ long;
                switch (arg.arity) {
                    .one, .accumulate => left = left ++ " " ++ arg.value_hint.?,
                    .none => {},
                }
                // Pad to max_left
                comptime var pad: []const u8 = "";
                comptime var pad_len: usize = max_left - left.len;
                inline while (pad_len > 0) : (pad_len -= 1)
                    pad = pad ++ " ";
                // Print left + padding + gap + description
                try writer.print("{s}{s}    {s}\n", .{ left, pad, arg.description });
            }
        }
        //<<<< }}}
    };
    //<<< }}}

    // and finally, returns this newly built struct
    return GeneratedParser;
}
//<< }}}
//>> {{{ Factory Functions
//>>> {{{ Struct Factory
fn buildCmdOpts(comptime args: []const Argument) type {
    // ========================================================
    //    Build the CmdOpts struct
    // ========================================================
    // array to hold the field names, tyes, and attributes
    var field_names: [args.len + 2][:0]const u8 = undefined;
    var field_types: [args.len + 2]type = undefined;
    var field_attrs: [args.len + 2]std.builtin.Type.StructField.Attributes = undefined;

    // --- First, the static ones (not Argument) ---
    // Command
    field_names[0] = "command";
    field_types[0] = [:0]const u8;
    field_attrs[0] = .{ .default_value_ptr = null };
    // Positionals
    field_names[1] = "positionals";
    field_types[1] = []const [:0]const u8;
    field_attrs[1] = .{ .default_value_ptr = @ptrCast(&@as([]const [:0]const u8, &.{})) };

    // --- Next, the dynamically generated Arguments fields ---
    for (args, 0..) |arg, i| {
        const idx = i + 2;
        // Name does not need switching on arg.arity
        field_names[idx] = arg.name;
        // Type and Attributes need switching on arg.arity
        switch (arg.arity) {
            // Binary flag
            .none => {
                field_types[idx] = bool;
                field_attrs[idx] = .{ .default_value_ptr = @ptrCast(&false) };
            },
            // Flag with a value
            .one => {
                field_types[idx] = ?[:0]const u8;
                field_attrs[idx] = .{ .default_value_ptr = @ptrCast(&@as(?[:0]const u8, null)) };
            },
            // Flag that accumulates values if repeated
            .accumulate => |max| {
                // per-flag struct to store slices
                const AccumField = struct {
                    items: [max][:0]const u8,
                    len: usize = 0,
                };
                const default = AccumField{ .items = undefined, .len = 0 };
                field_types[idx] = AccumField;
                field_attrs[idx] = .{ .default_value_ptr = @ptrCast(&default) };
            },
        }
    }
    return @Struct(
        .auto, // let Zig decide field ordering and padding, same as a normal struct
        null, // no backing integer (option here for packed structs, that I'd likely never need)
        &field_names,
        &field_types,
        &field_attrs,
    );
}
//<<< }}}
//>>> {{{ Short Option Map Factory
fn buildShortMap(comptime args: []const Argument) [128]?ArgInfo {
    // Fill array with nulls (0-127 selected for ASCII characters)
    var map = [_]?ArgInfo{null} ** 128;
    for (args) |arg| {
        map[arg.shortopt] = .{
            .name = arg.name,
            .arity = arg.arity,
        };
    }
    return map;
}
//<<< }}}
//>>> {{{ Long Option Map Factory
fn buildLongMap(comptime args: []const Argument) std.StaticStringMap(ArgInfo) {
    // Count the number of args that have longopt
    // This must be known at comptime, because the array size must be known at comptime
    comptime var count = 0;
    for (args) |arg| {
        if (arg.longopt != null) count += 1;
    }

    // Define a fixed size array that holds key, value
    var kvs: [count]struct { []const u8, ArgInfo } = undefined;
    var i = 0;
    for (args) |arg| {
        if (arg.longopt) |long| {
            kvs[i] = .{ long, .{ .name = arg.name, .arity = arg.arity } };
            i += 1;
        }
    }

    // The .initComptime(&kvs) is what generates this at comptime
    return std.StaticStringMap(ArgInfo).initComptime(&kvs);
}
//<<< }}}
//<< }}}
//>> {{{ Argument Validator
fn validateArgs(comptime args: []const Argument) ?[]const u8 {
    @setEvalBranchQuota(10000);
    comptime var seen_shortopts: []const u8 = "";
    comptime var seen_longopts: []const u8 = "";
    comptime var seen_names: []const u8 = "";
    inline for (args) |arg| {
        // Duplicate checks
        const short_key = &[_]u8{ '|', arg.shortopt, '|' };
        if (std.mem.indexOf(u8, seen_shortopts, short_key) != null)
            return "Duplicate shortopt '" ++ &[_]u8{arg.shortopt} ++ "' in argument '" ++ arg.name ++ "'";
        seen_shortopts = seen_shortopts ++ short_key;

        if (arg.longopt) |longopt| {
            const long_key = "|" ++ longopt ++ "|";
            if (std.mem.indexOf(u8, seen_longopts, long_key) != null)
                return "Duplicate longopt '" ++ longopt ++ "'";
            seen_longopts = seen_longopts ++ long_key;
        }

        const name_key = "|" ++ arg.name ++ "|";
        if (std.mem.indexOf(u8, seen_names, name_key) != null)
            return "Duplicate name '" ++ arg.name ++ "'";
        seen_names = seen_names ++ name_key;

        // Field checks
        if (arg.description.len == 0)
            return "Argument '" ++ arg.name ++ "' has an empty description";
        switch (arg.arity) {
            .accumulate => |max| {
                if (max == 0)
                    return "Argument '" ++ arg.name ++ "' has accumulate max of 0, which is invalid";
                if (arg.value_hint == null)
                    return "Argument '" ++ arg.name ++ "' has arity .one or .accumulate but no value_hint";
            },
            .one => {
                if (arg.value_hint == null)
                    return "Argument '" ++ arg.name ++ "' has arity .one or .accumulate but no value_hint";
            },
            .none => {
                if (arg.value_hint != null)
                    return "Argument '" ++ arg.name ++ "' has arity .none but value_hint is set — did you forget to set arity?";
            },
        }
    }
    return null;
}
//<< }}}
//>> {{{ Option Value Setters
//>>> {{{ Arity.none
fn setNone(comptime args: []const Argument, result_ptr: anytype, field_name: []const u8) void {
    inline for (args) |arg| {
        // Do NOT make a IF statement except for those that have arg.arity == .none
        comptime {
            if (arg.arity != .none) continue;
        }
        if (std.mem.eql(u8, arg.name, field_name)) {
            // We are taking a pointer, so that we don't get the struct by value.
            // However, because @field needs to work on the actual struct...
            // dereference it (result_ptr.*), so that @field can work on the actual struc.
            // This avoids copying the struct over here.
            @field(result_ptr.*, arg.name) = true;
            break;
        }
    }
}
//<<< }}}
//>>> {{{ Arity.one
fn setOne(comptime args: []const Argument, result_ptr: anytype, field_name: []const u8, field_value: [:0]const u8) void {
    inline for (args) |arg| {
        // Do NOT make a IF statement except for those that have arg.arity == .one
        comptime {
            if (arg.arity != .one) continue;
        }
        if (std.mem.eql(u8, arg.name, field_name)) {
            // We are taking a pointer, so that we don't get the struct by value.
            // However, because @field needs to work on the actual struct...
            // dereference it (result_ptr.*), so that @field can work on the actual struc.
            // This avoids copying the struct over here.
            @field(result_ptr.*, arg.name) = field_value;
            break;
        }
    }
}
//<<< }}}
//>>> {{{ Arity.accumulate
fn setAccum(comptime args: []const Argument, result_ptr: anytype, field_name: []const u8, appending_value: [:0]const u8) !void {
    inline for (args) |arg| {
        // Do NOT make a IF statement except for those that have arg.arity == .accumulate
        comptime {
            if (arg.arity != .accumulate) continue;
        }
        if (std.mem.eql(u8, arg.name, field_name)) {
            // We are taking a pointer, so that we don't get the struct by value.
            // However, because @field needs to work on the actual struct...
            // dereference it (result_ptr.*), so that @field can work on the actual struc.
            // This avoids copying the struct over here.
            const field = &@field(result_ptr.*, arg.name);
            if (field.len >= field.items.len) return error.AccumMaxExceeded;
            field.items[field.len] = appending_value;
            field.len += 1;
        }
    }
}
//<<< }}}
//<< }}}
//< }}}

//> {{{ Test Section
//>> {{{ Unit Test Helpers
//>>> {{{ Parser test helper
fn runTest(
    comptime args: []const Argument,
    argv: []const [:0]const u8,
) !DeclArgs.Parser(args).CmdOpts {
    const TestingParser = DeclArgs.Parser(args);
    return try TestingParser.parse(argv);
}
//<<< }}}
//>>> {{{ Usage test helper
fn runUsageTest(
    comptime args: []const Argument,
    command: []const u8,
    buffer: []u8,
) ![]u8 {
    var w: std.Io.Writer = .fixed(buffer);
    try DeclArgs.Parser(args).usage(command, &w);
    try w.flush();
    return buffer[0..w.end];
}
//<<< }}}
//<< }}}
//>> {{{ Tests
//>>> {{{ Argument Validation
test "validation: duplicate shortopt returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'a', .description = "First" },
        .{ .name = "bar", .shortopt = 'a', .description = "Second" },
    };
    try std.testing.expectEqualStrings(
        "Duplicate shortopt 'a' in argument 'bar'",
        validateArgs(&bad).?,
    );
}

test "validation: duplicate longopt returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'a', .longopt = "same", .description = "First" },
        .{ .name = "bar", .shortopt = 'b', .longopt = "same", .description = "Second" },
    };
    try std.testing.expectEqualStrings(
        "Duplicate longopt 'same'",
        validateArgs(&bad).?,
    );
}

test "validation: duplicate name returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'a', .description = "First" },
        .{ .name = "foo", .shortopt = 'b', .description = "Second" },
    };
    try std.testing.expectEqualStrings(
        "Duplicate name 'foo'",
        validateArgs(&bad).?,
    );
}

test "validation: empty description returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'f', .description = "" },
    };
    try std.testing.expectEqualStrings(
        "Argument 'foo' has an empty description",
        validateArgs(&bad).?,
    );
}

test "validation: .one without value_hint returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'f', .description = "A flag", .arity = .one },
    };
    try std.testing.expectEqualStrings(
        "Argument 'foo' has arity .one or .accumulate but no value_hint",
        validateArgs(&bad).?,
    );
}

test "validation: .accumulate without value_hint returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'f', .description = "A flag", .arity = .{ .accumulate = 4 } },
    };
    try std.testing.expectEqualStrings(
        "Argument 'foo' has arity .one or .accumulate but no value_hint",
        validateArgs(&bad).?,
    );
}

test "validation: accumulate max of 0 returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'f', .description = "A flag", .arity = .{ .accumulate = 0 }, .value_hint = "VAL" },
    };
    try std.testing.expectEqualStrings(
        "Argument 'foo' has accumulate max of 0, which is invalid",
        validateArgs(&bad).?,
    );
}

test "validation: .none with value_hint returns error message" {
    const bad = [_]Argument{
        .{ .name = "foo", .shortopt = 'f', .description = "A flag", .value_hint = "VAL" },
    };
    try std.testing.expectEqualStrings(
        "Argument 'foo' has arity .none but value_hint is set — did you forget to set arity?",
        validateArgs(&bad).?,
    );
}

test "validation: valid args returns null" {
    const good = [_]Argument{
        .{ .name = "foo", .shortopt = 'f', .description = "A flag" },
    };
    try std.testing.expect(validateArgs(&good) == null);
}

//<<< }}}
//>>> {{{ Long Options
test "longopt .none: --unbuffered sets true" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "--unbuffered" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == true);
}

test "longopt .none: absent flag stays false" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{"prog"};
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == false);
}

test "longopt .one: value is captured" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "--output", "file.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqualStrings("file.txt", result.output.?);
}

test "longopt .one: absent stays null" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{"prog"};
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.output == null);
}

test "longopt .one: missing value returns error" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "--output" };
    try std.testing.expectError(error.MissingValue, runTest(&args, &argv));
}

test "longopt .one: repeated .one takes last value" {
    const args = [_]Argument{
        .{ .name = "output", .shortopt = 'o', .longopt = "output", .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "--output", "first.txt", "--output", "second.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqualStrings("second.txt", result.output.?);
}

test "longopt .accumulate: single value captured" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "Headers for request", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER_LINE" },
    };
    const argv = [_][:0]const u8{ "prog", "--header", "Accept: text/html" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 1), result.header.len);
    try std.testing.expectEqualStrings("Accept: text/html", result.header.items[0]);
}

test "longopt .accumulate: multiple values in order" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "Headers for request", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER_LINE" },
    };
    const argv = [_][:0]const u8{ "prog", "--header", "Accept: text/html", "--header", "X-Foo: bar" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 2), result.header.len);
    try std.testing.expectEqualStrings("Accept: text/html", result.header.items[0]);
    try std.testing.expectEqualStrings("X-Foo: bar", result.header.items[1]);
}

test "longopt .accumulate: exceeding max returns error" {
    const args = [_]Argument{
        .{ .name = "header", .shortopt = 'H', .longopt = "header", .description = "HTTP header", .arity = .{ .accumulate = 2 }, .value_hint = "HEADER" },
    };
    const argv = [_][:0]const u8{ "prog", "--header", "first", "--header", "second", "--header", "third" };
    try std.testing.expectError(error.AccumMaxExceeded, runTest(&args, &argv));
}

test "longopt: -- sentinel makes rest positionals" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "--", "--unbuffered" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == false);
    try std.testing.expectEqual(@as(usize, 1), result.positionals.len);
    try std.testing.expectEqualStrings("--unbuffered", result.positionals[0]);
}

test "longopt: invalid option returns error" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "--nonexistent" };
    try std.testing.expectError(error.InvalidLongOpt, runTest(&args, &argv));
}
//<<< }}}
//>>> {{{ Short Options
test "shortopt .none: -u sets true" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "-u" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == true);
}

test "shortopt .none: stacked -un sets both" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
        .{ .name = "numbered", .longopt = "numbered", .shortopt = 'n', .description = "Line numbers" },
    };
    const argv = [_][:0]const u8{ "prog", "-un" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == true);
    try std.testing.expect(result.numbered == true);
}

test "shortopt .one: -o value captured" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "-o", "file.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqualStrings("file.txt", result.output.?);
}

test "shortopt .one: -ofile.txt adjacent value captured" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "-ofile.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqualStrings("file.txt", result.output.?);
}

test "shortopt .one: missing value returns error" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "-o" };
    try std.testing.expectError(error.MissingValue, runTest(&args, &argv));
}

test "shortopt .one: repeated .one takes last value" {
    const args = [_]Argument{
        .{ .name = "output", .shortopt = 'o', .longopt = "output", .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "-o", "first.txt", "-o", "second.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqualStrings("second.txt", result.output.?);
}

test "shortopt .accumulate: single value captured" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "Headers for request", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER_LINE" },
    };
    const argv = [_][:0]const u8{ "prog", "-H", "Accept: text/html" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 1), result.header.len);
    try std.testing.expectEqualStrings("Accept: text/html", result.header.items[0]);
}

test "shortopt .accumulate: multiple values in order" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "Headers for request", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER_LINE" },
    };
    const argv = [_][:0]const u8{ "prog", "-H", "Accept: text/html", "-H", "X-Foo: bar" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 2), result.header.len);
    try std.testing.expectEqualStrings("Accept: text/html", result.header.items[0]);
    try std.testing.expectEqualStrings("X-Foo: bar", result.header.items[1]);
}

test "shortopt .accumulate: exceeding max returns error" {
    const args = [_]Argument{
        .{ .name = "header", .shortopt = 'H', .longopt = "header", .description = "HTTP header", .arity = .{ .accumulate = 2 }, .value_hint = "HEADER" },
    };
    const argv = [_][:0]const u8{ "prog", "-H", "first", "-H", "second", "-H", "third" };
    try std.testing.expectError(error.AccumMaxExceeded, runTest(&args, &argv));
}

test "shortopt .accumulate: -Hvalue adjacent value captured" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "HTTP header", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER" },
    };
    const argv = [_][:0]const u8{ "prog", "-HAccept: text/html" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 1), result.header.len);
    try std.testing.expectEqualStrings("Accept: text/html", result.header.items[0]);
}

test "shortopt: stacked flags with adjacent value last" {
    const args = [_]Argument{
        .{ .name = "extract", .longopt = "extract", .shortopt = 'x', .description = "Extract" },
        .{ .name = "verbose", .longopt = "verbose", .shortopt = 'v', .description = "Verbose" },
        .{ .name = "file", .longopt = "file", .shortopt = 'f', .description = "Archive file", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "-xvfarchive.tar" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.extract == true);
    try std.testing.expect(result.verbose == true);
    try std.testing.expectEqualStrings("archive.tar", result.file.?);
}

test "shortopt: invalid flag returns error" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "-z" };
    try std.testing.expectError(error.InvalidShortOpt, runTest(&args, &argv));
}
//<<< }}}
//>>> {{{ Positionals
test "positionals: captured after options" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "-u", "file1.txt", "file2.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == true);
    try std.testing.expectEqual(@as(usize, 2), result.positionals.len);
    try std.testing.expectEqualStrings("file1.txt", result.positionals[0]);
    try std.testing.expectEqualStrings("file2.txt", result.positionals[1]);
}

test "positionals: no options just operands" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "file1.txt", "file2.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 2), result.positionals.len);
    try std.testing.expectEqualStrings("file1.txt", result.positionals[0]);
    try std.testing.expectEqualStrings("file2.txt", result.positionals[1]);
}

test "positionals: empty when none given" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{"prog"};
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 0), result.positionals.len);
}
//<<< }}}
//>>> {{{ Mixed
test "mixed: longopt and shortopt together" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output", .arity = .one, .value_hint = "PATH" },
    };
    const argv = [_][:0]const u8{ "prog", "-u", "--output", "file.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == true);
    try std.testing.expectEqualStrings("file.txt", result.output.?);
}

test "mixed: shortopts then -- then positionals verifies all" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Unbuffered output" },
    };
    const argv = [_][:0]const u8{ "prog", "-u", "--", "-z", "file.txt" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == true);
    try std.testing.expectEqual(@as(usize, 2), result.positionals.len);
    try std.testing.expectEqualStrings("-z", result.positionals[0]);
    try std.testing.expectEqualStrings("file.txt", result.positionals[1]);
}

test "mixed: mix of .none .one and .accumulate in single parse" {
    const args = [_]Argument{
        .{ .name = "verbose", .shortopt = 'v', .description = "Verbose output" },
        .{ .name = "output", .shortopt = 'o', .longopt = "output", .description = "Output file", .arity = .one, .value_hint = "PATH" },
        .{ .name = "header", .shortopt = 'H', .longopt = "header", .description = "HTTP header", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER" },
    };
    const argv = [_][:0]const u8{ "prog", "-v", "--output", "file.txt", "--header", "Accept: text/html", "--header", "X-Foo: bar", "operand1" };
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.verbose == true);
    try std.testing.expectEqualStrings("file.txt", result.output.?);
    try std.testing.expectEqual(@as(usize, 2), result.header.len);
    try std.testing.expectEqualStrings("Accept: text/html", result.header.items[0]);
    try std.testing.expectEqualStrings("X-Foo: bar", result.header.items[1]);
    try std.testing.expectEqual(@as(usize, 1), result.positionals.len);
    try std.testing.expectEqualStrings("operand1", result.positionals[0]);
}

//<< }}}
//>>> {{{ Edge Cases
test "edge: bare - becomes positional" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    const argv = [_][:0]const u8{ "prog", "-" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 1), result.positionals.len);
    try std.testing.expectEqualStrings("-", result.positionals[0]);
}

test "edge: -- with nothing after gives empty positionals" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    const argv = [_][:0]const u8{ "prog", "--" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqual(@as(usize, 0), result.positionals.len);
}

test "edge: empty argv gives all defaults" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    const argv = [_][:0]const u8{"prog"};
    const result = try runTest(&args, &argv);
    try std.testing.expect(result.unbuffered == false);
    try std.testing.expectEqual(@as(usize, 0), result.positionals.len);
}

test "edge: command field is set correctly" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    const argv = [_][:0]const u8{ "myprog", "-u" };
    const result = try runTest(&args, &argv);
    try std.testing.expectEqualStrings("myprog", result.command);
}
//<<< }}}
//>>> {{{ Usage
test "usage: basename strips path from command" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "/usr/bin/prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-u] [operand...]\n" ++
            "Options:\n" ++
            "  -u, --unbuffered    Disable output buffering\n",
        output,
    );
}

test "usage: expanded synopsis with .none" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-u] [operand...]\n" ++
            "Options:\n" ++
            "  -u, --unbuffered    Disable output buffering\n",
        output,
    );
}

test "usage: synopsis with only .none flags" {
    const args = [_]Argument{
        .{ .name = "verbose", .shortopt = 'v', .description = "Verbose output" },
        .{ .name = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-vu] [operand...]\n" ++
            "Options:\n" ++
            "  -v    Verbose output\n" ++
            "  -u    Disable output buffering\n",
        output,
    );
}

test "usage: expanded synopsis with .one" {
    const args = [_]Argument{
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output file", .arity = .one, .value_hint = "PATH" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-o PATH] [operand...]\n" ++
            "Options:\n" ++
            "  -o, --output PATH    Output file\n",
        output,
    );
}

test "usage: expanded synopsis with .accumulate" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "HTTP header", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-H HEADER]... [operand...]\n" ++
            "Options:\n" ++
            "  -H, --header HEADER    HTTP header\n",
        output,
    );
}

test "usage: collapsed synopsis when over 76 columns" {
    const args = [_]Argument{
        .{ .name = "aaa", .longopt = "aaa", .shortopt = 'a', .description = "Option a", .arity = .one, .value_hint = "AAAAAAAAAA" },
        .{ .name = "bbb", .longopt = "bbb", .shortopt = 'b', .description = "Option b", .arity = .one, .value_hint = "BBBBBBBBBB" },
        .{ .name = "ccc", .longopt = "ccc", .shortopt = 'c', .description = "Option c", .arity = .one, .value_hint = "CCCCCCCCCC" },
        .{ .name = "ddd", .longopt = "ddd", .shortopt = 'd', .description = "Option d", .arity = .one, .value_hint = "DDDDDDDDDD" },
    };
    var buf: [512]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [options] [operands]\n" ++
            "Options:\n" ++
            "  -a, --aaa AAAAAAAAAA    Option a\n" ++
            "  -b, --bbb BBBBBBBBBB    Option b\n" ++
            "  -c, --ccc CCCCCCCCCC    Option c\n" ++
            "  -d, --ddd DDDDDDDDDD    Option d\n",
        output,
    );
}

test "usage: no longopt" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-u] [operand...]\n" ++
            "Options:\n" ++
            "  -u    Disable output buffering\n",
        output,
    );
}

test "usage: options section alignment with mixed longopt" {
    const args = [_]Argument{
        .{ .name = "unbuffered", .longopt = "unbuffered", .shortopt = 'u', .description = "Disable output buffering" },
        .{ .name = "verbose", .shortopt = 'v', .description = "Verbose output" },
        .{ .name = "output", .longopt = "output", .shortopt = 'o', .description = "Output file", .arity = .one, .value_hint = "PATH" },
    };
    var buf: [512]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-uv] [-o PATH] [operand...]\n" ++
            "Options:\n" ++
            "  -u, --unbuffered     Disable output buffering\n" ++
            "  -v                   Verbose output\n" ++
            "  -o, --output PATH    Output file\n",
        output,
    );
}

test "usage: synopsis with only .accumulate no .none group" {
    const args = [_]Argument{
        .{ .name = "header", .longopt = "header", .shortopt = 'H', .description = "HTTP header", .arity = .{ .accumulate = 8 }, .value_hint = "HEADER" },
    };
    var buf: [256]u8 = undefined;
    const output = try runUsageTest(&args, "prog", &buf);
    try std.testing.expectEqualStrings(
        "Usage: prog [-H HEADER]... [operand...]\n" ++
            "Options:\n" ++
            "  -H, --header HEADER    HTTP header\n",
        output,
    );
}
//<<< }}}
//< }}}
//< }}}

// vim: set foldmethod=marker:
