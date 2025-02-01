//! DECALN - ESC # 8
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1B#8", .{});

    // const stdin = std.io.getStdIn().reader();
    // _ = try stdin.readByte();
}
