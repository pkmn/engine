const std = @import("std");
const build_options = @import("build_options");

const protocol = @import("../common/protocol.zig");

const trace = build_options.trace;

pub const ArgType = protocol.ArgType;
pub const Activate = protocol.Activate;
pub const Cant = protocol.Cant;
pub const Start = protocol.Start;
pub const End = protocol.End;

pub const expectTrace = protocol.expectTrace;

pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn cant(self: *Self, slot: u8, reason: Cant) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Cant), slot, @enumToInt(reason) });
        }

        pub fn disabled(self: *Self, slot: u8, mslot: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Cant),
                slot,
                @enumToInt(Cant.Disable),
                mslot,
            });
        }

        pub fn activate(self: *Self, slot: u8, reason: Activate) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Activate),
                slot,
                @enumToInt(reason),
            });
        }

        pub fn start(self: *Self, slot: u8, reason: Start, silent: bool) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                slot,
                @enumToInt(reason),
                @boolToInt(silent),
            });
        }

        pub fn end(self: *Self, slot: u8, reason: End) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.End), slot, @enumToInt(reason) });
        }

        pub fn fail(self: *Self, slot: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Fail), slot });
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
