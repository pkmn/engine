const std = @import("std");
const build_options = @import("build_options");

const protocol = @import("../common/protocol.zig");

const trace = build_options.trace;

pub const ArgType = protocol.ArgType;
pub const Cant = protocol.Cant;

pub const expectTrace = protocol.expectTrace;

pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn cant(self: *Self, slot: u8, reason: Cant) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Cant), slot, @enumToInt(reason) });
        }
    };
}

test "Log" {
    var buf = [_]u8{0} ** 3;
    var log: Log(std.io.FixedBufferStream([]u8).Writer) = .{
        .writer = std.io.fixedBufferStream(&buf).writer(),
    };

    try log.cant(1, .PartialTrap);

    try expectTrace(
        &[_]u8{ @enumToInt(ArgType.Cant), 1, @enumToInt(Cant.PartialTrap) },
        &buf,
    );
}
