const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.minidump_stream);

/// The known stream types.
pub const thread_list = @import("stream_threadlist.zig");

/// A stream within the minidump file. A stream can be either in an encoded
/// form or decoded form. The encoded form are raw bytes and aren't validated
/// until they're decoded. The decoded form is a structured form of the stream.
///
/// The decoded form is more ergonomic to work with but the encoded form is
/// more efficient to read/write.
pub const Stream = union(enum) {
    encoded: EncodedStream,
};

/// An encoded stream value. It is "encoded" in the sense that it is raw bytes
/// with a type associated. The raw bytes are not validated to be correct for
/// the type.
pub const EncodedStream = struct {
    type: u32,
    data: []const u8,
};

test {
    @import("std").testing.refAllDecls(@This());
}
