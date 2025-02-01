//! Outputs various box glyphs for testing.
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Box Drawing
    {
        try stdout.print("\x1b[4mBox Drawing\x1b[0m\n", .{});
        var i: usize = 0x2500;
        var step: usize = 32;
        while (i <= 0x257F) : (i += step) {
            var j: usize = 0;
            while (j < step) : (j += 1) {
                try stdout.print("{u} ", .{@as(u21, @intCast(i + j))});
            }

            try stdout.print("\n\n", .{});
        }
    }

    // Block Elements
    {
        try stdout.print("\x1b[4mBlock Elements\x1b[0m\n", .{});
        var i: usize = 0x2580;
        var step: usize = 32;
        while (i <= 0x259f) : (i += step) {
            var j: usize = 0;
            while (j < step) : (j += 1) {
                try stdout.print("{u} ", .{@as(u21, @intCast(i + j))});
            }

            try stdout.print("\n\n", .{});
        }
    }

    // Braille Elements
    {
        try stdout.print("\x1b[4mBraille\x1b[0m\n", .{});
        var i: usize = 0x2800;
        var step: usize = 32;
        while (i <= 0x28FF) : (i += step) {
            var j: usize = 0;
            while (j < step) : (j += 1) {
                try stdout.print("{u} ", .{@as(u21, @intCast(i + j))});
            }

            try stdout.print("\n\n", .{});
        }
    }

    {
        try stdout.print("\x1b[4mSextants\x1b[0m\n", .{});
        var i: usize = 0x1FB00;
        var step: usize = 32;
        const end = 0x1FB3B;
        while (i <= end) : (i += step) {
            var j: usize = 0;
            while (j < step) : (j += 1) {
                const v = i + j;
                if (v <= end) try stdout.print("{u} ", .{@as(u21, @intCast(v))});
            }

            try stdout.print("\n\n", .{});
        }
    }

    {
        try stdout.print("\x1b[4mWedge Triangles\x1b[0m\n", .{});
        var i: usize = 0x1FB3C;
        var step: usize = 32;
        const end = 0x1FB6B;
        while (i <= end) : (i += step) {
            var j: usize = 0;
            while (j < step) : (j += 1) {
                const v = i + j;
                if (v <= end) try stdout.print("{u} ", .{@as(u21, @intCast(v))});
            }

            try stdout.print("\n\n", .{});
        }
    }

    {
        try stdout.print("\x1b[4mOther\x1b[0m\n", .{});
        var i: usize = 0x1FB70;
        var step: usize = 32;
        const end = 0x1FB8B;
        while (i <= end) : (i += step) {
            var j: usize = 0;
            while (j < step) : (j += 1) {
                const v = i + j;
                if (v <= end) try stdout.print("{u} ", .{@as(u21, @intCast(v))});
            }

            try stdout.print("\n\n", .{});
        }
    }
}
