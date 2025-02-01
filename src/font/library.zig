//! A library represents the shared state that the underlying font
//! library implementation(s) require per-process.
const builtin = @import("builtin");
const options = @import("main.zig").options;
const freetype = @import("freetype");
const font = @import("main.zig");

/// Library implementation for the compile options.
pub const Library = switch (options.backend) {
    // Freetype requires a state library
    .freetype,
    .fontconfig_freetype,
    .coretext_freetype,
    => FreetypeLibrary,

    // Some backends such as CT and Canvas don't have a "library"
    .coretext,
    .web_canvas,
    => NoopLibrary,
};

pub const FreetypeLibrary = struct {
    lib: freetype.Library,

    pub fn init() freetype.Error!Library {
        return Library{ .lib = try freetype.Library.init() };
    }

    pub fn deinit(self: *Library) void {
        self.lib.deinit();
    }
};

pub const NoopLibrary = struct {
    pub fn init() !Library {
        return Library{};
    }

    pub fn deinit(self: *Library) void {
        _ = self;
    }
};
