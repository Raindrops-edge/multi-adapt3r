const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows.zig");

/// pipe() that works on Windows and POSIX.
pub fn pipe() ![2]std.os.fd_t {
    switch (builtin.os.tag) {
        else => return try std.os.pipe(),
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
