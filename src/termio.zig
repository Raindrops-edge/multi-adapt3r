//! IO implementation and utilities. The IO implementation is responsible
//! for taking the config, spinning up a child process, and handling IO
//! with the terminal.

pub usingnamespace @import("termio/message.zig");
pub const Exec = @import("termio/Exec.zig");
pub const Options = @import("termio/Options.zig");
pub const Thread = @import("termio/Thread.zig");
pub const Mailbox = Thread.Mailbox;

/// The implementation to use for the IO. This is just "exec" for now but
/// this is somewhat pluggable so that in the future we can introduce other
/// options for other platforms (i.e. wasm) or even potentially a vtable
/// implementation for runtime polymorphism.
pub const Impl = Exec;

test {
    @import("std").testing.refAllDecls(@This());
}
