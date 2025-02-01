//! OSC (Operating System Command) related functions and types. OSC is
//! another set of control sequences for terminal programs that start with
//! "ESC ]". Unlike CSI or standard ESC sequences, they may contain strings
//! and other irregular formatting so a dedicated parser is created to handle it.
const osc = @This();

const std = @import("std");
const mem = std.mem;

const log = std.log.scoped(.osc);

pub const Command = union(enum) {
    /// Set the window title of the terminal
    ///
    /// If title mode 0  is set text is expect to be hex encoded (i.e. utf-8
    /// with each code unit further encoded with two hex digets).
    ///
    /// If title mode 2 is set or the terminal is setup for unconditional
    /// utf-8 titles text is interpreted as utf-8. Else text is interpreted
    /// as latin1.
    change_window_title: []const u8,

    /// First do a fresh-line. Then start a new command, and enter prompt mode:
    /// Subsequent text (until a OSC "133;B" or OSC "133;I" command) is a
    /// prompt string (as if followed by OSC 133;P;k=i\007). Note: I've noticed
    /// not all shells will send the prompt end code.
    prompt_start: struct {
        aid: ?[]const u8 = null,
        kind: enum { primary, right, continuation } = .primary,
        redraw: bool = true,
    },

    /// End of prompt and start of user input, terminated by a OSC "133;C"
    /// or another prompt (OSC "133;P").
    prompt_end: void,

    /// The OSC "133;C" command can be used to explicitly end
    /// the input area and begin the output area.  However, some applications
    /// don't provide a convenient way to emit that command.
    /// That is why we also specify an implicit way to end the input area
    /// at the end of the line. In the case of  multiple input lines: If the
    /// cursor is on a fresh (empty) line and we see either OSC "133;P" or
    /// OSC "133;I" then this is the start of a continuation input line.
    /// If we see anything else, it is the start of the output area (or end
    /// of command).
    end_of_input: void,

    /// End of current command.
    ///
    /// The exit-code need not be specified if  if there are no options,
    /// or if the command was cancelled (no OSC "133;C"), such as by typing
    /// an interrupt/cancel character (typically ctrl-C) during line-editing.
    /// Otherwise, it must be an integer code, where 0 means the command
    /// succeeded, and other values indicate failure. In additing to the
    /// exit-code there may be an err= option, which non-legacy terminals
    /// should give precedence to. The err=_value_ option is more general:
    /// an empty string is success, and any non-empty value (which need not
    /// be an integer) is an error code. So to indicate success both ways you
    /// could send OSC "133;D;0;err=\007", though `OSC "133;D;0\007" is shorter.
    end_of_command: struct {
        exit_code: ?u8 = null,
        // TODO: err option
    },

    /// Reset the color for the cursor. This reverts changes made with
    /// change/read cursor color.
    reset_cursor_color: void,

    /// Set or get clipboard contents. If data is null, then the current
    /// clipboard contents are sent to the pty. If data is set, this
    /// contents is set on the clipboard.
    clipboard_contents: struct {
        kind: u8,
        data: []const u8,
    },

    /// OSC 7. Reports the current working directory of the shell. This is
    /// a moderately flawed escape sequence but one that many major terminals
    /// support so we also support it. To understand the flaws, read through
    /// this terminal-wg issue: https://gitlab.freedesktop.org/terminal-wg/specifications/-/issues/20
    report_pwd: struct {
        /// The reported pwd value. This is not checked for validity. It should
        /// be a file URL but it is up to the caller to utilize this value.
        value: []const u8,
    },

    /// OSC 22. Set the mouse shape. There doesn't seem to be a standard
    /// naming scheme for cursors but it looks like terminals such as Foot
    /// are moving towards using the W3C CSS cursor names. For OSC parsing,
    /// we just parse whatever string is given.
    mouse_shape: struct {
        value: []const u8,
    },

    /// OSC 10 and OSC 11 default color report.
    report_default_color: struct {
        /// OSC 10 requests the foreground color, OSC 11 the background color.
        kind: DefaultColorKind,

        /// We must reply with the same string terminator (ST) as used in the
        /// request.
        terminator: Terminator = .st,
    },

    pub const DefaultColorKind = enum {
        foreground,
        background,

        pub fn code(self: DefaultColorKind) []const u8 {
            return switch (self) {
                .foreground => "10",
                .background => "11",
            };
        }
    };
};

/// The terminator used to end an OSC command. For OSC commands that demand
/// a response, we try to match the terminator used in the request since that
/// is most likely to be accepted by the calling program.
pub const Terminator = enum {
    /// The preferred string terminator is ESC followed by \
    st,

    /// Some applications and terminals use BELL (0x07) as the string terminator.
    bel,

    /// Initialize the terminator based on the last byte seen. If the
    /// last byte is a BEL then we use BEL, otherwise we just assume ST.
    pub fn init(ch: ?u8) Terminator {
        return switch (ch orelse return .st) {
            0x07 => .bel,
            else => .st,
        };
    }

    /// The terminator as a string. This is static memory so it doesn't
    /// need to be freed.
    pub fn string(self: Terminator) []const u8 {
        return switch (self) {
            .st => "\x1b\\",
            .bel => "\x07",
        };
    }
};

pub const Parser = struct {
    /// Current state of the parser.
    state: State = .empty,

    /// Current command of the parser, this accumulates.
    command: Command = undefined,

    /// Buffer that stores the input we see for a single OSC command.
    /// Slices in Command are offsets into this buffer.
    buf: [MAX_BUF]u8 = undefined,
    buf_start: usize = 0,
    buf_idx: usize = 0,

    /// True when a command is complete/valid to return.
    complete: bool = false,

    /// Temporary state that is dependent on the current state.
    temp_state: union {
        /// Current string parameter being populated
        str: *[]const u8,

        /// Current numeric parameter being populated
        num: u16,

        /// Temporary state for key/value pairs
        key: []const u8,
    } = undefined,

    // Maximum length of a single OSC command. This is the full OSC command
    // sequence length (excluding ESC ]). This is arbitrary, I couldn't find
    // any definitive resource on how long this should be.
    const MAX_BUF = 2048;

    pub const State = enum {
        empty,
        invalid,

        // Command prefixes. We could just accumulate and compare (mem.eql)
        // but the state space is small enough that we just build it up this way.
        @"0",
        @"1",
        @"10",
        @"11",
        @"13",
        @"133",
        @"2",
        @"22",
        @"5",
        @"52",
        @"7",

        // OSC 10 is used to query the default foreground color, and to set the default foreground color.
        // Only querying is currently supported.
        query_default_fg,

        // OSC 11 is used to query the default background color, and to set the default background color.
        // Only querying is currently supported.
        query_default_bg,

        // We're in a semantic prompt OSC command but we aren't sure
        // what the command is yet, i.e. `133;`
        semantic_prompt,
        semantic_option_start,
        semantic_option_key,
        semantic_option_value,
        semantic_exit_code_start,
        semantic_exit_code,

        // Get/set clipboard states
        clipboard_kind,
        clipboard_kind_end,

        // Expect a string parameter. param_str must be set as well as
        // buf_start.
        string,
    };

    /// Reset the parser start.
    pub fn reset(self: *Parser) void {
        self.state = .empty;
        self.buf_start = 0;
        self.buf_idx = 0;
        self.complete = false;
    }

    /// Consume the next character c and advance the parser state.
    pub fn next(self: *Parser, c: u8) void {
        // If our buffer is full then we're invalid.
        if (self.buf_idx >= self.buf.len) {
            self.state = .invalid;
            return;
        }

        // We store everything in the buffer so we can do a better job
        // logging if we get to an invalid command.
        self.buf[self.buf_idx] = c;
        self.buf_idx += 1;

        // log.warn("state = {} c = {x}", .{ self.state, c });

        switch (self.state) {
            // If we get something during the invalid state, we've
            // ruined our entry.
            .invalid => self.complete = false,

            .empty => switch (c) {
                '0' => self.state = .@"0",
                '1' => self.state = .@"1",
                '2' => self.state = .@"2",
                '5' => self.state = .@"5",
                '7' => self.state = .@"7",
                else => self.state = .invalid,
            },

            .@"0" => switch (c) {
                ';' => {
                    self.command = .{ .change_window_title = undefined };

                    self.state = .string;
                    self.temp_state = .{ .str = &self.command.change_window_title };
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .@"1" => switch (c) {
                '0' => self.state = .@"10",
                '1' => self.state = .@"11",
                '3' => self.state = .@"13",
                else => self.state = .invalid,
            },

            .@"10" => switch (c) {
                ';' => self.state = .query_default_fg,
                else => self.state = .invalid,
            },

            .@"11" => switch (c) {
                ';' => self.state = .query_default_bg,
                '2' => {
                    self.complete = true;
                    self.command = .{ .reset_cursor_color = {} };
                    self.state = .invalid;
                },
                else => self.state = .invalid,
            },

            .@"13" => switch (c) {
                '3' => self.state = .@"133",
                else => self.state = .invalid,
            },

            .@"133" => switch (c) {
                ';' => self.state = .semantic_prompt,
                else => self.state = .invalid,
            },

            .@"2" => switch (c) {
                '2' => self.state = .@"22",
                ';' => {
                    self.command = .{ .change_window_title = undefined };

                    self.state = .string;
                    self.temp_state = .{ .str = &self.command.change_window_title };
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .@"22" => switch (c) {
                ';' => {
                    self.command = .{ .mouse_shape = undefined };

                    self.state = .string;
                    self.temp_state = .{ .str = &self.command.mouse_shape.value };
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .@"5" => switch (c) {
                '2' => self.state = .@"52",
                else => self.state = .invalid,
            },

            .@"7" => switch (c) {
                ';' => {
                    self.command = .{ .report_pwd = .{ .value = "" } };

                    self.state = .string;
                    self.temp_state = .{ .str = &self.command.report_pwd.value };
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .@"52" => switch (c) {
                ';' => {
                    self.command = .{ .clipboard_contents = undefined };
                    self.state = .clipboard_kind;
                },
                else => self.state = .invalid,
            },

            .clipboard_kind => switch (c) {
                ';' => {
                    self.command.clipboard_contents.kind = 'c';
                    self.state = .string;
                    self.temp_state = .{ .str = &self.command.clipboard_contents.data };
                    self.buf_start = self.buf_idx;
                },
                else => {
                    self.command.clipboard_contents.kind = c;
                    self.state = .clipboard_kind_end;
                },
            },

            .clipboard_kind_end => switch (c) {
                ';' => {
                    self.state = .string;
                    self.temp_state = .{ .str = &self.command.clipboard_contents.data };
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .query_default_fg => switch (c) {
                '?' => {
                    self.command = .{ .report_default_color = .{ .kind = .foreground } };
                    self.complete = true;
                },
                else => self.state = .invalid,
            },

            .query_default_bg => switch (c) {
                '?' => {
                    self.command = .{ .report_default_color = .{ .kind = .background } };
                    self.complete = true;
                },
                else => self.state = .invalid,
            },

            .semantic_prompt => switch (c) {
                'A' => {
                    self.state = .semantic_option_start;
                    self.command = .{ .prompt_start = .{} };
                    self.complete = true;
                },

                'B' => {
                    self.state = .semantic_option_start;
                    self.command = .{ .prompt_end = {} };
                    self.complete = true;
                },

                'C' => {
                    self.state = .semantic_option_start;
                    self.command = .{ .end_of_input = {} };
                    self.complete = true;
                },

                'D' => {
                    self.state = .semantic_exit_code_start;
                    self.command = .{ .end_of_command = .{} };
                    self.complete = true;
                },

                else => self.state = .invalid,
            },

            .semantic_option_start => switch (c) {
                ';' => {
                    self.state = .semantic_option_key;
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .semantic_option_key => switch (c) {
                '=' => {
                    self.temp_state = .{ .key = self.buf[self.buf_start .. self.buf_idx - 1] };
                    self.state = .semantic_option_value;
                    self.buf_start = self.buf_idx;
                },
                else => {},
            },

            .semantic_option_value => switch (c) {
                ';' => {
                    self.endSemanticOptionValue();
                    self.state = .semantic_option_key;
                    self.buf_start = self.buf_idx;
                },
                else => {},
            },

            .semantic_exit_code_start => switch (c) {
                ';' => {
                    // No longer complete, if ';' shows up we expect some code.
                    self.complete = false;
                    self.state = .semantic_exit_code;
                    self.temp_state = .{ .num = 0 };
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .semantic_exit_code => switch (c) {
                '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                    self.complete = true;

                    const idx = self.buf_idx - self.buf_start;
                    if (idx > 0) self.temp_state.num *|= 10;
                    self.temp_state.num +|= c - '0';
                },
                ';' => {
                    self.endSemanticExitCode();
                    self.state = .semantic_option_key;
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .string => self.complete = true,
        }
    }

    fn endSemanticOptionValue(self: *Parser) void {
        const value = self.buf[self.buf_start..self.buf_idx];

        if (mem.eql(u8, self.temp_state.key, "aid")) {
            switch (self.command) {
                .prompt_start => |*v| v.aid = value,
                else => {},
            }
        } else if (mem.eql(u8, self.temp_state.key, "redraw")) {
            // Kitty supports a "redraw" option for prompt_start. I can't find
            // this documented anywhere but can see in the code that this is used
            // by shell environments to tell the terminal that the shell will NOT
            // redraw the prompt so we should attempt to resize it.
            switch (self.command) {
                .prompt_start => |*v| {
                    const valid = if (value.len == 1) valid: {
                        switch (value[0]) {
                            '0' => v.redraw = false,
                            '1' => v.redraw = true,
                            else => break :valid false,
                        }

                        break :valid true;
                    } else false;

                    if (!valid) {
                        log.info("OSC 133 A invalid redraw value: {s}", .{value});
                    }
                },
                else => {},
            }
        } else if (mem.eql(u8, self.temp_state.key, "k")) {
            // The "k" marks the kind of prompt, or "primary" if we don't know.
            // This can be used to distinguish between the first prompt,
            // a continuation, etc.
            switch (self.command) {
                .prompt_start => |*v| if (value.len == 1) {
                    v.kind = switch (value[0]) {
                        'c', 's' => .continuation,
                        'r' => .right,
                        'i' => .primary,
                        else => .primary,
                    };
                },
                else => {},
            }
        } else log.info("unknown semantic prompts option: {s}", .{self.temp_state.key});
    }

    fn endSemanticExitCode(self: *Parser) void {
        switch (self.command) {
            .end_of_command => |*v| v.exit_code = @truncate(self.temp_state.num),
            else => {},
        }
    }

    fn endString(self: *Parser) void {
        self.temp_state.str.* = self.buf[self.buf_start..self.buf_idx];
    }

    /// End the sequence and return the command, if any. If the return value
    /// is null, then no valid command was found. The optional terminator_ch
    /// is the final character in the OSC sequence. This is used to determine
    /// the response terminator.
    pub fn end(self: *Parser, terminator_ch: ?u8) ?Command {
        if (!self.complete) {
            log.warn("invalid OSC command: {s}", .{self.buf[0..self.buf_idx]});
            return null;
        }

        // Other cleanup we may have to do depending on state.
        switch (self.state) {
            .semantic_exit_code => self.endSemanticExitCode(),
            .semantic_option_value => self.endSemanticOptionValue(),
            .string => self.endString(),
            else => {},
        }

        switch (self.command) {
            .report_default_color => |*c| c.terminator = Terminator.init(terminator_ch),
            else => {},
        }

        return self.command;
    }
};

test "OSC: change_window_title" {
    const testing = std.testing;

    var p: Parser = .{};
    p.next('0');
    p.next(';');
    p.next('a');
    p.next('b');
    const cmd = p.end(null).?;
    try testing.expect(cmd == .change_window_title);
    try testing.expectEqualStrings("ab", cmd.change_window_title);
}

test "OSC: change_window_title with 2" {
    const testing = std.testing;

    var p: Parser = .{};
    p.next('2');
    p.next(';');
    p.next('a');
    p.next('b');
    const cmd = p.end(null).?;
    try testing.expect(cmd == .change_window_title);
    try testing.expectEqualStrings("ab", cmd.change_window_title);
}

test "OSC: prompt_start" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;A";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .prompt_start);
    try testing.expect(cmd.prompt_start.aid == null);
    try testing.expect(cmd.prompt_start.redraw);
}

test "OSC: prompt_start with single option" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;A;aid=14";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .prompt_start);
    try testing.expectEqualStrings("14", cmd.prompt_start.aid.?);
}

test "OSC: prompt_start with redraw disabled" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;A;redraw=0";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .prompt_start);
    try testing.expect(!cmd.prompt_start.redraw);
}

test "OSC: prompt_start with redraw invalid value" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;A;redraw=42";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .prompt_start);
    try testing.expect(cmd.prompt_start.redraw);
    try testing.expect(cmd.prompt_start.kind == .primary);
}

test "OSC: prompt_start with continuation" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;A;k=c";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .prompt_start);
    try testing.expect(cmd.prompt_start.kind == .continuation);
}

test "OSC: end_of_command no exit code" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;D";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .end_of_command);
}

test "OSC: end_of_command with exit code" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;D;25";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .end_of_command);
    try testing.expectEqual(@as(u8, 25), cmd.end_of_command.exit_code.?);
}

test "OSC: prompt_end" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;B";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .prompt_end);
}

test "OSC: end_of_input" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "133;C";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .end_of_input);
}

test "OSC: reset_cursor_color" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "112";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .reset_cursor_color);
}

test "OSC: get/set clipboard" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "52;s;?";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .clipboard_contents);
    try testing.expect(cmd.clipboard_contents.kind == 's');
    try testing.expect(std.mem.eql(u8, "?", cmd.clipboard_contents.data));
}

test "OSC: get/set clipboard (optional parameter)" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "52;;?";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .clipboard_contents);
    try testing.expect(cmd.clipboard_contents.kind == 'c');
    try testing.expect(std.mem.eql(u8, "?", cmd.clipboard_contents.data));
}

test "OSC: report pwd" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "7;file:///tmp/example";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .report_pwd);
    try testing.expect(std.mem.eql(u8, "file:///tmp/example", cmd.report_pwd.value));
}

test "OSC: pointer cursor" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "22;pointer";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?;
    try testing.expect(cmd == .mouse_shape);
    try testing.expect(std.mem.eql(u8, "pointer", cmd.mouse_shape.value));
}

test "OSC: report pwd empty" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "7;";
    for (input) |ch| p.next(ch);

    try testing.expect(p.end(null) == null);
}

test "OSC: longer than buffer" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "a" ** (Parser.MAX_BUF + 2);
    for (input) |ch| p.next(ch);

    try testing.expect(p.end(null) == null);
}

test "OSC: report default foreground color" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "10;?";
    for (input) |ch| p.next(ch);

    // This corresponds to ST = ESC followed by \
    const cmd = p.end('\x1b').?;
    try testing.expect(cmd == .report_default_color);
    try testing.expectEqual(cmd.report_default_color.kind, .foreground);
    try testing.expectEqual(cmd.report_default_color.terminator, .st);
}

test "OSC: report default background color" {
    const testing = std.testing;

    var p: Parser = .{};

    const input = "11;?";
    for (input) |ch| p.next(ch);

    // This corresponds to ST = BEL character
    const cmd = p.end('\x07').?;
    try testing.expect(cmd == .report_default_color);
    try testing.expectEqual(cmd.report_default_color.kind, .background);
    try testing.expectEqual(cmd.report_default_color.terminator, .bel);
}
