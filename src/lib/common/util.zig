//! Index of common utilities.

const std = @import("std");

pub const bit = @import("./util/bit.zig");
pub const layout = @import("./util/layout.zig");

pub const debug = @import("./util/debug.zig").debug;
pub const inspect = @import("./util/debug.zig").inspect;

comptime {
    std.testing.refAllDecls(bit);
}
