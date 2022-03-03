const std = @import("std");
const build_options = @import("build_options");

const protocol = @import("../common/protocol.zig");

const trace = build_options.trace;

pub const Activate = protocol.Activate;
pub const ArgType = protocol.ArgType;
pub const Cant = protocol.Cant;
pub const End = protocol.End;
pub const Start = protocol.Start;
pub const expectTrace = protocol.expectTrace;

// FIXME
pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn cant(self: *Self, ident: u8, reason: Cant) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Cant), ident, @enumToInt(reason) });
        }

        pub fn disabled(self: *Self, ident: u8, mslot: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Cant),
                ident,
                @enumToInt(Cant.Disable),
                mslot,
            });
        }

        pub fn activate(self: *Self, ident: u8, reason: Activate) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Activate),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn start(self: *Self, ident: u8, reason: Start, silent: bool) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(reason),
                @boolToInt(silent),
            });
        }

        pub fn end(self: *Self, ident: u8, reason: End) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.End), ident, @enumToInt(reason) });
        }

        pub fn fail(self: *Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Fail), ident });
        }

        pub fn switched(self: *Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Switch), ident });
        }

        pub fn turn(self: *Self, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Turn), num });
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
