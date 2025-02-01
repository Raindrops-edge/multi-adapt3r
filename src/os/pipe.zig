const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows.zig");
const posix = std.posix;

/// pipe() that works on Windows and POSIX.
pub fn pipe() ![2]posix.fd_t {
    switch (builtin.os.tag) {
        else => return try posix.pipe(),
        .windows => {
            var read: windows.HANDLE = undefined;
            var write: windows.HANDLE = undefined;
            if (windows.exp.kernel32.CreatePipe(&read, &write, null, 0) == 0) {
                return windows.unexpectedError(windows.kernel32.GetLastError());
            }

            return .{ read, write };
        },
    }
}
