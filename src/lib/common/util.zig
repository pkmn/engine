//! Index of common utilities.

const std = @import("std");

pub const bit = @import("./util/bit.zig");
pub const layout = @import("./util/layout.zig");

pub fn debug(value: anytype) void {
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeByte('\n') catch return;
    nosuspend std.fmt.formatType(value, "any", .{}, stderr, 10) catch return;
}

// https://en.wikipedia.org/wiki/ANSI_escape_code
pub const Escapes = struct {
    pub const Green = "\x1b[32m";
    pub const Yellow = "\x1b[33m";
    pub const Bold = "\x1b[1m";
    pub const Dim = "\x1b[2m";
    pub const Reset = "\x1b[0m";
};

comptime {
    std.testing.refAllDecls(bit);
}
