const VertexArray = @This();

const c = @import("c.zig");
const glad = @import("glad.zig");
const errors = @import("errors.zig");

id: c.GLuint,

/// Create a single vertex array object.
pub inline fn create() !VertexArray {
    var vao: c.GLuint = undefined;
    glad.context.GenVertexArrays.?(1, &vao);
    return VertexArray{ .id = vao };
}

// Unbind any active vertex array.
pub inline fn unbind() !void {
    glad.context.BindVertexArray.?(0);
}

/// glBindVertexArray
pub inline fn bind(v: VertexArray) !void {
    glad.context.BindVertexArray.?(v.id);
    try errors.getError();
}

pub inline fn destroy(v: VertexArray) void {
    glad.context.DeleteVertexArrays.?(1, &v.id);
}
