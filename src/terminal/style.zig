const std = @import("std");
const assert = std.debug.assert;
const color = @import("color.zig");
const sgr = @import("sgr.zig");
const page = @import("page.zig");
const size = @import("size.zig");
const Offset = size.Offset;
const OffsetBuf = size.OffsetBuf;
const RefCountedSet = @import("ref_counted_set.zig").RefCountedSet;

const Wyhash = std.hash.Wyhash;
const autoHash = std.hash.autoHash;

/// The unique identifier for a style. This is at most the number of cells
/// that can fit into a terminal page.
pub const Id = size.CellCountInt;

/// The Id to use for default styling.
pub const default_id: Id = 0;

/// The style attributes for a cell.
pub const Style = struct {
    /// Various colors, all self-explanatory.
    fg_color: Color = .none,
    bg_color: Color = .none,
    underline_color: Color = .none,

    /// On/off attributes that don't require much bit width so we use
    /// a packed struct to make this take up significantly less space.
    flags: packed struct {
        bold: bool = false,
        italic: bool = false,
        faint: bool = false,
        blink: bool = false,
        inverse: bool = false,
        invisible: bool = false,
        strikethrough: bool = false,
        overline: bool = false,
        underline: sgr.Attribute.Underline = .none,
    } = .{},

    /// The color for an SGR attribute. A color can come from multiple
    /// sources so we use this to track the source plus color value so that
    /// we can properly react to things like palette changes.
    pub const Color = union(enum) {
        none: void,
        palette: u8,
        rgb: color.RGB,

        /// Formatting to make debug logs easier to read
        /// by only including non-default attributes.
        pub fn format(
            self: Color,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .none => {
                    _ = try writer.write("Color.none");
                },
                .palette => |p| {
                    _ = try writer.print("Color.palette{{ {} }}", .{p});
                },
                .rgb => |rgb| {
                    _ = try writer.print("Color.rgb{{ {}, {}, {} }}", .{ rgb.r, rgb.g, rgb.b });
                },
            }
        }
    };

    /// True if the style is the default style.
    pub fn default(self: Style) bool {
        return self.eql(.{});
    }

    /// True if the style is equal to another style.
    pub fn eql(self: Style, other: Style) bool {
        return std.meta.eql(self, other);
    }

    /// Returns the bg color for a cell with this style given the cell
    /// that has this style and the palette to use.
    ///
    /// Note that generally if a cell is a color-only cell, it SHOULD
    /// only have the default style, but this is meant to work with the
    /// default style as well.
    pub fn bg(
        self: Style,
        cell: *const page.Cell,
        palette: *const color.Palette,
    ) ?color.RGB {
        return switch (cell.content_tag) {
            .bg_color_palette => palette[cell.content.color_palette],
            .bg_color_rgb => rgb: {
                const rgb = cell.content.color_rgb;
                break :rgb .{ .r = rgb.r, .g = rgb.g, .b = rgb.b };
            },

            else => switch (self.bg_color) {
                .none => null,
                .palette => |idx| palette[idx],
                .rgb => |rgb| rgb,
            },
        };
    }

    /// Returns the fg color for a cell with this style given the palette.
    pub fn fg(
        self: Style,
        palette: *const color.Palette,
        bold_is_bright: bool,
    ) ?color.RGB {
        return switch (self.fg_color) {
            .none => null,
            .palette => |idx| palette: {
                if (bold_is_bright and self.flags.bold) {
                    const bright_offset = @intFromEnum(color.Name.bright_black);
                    if (idx < bright_offset)
                        break :palette palette[idx + bright_offset];
                }

                break :palette palette[idx];
            },
            .rgb => |rgb| rgb,
        };
    }

    /// Returns the underline color for this style.
    pub fn underlineColor(
        self: Style,
        palette: *const color.Palette,
    ) ?color.RGB {
        return switch (self.underline_color) {
            .none => null,
            .palette => |idx| palette[idx],
            .rgb => |rgb| rgb,
        };
    }

    /// Returns a bg-color only cell from this style, if it exists.
    pub fn bgCell(self: Style) ?page.Cell {
        return switch (self.bg_color) {
            .none => null,
            .palette => |idx| .{
                .content_tag = .bg_color_palette,
                .content = .{ .color_palette = idx },
            },
            .rgb => |rgb| .{
                .content_tag = .bg_color_rgb,
                .content = .{ .color_rgb = .{
                    .r = rgb.r,
                    .g = rgb.g,
                    .b = rgb.b,
                } },
            },
        };
    }

    /// Formatting to make debug logs easier to read
    /// by only including non-default attributes.
    pub fn format(
        self: Style,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const dflt: Style = .{};

        _ = try writer.write("Style{ ");

        var started = false;

        inline for (std.meta.fields(Style)) |f| {
            if (std.mem.eql(u8, f.name, "flags")) {
                if (started) {
                    _ = try writer.write(", ");
                }

                _ = try writer.write("flags={ ");

                started = false;

                inline for (std.meta.fields(@TypeOf(self.flags))) |ff| {
                    const v = @as(ff.type, @field(self.flags, ff.name));
                    const d = @as(ff.type, @field(dflt.flags, ff.name));
                    if (ff.type == bool) {
                        if (v) {
                            if (started) {
                                _ = try writer.write(", ");
                            }
                            _ = try writer.print("{s}", .{ff.name});
                            started = true;
                        }
                    } else if (!std.meta.eql(v, d)) {
                        if (started) {
                            _ = try writer.write(", ");
                        }
                        _ = try writer.print(
                            "{s}={any}",
                            .{ ff.name, v },
                        );
                        started = true;
                    }
                }
                _ = try writer.write(" }");

                started = true;
                comptime continue;
            }
            const value = @as(f.type, @field(self, f.name));
            const d_val = @as(f.type, @field(dflt, f.name));
            if (!std.meta.eql(value, d_val)) {
                if (started) {
                    _ = try writer.write(", ");
                }
                _ = try writer.print(
                    "{s}={any}",
                    .{ f.name, value },
                );
                started = true;
            }
        }

        _ = try writer.write(" }");
    }

    pub fn hash(self: *const Style) u64 {
        var hasher = Wyhash.init(0);
        autoHash(&hasher, self.*);
        return hasher.final();
    }

    test {
        // The size of the struct so we can be aware of changes.
        const testing = std.testing;
        try testing.expectEqual(@as(usize, 14), @sizeOf(Style));
    }
};

pub const Set = RefCountedSet(
    Style,
    Id,
    size.CellCountInt,
    struct {
        pub fn hash(self: *const @This(), style: Style) u64 {
            _ = self;
            return style.hash();
        }

        pub fn eql(self: *const @This(), a: Style, b: Style) bool {
            _ = self;
            return a.eql(b);
        }
    },
);

test "Set basic usage" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const layout = Set.layout(16);
    const buf = try alloc.alignedAlloc(u8, Set.base_align, layout.total_size);
    defer alloc.free(buf);

    const style: Style = .{ .flags = .{ .bold = true } };
    const style2: Style = .{ .flags = .{ .italic = true } };

    var set = Set.init(OffsetBuf.init(buf), layout, .{});

    // Add style
    const id = try set.add(buf, style);
    try testing.expect(id > 0);

    // Second add should return the same metadata.
    {
        const id2 = try set.add(buf, style);
        try testing.expectEqual(id, id2);
    }

    // Look it up
    {
        const v = set.get(buf, id);
        try testing.expect(v.flags.bold);

        const v2 = set.get(buf, id);
        try testing.expectEqual(v, v2);
    }

    // Add a second style
    const id2 = try set.add(buf, style2);

    // Look it up
    {
        const v = set.get(buf, id2);
        try testing.expect(v.flags.italic);
    }

    // Ref count
    try testing.expect(set.refCount(buf, id) == 2);
    try testing.expect(set.refCount(buf, id2) == 1);

    // Release
    set.release(buf, id);
    try testing.expect(set.refCount(buf, id) == 1);
    set.release(buf, id2);
    try testing.expect(set.refCount(buf, id2) == 0);

    // We added the first one twice, so
    set.release(buf, id);
    try testing.expect(set.refCount(buf, id) == 0);
}

test "Set capacities" {
    // We want to support at least this many styles without overflowing.
    _ = Set.layout(16384);
}
