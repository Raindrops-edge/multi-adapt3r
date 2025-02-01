//! Set Top and Bottom Margins (DECSTBM) - ESC [ r
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("A\nB\nC\nD", .{});
    try stdout.print("\x1B[1;3r", .{}); // cursor up
    try stdout.print("\x1B[1;1H", .{}); // top-left
    try stdout.print("\x1B[M", .{}); // delete line
    try stdout.print("E\n", .{});
    try stdout.print("\x1B[7;1H", .{}); // cursor up

    // const stdin = std.io.getStdIn().reader();
    // _ = try stdin.readByte();
}
