const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const macos = @import("macos");
const objc = @import("objc");
const math = @import("../../math.zig");

const mtl = @import("api.zig");

const log = std.log.scoped(.metal);

/// This contains the state for the shaders used by the Metal renderer.
pub const Shaders = struct {
    library: objc.Object,
    cell_pipeline: objc.Object,
    image_pipeline: objc.Object,

    pub fn init(device: objc.Object) !Shaders {
        const library = try initLibrary(device);
        errdefer library.msgSend(void, objc.sel("release"), .{});

        const cell_pipeline = try initCellPipeline(device, library);
        errdefer cell_pipeline.msgSend(void, objc.sel("release"), .{});

        const image_pipeline = try initImagePipeline(device, library);
        errdefer image_pipeline.msgSend(void, objc.sel("release"), .{});

        return .{
            .library = library,
            .cell_pipeline = cell_pipeline,
            .image_pipeline = image_pipeline,
        };
    }

    pub fn deinit(self: *Shaders) void {
        self.cell_pipeline.msgSend(void, objc.sel("release"), .{});
        self.image_pipeline.msgSend(void, objc.sel("release"), .{});
        self.library.msgSend(void, objc.sel("release"), .{});
    }
};

/// This is a single parameter for the terminal cell shader.
pub const Cell = extern struct {
    mode: Mode,
    grid_pos: [2]f32,
    glyph_pos: [2]u32 = .{ 0, 0 },
    glyph_size: [2]u32 = .{ 0, 0 },
    glyph_offset: [2]i32 = .{ 0, 0 },
    color: [4]u8,
    cell_width: u8,

    pub const Mode = enum(u8) {
        bg = 1,
        fg = 2,
        fg_color = 7,
        strikethrough = 8,
    };
};

/// Single parameter for the image shader. See shader for field details.
pub const Image = extern struct {
    grid_pos: [2]f32,
    cell_offset: [2]f32,
    source_rect: [4]f32,
    dest_size: [2]f32,
};

/// The uniforms that are passed to the terminal cell shader.
pub const Uniforms = extern struct {
    /// The projection matrix for turning world coordinates to normalized.
    /// This is calculated based on the size of the screen.
    projection_matrix: math.Mat,

    /// Size of a single cell in pixels, unscaled.
    cell_size: [2]f32,

    /// Metrics for underline/strikethrough
    strikethrough_position: f32,
    strikethrough_thickness: f32,
};

/// Initialize the MTLLibrary. A MTLLibrary is a collection of shaders.
fn initLibrary(device: objc.Object) !objc.Object {
    // Hardcoded since this file isn't meant to be reusable.
    const data = @embedFile("../shaders/cell.metal");
    const source = try macos.foundation.String.createWithBytes(
        data,
        .utf8,
        false,
    );
    defer source.release();

    var err: ?*anyopaque = null;
    const library = device.msgSend(
        objc.Object,
        objc.sel("newLibraryWithSource:options:error:"),
        .{
            source,
            @as(?*anyopaque, null),
            &err,
        },
    );
    try checkError(err);

    return library;
}

/// Initialize the cell render pipeline for our shader library.
fn initCellPipeline(device: objc.Object, library: objc.Object) !objc.Object {
    // Get our vertex and fragment functions
    const func_vert = func_vert: {
        const str = try macos.foundation.String.createWithBytes(
            "uber_vertex",
            .utf8,
            false,
        );
        defer str.release();

        const ptr = library.msgSend(?*anyopaque, objc.sel("newFunctionWithName:"), .{str});
        break :func_vert objc.Object.fromId(ptr.?);
    };
    const func_frag = func_frag: {
        const str = try macos.foundation.String.createWithBytes(
            "uber_fragment",
            .utf8,
            false,
        );
        defer str.release();

        const ptr = library.msgSend(?*anyopaque, objc.sel("newFunctionWithName:"), .{str});
        break :func_frag objc.Object.fromId(ptr.?);
    };

    // Create the vertex descriptor. The vertex descriptor describes the
    // data layout of the vertex inputs. We use indexed (or "instanced")
    // rendering, so this makes it so that each instance gets a single
    // Cell as input.
    const vertex_desc = vertex_desc: {
        const desc = init: {
            const Class = objc.Class.getClass("MTLVertexDescriptor").?;
            const id_alloc = Class.msgSend(objc.Object, objc.sel("alloc"), .{});
            const id_init = id_alloc.msgSend(objc.Object, objc.sel("init"), .{});
            break :init id_init;
        };

        // Our attributes are the fields of the input
        const attrs = objc.Object.fromId(desc.getProperty(?*anyopaque, "attributes"));
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 0)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.uchar));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "mode")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 1)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "grid_pos")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 2)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.uint2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "glyph_pos")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 3)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.uint2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "glyph_size")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 4)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.int2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "glyph_offset")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 5)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.uchar4));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "color")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 6)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.uchar));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Cell, "cell_width")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }

        // The layout describes how and when we fetch the next vertex input.
        const layouts = objc.Object.fromId(desc.getProperty(?*anyopaque, "layouts"));
        {
            const layout = layouts.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 0)},
            );

            // Access each Cell per instance, not per vertex.
            layout.setProperty("stepFunction", @intFromEnum(mtl.MTLVertexStepFunction.per_instance));
            layout.setProperty("stride", @as(c_ulong, @sizeOf(Cell)));
        }

        break :vertex_desc desc;
    };

    // Create our descriptor
    const desc = init: {
        const Class = objc.Class.getClass("MTLRenderPipelineDescriptor").?;
        const id_alloc = Class.msgSend(objc.Object, objc.sel("alloc"), .{});
        const id_init = id_alloc.msgSend(objc.Object, objc.sel("init"), .{});
        break :init id_init;
    };

    // Set our properties
    desc.setProperty("vertexFunction", func_vert);
    desc.setProperty("fragmentFunction", func_frag);
    desc.setProperty("vertexDescriptor", vertex_desc);

    // Set our color attachment
    const attachments = objc.Object.fromId(desc.getProperty(?*anyopaque, "colorAttachments"));
    {
        const attachment = attachments.msgSend(
            objc.Object,
            objc.sel("objectAtIndexedSubscript:"),
            .{@as(c_ulong, 0)},
        );

        // Value is MTLPixelFormatBGRA8Unorm
        attachment.setProperty("pixelFormat", @as(c_ulong, 80));

        // Blending. This is required so that our text we render on top
        // of our drawable properly blends into the bg.
        attachment.setProperty("blendingEnabled", true);
        attachment.setProperty("rgbBlendOperation", @intFromEnum(mtl.MTLBlendOperation.add));
        attachment.setProperty("alphaBlendOperation", @intFromEnum(mtl.MTLBlendOperation.add));
        attachment.setProperty("sourceRGBBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one));
        attachment.setProperty("sourceAlphaBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one));
        attachment.setProperty("destinationRGBBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one_minus_source_alpha));
        attachment.setProperty("destinationAlphaBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one_minus_source_alpha));
    }

    // Make our state
    var err: ?*anyopaque = null;
    const pipeline_state = device.msgSend(
        objc.Object,
        objc.sel("newRenderPipelineStateWithDescriptor:error:"),
        .{ desc, &err },
    );
    try checkError(err);

    return pipeline_state;
}

/// Initialize the image render pipeline for our shader library.
fn initImagePipeline(device: objc.Object, library: objc.Object) !objc.Object {
    // Get our vertex and fragment functions
    const func_vert = func_vert: {
        const str = try macos.foundation.String.createWithBytes(
            "image_vertex",
            .utf8,
            false,
        );
        defer str.release();

        const ptr = library.msgSend(?*anyopaque, objc.sel("newFunctionWithName:"), .{str});
        break :func_vert objc.Object.fromId(ptr.?);
    };
    const func_frag = func_frag: {
        const str = try macos.foundation.String.createWithBytes(
            "image_fragment",
            .utf8,
            false,
        );
        defer str.release();

        const ptr = library.msgSend(?*anyopaque, objc.sel("newFunctionWithName:"), .{str});
        break :func_frag objc.Object.fromId(ptr.?);
    };

    // Create the vertex descriptor. The vertex descriptor describes the
    // data layout of the vertex inputs. We use indexed (or "instanced")
    // rendering, so this makes it so that each instance gets a single
    // Image as input.
    const vertex_desc = vertex_desc: {
        const desc = init: {
            const Class = objc.Class.getClass("MTLVertexDescriptor").?;
            const id_alloc = Class.msgSend(objc.Object, objc.sel("alloc"), .{});
            const id_init = id_alloc.msgSend(objc.Object, objc.sel("init"), .{});
            break :init id_init;
        };

        // Our attributes are the fields of the input
        const attrs = objc.Object.fromId(desc.getProperty(?*anyopaque, "attributes"));
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 1)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Image, "grid_pos")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 2)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Image, "cell_offset")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 3)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float4));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Image, "source_rect")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }
        {
            const attr = attrs.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 4)},
            );

            attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float2));
            attr.setProperty("offset", @as(c_ulong, @offsetOf(Image, "dest_size")));
            attr.setProperty("bufferIndex", @as(c_ulong, 0));
        }

        // The layout describes how and when we fetch the next vertex input.
        const layouts = objc.Object.fromId(desc.getProperty(?*anyopaque, "layouts"));
        {
            const layout = layouts.msgSend(
                objc.Object,
                objc.sel("objectAtIndexedSubscript:"),
                .{@as(c_ulong, 0)},
            );

            // Access each Image per instance, not per vertex.
            layout.setProperty("stepFunction", @intFromEnum(mtl.MTLVertexStepFunction.per_instance));
            layout.setProperty("stride", @as(c_ulong, @sizeOf(Image)));
        }

        break :vertex_desc desc;
    };

    // Create our descriptor
    const desc = init: {
        const Class = objc.Class.getClass("MTLRenderPipelineDescriptor").?;
        const id_alloc = Class.msgSend(objc.Object, objc.sel("alloc"), .{});
        const id_init = id_alloc.msgSend(objc.Object, objc.sel("init"), .{});
        break :init id_init;
    };

    // Set our properties
    desc.setProperty("vertexFunction", func_vert);
    desc.setProperty("fragmentFunction", func_frag);
    desc.setProperty("vertexDescriptor", vertex_desc);

    // Set our color attachment
    const attachments = objc.Object.fromId(desc.getProperty(?*anyopaque, "colorAttachments"));
    {
        const attachment = attachments.msgSend(
            objc.Object,
            objc.sel("objectAtIndexedSubscript:"),
            .{@as(c_ulong, 0)},
        );

        // Value is MTLPixelFormatBGRA8Unorm
        attachment.setProperty("pixelFormat", @as(c_ulong, 80));

        // Blending. This is required so that our text we render on top
        // of our drawable properly blends into the bg.
        attachment.setProperty("blendingEnabled", true);
        attachment.setProperty("rgbBlendOperation", @intFromEnum(mtl.MTLBlendOperation.add));
        attachment.setProperty("alphaBlendOperation", @intFromEnum(mtl.MTLBlendOperation.add));
        attachment.setProperty("sourceRGBBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one));
        attachment.setProperty("sourceAlphaBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one));
        attachment.setProperty("destinationRGBBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one_minus_source_alpha));
        attachment.setProperty("destinationAlphaBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one_minus_source_alpha));
    }

    // Make our state
    var err: ?*anyopaque = null;
    const pipeline_state = device.msgSend(
        objc.Object,
        objc.sel("newRenderPipelineStateWithDescriptor:error:"),
        .{ desc, &err },
    );
    try checkError(err);

    return pipeline_state;
}

fn checkError(err_: ?*anyopaque) !void {
    const nserr = objc.Object.fromId(err_ orelse return);
    const str = @as(
        *macos.foundation.String,
        @ptrCast(nserr.getProperty(?*anyopaque, "localizedDescription").?),
    );

    log.err("metal error={s}", .{str.cstringPtr(.ascii).?});
    return error.MetalFailed;
}

// Intel macOS 13 doesn't like it when any field in a vertex buffer is not
// aligned on the alignment of the struct. I don't understand it, I think
// this must be some macOS 13 Metal GPU driver bug because it doesn't matter
// on macOS 12 or Apple Silicon macOS 13.
//
// To be safe, we put this test in here.
test "Cell offsets" {
    const testing = std.testing;
    const alignment = @alignOf(Cell);
    inline for (@typeInfo(Cell).Struct.fields) |field| {
        const offset = @offsetOf(Cell, field.name);
        try testing.expectEqual(0, @mod(offset, alignment));
    }
}
