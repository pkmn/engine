const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const data = @import("../common/data.zig");

const assert = std.debug.assert;
const expectEqualSlices = std.testing.expectEqualSlices;

const trace = build_options.trace;

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
    Unboost,
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
    Trapped,
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
    PoisonOf,
    BurnOf,
    RecoilOf,
    LeechSeedOf,
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
    Confusion,
    Bide,
    Haze,
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

// BUG: PS Haze has silent bide,substitute,parspeeddrop,brnattackdrop
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

pub const NULL = Log(@TypeOf(std.io.null_writer)){ .writer = std.io.null_writer };

pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub const Error = Writer.Error;

        pub fn move(self: Self, source: ID, m: anytype, target: ID, from: anytype) Error!void {
            if (!trace) return;
            assert(m != .None);
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Move),
                @bitCast(u8, source),
                @enumToInt(m),
                @bitCast(u8, target),
            });
            const none = &[_]u8{@enumToInt(Move.None)};
            try self.writer.writeAll(switch (@typeInfo(@TypeOf(from))) {
                .Null => none,
                .Optional => if (from) |f| &[_]u8{ @enumToInt(Move.From), @enumToInt(f) } else none,
                else => &[_]u8{ @enumToInt(Move.From), @enumToInt(from) },
            });
        }

        pub fn switched(self: Self, ident: ID, pokemon: anytype) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Switch), @bitCast(u8, ident) });
            try self.writer.writeAll(&.{ @enumToInt(pokemon.species), pokemon.level });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{pokemon.status});
        }

        pub fn cant(self: Self, ident: ID, reason: Cant) Error!void {
            if (!trace) return;
            assert(reason != .Disable);
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Cant),
                @bitCast(u8, ident),
                @enumToInt(reason),
            });
        }

        pub fn disabled(self: Self, ident: ID, m: anytype) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Cant),
                @bitCast(u8, ident),
                @enumToInt(Cant.Disable),
                @enumToInt(m),
            });
        }

        pub fn faint(self: Self, ident: ID, done: bool) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Faint), @bitCast(u8, ident) });
            if (done) try self.writer.writeByte(@enumToInt(ArgType.None));
        }

        pub fn turn(self: Self, num: u16) Error!void {
            if (!trace) return;
            try self.writer.writeByte(@enumToInt(ArgType.Turn));
            try self.writer.writeIntNative(u16, num);
            try self.writer.writeByte(@enumToInt(ArgType.None));
        }

        pub fn win(self: Self, player: Player) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Win),
                @enumToInt(player),
                @enumToInt(ArgType.None),
            });
        }

        pub fn tie(self: Self) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Tie), @enumToInt(ArgType.None) });
        }

        pub fn damage(self: Self, ident: ID, pokemon: anytype, reason: Damage) Error!void {
            if (!trace) return;
            assert(@enumToInt(reason) <= @enumToInt(Damage.Confusion));
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Damage), @bitCast(u8, ident) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{ pokemon.status, @enumToInt(reason) });
        }

        pub fn damageOf(
            self: Self,
            ident: ID,
            pokemon: anytype,
            reason: Damage,
            source: ID,
        ) Error!void {
            if (!trace) return;
            assert(@enumToInt(reason) >= @enumToInt(Damage.PoisonOf));
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Damage), @bitCast(u8, ident) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{
                pokemon.status,
                @enumToInt(reason),
                @bitCast(u8, source),
            });
        }

        pub fn heal(self: Self, ident: ID, pokemon: anytype, reason: Heal) Error!void {
            if (!trace) return;
            assert(reason != .Drain);
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Heal), @bitCast(u8, ident) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{ pokemon.status, @enumToInt(reason) });
        }

        pub fn drain(self: Self, source: ID, pokemon: anytype, target: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Heal), @bitCast(u8, source) });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&.{
                pokemon.status,
                @enumToInt(Heal.Drain),
                @bitCast(u8, target),
            });
        }

        pub fn status(self: Self, ident: ID, value: u8, reason: Status) Error!void {
            if (!trace) return;
            assert(reason != .From);
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Status),
                @bitCast(u8, ident),
                value,
                @enumToInt(reason),
            });
        }

        pub fn statusFrom(self: Self, ident: ID, value: u8, m: anytype) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Status),
                @bitCast(u8, ident),
                value,
                @enumToInt(Status.From),
                @enumToInt(m),
            });
        }

        pub fn curestatus(self: Self, ident: ID, value: u8, reason: CureStatus) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.CureStatus),
                @bitCast(u8, ident),
                value,
                @enumToInt(reason),
            });
        }

        pub fn boost(self: Self, ident: ID, reason: Boost, num: u8) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Boost),
                @bitCast(u8, ident),
                @enumToInt(reason),
                num,
            });
        }

        pub fn unboost(self: Self, ident: ID, reason: Boost, num: u8) Error!void {
            if (!trace) return;
            assert(reason != .Rage);
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Unboost),
                @bitCast(u8, ident),
                @enumToInt(reason),
                num,
            });
        }

        pub fn clearallboost(self: Self) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{@enumToInt(ArgType.ClearAllBoost)});
        }

        pub fn fail(self: Self, ident: ID, reason: Fail) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Fail),
                @bitCast(u8, ident),
                @enumToInt(reason),
            });
        }

        pub fn miss(self: Self, source: ID, target: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Miss),
                @bitCast(u8, source),
                @bitCast(u8, target),
            });
        }

        pub fn hitcount(self: Self, ident: ID, num: u8) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.HitCount), @bitCast(u8, ident), num });
        }

        pub fn prepare(self: Self, source: ID, m: anytype) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Prepare),
                @bitCast(u8, source),
                @enumToInt(m),
            });
        }

        pub fn mustrecharge(self: Self, ident: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.MustRecharge), @bitCast(u8, ident) });
        }

        pub fn activate(self: Self, ident: ID, reason: Activate) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Activate),
                @bitCast(u8, ident),
                @enumToInt(reason),
            });
        }

        pub fn fieldactivate(self: Self) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{@enumToInt(ArgType.FieldActivate)});
        }

        pub fn start(self: Self, ident: ID, reason: Start) Error!void {
            if (!trace) return;
            assert(@enumToInt(reason) < @enumToInt(Start.TypeChange));
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Start),
                @bitCast(u8, ident),
                @enumToInt(reason),
            });
        }

        pub fn typechange(self: Self, ident: ID, types: anytype) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Start),
                @bitCast(u8, ident),
                @enumToInt(Start.TypeChange),
                @bitCast(u8, types),
            });
        }

        pub fn startEffect(self: Self, ident: ID, reason: Start, m: anytype) Error!void {
            if (!trace) return;
            assert(@enumToInt(reason) > @enumToInt(Start.TypeChange));
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Start),
                @bitCast(u8, ident),
                @enumToInt(reason),
                @enumToInt(m),
            });
        }

        pub fn end(self: Self, ident: ID, reason: End) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.End),
                @bitCast(u8, ident),
                @enumToInt(reason),
            });
        }

        pub fn ohko(self: Self) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{@enumToInt(ArgType.OHKO)});
        }

        pub fn crit(self: Self, ident: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Crit), @bitCast(u8, ident) });
        }

        pub fn supereffective(self: Self, ident: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.SuperEffective), @bitCast(u8, ident) });
        }

        pub fn resisted(self: Self, ident: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{ @enumToInt(ArgType.Resisted), @bitCast(u8, ident) });
        }

        pub fn immune(self: Self, ident: ID, reason: Immune) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Immune),
                @bitCast(u8, ident),
                @enumToInt(reason),
            });
        }

        pub fn transform(self: Self, source: ID, target: ID) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{
                @enumToInt(ArgType.Transform),
                @bitCast(u8, source),
                @bitCast(u8, target),
            });
        }

        pub fn laststill(self: Self) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{@enumToInt(ArgType.LastStill)});
        }

        pub fn lastmiss(self: Self) Error!void {
            if (!trace) return;
            try self.writer.writeAll(&.{@enumToInt(ArgType.LastMiss)});
        }
    };
}

pub const FixedLog = Log(std.io.FixedBufferStream([]u8).Writer);

// @test-only
pub fn TestLogs(comptime n: comptime_int) type {
    return struct {
        const Self = @This();

        expected: [n]u8 = [_]u8{0xFF} ** n,
        actual: [n]u8 = [_]u8{0xFF} ** n,

        pub fn expectMatches(self: Self) !void {
            if (!trace) return;
            // NOTE: some logs can end in the 0xFF sentinel byte so expectMatches can't be used
            // indiscriminately - in niche cases expectLog should be used directly
            var i = self.expected.len;
            while (i > 0) {
                if (self.expected[i - 1] != 0xFF) break;
                i -= 1;
            }
            if (i != self.expected.len) {
                std.debug.print("Expected buffer should be {d} bytes, not {d}\n", .{
                    i,
                    self.expected.len,
                });
                return error.TestExpectedEqual;
            }
            try expectLog(&self.expected, &self.actual);
        }
    };
}

// @test-only
pub fn expectLog(expected: []const u8, actual: []const u8) !void {
    if (!trace) return;
    expectEqualSlices(u8, expected, actual) catch |err| switch (err) {
        error.TestExpectedEqual => {
            std.debug.print("Expected: {any}\nActual:   {any}\n", .{ expected, actual });
            return err;
        },
        else => return err,
    };
}

const endian = builtin.target.cpu.arch.endian();

fn N(e: anytype) u8 {
    return @enumToInt(e);
}

const p1 = Player.P1;
const p2 = Player.P2;

const gen1 = struct {
    usingnamespace @import("../gen1/data.zig");
    pub const helpers = @import("../gen1/helpers.zig");
};

var buf: [gen1.MAX_LOG_SIZE]u8 = undefined;
var stream = std.io.fixedBufferStream(&buf);
var log: FixedLog = .{ .writer = stream.writer() };

const M = gen1.Move;
const S = gen1.Species;

test "|move|" {
    try log.move(p2.ident(4), M.Thunderbolt, p1.ident(5), null);
    try expectLog(
        &.{ N(ArgType.Move), 0b1100, N(M.Thunderbolt), 0b0101, N(Move.None) },
        buf[0..5],
    );
    stream.reset();

    try log.move(p2.ident(4), M.Wrap, p1.ident(5), M.Wrap);
    const wrap = N(M.Wrap);
    try expectLog(
        &.{ N(ArgType.Move), 0b1100, wrap, 0b0101, N(Move.From), wrap },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), M.SkullBash, .{}, null);
    try log.laststill();
    try expectLog(
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
    try expectLog(
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
    try expectLog(expected, buf[0..9]);
    stream.reset();

    snorlax.level = 100;
    snorlax.hp = 0;
    snorlax.status = 0;
    try log.switched(p2.ident(3), &snorlax);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 0, 0, 1, 144, 0 },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 0, 0, 144, 1, 0 },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();

    snorlax.hp = 400;
    try log.switched(p2.ident(3), &snorlax);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 1, 144, 1, 144, 0 },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(S.Snorlax), 100, 144, 1, 144, 1, 0 },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();
}

test "|cant|" {
    try log.cant(p2.ident(6), .Trapped);
    try expectLog(&.{ N(ArgType.Cant), 0b1110, N(Cant.Trapped) }, buf[0..3]);
    stream.reset();

    try log.disabled(p1.ident(2), M.Earthquake);
    try expectLog(&.{ N(ArgType.Cant), 2, N(Cant.Disable), N(M.Earthquake) }, buf[0..4]);
    stream.reset();
}

test "|faint|" {
    try log.faint(p2.ident(2), false);
    try expectLog(&.{ N(ArgType.Faint), 0b1010 }, buf[0..2]);
    stream.reset();

    try log.faint(p2.ident(2), true);
    try expectLog(&.{ N(ArgType.Faint), 0b1010, N(ArgType.None) }, buf[0..3]);
    stream.reset();
}

test "|turn|" {
    try log.turn(42);
    var expected = switch (endian) {
        .Big => &.{ N(ArgType.Turn), 0, 42, N(ArgType.None) },
        .Little => &.{ N(ArgType.Turn), 42, 0, N(ArgType.None) },
    };
    try expectLog(expected, buf[0..4]);
    stream.reset();
}

test "|win|" {
    try log.win(.P2);
    try expectLog(&.{ N(ArgType.Win), 1, N(ArgType.None) }, buf[0..3]);
    stream.reset();
}

test "|tie|" {
    try log.tie();
    try expectLog(&.{ N(ArgType.Tie), N(ArgType.None) }, buf[0..2]);
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
    try expectLog(expected, buf[0..8]);
    stream.reset();

    chansey.hp = 100;
    chansey.stats.hp = 256;
    chansey.status = 0;
    try log.damage(p2.ident(2), &chansey, .Confusion);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Damage), 0b1010, 0, 100, 1, 0, 0, N(Damage.Confusion) },
        .Little => &.{ N(ArgType.Damage), 0b1010, 100, 0, 0, 1, 0, N(Damage.Confusion) },
    };
    try expectLog(expected, buf[0..8]);
    stream.reset();

    chansey.status = gen1.Status.init(.PSN);
    try log.damageOf(p2.ident(2), &chansey, .PoisonOf, p1.ident(1));
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Damage), 0b1010, 0, 100, 1, 0, 0b1000, N(Damage.PoisonOf), 1 },
        .Little => &.{ N(ArgType.Damage), 0b1010, 100, 0, 0, 1, 0b1000, N(Damage.PoisonOf), 1 },
    };
    try expectLog(expected, buf[0..9]);
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
    try expectLog(expected, buf[0..8]);
    stream.reset();

    chansey.hp = 100;
    chansey.stats.hp = 256;
    chansey.status = 0;
    try log.heal(p2.ident(2), &chansey, .Silent);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Heal), 0b1010, 0, 100, 1, 0, 0, N(Heal.Silent) },
        .Little => &.{ N(ArgType.Heal), 0b1010, 100, 0, 0, 1, 0, N(Heal.Silent) },
    };
    try expectLog(expected, buf[0..8]);
    stream.reset();

    try log.drain(p2.ident(2), &chansey, p1.ident(1));
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Heal), 0b1010, 0, 100, 1, 0, 0, N(Heal.Drain), 1 },
        .Little => &.{ N(ArgType.Heal), 0b1010, 100, 0, 0, 1, 0, N(Heal.Drain), 1 },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();
}

test "|-status|" {
    try log.status(p2.ident(6), gen1.Status.init(.BRN), .None);
    try expectLog(&.{ N(ArgType.Status), 0b1110, 0b10000, N(Status.None) }, buf[0..4]);
    stream.reset();

    try log.status(p1.ident(2), gen1.Status.init(.FRZ), .Silent);
    try expectLog(&.{ N(ArgType.Status), 0b0010, 0b100000, N(Status.Silent) }, buf[0..4]);
    stream.reset();

    try log.statusFrom(p1.ident(1), gen1.Status.init(.PAR), M.BodySlam);
    try expectLog(
        &.{ N(ArgType.Status), 0b0001, 0b1000000, N(Status.From), N(M.BodySlam) },
        buf[0..5],
    );
    stream.reset();
}

test "|-curestatus|" {
    try log.curestatus(p2.ident(6), gen1.Status.slp(7), .Message);
    try expectLog(&.{ N(ArgType.CureStatus), 0b1110, 0b111, N(CureStatus.Message) }, buf[0..4]);
    stream.reset();

    try log.curestatus(p1.ident(2), gen1.Status.init(.PSN), .Silent);
    try expectLog(&.{ N(ArgType.CureStatus), 0b0010, 0b1000, N(CureStatus.Silent) }, buf[0..4]);
    stream.reset();
}

test "|-boost|" {
    try log.boost(p2.ident(6), .Speed, 2);
    try expectLog(&.{ N(ArgType.Boost), 0b1110, N(Boost.Speed), 2 }, buf[0..4]);
    stream.reset();

    try log.boost(p1.ident(2), .Rage, 1);
    try expectLog(&.{ N(ArgType.Boost), 0b0010, N(Boost.Rage), 1 }, buf[0..4]);
    stream.reset();
}

test "|-unboost|" {
    try log.unboost(p2.ident(3), .Defense, 2);
    try expectLog(&.{ N(ArgType.Unboost), 0b1011, N(Boost.Defense), 2 }, buf[0..4]);
    stream.reset();
}

test "|-clearallboost|" {
    try log.clearallboost();
    try expectLog(&.{N(ArgType.ClearAllBoost)}, buf[0..1]);
    stream.reset();
}

test "|-fail|" {
    try log.fail(p2.ident(6), .None);
    try expectLog(&.{ N(ArgType.Fail), 0b1110, N(Fail.None) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Sleep);
    try expectLog(&.{ N(ArgType.Fail), 0b1110, N(Fail.Sleep) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Substitute);
    try expectLog(&.{ N(ArgType.Fail), 0b1110, N(Fail.Substitute) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Weak);
    try expectLog(&.{ N(ArgType.Fail), 0b1110, N(Fail.Weak) }, buf[0..3]);
    stream.reset();
}

test "|-miss|" {
    try log.miss(p2.ident(4), p1.ident(5));
    try expectLog(&.{ N(ArgType.Miss), 0b1100, 0b0101 }, buf[0..3]);
    stream.reset();
}
test "|-hitcount|" {
    try log.hitcount(p2.ident(1), 5);
    try expectLog(&.{ N(ArgType.HitCount), 0b1001, 5 }, buf[0..3]);
    stream.reset();
}

test "|-prepare|" {
    try log.prepare(p2.ident(2), M.Dig);
    try expectLog(&.{ N(ArgType.Prepare), 0b1010, N(M.Dig) }, buf[0..3]);
    stream.reset();
}

test "|-mustrecharge|" {
    try log.mustrecharge(p1.ident(6));
    try expectLog(&.{ N(ArgType.MustRecharge), 0b0110 }, buf[0..2]);
    stream.reset();
}

test "|-activate|" {
    try log.activate(p1.ident(2), .Struggle);
    try expectLog(&.{ N(ArgType.Activate), 0b0010, N(Activate.Struggle) }, buf[0..3]);
    stream.reset();

    try log.activate(p2.ident(6), .Substitute);
    try expectLog(&.{ N(ArgType.Activate), 0b1110, N(Activate.Substitute) }, buf[0..3]);
    stream.reset();

    try log.activate(p1.ident(2), .Splash);
    try expectLog(&.{ N(ArgType.Activate), 0b0010, N(Activate.Splash) }, buf[0..3]);
    stream.reset();
}

test "|-fieldactivate|" {
    try log.fieldactivate();
    try expectLog(&.{N(ArgType.FieldActivate)}, buf[0..1]);
    stream.reset();
}

test "|-start|" {
    try log.start(p2.ident(6), .Bide);
    try expectLog(&.{ N(ArgType.Start), 0b1110, N(Start.Bide) }, buf[0..3]);
    stream.reset();

    try log.start(p1.ident(2), .ConfusionSilent);
    try expectLog(&.{ N(ArgType.Start), 0b0010, N(Start.ConfusionSilent) }, buf[0..3]);
    stream.reset();

    try log.typechange(p2.ident(6), gen1.Types{ .type1 = .Fire, .type2 = .Fire });
    try expectLog(&.{ N(ArgType.Start), 0b1110, N(Start.TypeChange), 0b1000_1000 }, buf[0..4]);
    stream.reset();

    try log.typechange(p1.ident(2), gen1.Types{ .type1 = .Bug, .type2 = .Poison });
    try expectLog(&.{ N(ArgType.Start), 0b0010, N(Start.TypeChange), 0b0011_0110 }, buf[0..4]);
    stream.reset();

    try log.startEffect(p1.ident(2), .Disable, M.Surf);
    try expectLog(&.{ N(ArgType.Start), 0b0010, N(Start.Disable), N(M.Surf) }, buf[0..4]);
    stream.reset();

    try log.startEffect(p1.ident(2), .Mimic, M.Surf);
    try expectLog(&.{ N(ArgType.Start), 0b0010, N(Start.Mimic), N(M.Surf) }, buf[0..4]);
    stream.reset();
}

test "|-end|" {
    try log.end(p2.ident(6), .Bide);
    try expectLog(&.{ N(ArgType.End), 0b1110, N(End.Bide) }, buf[0..3]);
    stream.reset();

    try log.end(p1.ident(2), .ConfusionSilent);
    try expectLog(&.{ N(ArgType.End), 0b0010, N(End.ConfusionSilent) }, buf[0..3]);
    stream.reset();
}

test "|-ohko|" {
    try log.ohko();
    try expectLog(&.{N(ArgType.OHKO)}, buf[0..1]);
    stream.reset();
}
test "|-crit|" {
    try log.crit(p2.ident(5));
    try expectLog(&.{ N(ArgType.Crit), 0b1101 }, buf[0..2]);
    stream.reset();
}
test "|-supereffective|" {
    try log.supereffective(p1.ident(1));
    try expectLog(&.{ N(ArgType.SuperEffective), 0b0001 }, buf[0..2]);
    stream.reset();
}
test "|-resisted|" {
    try log.resisted(p2.ident(2));
    try expectLog(&.{ N(ArgType.Resisted), 0b1010 }, buf[0..2]);
    stream.reset();
}
test "|-immune|" {
    try log.immune(p1.ident(3), .None);
    try expectLog(&.{ N(ArgType.Immune), 0b0011, N(Immune.None) }, buf[0..3]);
    stream.reset();

    try log.immune(p2.ident(2), .OHKO);
    try expectLog(&.{ N(ArgType.Immune), 0b1010, N(Immune.OHKO) }, buf[0..3]);
    stream.reset();
}
test "|-transform|" {
    try log.transform(p2.ident(4), p1.ident(5));
    try expectLog(&.{ N(ArgType.Transform), 0b1100, 0b0101 }, buf[0..3]);
    stream.reset();
}
