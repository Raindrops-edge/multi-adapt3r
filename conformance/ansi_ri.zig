//! Reverse Index (RI) - ESC M
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("A\nB\nC", .{});
    try stdout.print("\x1BM", .{});
    try stdout.print("D\n\n", .{});

    // const stdin = std.io.getStdIn().reader();
    // _ = try stdin.readByte();
}
