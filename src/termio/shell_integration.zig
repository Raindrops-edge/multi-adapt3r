const std = @import("std");
const EnvMap = std.process.EnvMap;

const log = std.log.scoped(.shell_integration);

/// Shell types we support
pub const Shell = enum {
    fish,
    zsh,
};

/// Setup the command execution environment for automatic
/// integrated shell integration. This returns true if shell
/// integration was successful. False could mean many things:
/// the shell type wasn't detected, etc.
pub fn setup(
    resource_dir: []const u8,
    command_path: []const u8,
    env: *EnvMap,
    force_shell: ?Shell,
) !?Shell {
    const exe = if (force_shell) |shell| switch (shell) {
        .fish => "/fish",
        .zsh => "/zsh",
    } else std.fs.path.basename(command_path);

    if (std.mem.eql(u8, "fish", exe)) {
        try setupFish(resource_dir, env);
        return .fish;
    }

    if (std.mem.eql(u8, "zsh", exe)) {
        try setupZsh(resource_dir, env);
        return .zsh;
    }

    return null;
}

/// Setup the fish automatic shell integration. This works by
/// modify XDG_DATA_DIRS to include the resource directory.
/// Fish will automatically load configuration in XDG_DATA_DIRS
/// "fish/vendor_conf.d/*.fish".
fn setupFish(
    resource_dir: []const u8,
    env: *EnvMap,
) !void {
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Get our path to the shell integration directory.
    const integ_dir = try std.fmt.bufPrint(
        &path_buf,
        "{s}/shell-integration",
        .{resource_dir},
    );

    // Set an env var so we can remove this from XDG_DATA_DIRS later.
    // This happens in the shell integration config itself. We do this
    // so that our modifications don't interfere with other commands.
    try env.put("GHOSTTY_FISH_XDG_DIR", integ_dir);

    if (env.get("XDG_DATA_DIRS")) |old| {
        // We have an old value, We need to prepend our value to it.

        // We use a 4K buffer to hold our XDG_DATA_DIR value. The stack
        // on macOS is at least 512K and Linux is 8MB or more. So this
        // should fit. If the user has a XDG_DATA_DIR value that is longer
        // than this then it will fail... and we will cross that bridge
        // when we actually get there. This avoids us needing an allocator.
        var buf: [4096]u8 = undefined;
        const prepended = try std.fmt.bufPrint(
            &buf,
            "{s}{c}{s}",
            .{ integ_dir, std.fs.path.delimiter, old },
        );

        try env.put("XDG_DATA_DIRS", prepended);
    } else {
        // No XDG_DATA_DIRS set, we just set it our desired value.
        try env.put("XDG_DATA_DIRS", integ_dir);
    }
}

/// Setup the zsh automatic shell integration. This works by setting
/// ZDOTDIR to our resources dir so that zsh will load our config. This
/// config then loads the true user config.
fn setupZsh(
    resource_dir: []const u8,
    env: *EnvMap,
) !void {
    // Preserve the old zdotdir value so we can recover it.
    if (env.get("ZDOTDIR")) |old| {
        try env.put("GHOSTTY_ZSH_ZDOTDIR", old);
    }

    // Set our new ZDOTDIR
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const integ_dir = try std.fmt.bufPrint(
        &path_buf,
        "{s}/shell-integration/zsh",
        .{resource_dir},
    );
    try env.put("ZDOTDIR", integ_dir);
}
