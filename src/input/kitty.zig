const std = @import("std");
const key = @import("key.zig");

/// A single entry in the kitty keymap data. There are only ~100 entries
/// so the recommendation is to just use a linear search to find the entry
/// for a given key.
pub const Entry = struct {
    key: key.Key,
    code: u21,
    final: u8,
    modifier: bool,
};

/// The full list of entries for the current platform.
pub const entries: []const Entry = entries: {
    var result: [raw_entries.len]Entry = undefined;
    for (raw_entries, 0..) |raw, i| {
        result[i] = .{
            .key = raw[0],
            .code = raw[1],
            .final = raw[2],
            .modifier = raw[3],
        };
    }
    break :entries &result;
};

/// Raw entry is the tuple form of an entry for easy human management.
/// This should never be used in a real program so it is not pub. For
/// real programs, use `entries` which has properly typed, structured data.
const RawEntry = struct { key.Key, u21, u8, bool };

/// The raw data for how to map keys to Kitty data. Based on the information:
/// https://sw.kovidgoyal.net/kitty/keyboard-protocol/#functional-key-definitions
/// And the exact table is ported from Foot:
/// https://codeberg.org/dnkl/foot/src/branch/master/kitty-keymap.h
///
/// Note that we currently don't support all the same keysyms as Kitty,
/// but we can add them as we add support.
///
/// These are stored in order of the above Kitty link, so it is easy to
/// find the entry for a given key.
const raw_entries: []const RawEntry = &.{
    .{ .escape, 27, 'u', false },
    .{ .enter, 13, 'u', false },
    .{ .tab, 9, 'u', false },
    .{ .backspace, 127, 'u', false },
    .{ .insert, 2, '~', false },
    .{ .delete, 3, '~', false },
    .{ .left, 1, 'D', false },
    .{ .right, 1, 'C', false },
    .{ .up, 1, 'A', false },
    .{ .down, 1, 'B', false },
    .{ .page_up, 5, '~', false },
    .{ .page_down, 6, '~', false },
    .{ .home, 1, 'H', false },
    .{ .end, 1, 'F', false },
    .{ .caps_lock, 57358, 'u', true },
    .{ .scroll_lock, 57359, 'u', false },
    .{ .num_lock, 57360, 'u', true },
    .{ .print_screen, 57361, 'u', false },
    .{ .pause, 57362, 'u', false },

    .{ .f1, 1, 'P', false },
    .{ .f2, 1, 'Q', false },
    .{ .f3, 13, '~', false },
    .{ .f4, 1, 'S', false },
    .{ .f5, 15, '~', false },
    .{ .f6, 17, '~', false },
    .{ .f7, 18, '~', false },
    .{ .f8, 19, '~', false },
    .{ .f9, 20, '~', false },
    .{ .f10, 21, '~', false },
    .{ .f11, 23, '~', false },
    .{ .f12, 24, '~', false },
    .{ .f13, 57376, 'u', false },
    .{ .f14, 57377, 'u', false },
    .{ .f15, 57378, 'u', false },
    .{ .f16, 57379, 'u', false },
    .{ .f17, 57380, 'u', false },
    .{ .f18, 57381, 'u', false },
    .{ .f19, 57382, 'u', false },
    .{ .f20, 57383, 'u', false },
    .{ .f21, 57384, 'u', false },
    .{ .f22, 57385, 'u', false },
    .{ .f23, 57386, 'u', false },
    .{ .f24, 57387, 'u', false },
    .{ .f25, 57388, 'u', false },

    .{ .kp_0, 57399, 'u', false },
    .{ .kp_1, 57400, 'u', false },
    .{ .kp_2, 57401, 'u', false },
    .{ .kp_3, 57402, 'u', false },
    .{ .kp_4, 57403, 'u', false },
    .{ .kp_5, 57404, 'u', false },
    .{ .kp_6, 57405, 'u', false },
    .{ .kp_7, 57406, 'u', false },
    .{ .kp_8, 57407, 'u', false },
    .{ .kp_9, 57408, 'u', false },
    .{ .kp_decimal, 57409, 'u', false },
    .{ .kp_divide, 57410, 'u', false },
    .{ .kp_multiply, 57411, 'u', false },
    .{ .kp_subtract, 57412, 'u', false },
    .{ .kp_add, 57413, 'u', false },
    .{ .kp_enter, 57414, 'u', false },
    .{ .kp_equal, 57415, 'u', false },

    .{ .left_shift, 57441, 'u', true },
    .{ .right_shift, 57447, 'u', true },
    .{ .left_control, 57442, 'u', true },
    .{ .right_control, 57448, 'u', true },
    .{ .left_super, 57444, 'u', true },
    .{ .right_super, 57450, 'u', true },
    .{ .left_alt, 57443, 'u', true },
    .{ .right_alt, 57449, 'u', true },
};

test {
    // To force comptime to test it
    _ = entries;
}
