const std = @import("std");
const apple_sdk = @import("apple_sdk");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const coretext_enabled = b.option(bool, "enable-coretext", "Build coretext") orelse false;
    const freetype_enabled = b.option(bool, "enable-freetype", "Build freetype") orelse true;

    const freetype = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
        .@"enable-libpng" = true,
    });
    const macos = b.dependency("macos", .{ .target = target, .optimize = optimize });
    const upstream = b.dependency("harfbuzz", .{});

    const module = b.addModule("harfbuzz", .{
        .source_file = .{ .path = "main.zig" },
        .dependencies = &.{
            .{ .name = "freetype", .module = freetype.module("freetype") },
            .{ .name = "macos", .module = macos.module("macos") },
        },
    });

    const lib = b.addStaticLibrary(.{
        .name = "harfbuzz",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkLibCpp();
    lib.addIncludePath(upstream.path("src"));

    const freetype_dep = b.dependency("freetype", .{ .target = target, .optimize = optimize });
    lib.linkLibrary(freetype_dep.artifact("freetype"));

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(&.{
        "-DHAVE_STDBOOL_H",
    });
    if (!target.isWindows()) {
        try flags.appendSlice(&.{
            "-DHAVE_UNISTD_H",
            "-DHAVE_SYS_MMAN_H",
            "-DHAVE_PTHREAD=1",
        });
    }
    if (freetype_enabled) try flags.appendSlice(&.{
        "-DHAVE_FREETYPE=1",

        // Let's just assume a new freetype
        "-DHAVE_FT_GET_VAR_BLEND_COORDINATES=1",
        "-DHAVE_FT_SET_VAR_BLEND_COORDINATES=1",
        "-DHAVE_FT_DONE_MM_VAR=1",
        "-DHAVE_FT_GET_TRANSFORM=1",
    });
    if (coretext_enabled) {
        try flags.appendSlice(&.{"-DHAVE_CORETEXT=1"});
        try apple_sdk.addPaths(b, lib);
        lib.linkFramework("ApplicationServices");
    }

    lib.addCSourceFile(.{
        .file = upstream.path("src/harfbuzz.cc"),
        .flags = flags.items,
    });
    lib.installHeadersDirectoryOptions(.{
        .source_dir = upstream.path("src"),
        .install_dir = .header,
        .install_subdir = "",
        .include_extensions = &.{".h"},
    });

    b.installArtifact(lib);

    {
        const test_exe = b.addTest(.{
            .name = "test",
            .root_source_file = .{ .path = "main.zig" },
            .target = target,
            .optimize = optimize,
        });
        test_exe.linkLibrary(lib);

        var it = module.dependencies.iterator();
        while (it.next()) |entry| test_exe.addModule(entry.key_ptr.*, entry.value_ptr.*);
        test_exe.linkLibrary(freetype_dep.artifact("freetype"));
        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);
    }
}
