const std = @import("std");
const builtin = @import("builtin");
const NativeTargetInfo = std.zig.system.NativeTargetInfo;

/// Directories with our includes.
const root = thisDir() ++ "../../../vendor/fontconfig-2.14.0/";
const include_path = root;
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

pub const Options = struct {
    freetype: Freetype = .{},
    expat: Expat = .{},
    libxml2: bool = false,

    pub const Freetype = struct {
        enabled: bool = false,
        step: ?*std.build.LibExeObjStep = null,
        include: ?[]const []const u8 = null,
    };

    pub const Expat = struct {
        enabled: bool = false,
        step: ?*std.build.LibExeObjStep = null,
        include: ?[]const []const u8 = null,
    };
};

pub fn link(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
    opt: Options,
) !*std.build.LibExeObjStep {
    const lib = try buildFontconfig(b, step, opt);
    step.linkLibrary(lib);
    step.addIncludePath(.{ .path = include_path });
    step.addIncludePath(.{ .path = include_path_self });
    return lib;
}

pub fn buildFontconfig(
    b: *std.Build,
    step: *std.build.LibExeObjStep,
    opt: Options,
) !*std.build.LibExeObjStep {
    const target = step.target;
    const lib = b.addStaticLibrary(.{
        .name = "fontconfig",
        .target = step.target,
        .optimize = step.optimize,
    });

    // Include
    lib.addIncludePath(.{ .path = include_path });
    lib.addIncludePath(.{ .path = include_path_self });

    // Link
    lib.linkLibC();
    if (opt.expat.enabled) {
        if (opt.expat.step) |expat|
            lib.linkLibrary(expat)
        else
            lib.linkSystemLibrary("expat");

        if (opt.expat.include) |dirs|
            for (dirs) |dir| lib.addIncludePath(.{ .path = dir });
    }
    if (opt.freetype.enabled) {
        if (opt.freetype.step) |freetype|
            lib.linkLibrary(freetype)
        else
            lib.linkSystemLibrary("freetype2");

        if (opt.freetype.include) |dirs|
            for (dirs) |dir| lib.addIncludePath(.{ .path = dir });
    }
    if (!target.isWindows()) {
        lib.linkSystemLibrary("pthread");
    }

    // Compile
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DHAVE_DIRENT_H",
        "-DHAVE_FCNTL_H",
        "-DHAVE_STDLIB_H",
        "-DHAVE_STRING_H",
        "-DHAVE_UNISTD_H",
        "-DHAVE_SYS_PARAM_H",

        "-DHAVE_MKSTEMP",
        "-DHAVE__MKTEMP_S",
        "-DHAVE_MKDTEMP",
        "-DHAVE_GETOPT",
        "-DHAVE_GETOPT_LONG",
        //"-DHAVE_GETPROGNAME",
        //"-DHAVE_GETEXECNAME",
        "-DHAVE_RAND",
        //"-DHAVE_RANDOM_R",
        "-DHAVE_FSTATVFS",
        "-DHAVE_FSTATFS",
        "-DHAVE_VPRINTF",

        "-DHAVE_FT_GET_BDF_PROPERTY",
        "-DHAVE_FT_GET_PS_FONT_INFO",
        "-DHAVE_FT_HAS_PS_GLYPH_NAMES",
        "-DHAVE_FT_GET_X11_FONT_FORMAT",
        "-DHAVE_FT_DONE_MM_VAR",

        "-DHAVE_POSIX_FADVISE",

        //"-DHAVE_STRUCT_STATVFS_F_BASETYPE",
        // "-DHAVE_STRUCT_STATVFS_F_FSTYPENAME",
        // "-DHAVE_STRUCT_STATFS_F_FLAGS",
        // "-DHAVE_STRUCT_STATFS_F_FSTYPENAME",
        // "-DHAVE_STRUCT_DIRENT_D_TYPE",

        "-DFLEXIBLE_ARRAY_MEMBER",

        "-DHAVE_STDATOMIC_PRIMITIVES",

        "-DFC_GPERF_SIZE_T=size_t",

        // Default errors that fontconfig can't handle
        "-Wno-implicit-function-declaration",
        "-Wno-int-conversion",

        // https://gitlab.freedesktop.org/fontconfig/fontconfig/-/merge_requests/231
        "-fno-sanitize=undefined",
        "-fno-sanitize-trap=undefined",
    });
    const target_info = try NativeTargetInfo.detect(target);
    switch (target_info.target.ptrBitWidth()) {
        32 => try flags.appendSlice(&.{
            "-DSIZEOF_VOID_P=4",
            "-DALIGNOF_VOID_P=4",
        }),

        64 => try flags.appendSlice(&.{
            "-DSIZEOF_VOID_P=8",
            "-DALIGNOF_VOID_P=8",
        }),

        else => @panic("unsupported arch"),
    }

    if (opt.libxml2) {
        try flags.appendSlice(&.{
            "-DENABLE_LIBXML2",
        });
    }

    if (target.isWindows()) {
        try flags.appendSlice(&.{
            "-DFC_CACHEDIR=\"LOCAL_APPDATA_FONTCONFIG_CACHE\"",
            "-DFC_TEMPLATEDIR=\"c:/share/fontconfig/conf.avail\"",
            "-DCONFIGDIR=\"c:/etc/fonts/conf.d\"",
            "-DFC_DEFAULT_FONTS=\"\\t<dir>WINDOWSFONTDIR</dir>\\n\\t<dir>WINDOWSUSERFONTDIR</dir>\\n\"",
        });
    } else {
        try flags.appendSlice(&.{
            "-DHAVE_SYS_STATVFS_H",
            "-DHAVE_SYS_VFS_H",
            "-DHAVE_SYS_STATFS_H",
            "-DHAVE_SYS_MOUNT_H",
            "-DHAVE_LINK",
            "-DHAVE_MKOSTEMP",
            "-DHAVE_RANDOM",
            "-DHAVE_LRAND48",
            "-DHAVE_RAND_R",
            "-DHAVE_READLINK",
            "-DHAVE_LSTAT",
            "-DHAVE_MMAP",
            "-DHAVE_PTHREAD",

            "-DFC_CACHEDIR=\"/var/cache/fontconfig\"",
            "-DFC_TEMPLATEDIR=\"/usr/share/fontconfig/conf.avail\"",
            "-DFONTCONFIG_PATH=\"/etc/fonts\"",
            "-DCONFIGDIR=\"/usr/local/fontconfig/conf.d\"",
            "-DFC_DEFAULT_FONTS=\"<dir>/usr/share/fonts</dir><dir>/usr/local/share/fonts</dir>\"",
        });
    }

    // C files
    lib.addCSourceFiles(srcs, flags.items);

    return lib;
}

const srcs = &.{
    root ++ "src/fcatomic.c",
    root ++ "src/fccache.c",
    root ++ "src/fccfg.c",
    root ++ "src/fccharset.c",
    root ++ "src/fccompat.c",
    root ++ "src/fcdbg.c",
    root ++ "src/fcdefault.c",
    root ++ "src/fcdir.c",
    root ++ "src/fcformat.c",
    root ++ "src/fcfreetype.c",
    root ++ "src/fcfs.c",
    root ++ "src/fcptrlist.c",
    root ++ "src/fchash.c",
    root ++ "src/fcinit.c",
    root ++ "src/fclang.c",
    root ++ "src/fclist.c",
    root ++ "src/fcmatch.c",
    root ++ "src/fcmatrix.c",
    root ++ "src/fcname.c",
    root ++ "src/fcobjs.c",
    root ++ "src/fcpat.c",
    root ++ "src/fcrange.c",
    root ++ "src/fcserialize.c",
    root ++ "src/fcstat.c",
    root ++ "src/fcstr.c",
    root ++ "src/fcweight.c",
    root ++ "src/fcxml.c",
    root ++ "src/ftglue.c",
};
