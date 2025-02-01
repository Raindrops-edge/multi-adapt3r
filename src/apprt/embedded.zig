//! Application runtime for the embedded version of Ghostty. The embedded
//! version is when Ghostty is embedded within a parent host application,
//! rather than owning the application lifecycle itself. This is used for
//! example for the macOS build of Ghostty so that we can use a native
//! Swift+XCode-based application.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const objc = @import("objc");
const apprt = @import("../apprt.zig");
const input = @import("../input.zig");
const terminal = @import("../terminal/main.zig");
const CoreApp = @import("../App.zig");
const CoreSurface = @import("../Surface.zig");
const configpkg = @import("../config.zig");
const Config = configpkg.Config;

const log = std.log.scoped(.embedded_window);

pub const App = struct {
    /// Because we only expect the embedding API to be used in embedded
    /// environments, the options are extern so that we can expose it
    /// directly to a C callconv and not pay for any translation costs.
    ///
    /// C type: ghostty_runtime_config_s
    pub const Options = extern struct {
        /// These are just aliases to make the function signatures below
        /// more obvious what values will be sent.
        const AppUD = ?*anyopaque;
        const SurfaceUD = ?*anyopaque;

        /// Userdata that is passed to all the callbacks.
        userdata: AppUD = null,

        /// True if the selection clipboard is supported.
        supports_selection_clipboard: bool = false,

        /// Callback called to wakeup the event loop. This should trigger
        /// a full tick of the app loop.
        wakeup: *const fn (AppUD) callconv(.C) void,

        /// Reload the configuration and return the new configuration.
        /// The old configuration can be freed immediately when this is
        /// called.
        reload_config: *const fn (AppUD) callconv(.C) ?*const Config,

        /// Called to set the title of the window.
        set_title: *const fn (SurfaceUD, [*]const u8) callconv(.C) void,

        /// Called to set the cursor shape.
        set_mouse_shape: *const fn (SurfaceUD, terminal.MouseShape) callconv(.C) void,

        /// Called to set the mouse visibility.
        set_mouse_visibility: *const fn (SurfaceUD, bool) callconv(.C) void,

        /// Read the clipboard value. The return value must be preserved
        /// by the host until the next call. If there is no valid clipboard
        /// value then this should return null.
        read_clipboard: *const fn (SurfaceUD, c_int) callconv(.C) ?[*:0]const u8,

        /// Write the clipboard value.
        write_clipboard: *const fn (SurfaceUD, [*:0]const u8, c_int) callconv(.C) void,

        /// Create a new split view. If the embedder doesn't support split
        /// views then this can be null.
        new_split: ?*const fn (SurfaceUD, input.SplitDirection, apprt.Surface.Options) callconv(.C) void = null,

        /// New tab with options.
        new_tab: ?*const fn (SurfaceUD, apprt.Surface.Options) callconv(.C) void = null,

        /// New window with options.
        new_window: ?*const fn (SurfaceUD, apprt.Surface.Options) callconv(.C) void = null,

        /// Close the current surface given by this function.
        close_surface: ?*const fn (SurfaceUD, bool) callconv(.C) void = null,

        /// Focus the previous/next split (if any).
        focus_split: ?*const fn (SurfaceUD, input.SplitFocusDirection) callconv(.C) void = null,

        /// Zoom the current split.
        toggle_split_zoom: ?*const fn (SurfaceUD) callconv(.C) void = null,

        /// Goto tab
        goto_tab: ?*const fn (SurfaceUD, GotoTab) callconv(.C) void = null,

        /// Toggle fullscreen for current window.
        toggle_fullscreen: ?*const fn (SurfaceUD, configpkg.NonNativeFullscreen) callconv(.C) void = null,
    };

    /// Special values for the goto_tab callback.
    const GotoTab = enum(i32) {
        previous = -1,
        next = -2,
        _,
    };

    core_app: *CoreApp,
    config: *const Config,
    opts: Options,
    keymap: input.Keymap,

    pub fn init(core_app: *CoreApp, config: *const Config, opts: Options) !App {
        return .{
            .core_app = core_app,
            .config = config,
            .opts = opts,
            .keymap = try input.Keymap.init(),
        };
    }

    pub fn terminate(self: App) void {
        self.keymap.deinit();
    }

    /// This should be called whenever the keyboard layout was changed.
    pub fn reloadKeymap(self: *App) !void {
        // Reload the keymap
        try self.keymap.reload();

        // Clear the dead key state since we changed the keymap, any
        // dead key state is just forgotten. i.e. if you type ' on us-intl
        // and then switch to us and type a, you'll get a rather than á.
        for (self.core_app.surfaces.items) |surface| {
            surface.keymap_state = .{};
        }
    }

    pub fn reloadConfig(self: *App) !?*const Config {
        // Reload
        if (self.opts.reload_config(self.opts.userdata)) |new| {
            self.config = new;
            return self.config;
        }

        return null;
    }

    pub fn wakeup(self: App) void {
        self.opts.wakeup(self.opts.userdata);
    }

    pub fn wait(self: App) !void {
        _ = self;
    }

    /// Create a new surface for the app.
    fn newSurface(self: *App, opts: Surface.Options) !*Surface {
        // Grab a surface allocation because we're going to need it.
        var surface = try self.core_app.alloc.create(Surface);
        errdefer self.core_app.alloc.destroy(surface);

        // Create the surface -- because windows are surfaces for glfw.
        try surface.init(self, opts);
        errdefer surface.deinit();

        return surface;
    }

    /// Close the given surface.
    pub fn closeSurface(self: *App, surface: *Surface) void {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
    }

    pub fn redrawSurface(self: *App, surface: *Surface) void {
        _ = self;
        _ = surface;
        // No-op, we use a threaded interface so we're constantly drawing.
    }

    pub fn newWindow(self: *App, parent: ?*CoreSurface) !void {
        _ = self;

        // Right now we only support creating a new window with a parent
        // through this code.
        // The other case is handled by the embedding runtime.
        if (parent) |surface| {
            try surface.rt_surface.newWindow();
        }
    }
};

pub const Surface = struct {
    app: *App,
    nsview: objc.Object,
    core_surface: CoreSurface,
    content_scale: apprt.ContentScale,
    size: apprt.SurfaceSize,
    cursor_pos: apprt.CursorPos,
    opts: Options,
    keymap_state: input.Keymap.State,

    pub const Options = extern struct {
        /// Userdata passed to some of the callbacks.
        userdata: ?*anyopaque = null,

        /// The pointer to the backing NSView for the surface.
        nsview: ?*anyopaque = null,

        /// The scale factor of the screen.
        scale_factor: f64 = 1,

        /// The font size to inherit. If 0, default font size will be used.
        font_size: u16 = 0,
    };

    pub fn init(self: *Surface, app: *App, opts: Options) !void {
        const nsview = objc.Object.fromId(opts.nsview orelse
            return error.NSViewMustBeSet);

        self.* = .{
            .app = app,
            .core_surface = undefined,
            .nsview = nsview,
            .content_scale = .{
                .x = @floatCast(opts.scale_factor),
                .y = @floatCast(opts.scale_factor),
            },
            .size = .{ .width = 800, .height = 600 },
            .cursor_pos = .{ .x = 0, .y = 0 },
            .opts = opts,
            .keymap_state = .{},
        };

        // Add ourselves to the list of surfaces on the app.
        try app.core_app.addSurface(self);
        errdefer app.core_app.deleteSurface(self);

        // Shallow copy the config so that we can modify it.
        var config = try apprt.surface.newConfig(app.core_app, app.config);
        defer config.deinit();

        // Initialize our surface right away. We're given a view that is
        // ready to use.
        try self.core_surface.init(
            app.core_app.alloc,
            &config,
            app.core_app,
            app,
            self,
        );
        errdefer self.core_surface.deinit();

        // If our options requested a specific font-size, set that.
        if (opts.font_size != 0) {
            var font_size = self.core_surface.font_size;
            font_size.points = opts.font_size;
            self.core_surface.setFontSize(font_size);
        }
    }

    pub fn deinit(self: *Surface) void {
        // Remove ourselves from the list of known surfaces in the app.
        self.app.core_app.deleteSurface(self);

        // Clean up our core surface so that all the rendering and IO stop.
        self.core_surface.deinit();
    }

    pub fn newSplit(self: *const Surface, direction: input.SplitDirection) !void {
        const func = self.app.opts.new_split orelse {
            log.info("runtime embedder does not support splits", .{});
            return;
        };

        const options = self.newSurfaceOptions();
        func(self.opts.userdata, direction, options);
    }

    pub fn close(self: *const Surface, process_alive: bool) void {
        const func = self.app.opts.close_surface orelse {
            log.info("runtime embedder does not support closing a surface", .{});
            return;
        };

        func(self.opts.userdata, process_alive);
    }

    pub fn gotoSplit(self: *const Surface, direction: input.SplitFocusDirection) void {
        const func = self.app.opts.focus_split orelse {
            log.info("runtime embedder does not support focus split", .{});
            return;
        };

        func(self.opts.userdata, direction);
    }

    pub fn toggleSplitZoom(self: *const Surface) void {
        const func = self.app.opts.toggle_split_zoom orelse {
            log.info("runtime embedder does not support split zoom", .{});
            return;
        };

        func(self.opts.userdata);
    }

    pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
        return self.content_scale;
    }

    pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
        return self.size;
    }

    pub fn setSizeLimits(self: *Surface, min: apprt.SurfaceSize, max_: ?apprt.SurfaceSize) !void {
        _ = self;
        _ = min;
        _ = max_;
    }

    pub fn setTitle(self: *Surface, slice: [:0]const u8) !void {
        self.app.opts.set_title(
            self.opts.userdata,
            slice.ptr,
        );
    }

    pub fn setMouseShape(self: *Surface, shape: terminal.MouseShape) !void {
        self.app.opts.set_mouse_shape(
            self.opts.userdata,
            shape,
        );
    }

    /// Set the visibility of the mouse cursor.
    pub fn setMouseVisibility(self: *Surface, visible: bool) void {
        self.app.opts.set_mouse_visibility(
            self.opts.userdata,
            visible,
        );
    }

    pub fn supportsClipboard(
        self: *const Surface,
        clipboard_type: apprt.Clipboard,
    ) bool {
        return switch (clipboard_type) {
            .standard => true,
            .selection => self.app.opts.supports_selection_clipboard,
        };
    }

    pub fn getClipboardString(
        self: *const Surface,
        clipboard_type: apprt.Clipboard,
    ) ![:0]const u8 {
        const ptr = self.app.opts.read_clipboard(
            self.opts.userdata,
            @intCast(@intFromEnum(clipboard_type)),
        ) orelse return "";
        return std.mem.sliceTo(ptr, 0);
    }

    pub fn setClipboardString(
        self: *const Surface,
        val: [:0]const u8,
        clipboard_type: apprt.Clipboard,
    ) !void {
        self.app.opts.write_clipboard(
            self.opts.userdata,
            val.ptr,
            @intCast(@intFromEnum(clipboard_type)),
        );
    }

    pub fn setShouldClose(self: *Surface) void {
        _ = self;
    }

    pub fn shouldClose(self: *const Surface) bool {
        _ = self;
        return false;
    }

    pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
        return self.cursor_pos;
    }

    pub fn refresh(self: *Surface) void {
        self.core_surface.refreshCallback() catch |err| {
            log.err("error in refresh callback err={}", .{err});
            return;
        };
    }

    pub fn updateContentScale(self: *Surface, x: f64, y: f64) void {
        self.content_scale = .{
            .x = @floatCast(x),
            .y = @floatCast(y),
        };

        self.core_surface.contentScaleCallback(self.content_scale) catch |err| {
            log.err("error in content scale callback err={}", .{err});
            return;
        };
    }

    pub fn updateSize(self: *Surface, width: u32, height: u32) void {
        // Runtimes sometimes generate superfluous resize events even
        // if the size did not actually change (SwiftUI). We check
        // that the size actually changed from what we last recorded
        // since resizes are expensive.
        if (self.size.width == width and self.size.height == height) return;

        self.size = .{
            .width = width,
            .height = height,
        };

        // Call the primary callback.
        self.core_surface.sizeCallback(self.size) catch |err| {
            log.err("error in size callback err={}", .{err});
            return;
        };
    }

    pub fn mouseButtonCallback(
        self: *Surface,
        action: input.MouseButtonState,
        button: input.MouseButton,
        mods: input.Mods,
    ) void {
        self.core_surface.mouseButtonCallback(action, button, mods) catch |err| {
            log.err("error in mouse button callback err={}", .{err});
            return;
        };
    }

    pub fn scrollCallback(
        self: *Surface,
        xoff: f64,
        yoff: f64,
        mods: input.ScrollMods,
    ) void {
        self.core_surface.scrollCallback(xoff, yoff, mods) catch |err| {
            log.err("error in scroll callback err={}", .{err});
            return;
        };
    }

    pub fn cursorPosCallback(self: *Surface, x: f64, y: f64) void {
        // Convert our unscaled x/y to scaled.
        self.cursor_pos = self.cursorPosToPixels(.{
            .x = @floatCast(x),
            .y = @floatCast(y),
        }) catch |err| {
            log.err(
                "error converting cursor pos to scaled pixels in cursor pos callback err={}",
                .{err},
            );
            return;
        };

        self.core_surface.cursorPosCallback(self.cursor_pos) catch |err| {
            log.err("error in cursor pos callback err={}", .{err});
            return;
        };
    }

    pub fn keyCallback(
        self: *Surface,
        action: input.Action,
        keycode: u32,
        mods: input.Mods,
    ) !void {
        // True if this is a key down event
        const is_down = action == .press or action == .repeat;

        // If we're on macOS and we have macos-option-as-alt enabled,
        // then we strip the alt modifier from the mods for translation.
        const translate_mods = translate_mods: {
            var translate_mods = mods;
            switch (self.app.config.@"macos-option-as-alt") {
                .false => {},
                .true => translate_mods.alt = false,
                .left => if (mods.sides.alt == .left) {
                    translate_mods.alt = false;
                },
                .right => if (mods.sides.alt == .right) {
                    translate_mods.alt = false;
                },
            }

            // On macOS we strip ctrl because UCKeyTranslate
            // converts to the masked values (i.e. ctrl+c becomes 3)
            // and we don't want that behavior.
            //
            // We also strip super because its not used for translation
            // on macos and it results in a bad translation.
            if (comptime builtin.target.isDarwin()) {
                translate_mods.ctrl = false;
                translate_mods.super = false;
            }

            break :translate_mods translate_mods;
        };

        // Translate our key using the keymap for our localized keyboard layout.
        // We only translate for keydown events. Otherwise, we only care about
        // the raw keycode.
        var buf: [128]u8 = undefined;
        const result: input.Keymap.Translation = if (is_down) translate: {
            const result = try self.app.keymap.translate(
                &buf,
                &self.keymap_state,
                @intCast(keycode),
                translate_mods,
            );

            // If this is a dead key, then we're composing a character and
            // we need to set our proper preedit state.
            if (result.composing) {
                const view = std.unicode.Utf8View.init(result.text) catch |err| {
                    log.warn("cannot build utf8 view over input: {}", .{err});
                    return;
                };
                var it = view.iterator();

                const cp: u21 = it.nextCodepoint() orelse 0;
                self.core_surface.preeditCallback(cp) catch |err| {
                    log.err("error in preedit callback err={}", .{err});
                    return;
                };
            } else {
                // If we aren't composing, then we set our preedit to
                // empty no matter what.
                self.core_surface.preeditCallback(null) catch {};

                // If the text is just a single non-printable ASCII character
                // then we clear the text. We handle non-printables in the
                // key encoder manual (such as tab, ctrl+c, etc.)
                if (result.text.len == 1 and result.text[0] < 0x20) {
                    break :translate .{ .composing = false, .text = "" };
                }
            }

            break :translate result;
        } else .{ .composing = false, .text = "" };

        // UCKeyTranslate always consumes all mods, so if we have any output
        // then we've consumed our translate mods.
        const consumed_mods: input.Mods = if (result.text.len > 0) translate_mods else .{};

        // We need to always do a translation with no modifiers at all in
        // order to get the "unshifted_codepoint" for the key event.
        const unshifted_codepoint: u21 = unshifted: {
            var nomod_buf: [128]u8 = undefined;
            var nomod_state: input.Keymap.State = undefined;
            const nomod = try self.app.keymap.translate(
                &nomod_buf,
                &nomod_state,
                @intCast(keycode),
                .{},
            );

            const view = std.unicode.Utf8View.init(nomod.text) catch |err| {
                log.warn("cannot build utf8 view over text: {}", .{err});
                break :unshifted 0;
            };
            var it = view.iterator();
            break :unshifted it.nextCodepoint() orelse 0;
        };

        // log.warn("TRANSLATE: action={} keycode={x} dead={} key_len={} key={any} key_str={s} mods={}", .{
        //     action,
        //     keycode,
        //     result.composing,
        //     result.text.len,
        //     result.text,
        //     result.text,
        //     mods,
        // });

        // We want to get the physical unmapped key to process keybinds.
        const physical_key = keycode: for (input.keycodes.entries) |entry| {
            if (entry.native == keycode) break :keycode entry.key;
        } else .invalid;

        // If the resulting text has length 1 then we can take its key
        // and attempt to translate it to a key enum and call the key callback.
        // If the length is greater than 1 then we're going to call the
        // charCallback.
        //
        // We also only do key translation if this is not a dead key.
        const key = if (!result.composing) key: {
            // A completed key. If the length of the key is one then we can
            // attempt to translate it to a key enum and call the key
            // callback. First try plain ASCII.
            if (result.text.len > 0) {
                if (input.Key.fromASCII(result.text[0])) |key| {
                    break :key key;
                }
            }

            // If the above doesn't work, we use the unmodified value.
            if (std.math.cast(u8, unshifted_codepoint)) |ascii| {
                if (input.Key.fromASCII(ascii)) |key| {
                    break :key key;
                }
            }

            break :key physical_key;
        } else .invalid;

        // Invoke the core Ghostty logic to handle this input.
        const consumed = self.core_surface.keyCallback(.{
            .action = action,
            .key = key,
            .physical_key = physical_key,
            .mods = mods,
            .consumed_mods = consumed_mods,
            .composing = result.composing,
            .utf8 = result.text,
            .unshifted_codepoint = unshifted_codepoint,
        }) catch |err| {
            log.err("error in key callback err={}", .{err});
            return;
        };

        // If we consume the key then we want to reset the dead key state.
        if (consumed and is_down) {
            self.keymap_state = .{};
            self.core_surface.preeditCallback(null) catch {};
            return;
        }
    }

    pub fn charCallback(self: *Surface, cp_: u32) void {
        const cp = std.math.cast(u21, cp_) orelse return;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch |err| {
            log.err("error encoding codepoint={} err={}", .{ cp, err });
            return;
        };

        // For a char callback we just construct a key event with invalid
        // keys but with text. This should result in the text being sent
        // as-is.
        _ = self.core_surface.keyCallback(.{
            .action = .press,
            .key = .invalid,
            .physical_key = .invalid,
            .mods = .{},
            .consumed_mods = .{},
            .composing = false,
            .utf8 = buf[0..len],
            .unshifted_codepoint = 0,
        }) catch |err| {
            log.err("error in key callback err={}", .{err});
            return;
        };
    }

    pub fn focusCallback(self: *Surface, focused: bool) void {
        self.core_surface.focusCallback(focused) catch |err| {
            log.err("error in focus callback err={}", .{err});
            return;
        };
    }

    pub fn gotoTab(self: *Surface, n: usize) void {
        const func = self.app.opts.goto_tab orelse {
            log.info("runtime embedder does not goto_tab", .{});
            return;
        };

        const idx = std.math.cast(i32, n) orelse {
            log.warn("cannot cast tab index to i32 n={}", .{n});
            return;
        };

        func(self.opts.userdata, @enumFromInt(idx));
    }

    pub fn gotoPreviousTab(self: *Surface) void {
        const func = self.app.opts.goto_tab orelse {
            log.info("runtime embedder does not goto_tab", .{});
            return;
        };

        func(self.opts.userdata, .previous);
    }

    pub fn gotoNextTab(self: *Surface) void {
        const func = self.app.opts.goto_tab orelse {
            log.info("runtime embedder does not goto_tab", .{});
            return;
        };

        func(self.opts.userdata, .next);
    }

    pub fn toggleFullscreen(self: *Surface, nonNativeFullscreen: configpkg.NonNativeFullscreen) void {
        const func = self.app.opts.toggle_fullscreen orelse {
            log.info("runtime embedder does not toggle_fullscreen", .{});
            return;
        };

        func(self.opts.userdata, nonNativeFullscreen);
    }

    pub fn newTab(self: *const Surface) !void {
        const func = self.app.opts.new_tab orelse {
            log.info("runtime embedder does not support new_tab", .{});
            return;
        };

        const options = self.newSurfaceOptions();
        func(self.opts.userdata, options);
    }

    pub fn newWindow(self: *const Surface) !void {
        const func = self.app.opts.new_window orelse {
            log.info("runtime embedder does not support new_window", .{});
            return;
        };

        const options = self.newSurfaceOptions();
        func(self.opts.userdata, options);
    }

    fn newSurfaceOptions(self: *const Surface) apprt.Surface.Options {
        const font_size: u16 = font_size: {
            if (!self.app.config.@"window-inherit-font-size") break :font_size 0;
            break :font_size self.core_surface.font_size.points;
        };

        return .{
            .font_size = font_size,
        };
    }

    /// The cursor position from the host directly is in screen coordinates but
    /// all our interface works in pixels.
    fn cursorPosToPixels(self: *const Surface, pos: apprt.CursorPos) !apprt.CursorPos {
        const scale = try self.getContentScale();
        return .{ .x = pos.x * scale.x, .y = pos.y * scale.y };
    }
};

// C API
pub const CAPI = struct {
    const global = &@import("../main.zig").state;

    /// Create a new app.
    export fn ghostty_app_new(
        opts: *const apprt.runtime.App.Options,
        config: *const Config,
    ) ?*App {
        return app_new_(opts, config) catch |err| {
            log.err("error initializing app err={}", .{err});
            return null;
        };
    }

    fn app_new_(
        opts: *const apprt.runtime.App.Options,
        config: *const Config,
    ) !*App {
        var core_app = try CoreApp.create(global.alloc);
        errdefer core_app.destroy();

        // Create our runtime app
        var app = try global.alloc.create(App);
        errdefer global.alloc.destroy(app);
        app.* = try App.init(core_app, config, opts.*);
        errdefer app.terminate();

        return app;
    }

    /// Tick the event loop. This should be called whenever the "wakeup"
    /// callback is invoked for the runtime.
    export fn ghostty_app_tick(v: *App) bool {
        return v.core_app.tick(v) catch |err| err: {
            log.err("error app tick err={}", .{err});
            break :err false;
        };
    }

    /// Return the userdata associated with the app.
    export fn ghostty_app_userdata(v: *App) ?*anyopaque {
        return v.opts.userdata;
    }

    export fn ghostty_app_free(v: *App) void {
        const core_app = v.core_app;
        v.terminate();
        global.alloc.destroy(v);
        core_app.destroy();
    }

    /// Notify the app that the keyboard was changed. This causes the
    /// keyboard layout to be reloaded from the OS.
    export fn ghostty_app_keyboard_changed(v: *App) void {
        v.reloadKeymap() catch |err| {
            log.err("error reloading keyboard map err={}", .{err});
            return;
        };
    }

    /// Reload the configuration.
    export fn ghostty_app_reload_config(v: *App) void {
        _ = v.core_app.reloadConfig(v) catch |err| {
            log.err("error reloading config err={}", .{err});
            return;
        };
    }

    /// Returns true if the app needs to confirm quitting.
    export fn ghostty_app_needs_confirm_quit(v: *App) bool {
        return v.core_app.needsConfirmQuit();
    }

    /// Returns initial surface options.
    export fn ghostty_surface_config_new() apprt.Surface.Options {
        return .{};
    }

    /// Create a new surface as part of an app.
    export fn ghostty_surface_new(
        app: *App,
        opts: *const apprt.Surface.Options,
    ) ?*Surface {
        return surface_new_(app, opts) catch |err| {
            log.err("error initializing surface err={}", .{err});
            return null;
        };
    }

    fn surface_new_(
        app: *App,
        opts: *const apprt.Surface.Options,
    ) !*Surface {
        return try app.newSurface(opts.*);
    }

    export fn ghostty_surface_free(ptr: *Surface) void {
        ptr.app.closeSurface(ptr);
    }

    /// Returns the app associated with a surface.
    export fn ghostty_surface_app(surface: *Surface) *App {
        return surface.app;
    }

    /// Returns true if the surface has transparency set.
    export fn ghostty_surface_transparent(surface: *Surface) bool {
        return surface.app.config.@"background-opacity" < 1.0;
    }

    /// Tell the surface that it needs to schedule a render
    export fn ghostty_surface_refresh(surface: *Surface) void {
        surface.refresh();
    }

    /// Update the size of a surface. This will trigger resize notifications
    /// to the pty and the renderer.
    export fn ghostty_surface_set_size(surface: *Surface, w: u32, h: u32) void {
        surface.updateSize(w, h);
    }

    /// Update the content scale of the surface.
    export fn ghostty_surface_set_content_scale(surface: *Surface, x: f64, y: f64) void {
        surface.updateContentScale(x, y);
    }

    /// Update the focused state of a surface.
    export fn ghostty_surface_set_focus(surface: *Surface, focused: bool) void {
        surface.focusCallback(focused);
    }

    /// Send this for raw keypresses (i.e. the keyDown event on macOS).
    /// This will handle the keymap translation and send the appropriate
    /// key and char events.
    ///
    /// You do NOT need to also send "ghostty_surface_char" unless
    /// you want to send a unicode character that is not associated
    /// with a keypress, i.e. IME keyboard.
    export fn ghostty_surface_key(
        surface: *Surface,
        action: input.Action,
        keycode: u32,
        c_mods: c_int,
    ) void {
        surface.keyCallback(
            action,
            keycode,
            @bitCast(@as(
                input.Mods.Backing,
                @truncate(@as(c_uint, @bitCast(c_mods))),
            )),
        ) catch |err| {
            log.err("error processing key event err={}", .{err});
            return;
        };
    }

    /// Send for a unicode character. This is used for IME input. This
    /// should only be sent for characters that are not the result of
    /// key events.
    export fn ghostty_surface_char(surface: *Surface, codepoint: u32) void {
        surface.charCallback(codepoint);
    }

    /// Tell the surface that it needs to schedule a render
    export fn ghostty_surface_mouse_button(
        surface: *Surface,
        action: input.MouseButtonState,
        button: input.MouseButton,
        mods: c_int,
    ) void {
        surface.mouseButtonCallback(
            action,
            button,
            @bitCast(@as(
                input.Mods.Backing,
                @truncate(@as(c_uint, @bitCast(mods))),
            )),
        );
    }

    /// Update the mouse position within the view.
    export fn ghostty_surface_mouse_pos(surface: *Surface, x: f64, y: f64) void {
        surface.cursorPosCallback(x, y);
    }

    export fn ghostty_surface_mouse_scroll(
        surface: *Surface,
        x: f64,
        y: f64,
        scroll_mods: c_int,
    ) void {
        surface.scrollCallback(
            x,
            y,
            @bitCast(@as(u8, @truncate(@as(c_uint, @bitCast(scroll_mods))))),
        );
    }

    export fn ghostty_surface_ime_point(surface: *Surface, x: *f64, y: *f64) void {
        const pos = surface.core_surface.imePoint();
        x.* = pos.x;
        y.* = pos.y;
    }

    /// Request that the surface become closed. This will go through the
    /// normal trigger process that a close surface input binding would.
    export fn ghostty_surface_request_close(ptr: *Surface) void {
        ptr.core_surface.close();
    }

    /// Request that the surface split in the given direction.
    export fn ghostty_surface_split(ptr: *Surface, direction: input.SplitDirection) void {
        ptr.newSplit(direction) catch {};
    }

    /// Focus on the next split (if any).
    export fn ghostty_surface_split_focus(ptr: *Surface, direction: input.SplitFocusDirection) void {
        ptr.gotoSplit(direction);
    }

    /// Invoke an action on the surface.
    export fn ghostty_surface_binding_action(
        ptr: *Surface,
        action_ptr: [*]const u8,
        action_len: usize,
    ) bool {
        const action_str = action_ptr[0..action_len];
        const action = input.Binding.Action.parse(action_str) catch |err| {
            log.err("error parsing binding action action={s} err={}", .{ action_str, err });
            return false;
        };

        ptr.core_surface.performBindingAction(action) catch |err| {
            log.err("error performing binding action action={} err={}", .{ action, err });
            return false;
        };

        return true;
    }

    /// Sets the window background blur on macOS to the desired value.
    /// I do this in Zig as an extern function because I don't know how to
    /// call these functions in Swift.
    ///
    /// This uses an undocumented, non-public API because this is what
    /// every terminal appears to use, including Terminal.app.
    export fn ghostty_set_window_background_blur(
        ptr: *Surface,
        window: *anyopaque,
    ) void {
        const config = ptr.app.config;

        // Do nothing if we don't have background transparency enabled
        if (config.@"background-opacity" >= 1.0) return;

        // Do nothing if our blur value is zero
        if (config.@"background-blur-radius" == 0) return;

        const nswindow = objc.Object.fromId(window);
        _ = CGSSetWindowBackgroundBlurRadius(
            CGSDefaultConnectionForThread(),
            nswindow.msgSend(usize, objc.sel("windowNumber"), .{}),
            @intCast(config.@"background-blur-radius"),
        );
    }

    /// See ghostty_set_window_background_blur
    extern "c" fn CGSSetWindowBackgroundBlurRadius(*anyopaque, usize, c_int) i32;
    extern "c" fn CGSDefaultConnectionForThread() *anyopaque;
};
