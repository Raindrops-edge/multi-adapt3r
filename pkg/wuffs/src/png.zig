const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c.zig").c;
const Error = @import("error.zig").Error;

const log = std.log.scoped(.wuffs_png);

/// Decode a PNG image.
pub fn decode(alloc: Allocator, data: []const u8) Error!struct {
    width: u32,
    height: u32,
    data: []const u8,
} {
    // Work around some weirdness in WUFFS/Zig, there are some structs that
    // are defined as "extern" by the Zig compiler which means that Zig won't
    // allocate them on the stack at compile time. WUFFS has functions for
    // dynamically allocating these structs but they use the C malloc/free. This
    // gets around that by using the Zig allocator to allocate enough memory for
    // the struct and then casts it to the appropriate pointer.

    const decoder_buf = try alloc.alloc(u8, c.sizeof__wuffs_png__decoder());
    defer alloc.free(decoder_buf);

    const decoder: ?*c.wuffs_png__decoder = @ptrCast(decoder_buf);
    {
        const status = c.wuffs_png__decoder__initialize(
            decoder,
            c.sizeof__wuffs_png__decoder(),
            c.WUFFS_VERSION,
            0,
        );
        if (!c.wuffs_base__status__is_ok(&status)) {
            const e = c.wuffs_base__status__message(&status);
            log.warn("decode err={s}", .{e});
            return error.WuffsError;
        }
    }

    var source_buffer: c.wuffs_base__io_buffer = .{
        .data = .{ .ptr = @constCast(@ptrCast(data.ptr)), .len = data.len },
        .meta = .{
            .wi = data.len,
            .ri = 0,
            .pos = 0,
            .closed = true,
        },
    };

    var image_config: c.wuffs_base__image_config = undefined;
    {
        const status = c.wuffs_png__decoder__decode_image_config(
            decoder,
            &image_config,
            &source_buffer,
        );
        if (!c.wuffs_base__status__is_ok(&status)) {
            const e = c.wuffs_base__status__message(&status);
            log.warn("decode err={s}", .{e});
            return error.WuffsError;
        }
    }

    const width = c.wuffs_base__pixel_config__width(&image_config.pixcfg);
    const height = c.wuffs_base__pixel_config__height(&image_config.pixcfg);

    c.wuffs_base__pixel_config__set(
        &image_config.pixcfg,
        c.WUFFS_BASE__PIXEL_FORMAT__RGBA_PREMUL,
        c.WUFFS_BASE__PIXEL_SUBSAMPLING__NONE,
        width,
        height,
    );

    const destination = try alloc.alloc(
        u8,
        width * height * @sizeOf(c.wuffs_base__color_u32_argb_premul),
    );
    errdefer alloc.free(destination);

    // temporary buffer for intermediate processing of image
    const work_buffer = try alloc.alloc(
        u8,

        // The type of this is a u64 on all systems but our allocator
        // uses a usize which is a u32 on 32-bit systems.
        std.math.cast(
            usize,
            c.wuffs_png__decoder__workbuf_len(decoder).max_incl,
        ) orelse return error.OutOfMemory,
    );
    defer alloc.free(work_buffer);

    const work_slice = c.wuffs_base__make_slice_u8(
        work_buffer.ptr,
        work_buffer.len,
    );

    var pixel_buffer: c.wuffs_base__pixel_buffer = undefined;
    {
        const status = c.wuffs_base__pixel_buffer__set_from_slice(
            &pixel_buffer,
            &image_config.pixcfg,
            c.wuffs_base__make_slice_u8(destination.ptr, destination.len),
        );
        if (!c.wuffs_base__status__is_ok(&status)) {
            const e = c.wuffs_base__status__message(&status);
            log.warn("decode err={s}", .{e});
            return error.WuffsError;
        }
    }

    var frame_config: c.wuffs_base__frame_config = undefined;
    {
        const status = c.wuffs_png__decoder__decode_frame_config(
            decoder,
            &frame_config,
            &source_buffer,
        );
        if (!c.wuffs_base__status__is_ok(&status)) {
            const e = c.wuffs_base__status__message(&status);
            log.warn("decode err={s}", .{e});
            return error.WuffsError;
        }
    }

    {
        const status = c.wuffs_png__decoder__decode_frame(
            decoder,
            &pixel_buffer,
            &source_buffer,
            c.WUFFS_BASE__PIXEL_BLEND__SRC,
            work_slice,
            null,
        );
        if (!c.wuffs_base__status__is_ok(&status)) {
            const e = c.wuffs_base__status__message(&status);
            log.warn("decode err={s}", .{e});
            return error.WuffsError;
        }
    }

    return .{
        .width = width,
        .height = height,
        .data = destination,
    };
}
