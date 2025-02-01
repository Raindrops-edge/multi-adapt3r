pub const c = @import("c.zig");
pub usingnamespace @import("blob.zig");
pub usingnamespace @import("buffer.zig");
pub usingnamespace @import("common.zig");
pub usingnamespace @import("errors.zig");
pub usingnamespace @import("face.zig");
pub usingnamespace @import("font.zig");
pub usingnamespace @import("shape.zig");
pub usingnamespace @import("version.zig");
pub const freetype = @import("freetype.zig");
pub const coretext = @import("coretext.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
