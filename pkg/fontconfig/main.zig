pub const c = @import("c.zig");
pub usingnamespace @import("init.zig");
pub usingnamespace @import("char_set.zig");
pub usingnamespace @import("common.zig");
pub usingnamespace @import("config.zig");
pub usingnamespace @import("error.zig");
pub usingnamespace @import("font_set.zig");
pub usingnamespace @import("lang_set.zig");
pub usingnamespace @import("matrix.zig");
pub usingnamespace @import("object_set.zig");
pub usingnamespace @import("pattern.zig");
pub usingnamespace @import("range.zig");
pub usingnamespace @import("value.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test {
    _ = @import("test.zig");
}
