const builtin = @import("builtin");

pub usingnamespace @import("config/key.zig");
pub const Config = @import("config/Config.zig");

// Field types
pub const CopyOnSelect = Config.CopyOnSelect;
pub const Keybinds = Config.Keybinds;
pub const NonNativeFullscreen = Config.NonNativeFullscreen;
pub const OptionAsAlt = Config.OptionAsAlt;

// Alternate APIs
pub const CAPI = @import("config/CAPI.zig");
pub const Wasm = if (!builtin.target.isWasm()) struct {} else @import("config/Wasm.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
