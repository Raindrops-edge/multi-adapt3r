const builtin = @import("builtin");

pub usingnamespace @cImport({
    @cInclude("hb.h");
    @cInclude("hb-ft.h");
    if (builtin.os.tag == .macos) @cInclude("hb-coretext.h");
});
