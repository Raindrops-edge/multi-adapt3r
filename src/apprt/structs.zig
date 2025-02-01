/// ContentScale is the ratio between the current DPI and the platform's
/// default DPI. This is used to determine how much certain rendered elements
/// need to be scaled up or down.
pub const ContentScale = struct {
    x: f32,
    y: f32,
};

/// The size of the surface in pixels.
pub const SurfaceSize = struct {
    width: u32,
    height: u32,
};

/// The position of the cursor in pixels.
pub const CursorPos = struct {
    x: f32,
    y: f32,
};

/// Input Method Editor (IME) position.
pub const IMEPos = struct {
    x: f64,
    y: f64,
};

/// The clipboard type.
///
/// If this is changed, you must also update ghostty.h
pub const Clipboard = enum(u2) {
    standard = 0, // ctrl+c/v
    selection = 1,
    primary = 2,
};

pub const ClipboardRequestType = enum(u8) {
    paste,
    osc_52_read,
    osc_52_write,
};

/// Clipboard request. This is used to request clipboard contents and must
/// be sent as a response to a ClipboardRequest event.
pub const ClipboardRequest = union(ClipboardRequestType) {
    /// A direct paste of clipboard contents.
    paste: void,

    /// A request to read clipboard contents via OSC 52.
    osc_52_read: Clipboard,

    /// A request to write clipboard contents via OSC 52.
    osc_52_write: Clipboard,
};

/// A desktop notification.
pub const DesktopNotification = struct {
    /// The title of the notification. May be an empty string to not show a
    /// title.
    title: []const u8,

    /// The body of a notification. This will always be shown.
    body: []const u8,
};

/// The tab to jump to. This is non-exhaustive so that integer values represent
/// the index (zero-based) of the tab to jump to. Negative values are special
/// values.
pub const GotoTab = enum(c_int) {
    previous = -1,
    next = -2,
    last = -3,
    _,
};

// This is made extern (c_int) to make interop easier with our embedded
// runtime. The small size cost doesn't make a difference in our union.
pub const SplitDirection = enum(c_int) {
    right,
    down,
};

/// The color scheme in use (light vs dark).
pub const ColorScheme = enum(u2) {
    light = 0,
    dark = 1,
};

/// Selection information
pub const Selection = struct {
    /// Top-left point of the selection in the viewport in scaled
    /// window pixels. (0,0) is the top-left of the window.
    tl_x_px: f64,
    tl_y_px: f64,

    /// The offset of the selection start in cells from the top-left
    /// of the viewport.
    ///
    /// This is a strange metric but its used by macOS.
    offset_start: u32,
    offset_len: u32,
};
