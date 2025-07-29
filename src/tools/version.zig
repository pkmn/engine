const builtin = @import("builtin");
const std = @import("std");

const writergate = @hasDecl(std.fs.File, "stdout");

pub fn main() !void {
    const version = try std.SemanticVersion.parse("0.14.0");
    const modern = builtin.zig_version.order(version) != .lt;
    var stdout = if (writergate) std.fs.File.stdout().writer(&.{}) else std.io.getStdOut();
    var writer = if (writergate) &stdout.interface else stdout.writer();
    try writer.writeAll(if (modern) "modern" else "legacy");
}
