//! Inspired by WebKit's quirks.cpp[1], this file centralizes all our
//! sad environment-specific hacks that we have to do to make things work.
//! This is a last resort; if we can find a general solution to a problem,
//! we of course prefer that, but sometimes other software, fonts, etc. are
//! just broken or weird and we have to work around it.
//!
//! [1]: https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/Quirks.cpp

const std = @import("std");

const font = @import("font/main.zig");

/// If true, the default font features should be disabled for the given face.
pub fn disableDefaultFontFeatures(face: *const font.Face) bool {
    _ = face;

    // This function used to do something, but we integrated the logic
    // we checked for directly into our shaping algorithm. It's likely
    // there are other broken fonts for other reasons so I'm keeping this
    // around so its easy to add more checks in the future.
    return false;

    // var buf: [64]u8 = undefined;
    // const name = face.name(&buf) catch |err| switch (err) {
    //     // If the name doesn't fit in buf we know this will be false
    //     // because we have no quirks fonts that are longer than buf!
    //     error.OutOfMemory => return false,
    // };
}
