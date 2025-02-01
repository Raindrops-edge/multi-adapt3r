const std = @import("std");
const builtin = @import("builtin");

/// Directories with our includes.
const root = thisDir() ++ "../../../vendor/pixman/";
const include_path = root ++ "pixman/";
const include_path_self = thisDir();

pub const include_paths = .{ include_path, include_path_self };

pub fn module(b: *std.Build) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = (comptime thisDir()) ++ "/main.zig" },
    });
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub const Options = struct {};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const tests = b.addTestExe("pixman-test", "main.zig");
    tests.setBuildMode(mode);
    tests.setTarget(target);
    _ = try link(b, tests, .{});
    b.installArtifact(tests);

    const test_step = b.step("test", "Run tests");
    const tests_run = b.addRunArtifact(tests);
    test_step.dependOn(&tests_run.step);
}

pub fn link(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
    opt: Options,
) !*std.build.LibExeObjStep {
    const lib = try buildPixman(b, step, opt);
    step.linkLibrary(lib);
    step.addIncludePath(.{ .path = include_path });
    step.addIncludePath(.{ .path = include_path_self });
    return lib;
}

pub fn buildPixman(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
    opt: Options,
) !*std.build.LibExeObjStep {
    _ = opt;

    const target = step.target;
    const lib = b.addStaticLibrary(.{
        .name = "pixman",
        .target = step.target,
        .optimize = step.optimize,
    });

    // Include
    lib.addIncludePath(.{ .path = include_path });
    lib.addIncludePath(.{ .path = include_path_self });

    // Link
    lib.linkLibC();
    if (!target.isWindows()) {
        lib.linkSystemLibrary("pthread");
    }

    // Compile
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DHAVE_SIGACTION=1",
        "-DHAVE_ALARM=1",
        "-DHAVE_MPROTECT=1",
        "-DHAVE_GETPAGESIZE=1",
        "-DHAVE_MMAP=1",
        "-DHAVE_GETISAX=1",
        "-DHAVE_GETTIMEOFDAY=1",

        "-DHAVE_FENV_H=1",
        "-DHAVE_SYS_MMAN_H=1",
        "-DHAVE_UNISTD_H=1",

        "-DSIZEOF_LONG=8",
        "-DPACKAGE=foo",

        // There is ubsan
        "-fno-sanitize=undefined",
        "-fno-sanitize-trap=undefined",
    });

    if (!target.isWindows()) {
        try flags.appendSlice(&.{
            "-DHAVE_PTHREADS=1",

            "-DHAVE_POSIX_MEMALIGN=1",
        });
    }

    // C files
    lib.addCSourceFiles(srcs, flags.items);

    return lib;
}

const srcs = &.{
    root ++ "pixman/pixman.c",
    root ++ "pixman/pixman-access.c",
    root ++ "pixman/pixman-access-accessors.c",
    root ++ "pixman/pixman-bits-image.c",
    root ++ "pixman/pixman-combine32.c",
    root ++ "pixman/pixman-combine-float.c",
    root ++ "pixman/pixman-conical-gradient.c",
    root ++ "pixman/pixman-filter.c",
    root ++ "pixman/pixman-x86.c",
    root ++ "pixman/pixman-mips.c",
    root ++ "pixman/pixman-arm.c",
    root ++ "pixman/pixman-ppc.c",
    root ++ "pixman/pixman-edge.c",
    root ++ "pixman/pixman-edge-accessors.c",
    root ++ "pixman/pixman-fast-path.c",
    root ++ "pixman/pixman-glyph.c",
    root ++ "pixman/pixman-general.c",
    root ++ "pixman/pixman-gradient-walker.c",
    root ++ "pixman/pixman-image.c",
    root ++ "pixman/pixman-implementation.c",
    root ++ "pixman/pixman-linear-gradient.c",
    root ++ "pixman/pixman-matrix.c",
    root ++ "pixman/pixman-noop.c",
    root ++ "pixman/pixman-radial-gradient.c",
    root ++ "pixman/pixman-region16.c",
    root ++ "pixman/pixman-region32.c",
    root ++ "pixman/pixman-solid-fill.c",
    //root ++ "pixman/pixman-timer.c",
    root ++ "pixman/pixman-trap.c",
    root ++ "pixman/pixman-utils.c",
};
