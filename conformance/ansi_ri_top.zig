//! Reverse Index (RI) - ESC M
//! Case: test that if the cursor is at the top, it scrolls down.
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("A\nB\n\n", .{});

    try stdout.print("\x1B[H", .{}); // Top-left
    try stdout.print("\x1BM", .{}); // Reverse-Index
    try stdout.print("D", .{});

    try stdout.print("\x0D", .{}); // CR
    try stdout.print("\x0A", .{}); // LF
    try stdout.print("\x1B[H", .{}); // Top-left
    try stdout.print("\x1BM", .{}); // Reverse-Index
    try stdout.print("E", .{});

    try stdout.print("\n", .{});

    // const stdin = std.io.getStdIn().reader();
    // _ = try stdin.readByte();
}
