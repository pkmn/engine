const std = @import("std");
const builtin = @import("builtin");

const data = @import("./data.zig");
const options = @import("./options.zig");

const assert = std.debug.assert;
const print = std.debug.print;

const enabled = options.log;

const Player = data.Player;
const ID = data.ID;

pub const ArgType = enum(u8) {
    None,

    // Special
    LastStill,
    LastMiss,

    // Gen 1
    Move,
    Switch,
    Cant,
    Faint,
    Turn,
    Win,
    Tie,
    Damage,
    Heal,
    Status,
    CureStatus,
    Boost,
    ClearAllBoost,
    Fail,
    Miss,
    HitCount,
    Prepare,
    MustRecharge,
    Activate,
    FieldActivate,
    Start,
    End,
    OHKO,
    Crit,
    SuperEffective,
    Resisted,
    Immune,
    Transform,

    // Gen 2
    Drag,
    Item,
    EndItem,
    CureTeam,
    SetHP,
    SetBoost,
    CopyBoost,
    SideStart,
    SideEnd,
    SingleMove,
    SingleTurn,
    Weather,

    // Gen 3
    Block,
    Ability,
    EndAbility,
    ClearNegativeBoost,
    FormeChange,
    NoTarget,

    // Gen 4
    SwapBoost,
    FieldStart,
    FieldEnd,
    DetailsChange,

    // Gen 5
    ClearPoke,
    Poke,
    TeamPreview,
    Center,
    Swap,
    Combine,
    Waiting,
    Replace,
    ClearBoost,

    // Gen 6
    Mega,
    Primal,
    InvertBoost,

    // Gen 7
    ZBroken,
    ZPower,
    Burst,
    ClearPositiveBoost,

    // Gen 8
    CanDynamax,
    SwapSideConditions,

    // Gen 9
    Terastallize,
};

pub const Move = enum(u8) {
    None,
    From,
};

/// Null object pattern implementation of `Log` backed by a `std.io.null_writer`.
/// Ignores anything sent to it, though protocol logging should additionally be turned off
/// entirely with `options.log`.
pub const NULL = Log(@TypeOf(std.io.null_writer)){ .writer = std.io.null_writer };

/// Logs protocol information to its `Writer` during a battle update when `options.log` is enabled.
pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub const Error = Writer.Error;

        pub fn move(self: Self, source: ID, m: anytype, target: ID) Error!void {
            if (!enabled) return;

            assert(m != .None);
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Move),
                @as(u8, @bitCast(source)),
                @intFromEnum(m),
                @as(u8, @bitCast(target)),
                @intFromEnum(Move.None),
            });
        }

        pub fn moveFrom(self: Self, source: ID, m: anytype, target: ID, from: anytype) Error!void {
            if (!enabled) return;

            assert(m != .None);
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Move),
                @as(u8, @bitCast(source)),
                @intFromEnum(m),
                @as(u8, @bitCast(target)),
            });
            try self.writer.writeAll(if (@intFromEnum(from) == 0)
                &.{@intFromEnum(Move.None)}
            else
                &.{ @intFromEnum(Move.From), @intFromEnum(from) });
        }

        pub fn laststill(self: Self) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{@intFromEnum(ArgType.LastStill)});
        }

        pub fn lastmiss(self: Self) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{@intFromEnum(ArgType.LastMiss)});
        }
    };
}

/// `Log` type backed by the optimized `ByteStream.Writer`.
pub const FixedLog = Log(ByteStream.Writer);

/// Stripped down version of `std.io.FixedBufferStream` optimized for efficiently writing the
/// individual protocol bytes. Note that the `ByteStream.Writer` is **not** a `std.io.Writer` and
/// should not be used for general purpose writing.
pub const ByteStream = struct {
    buffer: []u8,
    pos: usize = 0,

    pub const Writer = struct {
        stream: *ByteStream,

        pub const Error = error{NoSpaceLeft};

        pub fn writeAll(self: Writer, bytes: []const u8) Error!void {
            for (bytes) |b| try self.writeByte(b);
        }

        pub fn writeByte(self: Writer, byte: u8) Error!void {
            try self.stream.writeByte(byte);
        }

        pub fn writeIntNative(self: Writer, comptime T: type, value: T) Error!void {
            // TODO: rework this to write directly to the buffer?
            var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
            std.mem.writeIntNative(T, &bytes, value);
            return self.writeAll(&bytes);
        }
    };

    pub fn writer(self: *ByteStream) Writer {
        return .{ .stream = self };
    }

    pub fn writeByte(self: *ByteStream, byte: u8) Writer.Error!void {
        if (self.pos >= self.buffer.len) return error.NoSpaceLeft;
        self.buffer[self.pos] = byte;
        self.pos += 1;
    }

    pub fn reset(self: *ByteStream) void {
        self.pos = 0;
    }
};

pub fn format(
    comptime gen: anytype,
    a: []const u8,
    b: ?[]const u8,
    color: bool,
) void {
    print("\n", .{});

    var i: usize = 0;
    while (i < a.len) {
        const arg: ArgType = @enumFromInt(a[i]);
        const name = switch (arg) {
            .None => if (color) "\x1b[2m-\x1b[0m" else "-",
            .LastStill => "|[still]",
            .LastMiss => "|[miss]",
            .Move => "|move|",
            else => unreachable,
        };
        printc("{s}", .{name}, a, b, &i, 1, color);
        switch (arg) {
            .None,
            .LastStill,
            .LastMiss,
            => {},
            .Move => {
                const source = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(source.player), source.id }, a, b, &i, 1, color);
                printc(" {s}", .{formatter(gen, .Move, a[i])}, a, b, &i, 1, color);
                const target = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(target.player), target.id }, a, b, &i, 1, color);
                const reason: Move = @enumFromInt(a[i]);
                printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
                if (reason == .From) {
                    printc(" {s}", .{formatter(gen, .Move, a[i])}, a, b, &i, 1, color);
                }
            },
            else => unreachable,
        }
        print("\n", .{});
    }

    print("\n", .{});
}

pub const Kind = enum { Move, Species, Type, Status, Item, Weather };

fn formatter(comptime gen: anytype, kind: Kind, byte: u8) []const u8 {
    return switch (kind) {
        .Move => @tagName(@as(gen.Move, @enumFromInt(byte))),
        .Species => @tagName(@as(gen.Species, @enumFromInt(byte))),
        .Type => @tagName(@as(gen.Type, @enumFromInt(byte))),
        .Status => gen.Status.name(byte),
        .Item => if (@hasDecl(gen, "Item"))
            @tagName(@as(gen.Item, @enumFromInt(byte)))
        else
            unreachable,
        .Weather => if (@hasDecl(gen, "Weather"))
            @tagName(@as(gen.Weather, @enumFromInt(byte)))
        else
            unreachable,
    };
}

fn printc(
    comptime fmt: []const u8,
    args: anytype,
    a: []const u8,
    b: ?[]const u8,
    i: *usize,
    n: usize,
    color: bool,
) void {
    const c = color and (if (b) |x| mismatch: {
        const end = i.* + n;
        if (end > a.len or end > x.len) break :mismatch true;
        var j: usize = i.*;
        while (j < end) : (j += 1) if (a[j] != x[j]) break :mismatch true;
        break :mismatch false;
    } else false);
    if (c) print("\x1b[31m", .{});
    print(fmt, args);
    if (c) print("\x1b[0m", .{});
    i.* += n;
}

pub fn expectLog(
    comptime gen: anytype,
    expected: []const u8,
    actual: []const u8,
    offset: usize,
) !void {
    if (!enabled) return;

    const color = color: {
        if (std.process.hasEnvVarConstant("ZIG_DEBUG_COLOR")) {
            break :color true;
        } else if (std.process.hasEnvVarConstant("NO_COLOR")) {
            break :color false;
        } else {
            break :color std.io.getStdErr().supportsAnsiEscapeCodes();
        }
    };

    expectEqualBytes(expected, actual, offset) catch |err| switch (err) {
        error.TestExpectedEqual => {
            format(gen, expected, null, color);
            format(gen, actual, expected, color);
            return err;
        },
        else => return err,
    };
}

fn expectEqualBytes(expected: []const u8, actual: []const u8, offset: usize) !void {
    for (offset..@min(expected.len, actual.len)) |i| {
        if (expected[i] != actual[i]) {
            print(
                "index {} incorrect. expected 0x{X:0>2}, found 0x{X:0>2}\n",
                .{ i, expected[i], actual[i] },
            );
            return error.TestExpectedEqual;
        }
    }
    if (expected.len != actual.len) {
        print(
            "slice lengths differ. expected {d}, found {d}\n",
            .{ expected.len, actual.len },
        );
        return error.TestExpectedEqual;
    }
}

const endian = builtin.target.cpu.arch.endian();

fn N(e: anytype) u8 {
    return @intFromEnum(e);
}

const p1 = Player.P1;
const p2 = Player.P2;

const gen1 = struct {
    pub usingnamespace @import("../gen1/data.zig");
    pub const helpers = @import("../gen1/helpers.zig");
};

const gen2 = struct {
    pub usingnamespace @import("../gen2/data.zig");
    pub const helpers = @import("../gen2/helpers.zig");
};

var buf: [gen1.LOGS_SIZE]u8 = undefined;
var stream: ByteStream = .{ .buffer = &buf };
var log: FixedLog = .{ .writer = stream.writer() };

const M1 = gen1.Move;
const S1 = gen1.Species;

const M2 = gen2.Move;
const S2 = gen2.Species;
const I2 = gen2.Item;
const W2 = gen2.Weather;

fn expectLog1(expected: []const u8, actual: []const u8) !void {
    return expectLog(gen1, expected, actual, 0);
}

fn expectLog2(expected: []const u8, actual: []const u8) !void {
    return expectLog(gen2, expected, actual, 0);
}

test "|move|" {
    try log.move(p2.ident(4), M1.Thunderbolt, p1.ident(5));
    try expectLog1(
        &.{ N(ArgType.Move), 0b1100, N(M1.Thunderbolt), 0b0101, N(Move.None) },
        buf[0..5],
    );
    stream.reset();

    try log.moveFrom(p2.ident(4), M1.Pound, p1.ident(5), M1.Metronome);
    try expectLog1(
        &.{ N(ArgType.Move), 0b1100, N(M1.Pound), 0b0101, N(Move.From), N(M1.Metronome) },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), M1.SkullBash, .{});
    try log.laststill();
    try expectLog1(
        &.{
            N(ArgType.Move),
            0b1100,
            N(M1.SkullBash),
            0,
            N(Move.None),
            N(ArgType.LastStill),
        },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), M1.Tackle, p1.ident(5));
    try log.lastmiss();
    try expectLog1(
        &.{
            N(ArgType.Move),
            0b1100,
            N(M1.Tackle),
            0b0101,
            N(Move.None),
            N(ArgType.LastMiss),
        },
        buf[0..6],
    );
    stream.reset();
}
