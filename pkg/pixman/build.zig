const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("pixman", .{ .source_file = .{ .path = "main.zig" } });

    const upstream = b.dependency("pixman", .{});
    const lib = b.addStaticLibrary(.{
        .name = "pixman",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    if (!target.isWindows()) {
        lib.linkSystemLibrary("pthread");
    }

    lib.addIncludePath(upstream.path(""));
    lib.addIncludePath(.{ .path = "" });

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

    for (srcs) |src| {
        lib.addCSourceFile(.{
            .file = upstream.path(src),
            .flags = flags.items,
        });
    }

    lib.installHeader("pixman-version.h", "pixman-version.h");
    lib.installHeadersDirectoryOptions(.{
        .source_dir = upstream.path("pixman"),
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

        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);
    }
}

const srcs: []const []const u8 = &.{
    "pixman/pixman.c",
    "pixman/pixman-access.c",
    "pixman/pixman-access-accessors.c",
    "pixman/pixman-bits-image.c",
    "pixman/pixman-combine32.c",
    "pixman/pixman-combine-float.c",
    "pixman/pixman-conical-gradient.c",
    "pixman/pixman-filter.c",
    "pixman/pixman-x86.c",
    "pixman/pixman-mips.c",
    "pixman/pixman-arm.c",
    "pixman/pixman-ppc.c",
    "pixman/pixman-edge.c",
    "pixman/pixman-edge-accessors.c",
    "pixman/pixman-fast-path.c",
    "pixman/pixman-glyph.c",
    "pixman/pixman-general.c",
    "pixman/pixman-gradient-walker.c",
    "pixman/pixman-image.c",
    "pixman/pixman-implementation.c",
    "pixman/pixman-linear-gradient.c",
    "pixman/pixman-matrix.c",
    "pixman/pixman-noop.c",
    "pixman/pixman-radial-gradient.c",
    "pixman/pixman-region16.c",
    "pixman/pixman-region32.c",
    "pixman/pixman-solid-fill.c",
    //"pixman/pixman-timer.c",
    "pixman/pixman-trap.c",
    "pixman/pixman-utils.c",
};
