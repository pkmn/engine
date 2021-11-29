//! Index of common utilities.

const std = @import("std");

pub const bit = @import("./util/bit.zig");
pub const debug = @import("./util/debug.zig");
pub const layout = @import("./util/layout.zig");

comptime {
    std.testing.refAllDecls(bit);
}
