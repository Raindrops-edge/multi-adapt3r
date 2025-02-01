//! The options that are used to configure a terminal IO implementation.

const builtin = @import("builtin");
const xev = @import("xev");
const apprt = @import("../apprt.zig");
const renderer = @import("../renderer.zig");
const Command = @import("../Command.zig");
const Config = @import("../config.zig").Config;
const termio = @import("../termio.zig");

/// The size of the terminal grid.
grid_size: renderer.GridSize,

/// The size of a single cell, in pixels.
cell_size: renderer.CellSize,

/// The size of the viewport in pixels.
screen_size: renderer.ScreenSize,

/// The padding of the viewport.
padding: renderer.Padding,

/// The full app configuration. This is only available during initialization.
/// The memory it points to is NOT stable after the init call so any values
/// in here must be copied.
full_config: *const Config,

/// The derived configuration for this termio implementation.
config: termio.Termio.DerivedConfig,

/// The backend for termio that implements where reads/writes are sourced.
backend: termio.Backend,

/// The mailbox for the terminal. This is how messages are delivered.
/// If you're using termio.Thread this MUST be "mailbox".
mailbox: termio.Mailbox,

/// The render state. The IO implementation can modify anything here. The
/// surface thread will setup the initial "terminal" pointer but the IO impl
/// is free to change that if that is useful (i.e. doing some sort of dual
/// terminal implementation.)
renderer_state: *renderer.State,

/// A handle to wake up the renderer. This hints to the renderer that that
/// a repaint should happen.
renderer_wakeup: xev.Async,

/// The mailbox for renderer messages.
renderer_mailbox: *renderer.Thread.Mailbox,

/// The mailbox for sending the surface messages.
surface_mailbox: apprt.surface.Mailbox,
