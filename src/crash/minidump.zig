pub const reader = @import("minidump/reader.zig");
pub const stream = @import("minidump/stream.zig");
pub const Reader = reader.Reader;

test {
    @import("std").testing.refAllDecls(@This());
}
