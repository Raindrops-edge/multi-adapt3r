const std = @import("std");
const format = @import("format.zig");
const image = @import("image.zig");
const types = @import("types.zig");

pub const c = @import("c.zig").c;
pub const Color = types.Color;
pub const Error = @import("error.zig").Error;
pub const Fixed = types.Fixed;
pub const FormatCode = format.FormatCode;
pub const Image = image.Image;
pub const Op = types.Op;
pub const PointFixed = types.PointFixed;
pub const LineFixed = types.LineFixed;
pub const Triangle = types.Triangle;
pub const Trapezoid = types.Trapezoid;
pub const Rectangle16 = types.Rectangle16;
pub const Box32 = types.Box32;
pub const Indexed = types.Indexed;

test {
    std.testing.refAllDecls(@This());
}
