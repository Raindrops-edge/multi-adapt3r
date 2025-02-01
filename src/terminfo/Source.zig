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
