//! Index of common utilities.

const std = @import("std");

pub const bit = @import("./util/bit.zig");

comptime {
    std.testing.refAllDecls(bit);
}
