const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.os);

/// This maximizes the number of file descriptors we can have open. We
/// need to do this because each window consumes at least a handful of fds.
/// This is extracted from the Zig compiler source code.
pub fn fixMaxFiles() void {
    if (!@hasDecl(std.os.system, "rlimit")) return;
    const posix = std.os;

    var lim = posix.getrlimit(.NOFILE) catch {
        log.warn("failed to query file handle limit, may limit max windows", .{});
        return; // Oh well; we tried.
    };

    // If we're already at the max, we're done.
    if (lim.cur >= lim.max) {
        log.debug("file handle limit already maximized value={}", .{lim.cur});
        return;
    }

    // Do a binary search for the limit.
    var min: posix.rlim_t = lim.cur;
    var max: posix.rlim_t = 1 << 20;
    // But if there's a defined upper bound, don't search, just set it.
    if (lim.max != posix.RLIM.INFINITY) {
        min = lim.max;
        max = lim.max;
    }

    while (true) {
        lim.cur = min + @divTrunc(max - min, 2); // on freebsd rlim_t is signed
        if (posix.setrlimit(.NOFILE, lim)) |_| {
            min = lim.cur;
        } else |_| {
            max = lim.cur;
        }
        if (min + 1 >= max) break;
    }

    log.debug("file handle limit raised value={}", .{lim.cur});
}

/// Return the recommended path for temporary files.
pub fn tmpDir() ?[]const u8 {
    if (builtin.os.tag == .windows) {
        // TODO: what is a good fallback path on windows?
        const v = std.os.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("TMP")) orelse return null;
        // MAX_PATH is very likely sufficient, but it's theoretically possible for someone to
        // configure their os to allow paths as big as std.os.windows.PATH_MAX_WIDE, which is MUCH
        // larger. Even if they did that, though, it's very unlikey that their Temp dir will use
        // such a long path. We can switch if we see any issues, though it seems fairly unlikely.
        var buf = [_]u8{0} ** std.os.windows.MAX_PATH;
        const len = std.unicode.utf16leToUtf8(buf[0..], v[0..v.len]) catch |e| {
            log.warn("failed to convert temp dir path from windows string: {}", .{e});
            return null;
        };
        return buf[0..len];
    }
    if (std.os.getenv("TMPDIR")) |v| return v;
    if (std.os.getenv("TMP")) |v| return v;
    return "/tmp";
}
