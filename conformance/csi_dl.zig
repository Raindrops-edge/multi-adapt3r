//! Delete Line (DL) - Esc [ M
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("A\nB\nC\nD", .{});
    try stdout.print("\x1B[2A", .{}); // cursor up
    try stdout.print("\x1B[M", .{});
    try stdout.print("E\n", .{});
    try stdout.print("\x1B[B", .{});

    // const stdin = std.io.getStdIn().reader();
    // _ = try stdin.readByte();
}
