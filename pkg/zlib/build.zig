const std = @import("std");

/// Directories with our includes.
const root = thisDir() ++ "../../../vendor/zlib/";
const include_path = root;

pub const include_paths = .{include_path};

pub const pkg = std.build.Pkg{
    .name = "zlib",
    .source = .{ .path = thisDir() ++ "/main.zig" },
};

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn link(b: *std.build.Builder, step: *std.build.LibExeObjStep) !*std.build.LibExeObjStep {
    const lib = try buildLib(b, step);
    step.linkLibrary(lib);
    step.addIncludePath(.{ .path = include_path });
    return lib;
}

pub fn buildLib(
    b: *std.build.Builder,
    step: *std.build.LibExeObjStep,
) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary(.{
        .name = "z",
        .target = step.target,
        .optimize = step.optimize,
    });

    // Include
    lib.addIncludePath(.{ .path = include_path });

    // Link
    lib.linkLibC();

    // Compile
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DHAVE_SYS_TYPES_H",
        "-DHAVE_STDINT_H",
        "-DHAVE_STDDEF_H",
        "-DZ_HAVE_UNISTD_H",
    });

    // C files
    lib.addCSourceFiles(srcs, flags.items);

    return lib;
}

const srcs = &.{
    root ++ "adler32.c",
    root ++ "compress.c",
    root ++ "crc32.c",
    root ++ "deflate.c",
    root ++ "gzclose.c",
    root ++ "gzlib.c",
    root ++ "gzread.c",
    root ++ "gzwrite.c",
    root ++ "inflate.c",
    root ++ "infback.c",
    root ++ "inftrees.c",
    root ++ "inffast.c",
    root ++ "trees.c",
    root ++ "uncompr.c",
    root ++ "zutil.c",
};
