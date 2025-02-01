//! Represents the IO thread logic. The IO thread is responsible for
//! the child process and pty management.
pub const Thread = @This();

const std = @import("std");
const builtin = @import("builtin");
const xev = @import("xev");
const termio = @import("../termio.zig");
const BlockingQueue = @import("../blocking_queue.zig").BlockingQueue;
const tracy = @import("tracy");
const trace = tracy.trace;

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.io_thread);

/// The type used for sending messages to the IO thread. For now this is
/// hardcoded with a capacity. We can make this a comptime parameter in
/// the future if we want it configurable.
pub const Mailbox = BlockingQueue(termio.Message, 64);

/// This stores the information that is coalesced.
const Coalesce = struct {
    /// The number of milliseconds to coalesce certain messages like resize for.
    /// Not all message types are coalesced.
    const min_ms = 25;

    resize: ?termio.Message.Resize = null,
};

/// The number of milliseconds before we reset the synchronized output flag
/// if the running program hasn't already.
const sync_reset_ms = 1000;

/// Allocator used for some state
alloc: std.mem.Allocator,

/// The main event loop for the thread. The user data of this loop
/// is always the allocator used to create the loop. This is a convenience
/// so that users of the loop always have an allocator.
loop: xev.Loop,

/// This can be used to wake up the thread.
wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

/// This can be used to stop the thread on the next loop iteration.
stop: xev.Async,
stop_c: xev.Completion = .{},

/// This is used to coalesce resize events.
coalesce: xev.Timer,
coalesce_c: xev.Completion = .{},
coalesce_cancel_c: xev.Completion = .{},
coalesce_data: Coalesce = .{},

/// This timer is used to reset synchronized output modes so that
/// the terminal doesn't freeze with a bad actor.
sync_reset: xev.Timer,
sync_reset_c: xev.Completion = .{},
sync_reset_cancel_c: xev.Completion = .{},

/// The underlying IO implementation.
impl: *termio.Impl,

/// The mailbox that can be used to send this thread messages. Note
/// this is a blocking queue so if it is full you will get errors (or block).
mailbox: *Mailbox,

/// Initialize the thread. This does not START the thread. This only sets
/// up all the internal state necessary prior to starting the thread. It
/// is up to the caller to start the thread with the threadMain entrypoint.
pub fn init(
    alloc: Allocator,
    impl: *termio.Impl,
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

    // This timer is used to coalesce resize events.
    var coalesce_h = try xev.Timer.init();
    errdefer coalesce_h.deinit();

    // This timer is used to reset synchronized output modes.
    var sync_reset_h = try xev.Timer.init();
    errdefer sync_reset_h.deinit();

    // The mailbox for messaging this thread
    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return Thread{
        .alloc = alloc,
        .loop = loop,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .coalesce = coalesce_h,
        .sync_reset = sync_reset_h,
        .impl = impl,
        .mailbox = mailbox,
    };
}

/// Clean up the thread. This is only safe to call once the thread
/// completes executing; the caller must join prior to this.
pub fn deinit(self: *Thread) void {
    self.coalesce.deinit();
    self.sync_reset.deinit();
    self.stop.deinit();
    self.wakeup.deinit();
    self.loop.deinit();

    // Nothing can possibly access the mailbox anymore, destroy it.
    self.mailbox.destroy(self.alloc);
}

/// The main entrypoint for the thread.
pub fn threadMain(self: *Thread) void {
    // Call child function so we can use errors...
    self.threadMain_() catch |err| {
        // In the future, we should expose this on the thread struct.
        log.warn("error in io thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("IO thread exited", .{});
    tracy.setThreadName("pty io");

    // Run our thread start/end callbacks. This allows the implementation
    // to hook into the event loop as needed.
    var data = try self.impl.threadEnter(self);
    defer data.deinit();
    defer self.impl.threadExit(data);

    // Start the async handlers
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);

    // Run
    log.debug("starting IO thread", .{});
    defer log.debug("starting IO thread shutdown", .{});
    try self.loop.run(.until_done);
}

/// Drain the mailbox, handling all the messages in our terminal implementation.
fn drainMailbox(self: *Thread) !void {
    const zone = trace(@src());
    defer zone.end();

    // This holds the mailbox lock for the duration of the drain. The
    // expectation is that all our message handlers will be non-blocking
    // ENOUGH to not mess up throughput on producers.
    var redraw: bool = false;
    while (self.mailbox.pop()) |message| {
        // If we have a message we always redraw
        redraw = true;

        log.debug("mailbox message={}", .{message});
        switch (message) {
            .change_config => |config| {
                defer config.alloc.destroy(config.ptr);
                try self.impl.changeConfig(config.ptr);
            },
            .resize => |v| self.handleResize(v),
            .clear_screen => |v| try self.impl.clearScreen(v.history),
            .scroll_viewport => |v| try self.impl.scrollViewport(v),
            .jump_to_prompt => |v| try self.impl.jumpToPrompt(v),
            .start_synchronized_output => self.startSynchronizedOutput(),
            .write_small => |v| try self.impl.queueWrite(v.data[0..v.len]),
            .write_stable => |v| try self.impl.queueWrite(v),
            .write_alloc => |v| {
                defer v.alloc.free(v.data);
                try self.impl.queueWrite(v.data);
            },
        }
    }

    // Trigger a redraw after we've drained so we don't waste cyces
    // messaging a redraw.
    if (redraw) {
        try self.impl.renderer_wakeup.notify();
    }
}

fn startSynchronizedOutput(self: *Thread) void {
    self.sync_reset.reset(
        &self.loop,
        &self.sync_reset_c,
        &self.sync_reset_cancel_c,
        sync_reset_ms,
        Thread,
        self,
        syncResetCallback,
    );
}

fn handleResize(self: *Thread, resize: termio.Message.Resize) void {
    self.coalesce_data.resize = resize;

    // If the timer is already active we just return. In the future we want
    // to reset the timer up to a maximum wait time but for now this ensures
    // relatively smooth resizing.
    if (self.coalesce_c.state() == .active) return;

    self.coalesce.reset(
        &self.loop,
        &self.coalesce_c,
        &self.coalesce_cancel_c,
        Coalesce.min_ms,
        Thread,
        self,
        coalesceCallback,
    );
}

fn syncResetCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch |err| switch (err) {
        error.Canceled => {},
        else => {
            log.warn("error during sync reset callback err={}", .{err});
            return .disarm;
        },
    };

    const self = self_ orelse return .disarm;
    self.impl.resetSynchronizedOutput();
    return .disarm;
}

fn coalesceCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch |err| switch (err) {
        error.Canceled => {},
        else => {
            log.warn("error during coalesce callback err={}", .{err});
            return .disarm;
        },
    };

    const self = self_ orelse return .disarm;

    if (self.coalesce_data.resize) |v| {
        self.coalesce_data.resize = null;
        self.impl.resize(v.grid_size, v.screen_size, v.padding) catch |err| {
            log.warn("error during resize err={}", .{err});
        };
    }

    return .disarm;
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

    return .rearm;
}

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
