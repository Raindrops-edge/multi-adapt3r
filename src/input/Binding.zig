//! A binding maps some input trigger to an action. When the trigger
//! occurs, the action is performed.
const Binding = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const key = @import("key.zig");

/// The trigger that needs to be performed to execute the action.
trigger: Trigger,

/// The action to take if this binding matches
action: Action,

/// True if this binding should consume the input when the
/// action is triggered.
consumed: bool = true,

pub const Error = error{
    InvalidFormat,
    InvalidAction,
};

/// Full binding parser. The binding parser is implemented as an iterator
/// which yields elements to support multi-key sequences without allocation.
pub const Parser = struct {
    unconsumed: bool = false,
    trigger_it: SequenceIterator,
    action: Action,

    pub const Elem = union(enum) {
        /// A leader trigger in a sequence.
        leader: Trigger,

        /// The final trigger and action in a sequence.
        binding: Binding,
    };

    pub fn init(raw_input: []const u8) Error!Parser {
        // If our entire input is prefixed with "unconsumed:" then we are
        // not consuming this keybind when the action is triggered.
        const unconsumed_prefix = "unconsumed:";
        const unconsumed = std.mem.startsWith(u8, raw_input, unconsumed_prefix);
        const start_idx = if (unconsumed) unconsumed_prefix.len else 0;
        const input = raw_input[start_idx..];

        // Find the first = which splits are mapping into the trigger
        // and action, respectively.
        const eql_idx = std.mem.indexOf(u8, input, "=") orelse return Error.InvalidFormat;

        // Sequence iterator goes up to the equal, action is after. We can
        // parse the action now.
        return .{
            .unconsumed = unconsumed,
            .trigger_it = .{ .input = input[0..eql_idx] },
            .action = try Action.parse(input[eql_idx + 1 ..]),
        };
    }

    pub fn next(self: *Parser) Error!?Elem {
        // Get our trigger. If we're out of triggers then we're done.
        const trigger = (try self.trigger_it.next()) orelse return null;

        // If this is our last trigger then it is our final binding.
        if (!self.trigger_it.done()) return .{ .leader = trigger };

        // Out of triggers, yield the final action.
        return .{ .binding = .{
            .trigger = trigger,
            .action = self.action,
            .consumed = !self.unconsumed,
        } };
    }

    pub fn reset(self: *Parser) void {
        self.trigger_it.i = 0;
    }
};

/// An iterator that yields each trigger in a sequence of triggers. For
/// example, the sequence "ctrl+a>ctrl+b" would yield "ctrl+a" and then
/// "ctrl+b". The iterator approach allows us to parse a sequence of
/// triggers without allocations.
const SequenceIterator = struct {
    /// The input of triggers. This is expected to be ONLY triggers. Things
    /// like the "unconsumed:" prefix or action must be stripped before
    /// passing to this iterator.
    input: []const u8,
    i: usize = 0,

    /// Returns the next trigger in the sequence if there is no parsing error.
    pub fn next(self: *SequenceIterator) Error!?Trigger {
        if (self.done()) return null;
        const rem = self.input[self.i..];
        const idx = std.mem.indexOf(u8, rem, ">") orelse rem.len;
        defer self.i += idx + 1;
        return try Trigger.parse(rem[0..idx]);
    }

    /// Returns true if there are no more triggers to parse.
    pub fn done(self: *const SequenceIterator) bool {
        return self.i > self.input.len;
    }
};

/// Parse a single, non-sequenced binding. To support sequences you must
/// use parse. This is a convenience function for single bindings aimed
/// primarily at tests.
fn parseSingle(raw_input: []const u8) (Error || error{UnexpectedSequence})!Binding {
    var p = try Parser.init(raw_input);
    const elem = (try p.next()) orelse return Error.InvalidFormat;
    return switch (elem) {
        .leader => error.UnexpectedSequence,
        .binding => elem.binding,
    };
}

/// Returns true if lhs should be sorted before rhs
pub fn lessThan(_: void, lhs: Binding, rhs: Binding) bool {
    const lhs_count: usize = blk: {
        var count: usize = 0;
        if (lhs.trigger.mods.super) count += 1;
        if (lhs.trigger.mods.ctrl) count += 1;
        if (lhs.trigger.mods.shift) count += 1;
        if (lhs.trigger.mods.alt) count += 1;
        break :blk count;
    };
    const rhs_count: usize = blk: {
        var count: usize = 0;
        if (rhs.trigger.mods.super) count += 1;
        if (rhs.trigger.mods.ctrl) count += 1;
        if (rhs.trigger.mods.shift) count += 1;
        if (rhs.trigger.mods.alt) count += 1;
        break :blk count;
    };
    if (lhs_count == rhs_count)
        return lhs.trigger.mods.int() > rhs.trigger.mods.int();

    return lhs_count > rhs_count;
}

/// The set of actions that a keybinding can take.
pub const Action = union(enum) {
    /// Ignore this key combination, don't send it to the child process, just
    /// black hole it.
    ignore: void,

    /// This action is used to flag that the binding should be removed from
    /// the set. This should never exist in an active set and `set.put` has an
    /// assertion to verify this.
    unbind: void,

    /// Send a CSI sequence. The value should be the CSI sequence without the
    /// CSI header (`ESC ]` or `\x1b]`).
    csi: []const u8,

    /// Send an `ESC` sequence.
    esc: []const u8,

    // Send the given text. Uses Zig string literal syntax. This is currently
    // not validated. If the text is invalid (i.e. contains an invalid escape
    // sequence), the error will currently only show up in logs.
    text: []const u8,

    /// Send data to the pty depending on whether cursor key mode is enabled
    /// (`application`) or disabled (`normal`).
    cursor_key: CursorKey,

    /// Reset the terminal. This can fix a lot of issues when a running
    /// program puts the terminal into a broken state. This is equivalent to
    /// when you type "reset" and press enter.
    ///
    /// If you do this while in a TUI program such as vim, this may break
    /// the program. If you do this while in a shell, you may have to press
    /// enter after to get a new prompt.
    reset: void,

    /// Copy and paste.
    copy_to_clipboard: void,
    paste_from_clipboard: void,
    paste_from_selection: void,

    /// Increase/decrease the font size by a certain amount.
    increase_font_size: f32,
    decrease_font_size: f32,

    /// Reset the font size to the original configured size.
    reset_font_size: void,

    /// Clear the screen. This also clears all scrollback.
    clear_screen: void,

    /// Select all text on the screen.
    select_all: void,

    /// Scroll the screen varying amounts.
    scroll_to_top: void,
    scroll_to_bottom: void,
    scroll_page_up: void,
    scroll_page_down: void,
    scroll_page_fractional: f32,
    scroll_page_lines: i16,

    /// Adjust an existing selection in a given direction. This action
    /// does nothing if there is no active selection.
    adjust_selection: AdjustSelection,

    /// Jump the viewport forward or back by prompt. Positive number is the
    /// number of prompts to jump forward, negative is backwards.
    jump_to_prompt: i16,

    /// Write the entire scrollback into a temporary file. The action
    /// determines what to do with the filepath. Valid values are:
    ///
    ///   - "paste": Paste the file path into the terminal.
    ///   - "open": Open the file in the default OS editor for text files.
    ///
    write_scrollback_file: WriteScreenAction,

    /// Same as write_scrollback_file but writes the full screen contents.
    /// See write_scrollback_file for available values.
    write_screen_file: WriteScreenAction,

    /// Same as write_scrollback_file but writes the selected text.
    /// If there is no selected text this does nothing (it doesn't
    /// even create an empty file). See write_scrollback_file for
    /// available values.
    write_selection_file: WriteScreenAction,

    /// Open a new window.
    new_window: void,

    /// Open a new tab.
    new_tab: void,

    /// Go to the previous tab.
    previous_tab: void,

    /// Go to the next tab.
    next_tab: void,

    /// Go to the last tab (the one with the highest index)
    last_tab: void,

    /// Go to the tab with the specific number, 1-indexed.
    goto_tab: usize,

    /// Create a new split in the given direction. The new split will appear in
    /// the direction given.
    new_split: SplitDirection,

    /// Focus on a split in a given direction.
    goto_split: SplitFocusDirection,

    /// zoom/unzoom the current split.
    toggle_split_zoom: void,

    /// Resize the current split by moving the split divider in the given
    /// direction
    resize_split: SplitResizeParameter,

    /// Equalize all splits in the current window
    equalize_splits: void,

    /// Show, hide, or toggle the terminal inspector for the currently focused
    /// terminal.
    inspector: InspectorMode,

    /// Open the configuration file in the default OS editor. If your default OS
    /// editor isn't configured then this will fail. Currently, any failures to
    /// open the configuration will show up only in the logs.
    open_config: void,

    /// Reload the configuration. The exact meaning depends on the app runtime
    /// in use but this usually involves re-reading the configuration file
    /// and applying any changes. Note that not all changes can be applied at
    /// runtime.
    reload_config: void,

    /// Close the current "surface", whether that is a window, tab, split, etc.
    /// This only closes ONE surface. This will trigger close confirmation as
    /// configured.
    close_surface: void,

    /// Close the window, regardless of how many tabs or splits there may be.
    /// This will trigger close confirmation as configured.
    close_window: void,

    /// Close all windows. This will trigger close confirmation as configured.
    /// This only works for macOS currently.
    close_all_windows: void,

    /// Toggle fullscreen mode of window.
    toggle_fullscreen: void,

    /// Toggle window decorations on and off. This only works on Linux.
    toggle_window_decorations: void,

    /// Quit ghostty.
    quit: void,

    /// Crash ghostty in the desired thread for the focused surface.
    ///
    /// WARNING: This is a hard crash (panic) and data can be lost.
    ///
    /// The purpose of this action is to test crash handling. For some
    /// users, it may be useful to test crash reporting functionality in
    /// order to determine if it all works as expected.
    ///
    /// The value determines the crash location:
    ///
    ///   - "main" - crash on the main (GUI) thread.
    ///   - "io" - crash on the IO thread for the focused surface.
    ///   - "render" - crash on the render thread for the focused surface.
    ///
    crash: CrashThread,

    pub const CrashThread = enum {
        main,
        io,
        render,
    };

    pub const CursorKey = struct {
        normal: []const u8,
        application: []const u8,
    };

    pub const AdjustSelection = enum {
        left,
        right,
        up,
        down,
        page_up,
        page_down,
        home,
        end,
        beginning_of_line,
        end_of_line,
    };

    pub const SplitDirection = enum {
        right,
        down,
        auto, // splits along the larger direction

        // Note: we don't support top or left yet
    };

    // Extern because it is used in the embedded runtime ABI.
    pub const SplitFocusDirection = enum(c_int) {
        previous,
        next,

        top,
        left,
        bottom,
        right,
    };

    // Extern because it is used in the embedded runtime ABI.
    pub const SplitResizeDirection = enum(c_int) {
        up,
        down,
        left,
        right,
    };

    pub const SplitResizeParameter = struct {
        SplitResizeDirection,
        u16,
    };

    pub const WriteScreenAction = enum {
        paste,
        open,
    };

    // Extern because it is used in the embedded runtime ABI.
    pub const InspectorMode = enum(c_int) {
        toggle,
        show,
        hide,
    };

    fn parseEnum(comptime T: type, value: []const u8) !T {
        return std.meta.stringToEnum(T, value) orelse return Error.InvalidFormat;
    }

    fn parseInt(comptime T: type, value: []const u8) !T {
        return std.fmt.parseInt(T, value, 10) catch return Error.InvalidFormat;
    }

    fn parseFloat(comptime T: type, value: []const u8) !T {
        return std.fmt.parseFloat(T, value) catch return Error.InvalidFormat;
    }

    fn parseParameter(
        comptime field: std.builtin.Type.UnionField,
        param: []const u8,
    ) !field.type {
        return switch (@typeInfo(field.type)) {
            .Enum => try parseEnum(field.type, param),
            .Int => try parseInt(field.type, param),
            .Float => try parseFloat(field.type, param),
            .Struct => |info| blk: {
                // Only tuples are supported to avoid ambiguity with field
                // ordering
                comptime assert(info.is_tuple);

                var it = std.mem.splitAny(u8, param, ",");
                var value: field.type = undefined;
                inline for (info.fields) |field_| {
                    const next = it.next() orelse return Error.InvalidFormat;
                    @field(value, field_.name) = switch (@typeInfo(field_.type)) {
                        .Enum => try parseEnum(field_.type, next),
                        .Int => try parseInt(field_.type, next),
                        .Float => try parseFloat(field_.type, next),
                        else => unreachable,
                    };
                }

                // If we have extra parameters it is an error
                if (it.next() != null) return Error.InvalidFormat;

                break :blk value;
            },

            else => unreachable,
        };
    }

    /// Parse an action in the format of "key=value" where key is the
    /// action name and value is the action parameter. The parameter
    /// is optional depending on the action.
    pub fn parse(input: []const u8) !Action {
        // Split our action by colon. A colon may not exist for some
        // actions so it is optional. The part preceding the colon is the
        // action name.
        const colonIdx = std.mem.indexOf(u8, input, ":");
        const action = input[0..(colonIdx orelse input.len)];

        // An action name is always required
        if (action.len == 0) return Error.InvalidFormat;

        const actionInfo = @typeInfo(Action).Union;
        inline for (actionInfo.fields) |field| {
            if (std.mem.eql(u8, action, field.name)) {
                // If the field type is void we expect no value
                switch (field.type) {
                    void => {
                        if (colonIdx != null) return Error.InvalidFormat;
                        return @unionInit(Action, field.name, {});
                    },

                    []const u8 => {
                        const idx = colonIdx orelse return Error.InvalidFormat;
                        const param = input[idx + 1 ..];
                        return @unionInit(Action, field.name, param);
                    },

                    // Cursor keys can't be set currently
                    Action.CursorKey => return Error.InvalidAction,

                    else => {
                        const idx = colonIdx orelse return Error.InvalidFormat;
                        const param = input[idx + 1 ..];
                        return @unionInit(
                            Action,
                            field.name,
                            try parseParameter(field, param),
                        );
                    },
                }
            }
        }

        return Error.InvalidAction;
    }

    /// Implements the formatter for the fmt package. This encodes the
    /// action back into the format used by parse.
    pub fn format(
        self: Action,
        comptime layout: []const u8,
        opts: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = layout;
        _ = opts;

        switch (self) {
            inline else => |value| {
                // All actions start with the tag.
                try writer.print("{s}", .{@tagName(self)});

                // Only write the value depending on the type if it's not void
                if (@TypeOf(value) != void) {
                    try writer.writeAll(":");
                    try formatValue(writer, value);
                }
            },
        }
    }

    fn formatValue(
        writer: anytype,
        value: anytype,
    ) !void {
        const Value = @TypeOf(value);
        const value_info = @typeInfo(Value);
        switch (Value) {
            void => {},
            []const u8 => try writer.print("{s}", .{value}),
            else => switch (value_info) {
                .Enum => try writer.print("{s}", .{@tagName(value)}),
                .Float => try writer.print("{d}", .{value}),
                .Int => try writer.print("{d}", .{value}),
                .Struct => |info| if (!info.is_tuple) {
                    try writer.print("{} (not configurable)", .{value});
                } else {
                    inline for (info.fields, 0..) |field, i| {
                        try formatValue(writer, @field(value, field.name));
                        if (i + 1 < info.fields.len) try writer.writeAll(",");
                    }
                },
                else => @compileError("unhandled type: " ++ @typeName(Value)),
            },
        }
    }

    /// Returns a hash code that can be used to uniquely identify this
    /// action.
    pub fn hash(self: Action) u64 {
        var hasher = std.hash.Wyhash.init(0);

        // Always has the active tag.
        const Tag = @typeInfo(Action).Union.tag_type.?;
        std.hash.autoHash(&hasher, @as(Tag, self));

        // Hash the value of the field.
        switch (self) {
            inline else => |field| {
                const FieldType = @TypeOf(field);
                switch (FieldType) {
                    // Do nothing for void
                    void => {},

                    // Floats are hashed by their bits. This is totally not
                    // portable and there are edge cases such as NaNs and
                    // signed zeros but these are not cases we expect for
                    // our bindings.
                    f32 => std.hash.autoHash(
                        &hasher,
                        @as(u32, @bitCast(field)),
                    ),
                    f64 => std.hash.autoHash(
                        &hasher,
                        @as(u64, @bitCast(field)),
                    ),

                    // Everything else automatically handle.
                    else => std.hash.autoHashStrat(
                        &hasher,
                        field,
                        .DeepRecursive,
                    ),
                }
            },
        }

        return hasher.final();
    }
};

// A key for the C API to execute an action. This must be kept in sync
// with include/ghostty.h.
pub const Key = enum(c_int) {
    copy_to_clipboard,
    paste_from_clipboard,
    new_tab,
    new_window,
};

/// Trigger is the associated key state that can trigger an action.
/// This is an extern struct because this is also used in the C API.
///
/// This must be kept in sync with include/ghostty.h ghostty_input_trigger_s
pub const Trigger = struct {
    /// The key that has to be pressed for a binding to take action.
    key: Trigger.Key = .{ .translated = .invalid },

    /// The key modifiers that must be active for this to match.
    mods: key.Mods = .{},

    pub const Key = union(C.Tag) {
        /// key is the translated version of a key. This is the key that
        /// a logical keyboard layout at the OS level would translate the
        /// physical key to. For example if you use a US hardware keyboard
        /// but have a Dvorak layout, the key would be the Dvorak key.
        translated: key.Key,

        /// key is the "physical" version. This is the same as mapped for
        /// standard US keyboard layouts. For non-US keyboard layouts, this
        /// is used to bind to a physical key location rather than a translated
        /// key.
        physical: key.Key,

        /// This is used for binding to keys that produce a certain unicode
        /// codepoint. This is useful for binding to keys that don't have a
        /// registered keycode with Ghostty.
        unicode: u21,
    };

    /// The extern struct used for triggers in the C API.
    pub const C = extern struct {
        tag: Tag = .translated,
        key: C.Key = .{ .translated = .invalid },
        mods: key.Mods = .{},

        pub const Tag = enum(c_int) {
            translated,
            physical,
            unicode,
        };

        pub const Key = extern union {
            translated: key.Key,
            physical: key.Key,
            unicode: u32,
        };
    };

    /// Parse a single trigger. The input is expected to be ONLY the trigger
    /// (i.e. in the sequence `a=ignore` input is only `a`). The trigger may
    /// not be part of a sequence (i.e. `a>b`). This parses exactly a single
    /// trigger.
    pub fn parse(input: []const u8) !Trigger {
        if (input.len == 0) return Error.InvalidFormat;
        var result: Trigger = .{};
        var iter = std.mem.tokenizeScalar(u8, input, '+');
        loop: while (iter.next()) |part| {
            // All parts must be non-empty
            if (part.len == 0) return Error.InvalidFormat;

            // Check if its a modifier
            const modsInfo = @typeInfo(key.Mods).Struct;
            inline for (modsInfo.fields) |field| {
                if (field.type == bool) {
                    if (std.mem.eql(u8, part, field.name)) {
                        // Repeat not allowed
                        if (@field(result.mods, field.name)) return Error.InvalidFormat;
                        @field(result.mods, field.name) = true;
                        continue :loop;
                    }
                }
            }

            // Alias modifiers
            const alias_mods = .{
                .{ "cmd", "super" },    .{ "command", "super" },
                .{ "opt", "alt" },      .{ "option", "alt" },
                .{ "control", "ctrl" },
            };
            inline for (alias_mods) |pair| {
                if (std.mem.eql(u8, part, pair[0])) {
                    // Repeat not allowed
                    if (@field(result.mods, pair[1])) return Error.InvalidFormat;
                    @field(result.mods, pair[1]) = true;
                    continue :loop;
                }
            }

            // If the key starts with "physical" then this is an physical key.
            const physical_prefix = "physical:";
            const physical = std.mem.startsWith(u8, part, physical_prefix);
            const key_part = if (physical) part[physical_prefix.len..] else part;

            // Check if its a key
            const keysInfo = @typeInfo(key.Key).Enum;
            inline for (keysInfo.fields) |field| {
                if (!std.mem.eql(u8, field.name, "invalid")) {
                    if (std.mem.eql(u8, key_part, field.name)) {
                        // Repeat not allowed
                        if (!result.isKeyUnset()) return Error.InvalidFormat;

                        const keyval = @field(key.Key, field.name);
                        result.key = if (physical)
                            .{ .physical = keyval }
                        else
                            .{ .translated = keyval };
                        continue :loop;
                    }
                }
            }

            // If we're still unset and we have exactly one unicode
            // character then we can use that as a key.
            if (result.isKeyUnset()) unicode: {
                // Invalid UTF8 drops to invalid format
                const view = std.unicode.Utf8View.init(key_part) catch break :unicode;
                var it = view.iterator();

                // No codepoints or multiple codepoints drops to invalid format
                const cp = it.nextCodepoint() orelse break :unicode;
                if (it.nextCodepoint() != null) break :unicode;

                result.key = .{ .unicode = cp };
                continue :loop;
            }

            // We didn't recognize this value
            return Error.InvalidFormat;
        }

        return result;
    }
    /// Returns true if this trigger has no key set.
    pub fn isKeyUnset(self: Trigger) bool {
        return switch (self.key) {
            .translated => |v| v == .invalid,
            else => false,
        };
    }

    /// Returns a hash code that can be used to uniquely identify this trigger.
    pub fn hash(self: Trigger) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, self.key);
        std.hash.autoHash(&hasher, self.mods.binding());
        return hasher.final();
    }

    /// Convert the trigger to a C API compatible trigger.
    pub fn cval(self: Trigger) C {
        return .{
            .tag = self.key,
            .key = switch (self.key) {
                .translated => |v| .{ .translated = v },
                .physical => |v| .{ .physical = v },
                .unicode => |v| .{ .unicode = @intCast(v) },
            },
            .mods = self.mods,
        };
    }

    /// Format implementation for fmt package.
    pub fn format(
        self: Trigger,
        comptime layout: []const u8,
        opts: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = layout;
        _ = opts;

        // Modifiers first
        if (self.mods.super) try writer.writeAll("super+");
        if (self.mods.ctrl) try writer.writeAll("ctrl+");
        if (self.mods.alt) try writer.writeAll("alt+");
        if (self.mods.shift) try writer.writeAll("shift+");

        // Key
        switch (self.key) {
            .translated => |k| try writer.print("{s}", .{@tagName(k)}),
            .physical => |k| try writer.print("physical:{s}", .{@tagName(k)}),
            .unicode => |c| try writer.print("{u}", .{c}),
        }
    }
};

/// A structure that contains a set of bindings and focuses on fast lookup.
/// The use case is that this will be called on EVERY key input to look
/// for an associated action so it must be fast.
pub const Set = struct {
    const HashMap = std.HashMapUnmanaged(
        Trigger,
        Entry,
        Context(Trigger),
        std.hash_map.default_max_load_percentage,
    );

    const ReverseMap = std.HashMapUnmanaged(
        Action,
        Trigger,
        Context(Action),
        std.hash_map.default_max_load_percentage,
    );

    /// The set of bindings.
    bindings: HashMap = .{},

    /// The reverse mapping of action to binding. Note that multiple
    /// bindings can map to the same action and this map will only have
    /// the most recently added binding for an action.
    ///
    /// Sequenced triggers are never present in the reverse map at this time.
    /// This is a conscious decision since the primary use case of the reverse
    /// map is to support GUI toolkit keyboard accelerators and no mainstream
    /// GUI toolkit supports sequences.
    reverse: ReverseMap = .{},

    /// The entry type for the forward mapping of trigger to action.
    pub const Entry = union(enum) {
        /// This key is a leader key in a sequence. You must follow the given
        /// set to find the next key in the sequence.
        leader: *Set,

        /// This trigger completes a sequence and the value is the action
        /// to take. The "_unconsumed" variant is used for triggers that
        /// should not consume the input.
        action: Action,
        action_unconsumed: Action,

        /// Implements the formatter for the fmt package. This encodes the
        /// action back into the format used by parse.
        pub fn format(
            self: Entry,
            comptime layout: []const u8,
            opts: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = layout;
            _ = opts;

            switch (self) {
                .leader => |set| {
                    // the leader key was already printed.
                    var iter = set.bindings.iterator();
                    while (iter.next()) |binding| {
                        try writer.print(
                            ">{s}{s}",
                            .{ binding.key_ptr.*, binding.value_ptr.* },
                        );
                    }
                },

                .action, .action_unconsumed => |action| {
                    // action implements the format
                    try writer.print("={s}", .{action});
                },
            }
        }
    };

    pub fn deinit(self: *Set, alloc: Allocator) void {
        // Clear any leaders if we have them
        var it = self.bindings.iterator();
        while (it.next()) |entry| switch (entry.value_ptr.*) {
            .leader => |s| {
                s.deinit(alloc);
                alloc.destroy(s);
            },
            .action, .action_unconsumed => {},
        };

        self.bindings.deinit(alloc);
        self.reverse.deinit(alloc);
        self.* = undefined;
    }

    /// Parse a user input binding and add it to the set. This will handle
    /// the "unbind" case, ensure consumed/unconsumed fields are set correctly,
    /// handle sequences, etc.
    ///
    /// If this returns an OutOfMemory error then the set is in a broken
    /// state and should not be used again. Any Error returned is validated
    /// before any set modifications are made.
    pub fn parseAndPut(
        self: *Set,
        alloc: Allocator,
        input: []const u8,
    ) (Allocator.Error || Error)!void {
        // To make cleanup easier, we ensure that the full sequence is
        // valid before making any set modifications. This is more expensive
        // computationally but it makes cleanup way, way easier.
        var it = try Parser.init(input);
        while (try it.next()) |_| {}
        it.reset();

        // We use recursion so that we can utilize the stack as our state
        // for cleanup.
        self.parseAndPutRecurse(alloc, &it) catch |err| switch (err) {
            // If this gets sent up to the root then we've unbound
            // all the way up and this put was a success.
            error.SequenceUnbind => {},

            // Unrecoverable
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    const ParseAndPutRecurseError = Allocator.Error || error{
        SequenceUnbind,
    };

    fn parseAndPutRecurse(
        set: *Set,
        alloc: Allocator,
        it: *Parser,
    ) ParseAndPutRecurseError!void {
        const elem = (it.next() catch unreachable) orelse return;
        switch (elem) {
            .leader => |t| {
                // If we have a leader, we need to upsert a set for it.
                const old = set.get(t);
                if (old) |entry| switch (entry) {
                    // We have an existing leader for this key already
                    // so recurse into this set.
                    .leader => |s| return parseAndPutRecurse(
                        s,
                        alloc,
                        it,
                    ) catch |err| switch (err) {
                        // Our child put unbound. If our set is empty we
                        // need to dealloc and continue up. If our set is
                        // not empty then we're done.
                        error.SequenceUnbind => if (s.bindings.count() == 0) {
                            set.remove(alloc, t);
                            return error.SequenceUnbind;
                        },

                        error.OutOfMemory => return error.OutOfMemory,
                    },

                    .action, .action_unconsumed => {
                        // Remove the existing action. Fallthrough as if
                        // we don't have a leader.
                        set.remove(alloc, t);
                    },
                };

                // Create our new set for this leader
                const next = try alloc.create(Set);
                errdefer alloc.destroy(next);
                next.* = .{};
                errdefer next.deinit(alloc);

                // Insert the leader entry
                try set.bindings.put(alloc, t, .{ .leader = next });

                // Recurse
                parseAndPutRecurse(next, alloc, it) catch |err| switch (err) {
                    // If our action was to unbind, we restore the old
                    // action if we have it.
                    error.SequenceUnbind => {
                        set.remove(alloc, t);
                        if (old) |entry| switch (entry) {
                            .leader => unreachable, // Handled above
                            inline .action, .action_unconsumed => |action, tag| set.put_(
                                alloc,
                                t,
                                action,
                                tag == .action,
                            ) catch {},
                        };
                    },

                    error.OutOfMemory => return error.OutOfMemory,
                };
            },

            .binding => |b| switch (b.action) {
                .unbind => {
                    set.remove(alloc, b.trigger);
                    return error.SequenceUnbind;
                },

                else => if (b.consumed) {
                    try set.put(alloc, b.trigger, b.action);
                } else {
                    try set.putUnconsumed(alloc, b.trigger, b.action);
                },
            },
        }
    }

    /// Add a binding to the set. If the binding already exists then
    /// this will overwrite it.
    pub fn put(
        self: *Set,
        alloc: Allocator,
        t: Trigger,
        action: Action,
    ) Allocator.Error!void {
        try self.put_(alloc, t, action, true);
    }

    /// Same as put but marks the trigger as unconsumed. An unconsumed
    /// trigger will evaluate the action and continue to encode for the
    /// terminal.
    ///
    /// This is a separate function because this case is rare.
    pub fn putUnconsumed(
        self: *Set,
        alloc: Allocator,
        t: Trigger,
        action: Action,
    ) Allocator.Error!void {
        try self.put_(alloc, t, action, false);
    }

    fn put_(
        self: *Set,
        alloc: Allocator,
        t: Trigger,
        action: Action,
        consumed: bool,
    ) Allocator.Error!void {
        // unbind should never go into the set, it should be handled prior
        assert(action != .unbind);

        const gop = try self.bindings.getOrPut(alloc, t);

        if (gop.found_existing) switch (gop.value_ptr.*) {
            // If we have a leader we need to clean up the memory
            .leader => |s| {
                s.deinit(alloc);
                alloc.destroy(s);
            },

            // If we have an existing binding for this trigger, we have to
            // update the reverse mapping to remove the old action.
            .action, .action_unconsumed => {
                const t_hash = t.hash();
                var it = self.reverse.iterator();
                while (it.next()) |reverse_entry| it: {
                    if (t_hash == reverse_entry.value_ptr.hash()) {
                        self.reverse.removeByPtr(reverse_entry.key_ptr);
                        break :it;
                    }
                }
            },
        };

        gop.value_ptr.* = if (consumed) .{
            .action = action,
        } else .{
            .action_unconsumed = action,
        };
        errdefer _ = self.bindings.remove(t);
        try self.reverse.put(alloc, action, t);
        errdefer _ = self.reverse.remove(action);
    }

    /// Get a binding for a given trigger.
    pub fn get(self: Set, t: Trigger) ?Entry {
        return self.bindings.get(t);
    }

    /// Get a trigger for the given action. An action can have multiple
    /// triggers so this will return the first one found.
    pub fn getTrigger(self: Set, a: Action) ?Trigger {
        return self.reverse.get(a);
    }

    /// Remove a binding for a given trigger.
    pub fn remove(self: *Set, alloc: Allocator, t: Trigger) void {
        const entry = self.bindings.get(t) orelse return;
        _ = self.bindings.remove(t);

        switch (entry) {
            // For a leader removal, we need to deallocate our child set.
            // Leaders are never part of reverse maps so no other accounting
            // needs to be done.
            .leader => |s| {
                s.deinit(alloc);
                alloc.destroy(s);
            },

            // For an action we need to fix up the reverse mapping.
            // Note: we'd LIKE to replace this with the most recent binding but
            // our hash map obviously has no concept of ordering so we have to
            // choose whatever. Maybe a switch to an array hash map here.
            .action, .action_unconsumed => |action| {
                const action_hash = action.hash();
                var it = self.bindings.iterator();
                while (it.next()) |it_entry| {
                    switch (it_entry.value_ptr.*) {
                        .leader => {},
                        .action, .action_unconsumed => |action_search| {
                            if (action_search.hash() == action_hash) {
                                self.reverse.putAssumeCapacity(action, it_entry.key_ptr.*);
                                break;
                            }
                        },
                    }
                } else {
                    // No over trigger points to this action so we remove
                    // the reverse mapping completely.
                    _ = self.reverse.remove(action);
                }
            },
        }
    }

    /// Deep clone the set.
    pub fn clone(self: *const Set, alloc: Allocator) !Set {
        var result: Set = .{
            .bindings = try self.bindings.clone(alloc),
            .reverse = try self.reverse.clone(alloc),
        };

        // If we have any leaders we need to clone them.
        var it = result.bindings.iterator();
        while (it.next()) |entry| switch (entry.value_ptr.*) {
            // No data to clone
            .action, .action_unconsumed => {},

            // Must be deep cloned.
            .leader => |*s| {
                const ptr = try alloc.create(Set);
                errdefer alloc.destroy(ptr);
                ptr.* = try s.*.clone(alloc);
                errdefer ptr.deinit(alloc);
                s.* = ptr;
            },
        };

        return result;
    }

    /// The hash map context for the set. This defines how the hash map
    /// gets the hash key and checks for equality.
    fn Context(comptime KeyType: type) type {
        return struct {
            pub fn hash(ctx: @This(), k: KeyType) u64 {
                _ = ctx;
                return k.hash();
            }

            pub fn eql(ctx: @This(), a: KeyType, b: KeyType) bool {
                return ctx.hash(a) == ctx.hash(b);
            }
        };
    }
};

test "parse: triggers" {
    const testing = std.testing;

    // single character
    try testing.expectEqual(
        Binding{
            .trigger = .{ .key = .{ .translated = .a } },
            .action = .{ .ignore = {} },
        },
        try parseSingle("a=ignore"),
    );

    // single modifier
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("shift+a=ignore"));
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .ctrl = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("ctrl+a=ignore"));

    // multiple modifier
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true, .ctrl = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("shift+ctrl+a=ignore"));

    // key can come before modifier
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("a+shift=ignore"));

    // physical keys
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true },
            .key = .{ .physical = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("shift+physical:a=ignore"));

    // unicode keys
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true },
            .key = .{ .unicode = 'ö' },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("shift+ö=ignore"));

    // unconsumed keys
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
        .consumed = false,
    }, try parseSingle("unconsumed:shift+a=ignore"));

    // unconsumed physical keys
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .shift = true },
            .key = .{ .physical = .a },
        },
        .action = .{ .ignore = {} },
        .consumed = false,
    }, try parseSingle("unconsumed:physical:a+shift=ignore"));

    // invalid key
    try testing.expectError(Error.InvalidFormat, parseSingle("foo=ignore"));

    // repeated control
    try testing.expectError(Error.InvalidFormat, parseSingle("shift+shift+a=ignore"));

    // multiple character
    try testing.expectError(Error.InvalidFormat, parseSingle("a+b=ignore"));
}

test "parse: modifier aliases" {
    const testing = std.testing;

    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .super = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("cmd+a=ignore"));
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .super = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("command+a=ignore"));

    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .alt = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("opt+a=ignore"));
    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .alt = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("option+a=ignore"));

    try testing.expectEqual(Binding{
        .trigger = .{
            .mods = .{ .ctrl = true },
            .key = .{ .translated = .a },
        },
        .action = .{ .ignore = {} },
    }, try parseSingle("control+a=ignore"));
}

test "parse: action invalid" {
    const testing = std.testing;

    // invalid action
    try testing.expectError(Error.InvalidAction, parseSingle("a=nopenopenope"));
}

test "parse: action no parameters" {
    const testing = std.testing;

    // no parameters
    try testing.expectEqual(
        Binding{
            .trigger = .{ .key = .{ .translated = .a } },
            .action = .{ .ignore = {} },
        },
        try parseSingle("a=ignore"),
    );
    try testing.expectError(Error.InvalidFormat, parseSingle("a=ignore:A"));
}

test "parse: action with string" {
    const testing = std.testing;

    // parameter
    {
        const binding = try parseSingle("a=csi:A");
        try testing.expect(binding.action == .csi);
        try testing.expectEqualStrings("A", binding.action.csi);
    }
    // parameter
    {
        const binding = try parseSingle("a=esc:A");
        try testing.expect(binding.action == .esc);
        try testing.expectEqualStrings("A", binding.action.esc);
    }
}

test "parse: action with enum" {
    const testing = std.testing;

    // parameter
    {
        const binding = try parseSingle("a=new_split:right");
        try testing.expect(binding.action == .new_split);
        try testing.expectEqual(Action.SplitDirection.right, binding.action.new_split);
    }
}

test "parse: action with int" {
    const testing = std.testing;

    // parameter
    {
        const binding = try parseSingle("a=jump_to_prompt:-1");
        try testing.expect(binding.action == .jump_to_prompt);
        try testing.expectEqual(@as(i16, -1), binding.action.jump_to_prompt);
    }
    {
        const binding = try parseSingle("a=jump_to_prompt:10");
        try testing.expect(binding.action == .jump_to_prompt);
        try testing.expectEqual(@as(i16, 10), binding.action.jump_to_prompt);
    }
}

test "parse: action with float" {
    const testing = std.testing;

    // parameter
    {
        const binding = try parseSingle("a=scroll_page_fractional:-0.5");
        try testing.expect(binding.action == .scroll_page_fractional);
        try testing.expectEqual(@as(f32, -0.5), binding.action.scroll_page_fractional);
    }
    {
        const binding = try parseSingle("a=scroll_page_fractional:+0.5");
        try testing.expect(binding.action == .scroll_page_fractional);
        try testing.expectEqual(@as(f32, 0.5), binding.action.scroll_page_fractional);
    }
}

test "parse: action with a tuple" {
    const testing = std.testing;

    // parameter
    {
        const binding = try parseSingle("a=resize_split:up,10");
        try testing.expect(binding.action == .resize_split);
        try testing.expectEqual(Action.SplitResizeDirection.up, binding.action.resize_split[0]);
        try testing.expectEqual(@as(u16, 10), binding.action.resize_split[1]);
    }

    // missing parameter
    try testing.expectError(Error.InvalidFormat, parseSingle("a=resize_split:up"));

    // too many
    try testing.expectError(Error.InvalidFormat, parseSingle("a=resize_split:up,10,12"));

    // invalid type
    try testing.expectError(Error.InvalidFormat, parseSingle("a=resize_split:up,four"));
}

test "sequence iterator" {
    const testing = std.testing;

    // single character
    {
        var it: SequenceIterator = .{ .input = "a" };
        try testing.expectEqual(Trigger{ .key = .{ .translated = .a } }, (try it.next()).?);
        try testing.expect(try it.next() == null);
    }

    // multi character
    {
        var it: SequenceIterator = .{ .input = "a>b" };
        try testing.expectEqual(Trigger{ .key = .{ .translated = .a } }, (try it.next()).?);
        try testing.expectEqual(Trigger{ .key = .{ .translated = .b } }, (try it.next()).?);
        try testing.expect(try it.next() == null);
    }

    // empty
    {
        var it: SequenceIterator = .{ .input = "" };
        try testing.expectError(Error.InvalidFormat, it.next());
    }

    // empty starting sequence
    {
        var it: SequenceIterator = .{ .input = ">a" };
        try testing.expectError(Error.InvalidFormat, it.next());
    }

    // empty ending sequence
    {
        var it: SequenceIterator = .{ .input = "a>" };
        try testing.expectEqual(Trigger{ .key = .{ .translated = .a } }, (try it.next()).?);
        try testing.expectError(Error.InvalidFormat, it.next());
    }
}

test "parse: sequences" {
    const testing = std.testing;

    // single character
    {
        var p = try Parser.init("ctrl+a=ignore");
        try testing.expectEqual(Parser.Elem{ .binding = .{
            .trigger = .{
                .mods = .{ .ctrl = true },
                .key = .{ .translated = .a },
            },
            .action = .{ .ignore = {} },
        } }, (try p.next()).?);
        try testing.expect(try p.next() == null);
    }

    // sequence
    {
        var p = try Parser.init("a>b=ignore");
        try testing.expectEqual(Parser.Elem{ .leader = .{
            .key = .{ .translated = .a },
        } }, (try p.next()).?);
        try testing.expectEqual(Parser.Elem{ .binding = .{
            .trigger = .{
                .key = .{ .translated = .b },
            },
            .action = .{ .ignore = {} },
        } }, (try p.next()).?);
        try testing.expect(try p.next() == null);
    }
}

test "set: parseAndPut typical binding" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a=new_window");

    // Creates forward mapping
    {
        const action = s.get(.{ .key = .{ .translated = .a } }).?.action;
        try testing.expect(action == .new_window);
    }

    // Creates reverse mapping
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }
}

test "set: parseAndPut unconsumed binding" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "unconsumed:a=new_window");

    // Creates forward mapping
    {
        const trigger: Trigger = .{ .key = .{ .translated = .a } };
        const action = s.get(trigger).?.action_unconsumed;
        try testing.expect(action == .new_window);
    }

    // Creates reverse mapping
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }
}

test "set: parseAndPut removed binding" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a=new_window");
    try s.parseAndPut(alloc, "a=unbind");

    // Creates forward mapping
    {
        const trigger: Trigger = .{ .key = .{ .translated = .a } };
        try testing.expect(s.get(trigger) == null);
    }
    try testing.expect(s.getTrigger(.{ .new_window = {} }) == null);
}

test "set: parseAndPut sequence" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a>b=new_window");
    var current: *Set = &s;
    {
        const t: Trigger = .{ .key = .{ .translated = .a } };
        const e = current.get(t).?;
        try testing.expect(e == .leader);
        current = e.leader;
    }
    {
        const t: Trigger = .{ .key = .{ .translated = .b } };
        const e = current.get(t).?;
        try testing.expect(e == .action);
        try testing.expect(e.action == .new_window);
    }
}

test "set: parseAndPut sequence with two actions" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a>b=new_window");
    try s.parseAndPut(alloc, "a>c=new_tab");
    var current: *Set = &s;
    {
        const t: Trigger = .{ .key = .{ .translated = .a } };
        const e = current.get(t).?;
        try testing.expect(e == .leader);
        current = e.leader;
    }
    {
        const t: Trigger = .{ .key = .{ .translated = .b } };
        const e = current.get(t).?;
        try testing.expect(e == .action);
        try testing.expect(e.action == .new_window);
    }
    {
        const t: Trigger = .{ .key = .{ .translated = .c } };
        const e = current.get(t).?;
        try testing.expect(e == .action);
        try testing.expect(e.action == .new_tab);
    }
}

test "set: parseAndPut overwrite sequence" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a>b=new_tab");
    try s.parseAndPut(alloc, "a>b=new_window");
    var current: *Set = &s;
    {
        const t: Trigger = .{ .key = .{ .translated = .a } };
        const e = current.get(t).?;
        try testing.expect(e == .leader);
        current = e.leader;
    }
    {
        const t: Trigger = .{ .key = .{ .translated = .b } };
        const e = current.get(t).?;
        try testing.expect(e == .action);
        try testing.expect(e.action == .new_window);
    }
}

test "set: parseAndPut overwrite leader" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a=new_tab");
    try s.parseAndPut(alloc, "a>b=new_window");
    var current: *Set = &s;
    {
        const t: Trigger = .{ .key = .{ .translated = .a } };
        const e = current.get(t).?;
        try testing.expect(e == .leader);
        current = e.leader;
    }
    {
        const t: Trigger = .{ .key = .{ .translated = .b } };
        const e = current.get(t).?;
        try testing.expect(e == .action);
        try testing.expect(e.action == .new_window);
    }
}

test "set: parseAndPut unbind sequence unbinds leader" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a>b=new_window");
    try s.parseAndPut(alloc, "a>b=unbind");
    var current: *Set = &s;
    {
        const t: Trigger = .{ .key = .{ .translated = .a } };
        try testing.expect(current.get(t) == null);
    }
}

test "set: parseAndPut unbind sequence unbinds leader if not set" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a>b=unbind");
    var current: *Set = &s;
    {
        const t: Trigger = .{ .key = .{ .translated = .a } };
        try testing.expect(current.get(t) == null);
    }
}

test "set: parseAndPut sequence preserves reverse mapping" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "a=new_window");
    try s.parseAndPut(alloc, "ctrl+a>b=new_window");

    // Creates reverse mapping
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }
}

test "set: put overwrites sequence" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.parseAndPut(alloc, "ctrl+a>b=new_window");
    try s.put(alloc, .{
        .mods = .{ .ctrl = true },
        .key = .{ .translated = .a },
    }, .{ .new_window = {} });

    // Creates reverse mapping
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }
}

test "set: maintains reverse mapping" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.put(alloc, .{ .key = .{ .translated = .a } }, .{ .new_window = {} });
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }

    // should be most recent
    try s.put(alloc, .{ .key = .{ .translated = .b } }, .{ .new_window = {} });
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .b);
    }

    // removal should replace
    s.remove(alloc, .{ .key = .{ .translated = .b } });
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }
}

test "set: overriding a mapping updates reverse" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.put(alloc, .{ .key = .{ .translated = .a } }, .{ .new_window = {} });
    {
        const trigger = s.getTrigger(.{ .new_window = {} }).?;
        try testing.expect(trigger.key.translated == .a);
    }

    // should be most recent
    try s.put(alloc, .{ .key = .{ .translated = .a } }, .{ .new_tab = {} });
    {
        const trigger = s.getTrigger(.{ .new_window = {} });
        try testing.expect(trigger == null);
    }
}

test "set: consumed state" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s: Set = .{};
    defer s.deinit(alloc);

    try s.put(alloc, .{ .key = .{ .translated = .a } }, .{ .new_window = {} });
    try testing.expect(s.get(.{ .key = .{ .translated = .a } }).? == .action);

    try s.putUnconsumed(alloc, .{ .key = .{ .translated = .a } }, .{ .new_window = {} });
    try testing.expect(s.get(.{ .key = .{ .translated = .a } }).? == .action_unconsumed);

    try s.put(alloc, .{ .key = .{ .translated = .a } }, .{ .new_window = {} });
    try testing.expect(s.get(.{ .key = .{ .translated = .a } }).? == .action);
}
