const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const objc = @import("objc");

const mtl = @import("api.zig");

const log = std.log.scoped(.metal);

/// Metal data storage for a certain set of equal types. This is usually
/// used for vertex buffers, etc. This helpful wrapper makes it easy to
/// prealloc, shrink, grow, sync, buffers with Metal.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: objc.Object, // MTLBuffer

        /// Initialize a buffer with the given length pre-allocated.
        pub fn init(device: objc.Object, len: usize) !Self {
            const buffer = device.msgSend(
                objc.Object,
                objc.sel("newBufferWithLength:options:"),
                .{
                    @as(c_ulong, @intCast(len * @sizeOf(T))),
                    mtl.MTLResourceStorageModeShared,
                },
            );

            return .{ .buffer = buffer };
        }

        /// Init the buffer filled with the given data.
        pub fn initFill(device: objc.Object, data: []const T) !Self {
            const buffer = device.msgSend(
                objc.Object,
                objc.sel("newBufferWithBytes:length:options:"),
                .{
                    @as(*const anyopaque, @ptrCast(data.ptr)),
                    @as(c_ulong, @intCast(data.len * @sizeOf(T))),
                    mtl.MTLResourceStorageModeShared,
                },
            );

            return .{ .buffer = buffer };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.msgSend(void, objc.sel("release"), .{});
        }

        /// Sync new contents to the buffer.
        pub fn sync(self: *Self, device: objc.Object, data: []const T) !void {
            // If we need more bytes than our buffer has, we need to reallocate.
            const req_bytes = data.len * @sizeOf(T);
            const avail_bytes = self.buffer.getProperty(c_ulong, "length");
            if (req_bytes > avail_bytes) {
                // Deallocate previous buffer
                self.buffer.msgSend(void, objc.sel("release"), .{});

                // Allocate a new buffer with enough to hold double what we require.
                const size = req_bytes * 2;
                self.buffer = device.msgSend(
                    objc.Object,
                    objc.sel("newBufferWithLength:options:"),
                    .{
                        @as(c_ulong, @intCast(size * @sizeOf(T))),
                        mtl.MTLResourceStorageModeShared,
                    },
                );
            }

            // We can fit within the buffer so we can just replace bytes.
            const dst = dst: {
                const ptr = self.buffer.msgSend(?[*]u8, objc.sel("contents"), .{}) orelse {
                    log.warn("buffer contents ptr is null", .{});
                    return error.MetalFailed;
                };

                break :dst ptr[0..req_bytes];
            };

            const src = src: {
                const ptr = @as([*]const u8, @ptrCast(data.ptr));
                break :src ptr[0..req_bytes];
            };

            @memcpy(dst, src);
        }
    };
}
