//! This is the render state that is given to a renderer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const terminal = @import("../terminal/main.zig");
const renderer = @import("../renderer.zig");

/// The mutex that must be held while reading any of the data in the
/// members of this state. Note that the state itself is NOT protected
/// by the mutex and is NOT thread-safe, only the members values of the
/// state (i.e. the terminal, devmode, etc. values).
mutex: *std.Thread.Mutex,

/// The terminal data.
terminal: *terminal.Terminal,

/// Dead key state. This will render the current dead key preedit text
/// over the cursor. This currently only ever renders a single codepoint.
/// Preedit can in theory be multiple codepoints long but that is left as
/// a future exercise.
preedit: ?Preedit = null,

/// The pre-edit state. See Surface.preeditCallback for more information.
pub const Preedit = struct {
    /// The codepoint to render as preedit text. We only support single
    /// codepoint for now. In theory this can be multiple codepoints but
    /// that is left as a future exercise.
    ///
    /// This can also be "0" in which case we can know we're in a preedit
    /// mode but we don't have any preedit text to render.
    codepoint: u21 = 0,
};
