pub const c = @import("foundation/c.zig");
pub usingnamespace @import("foundation/array.zig");
pub usingnamespace @import("foundation/attributed_string.zig");
pub usingnamespace @import("foundation/base.zig");
pub usingnamespace @import("foundation/character_set.zig");
pub usingnamespace @import("foundation/data.zig");
pub usingnamespace @import("foundation/dictionary.zig");
pub usingnamespace @import("foundation/number.zig");
pub usingnamespace @import("foundation/string.zig");
pub usingnamespace @import("foundation/type.zig");
pub usingnamespace @import("foundation/url.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
