const std = @import("std");

pub fn print(value: anytype) void {
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeByte('\n') catch return;
    nosuspend std.fmt.formatType(value, "any", .{}, stderr, 10) catch return;
}
