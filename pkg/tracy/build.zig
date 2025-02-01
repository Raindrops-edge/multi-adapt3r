const std = @import("std");

/// Directories with our includes.
const root = thisDir() ++ "../../../vendor/tracy/";

pub fn module(b: *std.Build) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = (comptime thisDir()) ++ "/tracy.zig" },
    });
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn link(b: *std.Build, step: *std.build.LibExeObjStep) !*std.build.LibExeObjStep {
    const tracy = try buildTracy(b, step);
    step.linkLibrary(tracy);
    step.addIncludePath(.{ .path = root });
    return tracy;
}

pub fn buildTracy(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
) !*std.build.LibExeObjStep {
    const target = step.target;
    const lib = b.addStaticLibrary(.{
        .name = "tracy",
        .target = step.target,
        .optimize = step.optimize,
    });

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DTRACY_ENABLE",
        "-fno-sanitize=undefined",
    });

    if (target.isWindows()) {
        try flags.appendSlice(&.{
            "-D_WIN32_WINNT=0x601",
        });
    }

    lib.addIncludePath(.{ .path = root });
    lib.addCSourceFile(.{
        .file = .{ .path = try std.fs.path.join(
            b.allocator,
            &.{ root, "TracyClient.cpp" },
        ) },
        .flags = flags.items,
    });

    lib.linkLibC();
    lib.linkSystemLibrary("c++");

    if (lib.target.isWindows()) {
        lib.linkSystemLibrary("Advapi32");
        lib.linkSystemLibrary("User32");
        lib.linkSystemLibrary("Ws2_32");
        lib.linkSystemLibrary("DbgHelp");
    }

    return lib;
}
