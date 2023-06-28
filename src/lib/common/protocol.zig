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
};

pub const Move = enum(u8) {
    None,
    From,
};

pub const Cant = enum(u8) {
    Sleep,
    Freeze,
    Paralysis,
    Bound,
    Flinch,
    Disable,
    Recharge,
    PP,
};

pub const Heal = enum(u8) {
    None,
    Silent,
    Drain,
};

pub const Damage = enum(u8) {
    None,
    Poison,
    Burn,
    Confusion,
    LeechSeed,
    RecoilOf,
};

pub const Status = enum(u8) {
    None,
    Silent,
    From,
};

pub const CureStatus = enum(u8) {
    Message,
    Silent,
};

pub const Boost = enum(u8) {
    Rage,
    Attack,
    Defense,
    Speed,
    SpecialAttack,
    SpecialDefense,
    Accuracy,
    Evasion,
};

pub const Fail = enum(u8) {
    None,
    Sleep,
    Poison,
    Burn,
    Freeze,
    Paralysis,
    Toxic,
    Substitute,
    Weak,
};

pub const Activate = enum(u8) {
    Bide,
    Confusion,
    Haze,
    Mist,
    Struggle,
    Substitute,
    Splash,
};

pub const Start = enum(u8) {
    Bide,
    Confusion,
    ConfusionSilent,
    FocusEnergy,
    LeechSeed,
    LightScreen,
    Mist,
    Reflect,
    Substitute,

    TypeChange,

    Disable,
    Mimic,
};

pub const End = enum(u8) {
    Disable,
    Confusion,
    Bide,
    Substitute,

    // Silent
    DisableSilent,
    ConfusionSilent,

    Mist,
    FocusEnergy,
    LeechSeed,
    Toxic,
    LightScreen,
    Reflect,
};

pub const Immune = enum(u8) {
    None,
    OHKO,
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

        pub fn move(self: Self, source: ID, m: anytype, target: ID, from: anytype) Error!void {
            if (!enabled) return;

            assert(m != .None);
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Move),
                @as(u8, @bitCast(source)),
                @intFromEnum(m),
                @as(u8, @bitCast(target)),
            });
            const none = &[_]u8{@intFromEnum(Move.None)};
            try self.writer.writeAll(switch (@typeInfo(@TypeOf(from))) {
                .Null => none,
                .Optional => if (from) |f| blk: {
                    assert(@intFromEnum(f) != 0);
                    break :blk &[_]u8{ @intFromEnum(Move.From), @intFromEnum(f) };
                } else none,
                else => blk: {
                    assert(@intFromEnum(from) != 0);
                    break :blk &[_]u8{ @intFromEnum(Move.From), @intFromEnum(from) };
                },
            });
        }

        pub fn switched(self: Self, ident: ID, pokemon: anytype) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Switch), @as(u8, @bitCast(ident)) });
            try self.writer.writeAll(&.{ @intFromEnum(pokemon.species), pokemon.level });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{pokemon.status});
        }

        pub fn cant(self: Self, ident: ID, reason: Cant) Error!void {
            if (!enabled) return;

            assert(reason != .Disable);
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Cant),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
            });
        }

        pub fn disabled(self: Self, ident: ID, m: anytype) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Cant),
                @as(u8, @bitCast(ident)),
                @intFromEnum(Cant.Disable),
                @intFromEnum(m),
            });
        }

        pub fn faint(self: Self, ident: ID, done: bool) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Faint), @as(u8, @bitCast(ident)) });
            if (done) try self.writer.writeByte(@intFromEnum(ArgType.None));
        }

        pub fn turn(self: Self, num: u16) Error!void {
            if (!enabled) return;

            try self.writer.writeByte(@intFromEnum(ArgType.Turn));
            try self.writer.writeIntNative(u16, num);
            try self.writer.writeByte(@intFromEnum(ArgType.None));
        }

        pub fn win(self: Self, player: Player) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Win),
                @intFromEnum(player),
                @intFromEnum(ArgType.None),
            });
        }

        pub fn tie(self: Self) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Tie), @intFromEnum(ArgType.None) });
        }

        pub fn damage(self: Self, ident: ID, pokemon: anytype, reason: Damage) Error!void {
            if (!enabled) return;

            assert(@intFromEnum(reason) <= @intFromEnum(Damage.LeechSeed));
            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Damage), @as(u8, @bitCast(ident)) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{ pokemon.status, @intFromEnum(reason) });
        }

        pub fn damageOf(
            self: Self,
            ident: ID,
            pokemon: anytype,
            reason: Damage,
            source: ID,
        ) Error!void {
            if (!enabled) return;

            assert(@intFromEnum(reason) == @intFromEnum(Damage.RecoilOf));
            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Damage), @as(u8, @bitCast(ident)) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{
                pokemon.status,
                @intFromEnum(reason),
                @as(u8, @bitCast(source)),
            });
        }

        pub fn heal(self: Self, ident: ID, pokemon: anytype, reason: Heal) Error!void {
            if (!enabled) return;

            assert(reason != .Drain);
            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Heal), @as(u8, @bitCast(ident)) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{ pokemon.status, @intFromEnum(reason) });
        }

        pub fn drain(self: Self, source: ID, pokemon: anytype, target: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Heal), @as(u8, @bitCast(source)) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{
                pokemon.status,
                @intFromEnum(Heal.Drain),
                @as(u8, @bitCast(target)),
            });
        }

        pub fn status(self: Self, ident: ID, value: u8, reason: Status) Error!void {
            if (!enabled) return;

            assert(reason != .From);
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Status),
                @as(u8, @bitCast(ident)),
                value,
                @intFromEnum(reason),
            });
        }

        pub fn statusFrom(self: Self, ident: ID, value: u8, m: anytype) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Status),
                @as(u8, @bitCast(ident)),
                value,
                @intFromEnum(Status.From),
                @intFromEnum(m),
            });
        }

        pub fn curestatus(self: Self, ident: ID, value: u8, reason: CureStatus) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.CureStatus),
                @as(u8, @bitCast(ident)),
                value,
                @intFromEnum(reason),
            });
        }

        pub fn boost(self: Self, ident: ID, reason: Boost, num: i8) Error!void {
            if (!enabled) return;

            assert(num != 0 and (reason != .Rage or num > 0));
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Boost),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
                @as(u8, @intCast(num + 6)),
            });
        }

        pub fn clearallboost(self: Self) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{@intFromEnum(ArgType.ClearAllBoost)});
        }

        pub fn fail(self: Self, ident: ID, reason: Fail) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Fail),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
            });
        }

        pub fn miss(self: Self, source: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Miss), @as(u8, @bitCast(source)) });
        }

        pub fn hitcount(self: Self, ident: ID, num: u8) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.HitCount),
                @as(u8, @bitCast(ident)),
                num,
            });
        }

        pub fn prepare(self: Self, source: ID, m: anytype) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Prepare),
                @as(u8, @bitCast(source)),
                @intFromEnum(m),
            });
        }

        pub fn mustrecharge(self: Self, ident: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.MustRecharge),
                @as(u8, @bitCast(ident)),
            });
        }

        pub fn activate(self: Self, ident: ID, reason: Activate) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Activate),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
            });
        }

        pub fn fieldactivate(self: Self) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{@intFromEnum(ArgType.FieldActivate)});
        }

        pub fn start(self: Self, ident: ID, reason: Start) Error!void {
            if (!enabled) return;

            assert(@intFromEnum(reason) < @intFromEnum(Start.TypeChange));
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Start),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
            });
        }

        pub fn typechange(self: Self, source: ID, types: anytype, target: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Start),
                @as(u8, @bitCast(source)),
                @intFromEnum(Start.TypeChange),
                @as(u8, @bitCast(types)),
                @as(u8, @bitCast(target)),
            });
        }

        pub fn startEffect(self: Self, ident: ID, reason: Start, m: anytype) Error!void {
            if (!enabled) return;

            assert(@intFromEnum(reason) > @intFromEnum(Start.TypeChange));
            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Start),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
                @intFromEnum(m),
            });
        }

        pub fn end(self: Self, ident: ID, reason: End) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.End),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
            });
        }

        pub fn ohko(self: Self) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{@intFromEnum(ArgType.OHKO)});
        }

        pub fn crit(self: Self, ident: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{ @intFromEnum(ArgType.Crit), @as(u8, @bitCast(ident)) });
        }

        pub fn supereffective(self: Self, ident: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.SuperEffective),
                @as(u8, @bitCast(ident)),
            });
        }

        pub fn resisted(self: Self, ident: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Resisted),
                @as(u8, @bitCast(ident)),
            });
        }

        pub fn immune(self: Self, ident: ID, reason: Immune) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Immune),
                @as(u8, @bitCast(ident)),
                @intFromEnum(reason),
            });
        }

        pub fn transform(self: Self, source: ID, target: ID) Error!void {
            if (!enabled) return;

            try self.writer.writeAll(&.{
                @intFromEnum(ArgType.Transform),
                @as(u8, @bitCast(source)),
                @as(u8, @bitCast(target)),
            });
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

pub const Kind = enum { Move, Species, Type, Status };
pub const Formatter = fn (Kind, u8) []const u8;

pub fn format(comptime formatter: Formatter, a: []const u8, b: ?[]const u8, color: bool) void {
    print("\n", .{});

    var i: usize = 0;
    while (i < a.len) {
        const arg: ArgType = @enumFromInt(a[i]);
        const name = switch (arg) {
            .None => if (color) "\x1b[2m-\x1b[0m" else "-",
            .LastStill => "|[still]",
            .LastMiss => "|[miss]",
            .Move => "|move|",
            .Switch => "|switch|",
            .Cant => "|cant|",
            .Faint => "|faint|",
            .Turn => "|turn|",
            .Win => "|win|",
            .Tie => "|tie|",
            .Damage => "|-damage|",
            .Heal => "|-heal|",
            .Status => "|-status|",
            .CureStatus => "|-curestatus|",
            .Boost => "|-boost|",
            .ClearAllBoost => "|-clearallboost|",
            .Fail => "|-fail|",
            .Miss => "|-miss|",
            .HitCount => "|-hitcount|",
            .Prepare => "|-prepare|",
            .MustRecharge => "|-mustrecharge|",
            .Activate => "|-activate|",
            .FieldActivate => "|-fieldactivate|",
            .Start => "|-start|",
            .End => "|-end|",
            .OHKO => "|-ohko|",
            .Crit => "|-crit|",
            .SuperEffective => "|-supereffective|",
            .Resisted => "|-resisted|",
            .Immune => "|-immune|",
            .Transform => "|-transform|",
            else => unreachable,
        };
        printc("{s}", .{name}, a, b, &i, 1, color);
        switch (arg) {
            .None,
            .LastStill,
            .LastMiss,
            .Tie,
            .ClearAllBoost,
            .FieldActivate,
            .OHKO,
            => {},
            .Move => {
                const source = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(source.player), source.id }, a, b, &i, 1, color);
                printc(" {s}", .{formatter(.Move, a[i])}, a, b, &i, 1, color);
                const target = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(target.player), target.id }, a, b, &i, 1, color);
                const reason: Move = @enumFromInt(a[i]);
                printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
                if (reason == .From) printc(" {s}", .{formatter(.Move, a[i])}, a, b, &i, 1, color);
            },
            .Switch => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{formatter(.Species, a[i])}, a, b, &i, 1, color);
                printc(" L{d}", .{a[i]}, a, b, &i, 1, color);
                switch (endian) {
                    .Big => {
                        var hp = @as(u16, a[i]) << 8 | @as(u16, a[i + 1]);
                        printc(" {d}", .{hp}, a, b, &i, 2, color);
                        hp = @as(u16, a[i]) << 8 | @as(u16, a[i + 1]);
                        printc("/{d}", .{hp}, a, b, &i, 2, color);
                    },
                    .Little => {
                        var hp = @as(u16, a[i + 1]) << 8 | @as(u16, a[i]);
                        printc(" {d}", .{hp}, a, b, &i, 2, color);
                        hp = @as(u16, a[i + 1]) << 8 | @as(u16, a[i]);
                        printc("/{d}", .{hp}, a, b, &i, 2, color);
                    },
                }
                printc(" {s}", .{formatter(.Status, a[i])}, a, b, &i, 1, color);
            },
            .Cant => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                const reason: Cant = @enumFromInt(a[i]);
                printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
                if (reason == .Disable) {
                    printc(" {s}", .{formatter(.Move, a[i])}, a, b, &i, 1, color);
                }
            },
            .Faint,
            .Miss,
            .MustRecharge,
            .Crit,
            .SuperEffective,
            .Resisted,
            => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
            },
            .Turn => {
                const turn = switch (endian) {
                    .Big => @as(u16, a[i]) << 8 | @as(u16, a[i + 1]),
                    .Little => @as(u16, a[i + 1]) << 8 | @as(u16, a[i]),
                };
                printc(" {d}", .{turn}, a, b, &i, 2, color);
            },
            .Win => {
                printc(" {s}", .{@tagName(@as(Player, @enumFromInt(a[i])))}, a, b, &i, 1, color);
            },
            .Damage, .Heal => {
                var id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                switch (endian) {
                    .Big => {
                        var hp = @as(u16, a[i]) << 8 | @as(u16, a[i + 1]);
                        printc(" {d}", .{hp}, a, b, &i, 2, color);
                        hp = @as(u16, a[i]) << 8 | @as(u16, a[i + 1]);
                        printc("/{d}", .{hp}, a, b, &i, 2, color);
                    },
                    .Little => {
                        var hp = @as(u16, a[i + 1]) << 8 | @as(u16, a[i]);
                        printc(" {d}", .{hp}, a, b, &i, 2, color);
                        hp = @as(u16, a[i + 1]) << 8 | @as(u16, a[i]);
                        printc("/{d}", .{hp}, a, b, &i, 2, color);
                    },
                }
                printc(" {s}", .{formatter(.Status, a[i])}, a, b, &i, 1, color);
                if (arg == .Damage) {
                    const reason: Damage = @enumFromInt(a[i]);
                    printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
                    if (reason == .RecoilOf) {
                        id = ID.from(@intCast(a[i]));
                        printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                    }
                } else {
                    const reason: Heal = @enumFromInt(a[i]);
                    printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
                    if (reason == .Drain) {
                        id = ID.from(@intCast(a[i]));
                        printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                    }
                }
            },
            .Status => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{formatter(.Status, a[i])}, a, b, &i, 1, color);
                const reason: Status = @enumFromInt(a[i]);
                printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
                if (reason == .From) printc(" {s}", .{formatter(.Move, a[i])}, a, b, &i, 1, color);
            },
            .CureStatus => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{formatter(.Status, a[i])}, a, b, &i, 1, color);
                const reason: CureStatus = @enumFromInt(a[i]);
                printc(" {s}", .{@tagName(reason)}, a, b, &i, 1, color);
            },
            .Boost => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{@tagName(@as(Boost, @enumFromInt(a[i])))}, a, b, &i, 1, color);
                printc(" {d}", .{a[i]}, a, b, &i, 1, color);
            },
            .Fail => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{@tagName(@as(Fail, @enumFromInt(a[i])))}, a, b, &i, 1, color);
            },
            .HitCount => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {d}", .{a[i]}, a, b, &i, 1, color);
            },
            .Prepare => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{formatter(.Move, a[i])}, a, b, &i, 1, color);
            },
            .Activate => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{@tagName(@as(Activate, @enumFromInt(a[i])))}, a, b, &i, 1, color);
            },
            .Start => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                const reason = a[i];
                printc(" {s}", .{@tagName(@as(Start, @enumFromInt(reason)))}, a, b, &i, 1, color);
                if (@as(Start, @enumFromInt(reason)) == .TypeChange) {
                    const types = @as(gen1.Types, @bitCast(a[i]));
                    const args = .{
                        formatter(.Type, @intFromEnum(types.type1)),
                        formatter(.Type, @intFromEnum(types.type2)),
                    };
                    printc(" {s}/{s}", args, a, b, &i, 1, color);
                } else if (reason >= @intFromEnum(Start.Disable)) {
                    printc(" {s}", .{formatter(.Move, a[i])}, a, b, &i, 1, color);
                }
            },
            .End => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{@tagName(@as(End, @enumFromInt(a[i])))}, a, b, &i, 1, color);
            },
            .Immune => {
                const id = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(id.player), id.id }, a, b, &i, 1, color);
                printc(" {s}", .{@tagName(@as(Immune, @enumFromInt(a[i])))}, a, b, &i, 1, color);
            },
            .Transform => {
                const source = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(source.player), source.id }, a, b, &i, 1, color);
                const target = ID.from(@intCast(a[i]));
                printc(" {s}({d})", .{ @tagName(target.player), target.id }, a, b, &i, 1, color);
            },
            else => unreachable,
        }
        print("\n", .{});
    }

    print("\n", .{});
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
    comptime formatter: Formatter,
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
            format(formatter, expected, null, color);
            format(formatter, actual, expected, color);
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

var buf: [gen1.LOGS_SIZE]u8 = undefined;
var stream = ByteStream{ .buffer = &buf };
var log: FixedLog = .{ .writer = stream.writer() };

const M = gen1.Move;
const S = gen1.Species;

fn expectLog1(expected: []const u8, actual: []const u8) !void {
    return expectLog(gen1Formatter, expected, actual, 0);
}

fn gen1Formatter(kind: Kind, byte: u8) []const u8 {
    return switch (kind) {
        .Move => @tagName(@as(M, @enumFromInt(byte))),
        .Species => @tagName(@as(S, @enumFromInt(byte))),
        .Type => @tagName(@as(gen1.Type, @enumFromInt(byte))),
        .Status => gen1.Status.name(byte),
    };
}

test "|move|" {
    try log.move(p2.ident(4), M.Thunderbolt, p1.ident(5), null);
    try expectLog1(
        &.{ N(ArgType.Move), 0b1100, N(M.Thunderbolt), 0b0101, N(Move.None) },
        buf[0..5],
    );
    stream.reset();

    try log.move(p2.ident(4), M.Wrap, p1.ident(5), M.Wrap);
    const wrap = N(M.Wrap);
    try expectLog1(
        &.{ N(ArgType.Move), 0b1100, wrap, 0b0101, N(Move.From), wrap },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), M.SkullBash, .{}, null);
    try log.laststill();
    try expectLog1(
        &.{
            N(ArgType.Move),
            0b1100,
            N(M.SkullBash),
            0,
            N(Move.None),
            N(ArgType.LastStill),
        },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), M.Tackle, p1.ident(5), null);
    try log.lastmiss();
    try expectLog1(
        &.{
            N(ArgType.Move),
            0b1100,
            N(M.Tackle),
            0b0101,
            N(Move.None),
            N(ArgType.LastMiss),
        },
        buf[0..6],
    );
    stream.reset();
}

test "|switch|" {
    var snorlax = gen1.helpers.Pokemon.init(.{ .species = .Snorlax, .moves = &.{.Splash} });
    snorlax.level = 91;
    snorlax.hp = 200;
    snorlax.stats.hp = 400;
    snorlax.status = gen1.Status.init(.PAR);
    try log.switched(p2.ident(3), &snorlax);
    const par = 0b1000000;
    var expected: []const u8 = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 91, 0, 200, 1, 144, par },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 91, 200, 0, 144, 1, par },
    };
    try expectLog1(expected, buf[0..9]);
    stream.reset();

    snorlax.level = 100;
    snorlax.hp = 0;
    snorlax.status = 0;
    try log.switched(p2.ident(3), &snorlax);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 0, 0, 1, 144, 0 },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 0, 0, 144, 1, 0 },
    };
    try expectLog1(expected, buf[0..9]);
    stream.reset();

    snorlax.hp = 400;
    try log.switched(p2.ident(3), &snorlax);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 1, 144, 1, 144, 0 },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 144, 1, 144, 1, 0 },
    };
    try expectLog1(expected, buf[0..9]);
    stream.reset();
}

test "|cant|" {
    try log.cant(p2.ident(6), .Bound);
    try expectLog1(&.{ N(ArgType.Cant), 0b1110, N(Cant.Bound) }, buf[0..3]);
    stream.reset();

    try log.disabled(p1.ident(2), M.Earthquake);
    try expectLog1(&.{ N(ArgType.Cant), 2, N(Cant.Disable), N(M.Earthquake) }, buf[0..4]);
    stream.reset();
}

test "|faint|" {
    try log.faint(p2.ident(2), false);
    try expectLog1(&.{ N(ArgType.Faint), 0b1010 }, buf[0..2]);
    stream.reset();

    try log.faint(p2.ident(2), true);
    try expectLog1(&.{ N(ArgType.Faint), 0b1010, N(ArgType.None) }, buf[0..3]);
    stream.reset();
}

test "|turn|" {
    try log.turn(42);
    var expected = switch (endian) {
        .Big => &.{ N(ArgType.Turn), 0, 42, N(ArgType.None) },
        .Little => &.{ N(ArgType.Turn), 42, 0, N(ArgType.None) },
    };
    try expectLog1(expected, buf[0..4]);
    stream.reset();
}

test "|win|" {
    try log.win(.P2);
    try expectLog1(&.{ N(ArgType.Win), 1, N(ArgType.None) }, buf[0..3]);
    stream.reset();
}

test "|tie|" {
    try log.tie();
    try expectLog1(&.{ N(ArgType.Tie), N(ArgType.None) }, buf[0..2]);
    stream.reset();
}

test "|-damage|" {
    var chansey = gen1.helpers.Pokemon.init(.{ .species = .Chansey, .moves = &.{.Splash} });
    chansey.hp = 612;
    chansey.status = gen1.Status.slp(1);
    try log.damage(p2.ident(2), &chansey, .None);
    var expected: []const u8 = switch (endian) {
        .Big => &.{ N(ArgType.Damage), 0b1010, 2, 100, 2, 191, 1, N(Damage.None) },
        .Little => &.{ N(ArgType.Damage), 0b1010, 100, 2, 191, 2, 1, N(Damage.None) },
    };
    try expectLog1(expected, buf[0..8]);
    stream.reset();

    chansey.hp = 100;
    chansey.stats.hp = 256;
    chansey.status = 0;
    try log.damage(p2.ident(2), &chansey, .Confusion);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Damage), 0b1010, 0, 100, 1, 0, 0, N(Damage.Confusion) },
        .Little => &.{ N(ArgType.Damage), 0b1010, 100, 0, 0, 1, 0, N(Damage.Confusion) },
    };
    try expectLog1(expected, buf[0..8]);
    stream.reset();

    chansey.status = gen1.Status.init(.PSN);
    try log.damageOf(p2.ident(2), &chansey, .RecoilOf, p1.ident(1));
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Damage), 0b1010, 0, 100, 1, 0, 0b1000, N(Damage.RecoilOf), 1 },
        .Little => &.{ N(ArgType.Damage), 0b1010, 100, 0, 0, 1, 0b1000, N(Damage.RecoilOf), 1 },
    };
    try expectLog1(expected, buf[0..9]);
    stream.reset();
}

test "|-heal|" {
    var chansey = gen1.helpers.Pokemon.init(.{ .species = .Chansey, .moves = &.{.Splash} });
    chansey.hp = 612;
    chansey.status = gen1.Status.slp(1);
    try log.heal(p2.ident(2), &chansey, .None);
    var expected: []const u8 = switch (endian) {
        .Big => &.{ N(ArgType.Heal), 0b1010, 2, 100, 2, 191, 1, N(Heal.None) },
        .Little => &.{ N(ArgType.Heal), 0b1010, 100, 2, 191, 2, 1, N(Heal.None) },
    };
    try expectLog1(expected, buf[0..8]);
    stream.reset();

    chansey.hp = 100;
    chansey.stats.hp = 256;
    chansey.status = 0;
    try log.heal(p2.ident(2), &chansey, .Silent);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Heal), 0b1010, 0, 100, 1, 0, 0, N(Heal.Silent) },
        .Little => &.{ N(ArgType.Heal), 0b1010, 100, 0, 0, 1, 0, N(Heal.Silent) },
    };
    try expectLog1(expected, buf[0..8]);
    stream.reset();

    try log.drain(p2.ident(2), &chansey, p1.ident(1));
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Heal), 0b1010, 0, 100, 1, 0, 0, N(Heal.Drain), 1 },
        .Little => &.{ N(ArgType.Heal), 0b1010, 100, 0, 0, 1, 0, N(Heal.Drain), 1 },
    };
    try expectLog1(expected, buf[0..9]);
    stream.reset();
}

test "|-status|" {
    try log.status(p2.ident(6), gen1.Status.init(.BRN), .None);
    try expectLog1(&.{ N(ArgType.Status), 0b1110, 0b10000, N(Status.None) }, buf[0..4]);
    stream.reset();

    try log.status(p2.ident(2), gen1.Status.init(.PSN), .Silent);
    try expectLog1(&.{ N(ArgType.Status), 0b1010, 0b1000, N(Status.Silent) }, buf[0..4]);
    stream.reset();

    try log.statusFrom(p1.ident(1), gen1.Status.init(.PAR), M.BodySlam);
    try expectLog1(
        &.{ N(ArgType.Status), 0b0001, 0b1000000, N(Status.From), N(M.BodySlam) },
        buf[0..5],
    );
    stream.reset();
}

test "|-curestatus|" {
    try log.curestatus(p2.ident(6), gen1.Status.slp(7), .Message);
    try expectLog1(&.{ N(ArgType.CureStatus), 0b1110, 0b111, N(CureStatus.Message) }, buf[0..4]);
    stream.reset();

    try log.curestatus(p1.ident(2), gen1.Status.TOX, .Silent);
    try expectLog1(&.{
        N(ArgType.CureStatus),
        0b0010,
        0b10001000,
        N(CureStatus.Silent),
    }, buf[0..4]);
    stream.reset();
}

test "|-boost|" {
    try log.boost(p2.ident(6), .Speed, 2);
    try expectLog1(&.{ N(ArgType.Boost), 0b1110, N(Boost.Speed), 8 }, buf[0..4]);
    stream.reset();

    try log.boost(p1.ident(2), .Rage, 1);
    try expectLog1(&.{ N(ArgType.Boost), 0b0010, N(Boost.Rage), 7 }, buf[0..4]);
    stream.reset();

    try log.boost(p2.ident(3), .Defense, -2);
    try expectLog1(&.{ N(ArgType.Boost), 0b1011, N(Boost.Defense), 4 }, buf[0..4]);
    stream.reset();
}

test "|-clearallboost|" {
    try log.clearallboost();
    try expectLog1(&.{N(ArgType.ClearAllBoost)}, buf[0..1]);
    stream.reset();
}

test "|-fail|" {
    try log.fail(p2.ident(6), .None);
    try expectLog1(&.{ N(ArgType.Fail), 0b1110, N(Fail.None) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Sleep);
    try expectLog1(&.{ N(ArgType.Fail), 0b1110, N(Fail.Sleep) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Substitute);
    try expectLog1(&.{ N(ArgType.Fail), 0b1110, N(Fail.Substitute) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Weak);
    try expectLog1(&.{ N(ArgType.Fail), 0b1110, N(Fail.Weak) }, buf[0..3]);
    stream.reset();
}

test "|-miss|" {
    try log.miss(p2.ident(4));
    try expectLog1(&.{ N(ArgType.Miss), 0b1100 }, buf[0..2]);
    stream.reset();
}
test "|-hitcount|" {
    try log.hitcount(p2.ident(1), 5);
    try expectLog1(&.{ N(ArgType.HitCount), 0b1001, 5 }, buf[0..3]);
    stream.reset();
}

test "|-prepare|" {
    try log.prepare(p2.ident(2), M.Dig);
    try expectLog1(&.{ N(ArgType.Prepare), 0b1010, N(M.Dig) }, buf[0..3]);
    stream.reset();
}

test "|-mustrecharge|" {
    try log.mustrecharge(p1.ident(6));
    try expectLog1(&.{ N(ArgType.MustRecharge), 0b0110 }, buf[0..2]);
    stream.reset();
}

test "|-activate|" {
    try log.activate(p1.ident(2), .Struggle);
    try expectLog1(&.{ N(ArgType.Activate), 0b0010, N(Activate.Struggle) }, buf[0..3]);
    stream.reset();

    try log.activate(p2.ident(4), .Mist);
    try expectLog1(&.{ N(ArgType.Activate), 0b1100, N(Activate.Mist) }, buf[0..3]);
    stream.reset();

    try log.activate(p2.ident(6), .Substitute);
    try expectLog1(&.{ N(ArgType.Activate), 0b1110, N(Activate.Substitute) }, buf[0..3]);
    stream.reset();

    try log.activate(p1.ident(2), .Splash);
    try expectLog1(&.{ N(ArgType.Activate), 0b0010, N(Activate.Splash) }, buf[0..3]);
    stream.reset();
}

test "|-fieldactivate|" {
    try log.fieldactivate();
    try expectLog1(&.{N(ArgType.FieldActivate)}, buf[0..1]);
    stream.reset();
}

test "|-start|" {
    try log.start(p2.ident(6), .Bide);
    try expectLog1(&.{ N(ArgType.Start), 0b1110, N(Start.Bide) }, buf[0..3]);
    stream.reset();

    try log.start(p1.ident(2), .ConfusionSilent);
    try expectLog1(&.{ N(ArgType.Start), 0b0010, N(Start.ConfusionSilent) }, buf[0..3]);
    stream.reset();

    try log.typechange(p2.ident(6), gen1.Types{ .type1 = .Fire, .type2 = .Fire }, p2.ident(5));
    try expectLog1(
        &.{ N(ArgType.Start), 0b1110, N(Start.TypeChange), 0b1000_1000, 0b1101 },
        buf[0..5],
    );
    stream.reset();

    try log.typechange(p1.ident(2), gen1.Types{ .type1 = .Bug, .type2 = .Poison }, p2.ident(4));
    try expectLog1(
        &.{ N(ArgType.Start), 0b0010, N(Start.TypeChange), 0b0011_0110, 0b1100 },
        buf[0..5],
    );
    stream.reset();

    try log.startEffect(p1.ident(2), .Disable, M.Surf);
    try expectLog1(&.{ N(ArgType.Start), 0b0010, N(Start.Disable), N(M.Surf) }, buf[0..4]);
    stream.reset();

    try log.startEffect(p1.ident(2), .Mimic, M.Surf);
    try expectLog1(&.{ N(ArgType.Start), 0b0010, N(Start.Mimic), N(M.Surf) }, buf[0..4]);
    stream.reset();
}

test "|-end|" {
    try log.end(p2.ident(6), .Bide);
    try expectLog1(&.{ N(ArgType.End), 0b1110, N(End.Bide) }, buf[0..3]);
    stream.reset();

    try log.end(p1.ident(2), .ConfusionSilent);
    try expectLog1(&.{ N(ArgType.End), 0b0010, N(End.ConfusionSilent) }, buf[0..3]);
    stream.reset();
}

test "|-ohko|" {
    try log.ohko();
    try expectLog1(&.{N(ArgType.OHKO)}, buf[0..1]);
    stream.reset();
}
test "|-crit|" {
    try log.crit(p2.ident(5));
    try expectLog1(&.{ N(ArgType.Crit), 0b1101 }, buf[0..2]);
    stream.reset();
}
test "|-supereffective|" {
    try log.supereffective(p1.ident(1));
    try expectLog1(&.{ N(ArgType.SuperEffective), 0b0001 }, buf[0..2]);
    stream.reset();
}
test "|-resisted|" {
    try log.resisted(p2.ident(2));
    try expectLog1(&.{ N(ArgType.Resisted), 0b1010 }, buf[0..2]);
    stream.reset();
}
test "|-immune|" {
    try log.immune(p1.ident(3), .None);
    try expectLog1(&.{ N(ArgType.Immune), 0b0011, N(Immune.None) }, buf[0..3]);
    stream.reset();

    try log.immune(p2.ident(2), .OHKO);
    try expectLog1(&.{ N(ArgType.Immune), 0b1010, N(Immune.OHKO) }, buf[0..3]);
    stream.reset();
}
test "|-transform|" {
    try log.transform(p2.ident(4), p1.ident(5));
    try expectLog1(&.{ N(ArgType.Transform), 0b1100, 0b0101 }, buf[0..3]);
    stream.reset();
}
