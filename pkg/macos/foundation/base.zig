const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig");

pub const ComparisonResult = enum(c_int) {
    less = -1,
    equal = 0,
    greater = 1,
};

pub const Range = extern struct {
    location: c.CFIndex,
    length: c.CFIndex,

    pub fn init(loc: usize, len: usize) Range {
        return @bitCast(c.CFRangeMake(@intCast(loc), @intCast(len)));
    }
};
