const std = @import("std");
const Allocator = std.mem.Allocator;
const internal_os = @import("../os/main.zig");

/// Open the configuration in the OS default editor according to the default
/// paths the main config file could be in.
pub fn open(alloc_gpa: Allocator) !void {
    // default location
    const config_path = try internal_os.xdg.config(alloc_gpa, .{ .subdir = "ghostty/config" });
    defer alloc_gpa.free(config_path);

    // Create config directory recursively.
    if (std.fs.path.dirname(config_path)) |config_dir| {
        try std.fs.cwd().makePath(config_dir);
    }

    // Try to create file and go on if it already exists
    _ = std.fs.createFileAbsolute(
        config_path,
        .{ .exclusive = true },
    ) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    try internal_os.open(alloc_gpa, config_path);
}
