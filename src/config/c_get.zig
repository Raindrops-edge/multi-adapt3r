const std = @import("std");

const key = @import("key.zig");
const Config = @import("Config.zig");
const Key = key.Key;
const Value = key.Value;

/// Get a value from the config by key into the given pointer. This is
/// specifically for C-compatible APIs. If you're using Zig, just access
/// the configuration directly.
///
/// The return value is false if the given key is not supported by the
/// C API yet. This is a fixable problem so if it is important to support
/// some key, please open an issue.
pub fn get(config: *const Config, k: Key, ptr_raw: *anyopaque) bool {
    @setEvalBranchQuota(10_000);
    switch (k) {
        inline else => |tag| {
            const value = fieldByKey(config, tag);
            switch (@TypeOf(value)) {
                ?[:0]const u8 => {
                    const ptr: *[*c]const u8 = @ptrCast(@alignCast(ptr_raw));
                    ptr.* = if (value) |slice| @ptrCast(slice.ptr) else null;
                },

                bool => {
                    const ptr: *bool = @ptrCast(@alignCast(ptr_raw));
                    ptr.* = value;
                },

                u8, u32 => {
                    const ptr: *c_uint = @ptrCast(@alignCast(ptr_raw));
                    ptr.* = @intCast(value);
                },

                f32, f64 => {
                    const ptr: *f64 = @ptrCast(@alignCast(ptr_raw));
                    ptr.* = @floatCast(value);
                },

                else => return false,
            }

            return true;
        },
    }
}

/// Get a value from the config by key.
fn fieldByKey(self: *const Config, comptime k: Key) Value(k) {
    const field = comptime field: {
        const fields = std.meta.fields(Config);
        for (fields) |field| {
            if (@field(Key, field.name) == k) {
                break :field field;
            }
        }

        unreachable;
    };

    return @field(self, field.name);
}

test "u8" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.@"font-size" = 24;

    var cval: c_uint = undefined;
    try testing.expect(get(&c, .@"font-size", &cval));
    try testing.expectEqual(@as(c_uint, 24), cval);
}
