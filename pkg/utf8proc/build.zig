const std = @import("std");

/// Directories with our includes.
const root = thisDir() ++ "../../../vendor/utf8proc/";
const include_path = root;

pub const include_paths = .{include_path};

pub fn module(b: *std.Build) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = (comptime thisDir()) ++ "/main.zig" },
    });
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn link(b: *std.Build, step: *std.build.LibExeObjStep) !*std.build.LibExeObjStep {
    const lib = try buildLib(b, step);
    step.linkLibrary(lib);
    step.addIncludePath(.{ .path = include_path });
    return lib;
}

pub fn buildLib(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary(.{
        .name = "utf8proc",
        .target = step.target,
        .optimize = step.optimize,
    });

    // Include
    lib.addIncludePath(.{ .path = include_path });

    // Link
    lib.linkLibC();

    // Compile
    var flags = std.ArrayList([]const u8).init(b.allocator);
    try flags.append("-DUTF8PROC_EXPORTS");
    defer flags.deinit();

    // C files
    lib.addCSourceFiles(srcs, flags.items);

    return lib;
}

const srcs = &.{
    root ++ "utf8proc.c",
};
