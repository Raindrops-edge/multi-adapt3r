const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("libpng", .{});

    const lib = b.addStaticLibrary(.{
        .name = "png",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    if (target.isLinux()) {
        lib.linkSystemLibrary("m");
    }

    const zlib_dep = b.dependency("zlib", .{ .target = target, .optimize = optimize });
    lib.linkLibrary(zlib_dep.artifact("z"));
    lib.addIncludePath(upstream.path(""));
    lib.addIncludePath(.{ .path = "" });

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(&.{
        "-DPNG_ARM_NEON_OPT=0",
        "-DPNG_POWERPC_VSX_OPT=0",
        "-DPNG_INTEL_SSE_OPT=0",
        "-DPNG_MIPS_MSA_OPT=0",
    });
    for (srcs) |src| {
        lib.addCSourceFile(.{
            .file = upstream.path(src),
            .flags = flags.items,
        });
    }

    lib.installHeader("pnglibconf.h", "pnglibconf.h");
    lib.installHeadersDirectoryOptions(.{
        .source_dir = upstream.path(""),
        .install_dir = .header,
        .install_subdir = "",
        .include_extensions = &.{".h"},
    });

    b.installArtifact(lib);
}

const srcs: []const []const u8 = &.{
    "png.c",
    "pngerror.c",
    "pngget.c",
    "pngmem.c",
    "pngpread.c",
    "pngread.c",
    "pngrio.c",
    "pngrtran.c",
    "pngrutil.c",
    "pngset.c",
    "pngtrans.c",
    "pngwio.c",
    "pngwrite.c",
    "pngwtran.c",
    "pngwutil.c",
};
