pub const c = @import("os/c.zig");
pub usingnamespace @import("os/log.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
