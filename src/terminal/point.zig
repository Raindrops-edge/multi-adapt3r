const std = @import("std");
const terminal = @import("main.zig");
const Screen = terminal.Screen;

// This file contains various types to represent x/y coordinates. We
// use different types so that we can lean on type-safety to get the
// exact expected type of point.

/// Viewport is a point within the viewport of the screen.
pub const Viewport = struct {
    x: usize = 0,
    y: usize = 0,

    pub fn toScreen(self: Viewport, screen: *const Screen) ScreenPoint {
        // x is unchanged, y we have to add the visible offset to
        // get the full offset from the top.
        return .{
            .x = self.x,
            .y = screen.viewport + self.y,
        };
    }

    test "toScreen with no scrollback" {
        const testing = std.testing;
        const alloc = testing.allocator;

        var s = try Screen.init(alloc, 3, 5, 0);
        defer s.deinit();

        try testing.expectEqual(ScreenPoint{
            .x = 1,
            .y = 1,
        }, (Viewport{ .x = 1, .y = 1 }).toScreen(&s));
    }

    test "toScreen with scrollback" {
        const testing = std.testing;
        const alloc = testing.allocator;

        var s = try Screen.init(alloc, 3, 5, 3);
        defer s.deinit();

        // At the bottom
        try s.scroll(.{ .screen = 6 });
        try testing.expectEqual(ScreenPoint{
            .x = 0,
            .y = 3,
        }, (Viewport{ .x = 0, .y = 0 }).toScreen(&s));

        // Move the viewport a bit up
        try s.scroll(.{ .screen = -1 });
        try testing.expectEqual(ScreenPoint{
            .x = 0,
            .y = 2,
        }, (Viewport{ .x = 0, .y = 0 }).toScreen(&s));

        // Move the viewport to top
        try s.scroll(.{ .top = {} });
        try testing.expectEqual(ScreenPoint{
            .x = 0,
            .y = 0,
        }, (Viewport{ .x = 0, .y = 0 }).toScreen(&s));
    }
};

/// A screen point. This is offset from the top of the scrollback
/// buffer. If the screen is scrolled or resized, this will have to
/// be recomputed.
pub const ScreenPoint = struct {
    x: usize = 0,
    y: usize = 0,

    /// Returns if this point is before another point.
    pub fn before(self: ScreenPoint, other: ScreenPoint) bool {
        return self.y < other.y or
            (self.y == other.y and self.x < other.x);
    }

    /// Returns true if this screen point is currently in the active viewport.
    pub fn inViewport(self: ScreenPoint, screen: *const Screen) bool {
        return self.y >= screen.viewport and
            self.y < screen.viewport + screen.rows;
    }

    /// Converts this to a viewport point. If the point is above the
    /// viewport this will move the point to (0, 0) and if it is below
    /// the viewport it'll move it to (cols - 1, rows - 1).
    pub fn toViewport(self: ScreenPoint, screen: *const Screen) Viewport {
        // TODO: test

        // Before viewport
        if (self.y < screen.viewport) return .{ .x = 0, .y = 0 };

        // After viewport
        if (self.y > screen.viewport + screen.rows) return .{
            .x = screen.cols - 1,
            .y = screen.rows - 1,
        };

        return .{ .x = self.x, .y = self.y - screen.viewport };
    }

    test "before" {
        const testing = std.testing;

        const p: ScreenPoint = .{ .x = 5, .y = 2 };
        try testing.expect(p.before(.{ .x = 6, .y = 2 }));
        try testing.expect(p.before(.{ .x = 3, .y = 3 }));
    }
};

test {
    std.testing.refAllDecls(@This());
}
