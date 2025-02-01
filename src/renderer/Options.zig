//! The options that are used to configure a renderer.

const apprt = @import("../apprt.zig");
const font = @import("../font/main.zig");
const renderer = @import("../renderer.zig");
const Config = @import("../config.zig").Config;

/// The derived configuration for this renderer implementation.
config: renderer.Renderer.DerivedConfig,

/// The font group that should be used.
font_group: *font.GroupCache,

/// Padding options for the viewport.
padding: Padding,

/// The mailbox for sending the surface messages. This is only valid
/// once the thread has started and should not be used outside of the thread.
surface_mailbox: apprt.surface.Mailbox,

pub const Padding = struct {
    // Explicit padding options, in pixels. The surface thread is
    // expected to convert points to pixels for a given DPI.
    explicit: renderer.Padding,

    // Balance options
    balance: bool = false,
};
