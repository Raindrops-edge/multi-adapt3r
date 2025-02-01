const svg = @import("opentype/svg.zig");

pub const SVG = svg.SVG;

test {
    @import("std").testing.refAllDecls(@This());
}
