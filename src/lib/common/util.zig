//! Index of common utilities.

const std = @import("std");

pub const bit = @import("./util/bit.zig");
pub const layout = @import("./util/layout.zig");

pub fn debug(value: anytype) void {
    std.debug.print("{s}", .{value});
}

comptime {
    std.testing.refAllDecls(bit);
}
