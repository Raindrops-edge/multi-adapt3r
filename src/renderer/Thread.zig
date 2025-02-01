//! Represents the renderer thread logic. The renderer thread is able to
//! be woken up to render.
pub const Thread = @This();

const std = @import("std");
const builtin = @import("builtin");
const xev = @import("xev");
const renderer = @import("../renderer.zig");
const apprt = @import("../apprt.zig");
const BlockingQueue = @import("../blocking_queue.zig").BlockingQueue;
const tracy = @import("tracy");
const trace = tracy.trace;
const App = @import("../App.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.renderer_thread);

const CURSOR_BLINK_INTERVAL = 600;

/// The type used for sending messages to the IO thread. For now this is
/// hardcoded with a capacity. We can make this a comptime parameter in
/// the future if we want it configurable.
pub const Mailbox = BlockingQueue(renderer.Message, 64);

/// Allocator used for some state
alloc: std.mem.Allocator,

/// The main event loop for the application. The user data of this loop
/// is always the allocator used to create the loop. This is a convenience
/// so that users of the loop always have an allocator.
loop: xev.Loop,

/// This can be used to wake up the renderer and force a render safely from
/// any thread.
wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

/// This can be used to stop the renderer on the next loop iteration.
stop: xev.Async,
stop_c: xev.Completion = .{},

/// The timer used for rendering
render_h: xev.Timer,
render_c: xev.Completion = .{},

/// The timer used for cursor blinking
cursor_h: xev.Timer,
cursor_c: xev.Completion = .{},
cursor_c_cancel: xev.Completion = .{},

/// This is true when a blinking cursor should be visible and false
/// when it should not be visible. This is toggled on a timer by the
/// thread automatically.
cursor_blink_visible: bool = false,

/// The surface we're rendering to.
surface: *apprt.Surface,

/// The underlying renderer implementation.
renderer: *renderer.Renderer,

/// Pointer to the shared state that is used to generate the final render.
state: *renderer.State,

/// The mailbox that can be used to send this thread messages. Note
/// this is a blocking queue so if it is full you will get errors (or block).
mailbox: *Mailbox,

/// Mailbox to send messages to the app thread
app_mailbox: App.Mailbox,

/// Initialize the thread. This does not START the thread. This only sets
/// up all the internal state necessary prior to starting the thread. It
/// is up to the caller to start the thread with the threadMain entrypoint.
pub fn init(
    alloc: Allocator,
    surface: *apprt.Surface,
    renderer_impl: *renderer.Renderer,
    state: *renderer.State,
    app_mailbox: App.Mailbox,
) !Thread {
    // Create our event loop.
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    // This async handle is used to "wake up" the renderer and force a render.
    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    // This async handle is used to stop the loop and force the thread to end.
    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    // The primary timer for rendering.
    var render_h = try xev.Timer.init();
    errdefer render_h.deinit();

    // Setup a timer for blinking the cursor
    var cursor_timer = try xev.Timer.init();
    errdefer cursor_timer.deinit();

    // The mailbox for messaging this thread
    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return Thread{
        .alloc = alloc,
        .loop = loop,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .render_h = render_h,
        .cursor_h = cursor_timer,
        .surface = surface,
        .renderer = renderer_impl,
        .state = state,
        .mailbox = mailbox,
        .app_mailbox = app_mailbox,
    };
}

/// Clean up the thread. This is only safe to call once the thread
/// completes executing; the caller must join prior to this.
pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.wakeup.deinit();
    self.render_h.deinit();
    self.cursor_h.deinit();
    self.loop.deinit();

    // Nothing can possibly access the mailbox anymore, destroy it.
    self.mailbox.destroy(self.alloc);
}

/// The main entrypoint for the thread.
pub fn threadMain(self: *Thread) void {
    // Call child function so we can use errors...
    self.threadMain_() catch |err| {
        // In the future, we should expose this on the thread struct.
        log.warn("error in renderer err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("renderer thread exited", .{});
    tracy.setThreadName("renderer");

    // Run our thread start/end callbacks. This is important because some
    // renderers have to do per-thread setup. For example, OpenGL has to set
    // some thread-local state since that is how it works.
    try self.renderer.threadEnter(self.surface);
    defer self.renderer.threadExit();

    // Start the async handlers
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);

    // Send an initial wakeup message so that we render right away.
    try self.wakeup.notify();

    // Start blinking the cursor.
    self.cursor_h.run(
        &self.loop,
        &self.cursor_c,
        CURSOR_BLINK_INTERVAL,
        Thread,
        self,
        cursorTimerCallback,
    );

    // If we are using tracy, then we setup a prepare handle so that
    // we can mark the frame.
    // TODO
    // var frame_h: libuv.Prepare = if (!tracy.enabled) undefined else frame_h: {
    //     const alloc_ptr = self.loop.getData(Allocator).?;
    //     const alloc = alloc_ptr.*;
    //     const h = try libuv.Prepare.init(alloc, self.loop);
    //     h.setData(self);
    //     try h.start(prepFrameCallback);
    //
    //     break :frame_h h;
    // };
    // defer if (tracy.enabled) {
    //     frame_h.close((struct {
    //         fn callback(h: *libuv.Prepare) void {
    //             const alloc_h = h.loop().getData(Allocator).?.*;
    //             h.deinit(alloc_h);
    //         }
    //     }).callback);
    //     _ = self.loop.run(.nowait) catch {};
    // };

    // Run
    log.debug("starting renderer thread", .{});
    defer log.debug("starting renderer thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

/// Drain the mailbox.
fn drainMailbox(self: *Thread) !void {
    const zone = trace(@src());
    defer zone.end();

    while (self.mailbox.pop()) |message| {
        log.debug("mailbox message={}", .{message});
        switch (message) {
            .focus => |v| {
                // Set it on the renderer
                try self.renderer.setFocus(v);

                if (!v) {
                    // If we're not focused, then we stop the cursor blink
                    if (self.cursor_c.state() == .active and
                        self.cursor_c_cancel.state() == .dead)
                    {
                        self.cursor_h.cancel(
                            &self.loop,
                            &self.cursor_c,
                            &self.cursor_c_cancel,
                            void,
                            null,
                            cursorCancelCallback,
                        );
                    }
                } else {
                    // If we're focused, we immediately show the cursor again
                    // and then restart the timer.
                    if (self.cursor_c.state() != .active) {
                        self.cursor_blink_visible = true;
                        self.cursor_h.run(
                            &self.loop,
                            &self.cursor_c,
                            CURSOR_BLINK_INTERVAL,
                            Thread,
                            self,
                            cursorTimerCallback,
                        );
                    }
                }
            },

            .reset_cursor_blink => {
                self.cursor_blink_visible = true;
                if (self.cursor_c.state() == .active) {
                    self.cursor_h.reset(
                        &self.loop,
                        &self.cursor_c,
                        &self.cursor_c_cancel,
                        CURSOR_BLINK_INTERVAL,
                        Thread,
                        self,
                        cursorTimerCallback,
                    );
                }
            },

            .font_size => |size| {
                try self.renderer.setFontSize(size);
            },

            .resize => |v| {
                try self.renderer.setScreenSize(v.screen_size, v.padding);
            },

            .change_config => |config| {
                defer config.alloc.destroy(config.ptr);
                try self.renderer.changeConfig(config.ptr);
            },
        }
    }
}

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const zone = trace(@src());
    defer zone.end();

    const t = self_.?;

    // When we wake up, we check the mailbox. Mailbox producers should
    // wake up our thread after publishing.
    t.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    // If the timer is already active then we don't have to do anything.
    if (t.render_c.state() == .active) return .rearm;

    // Timer is not active, let's start it
    t.render_h.run(
        &t.loop,
        &t.render_c,
        10,
        Thread,
        t,
        renderCallback,
    );

    return .rearm;
}

fn renderCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    const zone = trace(@src());
    defer zone.end();

    _ = r catch unreachable;
    const t = self_ orelse {
        // This shouldn't happen so we log it.
        log.warn("render callback fired without data set", .{});
        return .disarm;
    };

    t.renderer.render(
        t.surface,
        t.state,
        t.cursor_blink_visible,
    ) catch |err|
        log.warn("error rendering err={}", .{err});

    // If we're doing single-threaded GPU calls then we also wake up the
    // app thread to redraw at this point.
    if (renderer.Renderer == renderer.OpenGL and
        renderer.OpenGL.single_threaded_draw)
    {
        _ = t.app_mailbox.push(.{ .redraw_surface = t.surface }, .{ .instant = {} });
    }

    return .disarm;
}

fn cursorTimerCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    const zone = trace(@src());
    defer zone.end();

    _ = r catch |err| switch (err) {
        // This is sent when our timer is canceled. That's fine.
        error.Canceled => return .disarm,

        else => {
            log.warn("error in cursor timer callback err={}", .{err});
            unreachable;
        },
    };

    const t = self_ orelse {
        // This shouldn't happen so we log it.
        log.warn("render callback fired without data set", .{});
        return .disarm;
    };

    t.cursor_blink_visible = !t.cursor_blink_visible;
    t.wakeup.notify() catch {};

    t.cursor_h.run(&t.loop, &t.cursor_c, CURSOR_BLINK_INTERVAL, Thread, t, cursorTimerCallback);
    return .disarm;
}

fn cursorCancelCallback(
    _: ?*void,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.CancelError!void,
) xev.CallbackAction {
    // This makes it easier to work across platforms where different platforms
    // support different sets of errors, so we just unify it.
    const CancelError = xev.Timer.CancelError || error{
        Canceled,
        Unexpected,
    };

    _ = r catch |err| switch (@as(CancelError, @errSetCast(err))) {
        error.Canceled => {},
        else => {
            log.warn("error in cursor cancel callback err={}", .{err});
            unreachable;
        },
    };

    return .disarm;
}

// fn prepFrameCallback(h: *libuv.Prepare) void {
//     _ = h;
//
//     tracy.frameMark();
// }

fn stopCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    self_.?.loop.stop();
    return .disarm;
}
