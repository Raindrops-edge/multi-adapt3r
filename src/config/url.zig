const std = @import("std");
const oni = @import("oniguruma");

/// Default URL regex. This is used to detect URLs in terminal output.
/// This is here in the config package because one day the matchers will be
/// configurable and this will be a default.
///
/// This is adapted from a regex used in the Alacritty project.
///
/// This regex is liberal in what it accepts after the scheme, with exceptions
/// for URLs ending with . or ). Although such URLs are perfectly valid, it is
/// common for text to contain URLs surrounded by parentheses (such as in
/// Markdown links) or at the end of sentences. Therefore, this regex excludes
/// them as follows:
///
/// 1. Do not match regexes ending with .
/// 2. Do not match regexes ending with ), except for ones which contain a (
///    without a subsequent )
///
/// Rule 2 means that that we handle the following two cases:
///
///   "https://en.wikipedia.org/wiki/Rust_(video_game)" (include parens)
///   "(https://example.com)" (do not include the parens)
///
/// There are many complicated cases where these heuristics break down, but
/// handling them well requires a non-regex approach.
pub const regex = "(?:" ++ url_scheme ++ ")(?:[^" ++ url_exclude ++ "]*[^" ++ url_exclude ++ ").]|[^" ++ url_exclude ++ "(]*\\([^" ++ url_exclude ++ ")]*\\))";
const url_scheme = "ipfs:|ipns:|magnet:|mailto:|gemini://|gopher://|https://|http://|news:|file:|git://|ssh:|ftp://";
const url_exclude = "\u{0000}-\u{001F}\u{007F}-\u{009F}<>\x22\\s{-}\\^⟨⟩\x60";

test "url regex" {
    const testing = std.testing;

    try oni.testing.ensureInit();
    var re = try oni.Regex.init(
        regex,
        .{ .find_longest = true },
        oni.Encoding.utf8,
        oni.Syntax.default,
        null,
    );
    defer re.deinit();

    // The URL cases to test what our regex matches. Feel free to add to this
    // as we find bugs or just want more coverage.
    const cases = [_]struct {
        input: []const u8,
        expect: []const u8,
    }{
        .{
            .input = "hello https://example.com world",
            .expect = "https://example.com",
        },
        .{
            .input = "https://example.com/foo(bar) more",
            .expect = "https://example.com/foo(bar)",
        },
        .{
            .input = "https://example.com/foo(bar)baz more",
            .expect = "https://example.com/foo(bar)baz",
        },
        .{
            .input = "Link inside (https://example.com) parens",
            .expect = "https://example.com",
        },
        .{
            .input = "Link period https://example.com. More text.",
            .expect = "https://example.com",
        },
    };

    for (cases) |case| {
        var reg = try re.search(case.input, .{});
        defer reg.deinit();
        try testing.expectEqual(@as(usize, 1), reg.count());
        const match = case.input[@intCast(reg.starts()[0])..@intCast(reg.ends()[0])];
        try testing.expectEqualStrings(case.expect, match);
    }
}
