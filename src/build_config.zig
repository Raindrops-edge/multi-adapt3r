//! Build options, available at comptime. Used to configure features. This
//! will reproduce some of the fields from builtin and build_options just
//! so we can limit the amount of imports we need AND give us the ability
//! to shim logic and values into them later.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const assert = std.debug.assert;
const apprt = @import("apprt.zig");
const font = @import("font/main.zig");
const rendererpkg = @import("renderer.zig");

/// The semantic version of this build.
pub const version = options.app_version;
pub const version_string = options.app_version_string;

/// The artifact we're producing. This can be used to determine if we're
/// building a standalone exe, an embedded lib, etc.
pub const artifact = Artifact.detect();

/// The runtime to back exe artifacts with.
pub const app_runtime: apprt.Runtime = switch (artifact) {
    .lib => .none,
    else => std.meta.stringToEnum(apprt.Runtime, @tagName(options.app_runtime)).?,
};

/// The font backend desired for the build.
pub const font_backend: font.Backend = std.meta.stringToEnum(
    font.Backend,
    @tagName(options.font_backend),
).?;

/// The renderer implementation to use.
pub const renderer: rendererpkg.Impl = std.meta.stringToEnum(
    rendererpkg.Impl,
    @tagName(options.renderer),
).?;

/// We want to integrate with Flatpak APIs.
pub const flatpak = options.flatpak;

pub const Artifact = enum {
    /// Standalone executable
    exe,

    /// Embeddable library
    lib,

    /// The WASM-targeted module.
    wasm_module,

    pub fn detect() Artifact {
        if (builtin.target.isWasm()) {
            assert(builtin.output_mode == .Obj);
            assert(builtin.link_mode == .Static);
            return .wasm_module;
        }

        return switch (builtin.output_mode) {
            .Exe => .exe,
            .Lib => .lib,
            else => {
                @compileLog(builtin.output_mode);
                @compileError("unsupported artifact output mode");
            },
        };
    }
};
