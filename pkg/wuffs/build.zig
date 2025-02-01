const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wuffs = b.dependency("wuffs", .{});

    const module = b.addModule("wuffs", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (target.result.isDarwin()) {
        const apple_sdk = @import("apple_sdk");
        try apple_sdk.addPaths(b, module);
    }

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.append("-DWUFFS_IMPLEMENTATION");
    inline for (@import("src/c.zig").defines) |key| {
        try flags.append("-D" ++ key);
    }

    module.addIncludePath(wuffs.path("release/c"));
    module.addCSourceFile(.{
        .file = wuffs.path("release/c/wuffs-v0.4.c"),
        .flags = flags.items,
    });
}
