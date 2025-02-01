const std = @import("std");

// base64.cpp
extern "c" fn ghostty_simd_base64_max_length(
    input: [*]const u8,
    len: usize,
) usize;
extern "c" fn ghostty_simd_base64_decode(
    input: [*]const u8,
    len: usize,
    output: [*]u8,
) isize;

pub fn maxLen(input: []const u8) usize {
    return ghostty_simd_base64_max_length(input.ptr, input.len);
}

pub fn decode(input: []const u8, output: []u8) error{Base64Invalid}![]const u8 {
    const res = ghostty_simd_base64_decode(input.ptr, input.len, output.ptr);
    if (res < 0) return error.Base64Invalid;
    return output[0..@intCast(res)];
}

test "base64 maxLen" {
    const testing = std.testing;
    const len = maxLen("aGVsbG8gd29ybGQ=");
    try testing.expectEqual(11, len);
}

test "base64 decode" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const input = "aGVsbG8gd29ybGQ=";
    const len = maxLen(input);
    const output = try alloc.alloc(u8, len);
    defer alloc.free(output);
    const str = try decode(input, output);
    try testing.expectEqualStrings("hello world", str);
}
