const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("tracy", .{ .source_file = .{ .path = "tracy.zig" } });

    const upstream = b.dependency("tracy", .{});
    const lib = b.addStaticLibrary(.{
        .name = "tracy",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkLibCpp();
    if (target.isWindows()) {
        lib.linkSystemLibrary("Advapi32");
        lib.linkSystemLibrary("User32");
        lib.linkSystemLibrary("Ws2_32");
        lib.linkSystemLibrary("DbgHelp");
    }

    lib.addIncludePath(upstream.path(""));

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

    lib.addCSourceFile(.{
        .file = upstream.path("TracyClient.cpp"),
        .flags = flags.items,
    });

    lib.installHeadersDirectoryOptions(.{
        .source_dir = upstream.path(""),
        .install_dir = .header,
        .install_subdir = "",
        .include_extensions = &.{ ".h", ".hpp" },
    });

    b.installArtifact(lib);
}

const headers = &.{
    "TracyC.h",
    "TracyOpenGL.hpp",
    "Tracy.hpp",
    "TracyD3D11.hpp",
    "TracyD3D12.hpp",
    "TracyOpenCL.hpp",
    "TracyVulkan.hpp",
    "client/TracyCallstack.h",
    "client/TracyScoped.hpp",
    "client/TracyStringHelpers.hpp",
    "client/TracySysTrace.hpp",
    "client/TracyDxt1.hpp",
    "client/TracyRingBuffer.hpp",
    "client/tracy_rpmalloc.hpp",
    "client/TracyDebug.hpp",
    "client/TracyLock.hpp",
    "client/TracyThread.hpp",
    "client/TracyArmCpuTable.hpp",
    "client/TracyProfiler.hpp",
    "client/TracyCallstack.hpp",
    "client/TracySysTime.hpp",
    "client/TracyFastVector.hpp",
    "common/TracyApi.h",
    "common/TracyYield.hpp",
    "common/tracy_lz4hc.hpp",
    "common/TracySystem.hpp",
    "common/TracyProtocol.hpp",
    "common/TracyQueue.hpp",
    "common/TracyUwp.hpp",
    "common/TracyAlloc.hpp",
    "common/TracyAlign.hpp",
    "common/TracyForceInline.hpp",
    "common/TracyColor.hpp",
    "common/tracy_lz4.hpp",
    "common/TracyStackFrames.hpp",
    "common/TracySocket.hpp",
    "common/TracyMutex.hpp",
};
