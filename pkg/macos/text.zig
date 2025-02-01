pub const c = @import("text/c.zig");
pub usingnamespace @import("text/font.zig");
pub usingnamespace @import("text/font_collection.zig");
pub usingnamespace @import("text/font_descriptor.zig");
pub usingnamespace @import("text/font_manager.zig");
pub usingnamespace @import("text/frame.zig");
pub usingnamespace @import("text/framesetter.zig");
pub usingnamespace @import("text/line.zig");
pub usingnamespace @import("text/run.zig");
pub usingnamespace @import("text/stylized_strings.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
