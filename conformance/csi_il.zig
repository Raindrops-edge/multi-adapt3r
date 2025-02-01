//! Insert Line (IL) - Esc [ L
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1B[2J", .{}); // clear screen
    try stdout.print("\x1B[1;1H", .{}); // set cursor position
    try stdout.print("A\nB\nC\nD\nE", .{});
    try stdout.print("\x1B[1;2r", .{}); // set scroll region
    try stdout.print("\x1B[1;1H", .{}); // set cursor position
    try stdout.print("\x1B[1L", .{}); // insert lines
    try stdout.print("X", .{});
    try stdout.print("\x1B[7;1H", .{}); // set cursor position

    // const stdin = std.io.getStdIn().reader();
    // _ = try stdin.readByte();
}
