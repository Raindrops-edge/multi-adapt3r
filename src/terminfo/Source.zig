//! Terminfo source format. This can be used to encode terminfo files.
//! This cannot parse terminfo source files yet because it isn't something
//! I need to do but this can be added later.
//!
//! Background: https://invisible-island.net/ncurses/man/terminfo.5.html

const Source = @This();

const std = @import("std");

/// The set of names for the terminal. These match the TERM environment variable
/// and are used to look up this terminal. Historically, the final name in the
/// list was the most common name for the terminal and contains spaces and
/// other characters. See terminfo(5) for details.
names: []const []const u8,

/// The set of capabilities in this terminfo file.
capabilities: []const Capability,

/// A capability in a terminfo file. This also includes any "use" capabilities
/// since they behave just like other capabilities as documented in terminfo(5).
pub const Capability = struct {
    /// The name of capability. This is the "Cap-name" value in terminfo(5).
    name: []const u8,
    value: Value,

    pub const Value = union(enum) {
        /// Canceled value, i.e. suffixed with @
        canceled: void,

        /// Boolean values are always true if they exist so there is no value.
        boolean: void,

        /// Numeric values are always "unsigned decimal integers". The size
        /// of the integer is unspecified in terminfo(5). I chose 32-bits
        /// because it is a common integer size but this may be wrong.
        numeric: u32,

        string: []const u8,
    };
};

/// Encode as a terminfo source file. The encoding is always done in a
/// human-readable format with whitespace. Fields are always written in the
/// order of the slices on this struct; this will not do any reordering.
pub fn encode(self: Source, writer: anytype) !void {
    // Encode the names in the order specified
    for (self.names, 0..) |name, i| {
        if (i != 0) try writer.writeAll("|");
        try writer.writeAll(name);
    }
    try writer.writeAll(",\n");

    // Encode each of the capabilities in the order specified
    for (self.capabilities) |cap| {
        try writer.writeAll("\t");
        try writer.writeAll(cap.name);
        switch (cap.value) {
            .canceled => try writer.writeAll("@"),
            .boolean => {},
            .numeric => |v| try writer.print("#{d}", .{v}),
            .string => |v| try writer.print("={s}", .{v}),
        }
        try writer.writeAll(",\n");
    }
}

/// Returns a ComptimeStringMap for all of the capabilities in this terminfo.
/// The value is the value that should be sent as a response to XTGETTCAP.
/// Important: the value is the FULL response included the escape sequences.
pub fn xtgettcapMap(comptime self: Source) type {
    const KV = struct { []const u8, []const u8 };

    // We have all of our capabilities plus To, TN, and RGB which aren't
    // in the capabilities list but are query-able.
    const len = self.capabilities.len + 3;
    var kvs: [len]KV = .{.{ "", "" }} ** len;

    // We first build all of our entries with raw K=V pairs.
    kvs[0] = .{ "TN", self.names[0] };
    kvs[1] = .{ "Co", "256" };
    kvs[2] = .{ "RGB", "8" };
    for (self.capabilities, 3..) |cap, i| {
        kvs[i] = .{ cap.name, switch (cap.value) {
            .canceled => @compileError("canceled not handled yet"),
            .boolean => "",
            .string => |v| v,
            .numeric => |v| numeric: {
                var buf: [10]u8 = undefined;
                const num_len = std.fmt.formatIntBuf(&buf, v, 10, .upper, .{});
                break :numeric buf[0..num_len];
            },
        } };
    }

    // Now go through and convert them all to hex-encoded strings.
    for (&kvs) |*entry| {
        // The key is just the raw hex-encoded string
        entry[0] = hexencode(entry[0]);

        // The value is more complex
        var buf: [5 + entry[0].len + 1 + (entry[1].len * 2) + 2]u8 = undefined;
        entry[1] = if (std.mem.eql(u8, entry[1], "")) std.fmt.bufPrint(
            &buf,
            "\x1bP1+r{s}\x1b\\",
            .{entry[0]}, // important: hex-encoded name
        ) catch unreachable else std.fmt.bufPrint(
            &buf,
            "\x1bP1+r{s}={s}\x1b\\",
            .{ entry[0], hexencode(entry[1]) }, // important: hex-encoded name
        ) catch unreachable;
    }

    return std.ComptimeStringMap([]const u8, kvs);
}

fn hexencode(comptime input: []const u8) []const u8 {
    return comptime &(std.fmt.bytesToHex(input, .upper));
}

test "xtgettcap map" {
    const testing = std.testing;

    const src: Source = .{
        .names = &.{
            "ghostty",
            "xterm-ghostty",
            "Ghostty",
        },

        .capabilities = &.{
            .{ .name = "am", .value = .{ .boolean = {} } },
            .{ .name = "colors", .value = .{ .numeric = 256 } },
            .{ .name = "Smulx", .value = .{ .string = "\\E[4:%p1%dm" } },
        },
    };

    const map = comptime src.xtgettcapMap();
    try testing.expectEqualStrings(
        "\x1bP1+r616D\x1b\\",
        map.get(hexencode("am")).?,
    );
    try testing.expectEqualStrings(
        "\x1bP1+r536D756C78=5C455B343A25703125646D\x1b\\",
        map.get(hexencode("Smulx")).?,
    );
}

test "encode" {
    const src: Source = .{
        .names = &.{
            "ghostty",
            "xterm-ghostty",
            "Ghostty",
        },

        .capabilities = &.{
            .{ .name = "am", .value = .{ .boolean = {} } },
            .{ .name = "ccc", .value = .{ .canceled = {} } },
            .{ .name = "colors", .value = .{ .numeric = 256 } },
            .{ .name = "bel", .value = .{ .string = "^G" } },
        },
    };

    // Encode
    var buf: [1024]u8 = undefined;
    var buf_stream = std.io.fixedBufferStream(&buf);
    try src.encode(buf_stream.writer());

    const expected =
        \\ghostty|xterm-ghostty|Ghostty,
        \\	am,
        \\	ccc@,
        \\	colors#256,
        \\	bel=^G,
        \\
    ;
    try std.testing.expectEqualStrings(@as([]const u8, expected), buf_stream.getWritten());
}
