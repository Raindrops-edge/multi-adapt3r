//! This file contains all the terminal modes that we support
//! and various support types for them: an enum of supported modes,
//! a packed struct to store mode values, a more generalized state
//! struct to store values plus handle save/restore, and much more.
//!
//! There is pretty heavy comptime usage and type generation here.
//! I don't love to have this sort of complexity but its a good way
//! to ensure all our various types and logic remain in sync.

const std = @import("std");
const testing = std.testing;

/// A struct that maintains the state of all the settable modes.
pub const ModeState = struct {
    /// The values of the current modes.
    values: ModePacked = .{},

    /// The saved values. We only allow saving each mode once.
    /// This is in line with other terminals that implement XTSAVE
    /// and XTRESTORE. We can improve this in the future if it becomes
    /// a real-world issue but we need to be aware of a DoS vector.
    saved: ModePacked = .{},

    /// Set a mode to a value.
    pub fn set(self: *ModeState, mode: Mode, value: bool) void {
        switch (mode) {
            inline else => |mode_comptime| {
                const entry = comptime entryForMode(mode_comptime);
                @field(self.values, entry.name) = value;
            },
        }
    }

    /// Get the value of a mode.
    pub fn get(self: *ModeState, mode: Mode) bool {
        switch (mode) {
            inline else => |mode_comptime| {
                const entry = comptime entryForMode(mode_comptime);
                return @field(self.values, entry.name);
            },
        }
    }

    /// Save the state of the given mode. This can then be restored
    /// with restore. This will only be accurate if the previous
    /// mode was saved exactly once and not restored. Otherwise this
    /// will just keep restoring the last stored value in memory.
    pub fn save(self: *ModeState, mode: Mode) void {
        switch (mode) {
            inline else => |mode_comptime| {
                const entry = comptime entryForMode(mode_comptime);
                @field(self.saved, entry.name) = @field(self.values, entry.name);
            },
        }
    }

    /// See save. This will return the restored value.
    pub fn restore(self: *ModeState, mode: Mode) bool {
        switch (mode) {
            inline else => |mode_comptime| {
                const entry = comptime entryForMode(mode_comptime);
                @field(self.values, entry.name) = @field(self.saved, entry.name);
                return @field(self.values, entry.name);
            },
        }
    }

    test {
        // We have this here so that we explicitly fail when we change the
        // size of modes. The size of modes is NOT particularly important,
        // we just want to be mentally aware when it happens.
        try std.testing.expectEqual(4, @sizeOf(ModePacked));
    }
};

/// A packed struct of all the settable modes. This shouldn't
/// be used directly but rather through the ModeState struct.
pub const ModePacked = packed_struct: {
    const StructField = std.builtin.Type.StructField;
    var fields: [entries.len]StructField = undefined;
    for (entries, 0..) |entry, i| {
        fields[i] = .{
            .name = entry.name,
            .type = bool,
            .default_value = &entry.default,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    break :packed_struct @Type(.{ .Struct = .{
        .layout = .Packed,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
};

/// An enum(u16) of the available modes. See entries for available values.
pub const Mode = mode_enum: {
    const EnumField = std.builtin.Type.EnumField;
    var fields: [entries.len]EnumField = undefined;
    for (entries, 0..) |entry, i| {
        fields[i] = .{
            .name = entry.name,
            .value = entry.value,
        };
    }

    break :mode_enum @Type(.{ .Enum = .{
        .tag_type = u16,
        .fields = &fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
};

/// Returns true if we support the given mode. If this is true then
/// you can use `@enumFromInt` to get the Mode value. We don't do
/// this directly due to a Zig compiler bug.
pub fn hasSupport(v: u16) bool {
    inline for (@typeInfo(Mode).Enum.fields) |field| {
        if (field.value == v) return true;
    }

    return false;
}

fn entryForMode(comptime mode: Mode) ModeEntry {
    const name = @tagName(mode);
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry;
    }

    unreachable;
}

/// A single entry of a possible mode we support. This is used to
/// dynamically define the enum and other tables.
const ModeEntry = struct {
    name: []const u8,
    value: comptime_int,
    default: bool = false,
};

/// The full list of available entries. For documentation see how
/// they're used within Ghostty or google their values. It is not
/// valuable to redocument them all here.
const entries: []const ModeEntry = &.{
    .{ .name = "cursor_keys", .value = 1 },
    .{ .name = "132_column", .value = 3 },
    .{ .name = "insert", .value = 4 },
    .{ .name = "reverse_colors", .value = 5 },
    .{ .name = "origin", .value = 6 },
    .{ .name = "autowrap", .value = 7, .default = true },
    .{ .name = "mouse_event_x10", .value = 9 },
    .{ .name = "cursor_blinking", .value = 12 },
    .{ .name = "cursor_visible", .value = 25, .default = true },
    .{ .name = "enable_mode_3", .value = 40 },
    .{ .name = "keypad_keys", .value = 66 },
    .{ .name = "mouse_event_normal", .value = 1000 },
    .{ .name = "mouse_event_button", .value = 1002 },
    .{ .name = "mouse_event_any", .value = 1003 },
    .{ .name = "focus_event", .value = 1004 },
    .{ .name = "mouse_format_utf8", .value = 1005 },
    .{ .name = "mouse_format_sgr", .value = 1006 },
    .{ .name = "mouse_alternate_scroll", .value = 1007, .default = true },
    .{ .name = "mouse_format_urxvt", .value = 1015 },
    .{ .name = "mouse_format_sgr_pixels", .value = 1016 },
    .{ .name = "alt_esc_prefix", .value = 1036, .default = true },
    .{ .name = "alt_sends_escape", .value = 1039 },
    .{ .name = "alt_screen_save_cursor_clear_enter", .value = 1049 },
    .{ .name = "bracketed_paste", .value = 2004 },
    .{ .name = "synchronized_output", .value = 2026 },
};

test {
    _ = Mode;
    _ = ModePacked;
}

test hasSupport {
    try testing.expect(hasSupport(1));
    try testing.expect(hasSupport(2004));
    try testing.expect(!hasSupport(8888));
}

test ModeState {
    var state: ModeState = .{};

    // Normal set/get
    try testing.expect(!state.get(.cursor_keys));
    state.set(.cursor_keys, true);
    try testing.expect(state.get(.cursor_keys));

    // Save/restore
    state.save(.cursor_keys);
    state.set(.cursor_keys, false);
    try testing.expect(!state.get(.cursor_keys));
    try testing.expect(state.restore(.cursor_keys));
    try testing.expect(state.get(.cursor_keys));
}
