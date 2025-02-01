const std = @import("std");

pub const Error = std.mem.Allocator.Error || error{WuffsError};
