const std = @import("std");
const testing = std.testing;
const Parser = @import("Parser.zig");
const ansi = @import("ansi.zig");
const charsets = @import("charsets.zig");
const csi = @import("csi.zig");
const kitty = @import("kitty.zig");
const modes = @import("modes.zig");
const osc = @import("osc.zig");
const sgr = @import("sgr.zig");
const trace = @import("tracy").trace;
const MouseShape = @import("mouse_shape.zig").MouseShape;

const log = std.log.scoped(.stream);

/// Returns a type that can process a stream of tty control characters.
/// This will call various callback functions on type T. Type T only has to
/// implement the callbacks it cares about; any unimplemented callbacks will
/// logged at runtime.
///
/// To figure out what callbacks exist, search the source for "hasDecl". This
/// isn't ideal but for now that's the best approach.
///
/// This is implemented this way because we purposely do NOT want dynamic
/// dispatch for performance reasons. The way this is implemented forces
/// comptime resolution for all function calls.
pub fn Stream(comptime Handler: type) type {
    return struct {
        const Self = @This();

        // We use T with @hasDecl so it needs to be a struct. Unwrap the
        // pointer if we were given one.
        const T = switch (@typeInfo(Handler)) {
            .Pointer => |p| p.child,
            else => Handler,
        };

        handler: Handler,
        parser: Parser = .{},

        /// Process a string of characters.
        pub fn nextSlice(self: *Self, c: []const u8) !void {
            const tracy = trace(@src());
            defer tracy.end();
            for (c) |single| try self.next(single);
        }

        /// Process the next character and call any callbacks if necessary.
        pub fn next(self: *Self, c: u8) !void {
            const tracy = trace(@src());
            tracy.value(@as(u64, @intCast(c)));
            defer tracy.end();

            // log.debug("char: {c}", .{c});
            const actions = self.parser.next(c);
            for (actions) |action_opt| {
                // if (action_opt) |action| {
                //     if (action != .print)
                //         log.info("action: {}", .{action});
                // }
                switch (action_opt orelse continue) {
                    .print => |p| if (@hasDecl(T, "print")) try self.handler.print(p),
                    .execute => |code| try self.execute(code),
                    .csi_dispatch => |csi_action| try self.csiDispatch(csi_action),
                    .esc_dispatch => |esc| try self.escDispatch(esc),
                    .osc_dispatch => |cmd| try self.oscDispatch(cmd),
                    .dcs_hook => |dcs| log.warn("unhandled DCS hook: {}", .{dcs}),
                    .dcs_put => |code| log.warn("unhandled DCS put: {x}", .{code}),
                    .dcs_unhook => log.warn("unhandled DCS unhook", .{}),
                    .apc_start => if (@hasDecl(T, "apcStart")) {
                        try self.handler.apcStart();
                    } else log.warn("unimplemented APC start", .{}),
                    .apc_put => |code| if (@hasDecl(T, "apcPut")) {
                        try self.handler.apcPut(code);
                    } else log.warn("unimplemented APC put: {x}", .{code}),
                    .apc_end => if (@hasDecl(T, "apcEnd")) {
                        try self.handler.apcEnd();
                    } else log.warn("unimplemented APC end", .{}),
                }
            }
        }

        pub fn execute(self: *Self, c: u8) !void {
            const tracy = trace(@src());
            tracy.value(@as(u64, @intCast(c)));
            defer tracy.end();

            switch (@as(ansi.C0, @enumFromInt(c))) {
                // We ignore SOH/STX: https://github.com/microsoft/terminal/issues/10786
                .NUL, .SOH, .STX => {},

                .ENQ => if (@hasDecl(T, "enquiry"))
                    try self.handler.enquiry()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .BEL => if (@hasDecl(T, "bell"))
                    try self.handler.bell()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .BS => if (@hasDecl(T, "backspace"))
                    try self.handler.backspace()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .HT => if (@hasDecl(T, "horizontalTab"))
                    try self.handler.horizontalTab(1)
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .LF => if (@hasDecl(T, "linefeed"))
                    try self.handler.linefeed()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                // VT is same as LF
                .VT => if (@hasDecl(T, "linefeed"))
                    try self.handler.linefeed()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .CR => if (@hasDecl(T, "carriageReturn"))
                    try self.handler.carriageReturn()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .SO => if (@hasDecl(T, "invokeCharset"))
                    try self.handler.invokeCharset(.GL, .G1, false)
                else
                    log.warn("unimplemented invokeCharset: {x}", .{c}),

                .SI => if (@hasDecl(T, "invokeCharset"))
                    try self.handler.invokeCharset(.GL, .G0, false)
                else
                    log.warn("unimplemented invokeCharset: {x}", .{c}),

                else => log.warn("invalid C0 character, ignoring: {x}", .{c}),
            }
        }

        fn csiDispatch(self: *Self, input: Parser.Action.CSI) !void {
            // Handles aliases first
            const action = switch (input.final) {
                // Alias for set cursor position
                'f' => blk: {
                    var copy = input;
                    copy.final = 'H';
                    break :blk copy;
                },

                else => input,
            };

            switch (action.final) {
                // CUU - Cursor Up
                'A', 'k' => if (@hasDecl(T, "setCursorUp")) try self.handler.setCursorUp(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor up command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUD - Cursor Down
                'B' => if (@hasDecl(T, "setCursorDown")) try self.handler.setCursorDown(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor down command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUF - Cursor Right
                'C' => if (@hasDecl(T, "setCursorRight")) try self.handler.setCursorRight(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor right command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUB - Cursor Left
                'D', 'j' => if (@hasDecl(T, "setCursorLeft")) try self.handler.setCursorLeft(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor left command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // HPA - Cursor Horizontal Position Absolute
                // TODO: test
                'G', '`' => if (@hasDecl(T, "setCursorCol")) switch (action.params.len) {
                    0 => try self.handler.setCursorCol(1),
                    1 => try self.handler.setCursorCol(action.params[0]),
                    else => log.warn("invalid HPA command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUP - Set Cursor Position.
                // TODO: test
                'H', 'f' => if (@hasDecl(T, "setCursorPos")) switch (action.params.len) {
                    0 => try self.handler.setCursorPos(1, 1),
                    1 => try self.handler.setCursorPos(action.params[0], 1),
                    2 => try self.handler.setCursorPos(action.params[0], action.params[1]),
                    else => log.warn("invalid CUP command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // CHT - Cursor Horizontal Tabulation
                'I' => if (@hasDecl(T, "horizontalTab")) try self.handler.horizontalTab(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid horizontal tab command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Erase Display
                // TODO: test
                'J' => if (@hasDecl(T, "eraseDisplay")) try self.handler.eraseDisplay(
                    switch (action.params.len) {
                        0 => .below,
                        1 => mode: {
                            // TODO: use meta to get enum max
                            if (action.params[0] > 3) {
                                log.warn("invalid erase display command: {}", .{action});
                                return;
                            }

                            break :mode @enumFromInt(action.params[0]);
                        },
                        else => {
                            log.warn("invalid erase display command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Erase Line
                'K' => if (@hasDecl(T, "eraseLine")) try self.handler.eraseLine(
                    switch (action.params.len) {
                        0 => .right,
                        1 => mode: {
                            // TODO: use meta to get enum max
                            if (action.params[0] > 3) {
                                log.warn("invalid erase line command: {}", .{action});
                                return;
                            }

                            break :mode @enumFromInt(action.params[0]);
                        },
                        else => {
                            log.warn("invalid erase line command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // IL - Insert Lines
                // TODO: test
                'L' => if (@hasDecl(T, "insertLines")) switch (action.params.len) {
                    0 => try self.handler.insertLines(1),
                    1 => try self.handler.insertLines(action.params[0]),
                    else => log.warn("invalid IL command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // DL - Delete Lines
                // TODO: test
                'M' => if (@hasDecl(T, "deleteLines")) switch (action.params.len) {
                    0 => try self.handler.deleteLines(1),
                    1 => try self.handler.deleteLines(action.params[0]),
                    else => log.warn("invalid DL command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // Delete Character (DCH)
                'P' => if (@hasDecl(T, "deleteChars")) try self.handler.deleteChars(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid delete characters command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Scroll Up (SD)
                'S' => if (@hasDecl(T, "scrollUp")) try self.handler.scrollUp(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid scroll up command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Scroll Down (SD)
                'T' => if (@hasDecl(T, "scrollDown")) try self.handler.scrollDown(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid scroll down command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Cursor Tabulation Control
                'W' => {
                    switch (action.params.len) {
                        0 => if (action.intermediates.len == 1 and action.intermediates[0] == '?') {
                            if (@hasDecl(T, "tabClear"))
                                try self.handler.tabClear(.all)
                            else
                                log.warn("unimplemented tab clear callback: {}", .{action});
                        },

                        1 => switch (action.params[0]) {
                            0 => if (@hasDecl(T, "tabSet"))
                                try self.handler.tabSet()
                            else
                                log.warn("unimplemented tab set callback: {}", .{action}),

                            2 => if (@hasDecl(T, "tabClear"))
                                try self.handler.tabClear(.current)
                            else
                                log.warn("unimplemented tab clear callback: {}", .{action}),

                            5 => if (@hasDecl(T, "tabClear"))
                                try self.handler.tabClear(.all)
                            else
                                log.warn("unimplemented tab clear callback: {}", .{action}),

                            else => {},
                        },

                        else => {},
                    }

                    log.warn("invalid cursor tabulation control: {}", .{action});
                    return;
                },

                // Erase Characters (ECH)
                'X' => if (@hasDecl(T, "eraseChars")) try self.handler.eraseChars(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid erase characters command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // CHT - Cursor Horizontal Tabulation Back
                'Z' => if (@hasDecl(T, "horizontalTabBack")) try self.handler.horizontalTabBack(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid horizontal tab back command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Repeat Previous Char (REP)
                'b' => if (@hasDecl(T, "printRepeat")) try self.handler.printRepeat(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid print repeat command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // c - Device Attributes (DA1)
                'c' => if (@hasDecl(T, "deviceAttributes")) {
                    const req: ansi.DeviceAttributeReq = switch (action.intermediates.len) {
                        0 => ansi.DeviceAttributeReq.primary,
                        1 => switch (action.intermediates[0]) {
                            '>' => ansi.DeviceAttributeReq.secondary,
                            '=' => ansi.DeviceAttributeReq.tertiary,
                            else => null,
                        },
                        else => @as(?ansi.DeviceAttributeReq, null),
                    } orelse {
                        log.warn("invalid device attributes command: {}", .{action});
                        return;
                    };

                    try self.handler.deviceAttributes(req, action.params);
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // VPA - Cursor Vertical Position Absolute
                'd' => if (@hasDecl(T, "setCursorRow")) try self.handler.setCursorRow(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid VPA command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // TBC - Tab Clear
                // TODO: test
                'g' => if (@hasDecl(T, "tabClear")) try self.handler.tabClear(
                    switch (action.params.len) {
                        1 => @enumFromInt(action.params[0]),
                        else => {
                            log.warn("invalid tab clear command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // SM - Set Mode
                'h' => if (@hasDecl(T, "setMode")) {
                    for (action.params) |mode| {
                        if (modes.hasSupport(mode)) {
                            try self.handler.setMode(
                                @enumFromInt(mode),
                                true,
                            );
                        } else {
                            log.warn("unimplemented mode: {}", .{mode});
                        }
                    }
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // RM - Reset Mode
                'l' => if (@hasDecl(T, "setMode")) {
                    for (action.params) |mode| {
                        if (modes.hasSupport(mode)) {
                            try self.handler.setMode(
                                @enumFromInt(mode),
                                false,
                            );
                        } else {
                            log.warn("unimplemented mode: {}", .{mode});
                        }
                    }
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // SGR - Select Graphic Rendition
                'm' => switch (action.intermediates.len) {
                    0 => if (@hasDecl(T, "setAttribute")) {
                        var p: sgr.Parser = .{ .params = action.params, .colon = action.sep == .colon };
                        while (p.next()) |attr| {
                            // log.info("SGR attribute: {}", .{attr});
                            try self.handler.setAttribute(attr);
                        }
                    } else log.warn("unimplemented CSI callback: {}", .{action}),

                    1 => switch (action.intermediates[0]) {
                        '>' => if (@hasDecl(T, "setModifyKeyFormat")) blk: {
                            if (action.params.len == 0) {
                                // Reset
                                try self.handler.setModifyKeyFormat(.{ .legacy = {} });
                                break :blk;
                            }

                            var format: ansi.ModifyKeyFormat = switch (action.params[0]) {
                                0 => .{ .legacy = {} },
                                1 => .{ .cursor_keys = {} },
                                2 => .{ .function_keys = {} },
                                4 => .{ .other_keys = .none },
                                else => {
                                    log.warn("invalid setModifyKeyFormat: {}", .{action});
                                    break :blk;
                                },
                            };

                            if (action.params.len > 2) {
                                log.warn("invalid setModifyKeyFormat: {}", .{action});
                                break :blk;
                            }

                            if (action.params.len == 2) {
                                switch (format) {
                                    // We don't support any of the subparams yet for these.
                                    .legacy => {},
                                    .cursor_keys => {},
                                    .function_keys => {},

                                    // We only support the numeric form.
                                    .other_keys => |*v| switch (action.params[1]) {
                                        2 => v.* = .numeric,
                                        else => v.* = .none,
                                    },
                                }
                            }

                            try self.handler.setModifyKeyFormat(format);
                        } else log.warn("unimplemented setModifyKeyFormat: {}", .{action}),

                        else => log.warn(
                            "unknown CSI m with intermediate: {}",
                            .{action.intermediates[0]},
                        ),
                    },

                    else => {
                        // Nothing, but I wanted a place to put this comment:
                        // there are others forms of CSI m that have intermediates.
                        // `vim --clean` uses `CSI ? 4 m` and I don't know what
                        // that means. And there is also `CSI > m` which is used
                        // to control modifier key reporting formats that we don't
                        // support yet.
                        log.warn(
                            "ignoring unimplemented CSI m with intermediates: {s}",
                            .{action.intermediates},
                        );
                    },
                },

                // TODO: test
                'n' => switch (action.intermediates.len) {
                    0 => if (@hasDecl(T, "deviceStatusReport")) try self.handler.deviceStatusReport(
                        switch (action.params.len) {
                            1 => @enumFromInt(action.params[0]),
                            else => {
                                log.warn("invalid device status report command: {}", .{action});
                                return;
                            },
                        },
                    ) else log.warn("unimplemented CSI callback: {}", .{action}),

                    1 => switch (action.intermediates[0]) {
                        '>' => if (@hasDecl(T, "setModifyKeyFormat")) {
                            // This isn't strictly correct. CSI > n has parameters that
                            // control what exactly is being disabled. However, we
                            // only support reverting back to modify other keys in
                            // numeric except format.
                            try self.handler.setModifyKeyFormat(.{ .other_keys = .numeric_except });
                        } else log.warn("unimplemented setModifyKeyFormat: {}", .{action}),

                        else => log.warn(
                            "unknown CSI m with intermediate: {}",
                            .{action.intermediates[0]},
                        ),
                    },

                    else => log.warn(
                        "ignoring unimplemented CSI n with intermediates: {s}",
                        .{action.intermediates},
                    ),
                },

                // DECRQM - Request Mode
                'p' => switch (action.intermediates.len) {
                    2 => decrqm: {
                        if (action.intermediates[0] != '?' and
                            action.intermediates[1] != '$')
                        {
                            log.warn(
                                "ignoring unimplemented CSI p with intermediates: {s}",
                                .{action.intermediates},
                            );
                            break :decrqm;
                        }

                        if (action.params.len != 1) {
                            log.warn("invalid DECRQM command: {}", .{action});
                            break :decrqm;
                        }

                        if (@hasDecl(T, "requestMode")) {
                            try self.handler.requestMode(action.params[0]);
                        } else log.warn("unimplemented DECRQM callback: {}", .{action});
                    },

                    else => log.warn(
                        "ignoring unimplemented CSI p with intermediates: {s}",
                        .{action.intermediates},
                    ),
                },

                // DECSCUSR - Select Cursor Style
                // TODO: test
                'q' => switch (action.intermediates.len) {
                    1 => cursor: {
                        if (action.intermediates[0] != ' ') {
                            log.warn(
                                "ignoring unimplemented CSI q with intermediates: {s}",
                                .{action.intermediates},
                            );
                            break :cursor;
                        }

                        if (@hasDecl(T, "setCursorStyle")) try self.handler.setCursorStyle(
                            switch (action.params.len) {
                                0 => ansi.CursorStyle.default,
                                1 => @enumFromInt(action.params[0]),
                                else => {
                                    log.warn("invalid set curor style command: {}", .{action});
                                    return;
                                },
                            },
                        ) else log.warn("unimplemented CSI callback: {}", .{action});
                    },

                    else => log.warn(
                        "ignoring unimplemented CSI p with intermediates: {s}",
                        .{action.intermediates},
                    ),
                },

                'r' => switch (action.intermediates.len) {
                    // DECSTBM - Set Top and Bottom Margins
                    0 => if (@hasDecl(T, "setTopAndBottomMargin")) {
                        switch (action.params.len) {
                            0 => try self.handler.setTopAndBottomMargin(0, 0),
                            1 => try self.handler.setTopAndBottomMargin(action.params[0], 0),
                            2 => try self.handler.setTopAndBottomMargin(action.params[0], action.params[1]),
                            else => log.warn("invalid DECSTBM command: {}", .{action}),
                        }
                    } else log.warn(
                        "unimplemented CSI callback: {}",
                        .{action},
                    ),

                    1 => switch (action.intermediates[0]) {
                        // Restore Mode
                        '?' => if (@hasDecl(T, "restoreMode")) {
                            for (action.params) |mode| {
                                if (modes.hasSupport(mode)) {
                                    try self.handler.restoreMode(
                                        @enumFromInt(mode),
                                    );
                                } else {
                                    log.warn(
                                        "unimplemented restore mode: {}",
                                        .{mode},
                                    );
                                }
                            }
                        },

                        else => log.warn(
                            "unknown CSI s with intermediate: {}",
                            .{action},
                        ),
                    },

                    else => log.warn(
                        "ignoring unimplemented CSI s with intermediates: {s}",
                        .{action},
                    ),
                },

                // Save Mode
                's' => switch (action.intermediates.len) {
                    1 => switch (action.intermediates[0]) {
                        '?' => if (@hasDecl(T, "saveMode")) {
                            for (action.params) |mode| {
                                if (modes.hasSupport(mode)) {
                                    try self.handler.saveMode(
                                        @enumFromInt(mode),
                                    );
                                } else {
                                    log.warn(
                                        "unimplemented save mode: {}",
                                        .{mode},
                                    );
                                }
                            }
                        },

                        else => log.warn(
                            "unknown CSI s with intermediate: {}",
                            .{action},
                        ),
                    },

                    else => log.warn(
                        "ignoring unimplemented CSI s with intermediates: {s}",
                        .{action},
                    ),
                },

                // Kitty keyboard protocol
                'u' => switch (action.intermediates.len) {
                    1 => switch (action.intermediates[0]) {
                        '?' => if (@hasDecl(T, "queryKittyKeyboard")) {
                            try self.handler.queryKittyKeyboard();
                        },

                        '>' => if (@hasDecl(T, "pushKittyKeyboard")) push: {
                            const flags: u5 = if (action.params.len == 1)
                                std.math.cast(u5, action.params[0]) orelse {
                                    log.warn("invalid pushKittyKeyboard command: {}", .{action});
                                    break :push;
                                }
                            else
                                0;

                            try self.handler.pushKittyKeyboard(@bitCast(flags));
                        },

                        '<' => if (@hasDecl(T, "popKittyKeyboard")) {
                            const number: u16 = if (action.params.len == 1)
                                action.params[0]
                            else
                                1;

                            try self.handler.popKittyKeyboard(number);
                        },

                        '=' => if (@hasDecl(T, "setKittyKeyboard")) set: {
                            const flags: u5 = if (action.params.len >= 1)
                                std.math.cast(u5, action.params[0]) orelse {
                                    log.warn("invalid setKittyKeyboard command: {}", .{action});
                                    break :set;
                                }
                            else
                                0;

                            const number: u16 = if (action.params.len >= 2)
                                action.params[1]
                            else
                                1;

                            const mode: kitty.KeySetMode = switch (number) {
                                0 => .set,
                                1 => .@"or",
                                2 => .not,
                                else => {
                                    log.warn("invalid setKittyKeyboard command: {}", .{action});
                                    break :set;
                                },
                            };

                            try self.handler.setKittyKeyboard(
                                mode,
                                @bitCast(flags),
                            );
                        },

                        else => log.warn(
                            "unknown CSI s with intermediate: {}",
                            .{action},
                        ),
                    },

                    else => log.warn(
                        "ignoring unimplemented CSI u: {}",
                        .{action},
                    ),
                },

                // ICH - Insert Blanks
                // TODO: test
                '@' => if (@hasDecl(T, "insertBlanks")) switch (action.params.len) {
                    0 => try self.handler.insertBlanks(1),
                    1 => try self.handler.insertBlanks(action.params[0]),
                    else => log.warn("invalid ICH command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // DECSASD - Select Active Status Display
                '}' => {
                    const success = decsasd: {
                        // Verify we're getting a DECSASD command
                        if (action.intermediates.len != 1 or action.intermediates[0] != '$')
                            break :decsasd false;
                        if (action.params.len != 1)
                            break :decsasd false;
                        if (!@hasDecl(T, "setActiveStatusDisplay"))
                            break :decsasd false;

                        try self.handler.setActiveStatusDisplay(@enumFromInt(action.params[0]));
                        break :decsasd true;
                    };

                    if (!success) log.warn("unimplemented CSI callback: {}", .{action});
                },

                else => if (@hasDecl(T, "csiUnimplemented"))
                    try self.handler.csiUnimplemented(action)
                else
                    log.warn("unimplemented CSI action: {}", .{action}),
            }
        }

        fn oscDispatch(self: *Self, cmd: osc.Command) !void {
            switch (cmd) {
                .change_window_title => |title| {
                    if (@hasDecl(T, "changeWindowTitle")) {
                        try self.handler.changeWindowTitle(title);
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .clipboard_contents => |clip| {
                    if (@hasDecl(T, "clipboardContents")) {
                        try self.handler.clipboardContents(clip.kind, clip.data);
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .prompt_start => |v| {
                    if (@hasDecl(T, "promptStart")) switch (v.kind) {
                        .primary, .right => try self.handler.promptStart(v.aid, v.redraw),
                        .continuation => try self.handler.promptContinuation(v.aid),
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .prompt_end => {
                    if (@hasDecl(T, "promptEnd")) {
                        try self.handler.promptEnd();
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .end_of_input => {
                    if (@hasDecl(T, "endOfInput")) {
                        try self.handler.endOfInput();
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .end_of_command => |end| {
                    if (@hasDecl(T, "endOfCommand")) {
                        try self.handler.endOfCommand(end.exit_code);
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .report_pwd => |v| {
                    if (@hasDecl(T, "reportPwd")) {
                        try self.handler.reportPwd(v.value);
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .mouse_shape => |v| {
                    if (@hasDecl(T, "setMouseShape")) {
                        const shape = MouseShape.fromString(v.value) orelse {
                            log.warn("unknown cursor shape: {s}", .{v.value});
                            return;
                        };

                        try self.handler.setMouseShape(shape);
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                .report_default_color => |v| {
                    if (@hasDecl(T, "reportDefaultColor")) {
                        try self.handler.reportDefaultColor(v.kind, v.terminator);
                    } else log.warn("unimplemented OSC callback: {}", .{cmd});
                },

                else => if (@hasDecl(T, "oscUnimplemented"))
                    try self.handler.oscUnimplemented(cmd)
                else
                    log.warn("unimplemented OSC command: {}", .{cmd}),
            }
        }

        fn configureCharset(
            self: *Self,
            intermediates: []const u8,
            set: charsets.Charset,
        ) !void {
            if (intermediates.len != 1) {
                log.warn("invalid charset intermediate: {any}", .{intermediates});
                return;
            }

            const slot: charsets.Slots = switch (intermediates[0]) {
                // TODO: support slots '-', '.', '/'

                '(' => .G0,
                ')' => .G1,
                '*' => .G2,
                '+' => .G3,
                else => {
                    log.warn("invalid charset intermediate: {any}", .{intermediates});
                    return;
                },
            };

            if (@hasDecl(T, "configureCharset")) {
                try self.handler.configureCharset(slot, set);
                return;
            }

            log.warn("unimplemented configureCharset callback slot={} set={}", .{
                slot,
                set,
            });
        }

        fn escDispatch(
            self: *Self,
            action: Parser.Action.ESC,
        ) !void {
            switch (action.final) {
                // Charsets
                'B' => try self.configureCharset(action.intermediates, .ascii),
                'A' => try self.configureCharset(action.intermediates, .british),
                '0' => try self.configureCharset(action.intermediates, .dec_special),

                // DECSC - Save Cursor
                '7' => if (@hasDecl(T, "saveCursor")) switch (action.intermediates.len) {
                    0 => try self.handler.saveCursor(),
                    else => {
                        log.warn("invalid command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented ESC callback: {}", .{action}),

                '8' => blk: {
                    switch (action.intermediates.len) {
                        // DECRC - Restore Cursor
                        0 => if (@hasDecl(T, "restoreCursor")) {
                            try self.handler.restoreCursor();
                            break :blk {};
                        } else log.warn("unimplemented restore cursor callback: {}", .{action}),

                        1 => switch (action.intermediates[0]) {
                            // DECALN - Fill Screen with E
                            '#' => if (@hasDecl(T, "decaln")) {
                                try self.handler.decaln();
                                break :blk {};
                            } else log.warn("unimplemented ESC callback: {}", .{action}),

                            else => {},
                        },

                        else => {}, // fall through
                    }

                    log.warn("unimplemented ESC action: {}", .{action});
                },

                // IND - Index
                'D' => if (@hasDecl(T, "index")) switch (action.intermediates.len) {
                    0 => try self.handler.index(),
                    else => {
                        log.warn("invalid index command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented ESC callback: {}", .{action}),

                // NEL - Next Line
                'E' => if (@hasDecl(T, "nextLine")) switch (action.intermediates.len) {
                    0 => try self.handler.nextLine(),
                    else => {
                        log.warn("invalid next line command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented ESC callback: {}", .{action}),

                // HTS - Horizontal Tab Set
                'H' => if (@hasDecl(T, "tabSet"))
                    try self.handler.tabSet()
                else
                    log.warn("unimplemented tab set callback: {}", .{action}),

                // RI - Reverse Index
                'M' => if (@hasDecl(T, "reverseIndex")) switch (action.intermediates.len) {
                    0 => try self.handler.reverseIndex(),
                    else => {
                        log.warn("invalid reverse index command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented ESC callback: {}", .{action}),

                // SS2 - Single Shift 2
                'N' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GL, .G2, true),
                    else => {
                        log.warn("invalid single shift 2 command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // SS3 - Single Shift 3
                'O' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GL, .G3, true),
                    else => {
                        log.warn("invalid single shift 3 command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // RIS - Full Reset
                'c' => if (@hasDecl(T, "fullReset")) switch (action.intermediates.len) {
                    0 => try self.handler.fullReset(),
                    else => {
                        log.warn("invalid full reset command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented ESC callback: {}", .{action}),

                // LS2 - Locking Shift 2
                'n' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GL, .G2, false),
                    else => {
                        log.warn("invalid single shift 2 command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // LS3 - Locking Shift 3
                'o' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GL, .G3, false),
                    else => {
                        log.warn("invalid single shift 3 command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // LS1R - Locking Shift 1 Right
                '~' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GR, .G1, false),
                    else => {
                        log.warn("invalid locking shift 1 right command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // LS2R - Locking Shift 2 Right
                '}' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GR, .G2, false),
                    else => {
                        log.warn("invalid locking shift 2 right command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // LS3R - Locking Shift 3 Right
                '|' => if (@hasDecl(T, "invokeCharset")) switch (action.intermediates.len) {
                    0 => try self.handler.invokeCharset(.GR, .G3, false),
                    else => {
                        log.warn("invalid locking shift 3 right command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented invokeCharset: {}", .{action}),

                // Set application keypad mode
                '=' => if (@hasDecl(T, "setMode")) {
                    try self.handler.setMode(.keypad_keys, true);
                } else log.warn("unimplemented setMode: {}", .{action}),

                // Reset application keypad mode
                '>' => if (@hasDecl(T, "setMode")) {
                    try self.handler.setMode(.keypad_keys, false);
                } else log.warn("unimplemented setMode: {}", .{action}),

                else => if (@hasDecl(T, "escUnimplemented"))
                    try self.handler.escUnimplemented(action)
                else
                    log.warn("unimplemented ESC action: {}", .{action}),

                // Sets ST (string terminator). We don't have to do anything
                // because our parser always accepts ST.
                '\\' => {},
            }
        }
    };
}

test "stream: print" {
    const H = struct {
        c: ?u21 = 0,

        pub fn print(self: *@This(), c: u21) !void {
            self.c = c;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    try s.next('x');
    try testing.expectEqual(@as(u21, 'x'), s.handler.c.?);
}

test "stream: cursor right (CUF)" {
    const H = struct {
        amount: u16 = 0,

        pub fn setCursorRight(self: *@This(), v: u16) !void {
            self.amount = v;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    try s.nextSlice("\x1B[C");
    try testing.expectEqual(@as(u16, 1), s.handler.amount);

    try s.nextSlice("\x1B[5C");
    try testing.expectEqual(@as(u16, 5), s.handler.amount);

    s.handler.amount = 0;
    try s.nextSlice("\x1B[5;4C");
    try testing.expectEqual(@as(u16, 0), s.handler.amount);
}

test "stream: set mode (SM) and reset mode (RM)" {
    const H = struct {
        mode: modes.Mode = @as(modes.Mode, @enumFromInt(1)),
        pub fn setMode(self: *@This(), mode: modes.Mode, v: bool) !void {
            self.mode = @as(modes.Mode, @enumFromInt(1));
            if (v) self.mode = mode;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    try s.nextSlice("\x1B[?6h");
    try testing.expectEqual(@as(modes.Mode, .origin), s.handler.mode);

    try s.nextSlice("\x1B[?6l");
    try testing.expectEqual(@as(modes.Mode, @enumFromInt(1)), s.handler.mode);
}

test "stream: restore mode" {
    const H = struct {
        const Self = @This();
        called: bool = false,

        pub fn setTopAndBottomMargin(self: *Self, t: u16, b: u16) !void {
            _ = t;
            _ = b;
            self.called = true;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    for ("\x1B[?42r") |c| try s.next(c);
    try testing.expect(!s.handler.called);
}

test "stream: pop kitty keyboard with no params defaults to 1" {
    const H = struct {
        const Self = @This();
        n: u16 = 0,

        pub fn popKittyKeyboard(self: *Self, n: u16) !void {
            self.n = n;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    for ("\x1B[<u") |c| try s.next(c);
    try testing.expectEqual(@as(u16, 1), s.handler.n);
}
