pub const args = @import("cli/args.zig");
pub const Action = @import("cli/action.zig").Action;

test {
    @import("std").testing.refAllDecls(@This());
}
