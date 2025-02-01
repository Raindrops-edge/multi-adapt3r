const std = @import("std");
const builtin = @import("builtin");

pub fn module(b: *std.Build) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = (comptime thisDir()) ++ "/main.zig" },
    });
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub const Options = struct {};

pub fn link(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
    opt: Options,
) !*std.build.LibExeObjStep {
    _ = opt;
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    const lib = b.addStaticLibrary(.{
        .name = "macos",
        .target = step.target,
        .optimize = step.optimize,
    });
    step.addCSourceFile(.{
        .file = .{ .path = comptime thisDir() ++ "/os/log.c" },
        .flags = flags.items,
    });
    step.addCSourceFile(.{
        .file = .{ .path = comptime thisDir() ++ "/text/ext.c" },
        .flags = flags.items,
    });
    step.linkFramework("Carbon");
    step.linkFramework("CoreFoundation");
    step.linkFramework("CoreGraphics");
    step.linkFramework("CoreText");
    return lib;
}
