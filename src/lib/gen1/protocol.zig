const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const common = @import("../common/data.zig");
const protocol = @import("../common/protocol.zig");

const data = @import("data.zig");
const helpers = @import("helpers.zig");

const assert = std.debug.assert;

const trace = build_options.trace;

const Player = common.Player;

pub const Activate = protocol.Activate;
pub const ArgType = protocol.ArgType;
pub const Boost = protocol.Boost;
pub const Cant = protocol.Cant;
pub const CureStatus = protocol.CureStatus;
pub const Damage = protocol.Damage;
pub const End = protocol.End;
pub const Fail = protocol.Fail;
pub const Heal = protocol.Heal;
pub const Immune = protocol.Immune;
pub const Start = protocol.Start;
pub const Status = protocol.Status;
pub const expectLog = protocol.expectLog;

const Move = data.Move;
const Pokemon = data.Pokemon;
const Species = data.Species;
const Types = data.Types;

pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn move(self: Self, source: u8, m: Move, target: u8, reason: protocol.Move) !void {
            if (!trace) return;
            assert(reason != .From);
            assert(m != .None or reason == .Recharge);
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Move),
                source,
                @enumToInt(m),
                target,
                @enumToInt(reason),
            });
        }

        pub fn moveFrom(self: Self, source: u8, m: Move, target: u8, from: Move) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Move),
                source,
                @enumToInt(m),
                target,
                @enumToInt(protocol.Move.From),
                @enumToInt(from),
            });
        }

        pub fn switched(self: Self, ident: u8, pokemon: *const Pokemon) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Switch), ident });
            try self.writer.writeAll(&[_]u8{ @enumToInt(pokemon.species), pokemon.level });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{pokemon.status});
        }

        pub fn cant(self: Self, ident: u8, reason: Cant) !void {
            if (!trace) return;
            assert(reason != .Disable);
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Cant), ident, @enumToInt(reason) });
        }

        pub fn disabled(self: Self, ident: u8, m: Move) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Cant),
                ident,
                @enumToInt(Cant.Disable),
                @enumToInt(m),
            });
        }

        pub fn faint(self: Self, ident: u8, done: bool) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Faint), ident });
            if (done) try self.writer.writeByte(@enumToInt(ArgType.None));
        }

        pub fn turn(self: Self, num: u16) !void {
            if (!trace) return;
            try self.writer.writeByte(@enumToInt(ArgType.Turn));
            try self.writer.writeIntNative(u16, num);
            try self.writer.writeByte(@enumToInt(ArgType.None));
        }

        pub fn win(self: Self, player: Player) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Win),
                @enumToInt(player),
                @enumToInt(ArgType.None),
            });
        }

        pub fn tie(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Tie), @enumToInt(ArgType.None) });
        }

        pub fn damage(self: Self, ident: u8, pokemon: *const Pokemon, reason: Damage) !void {
            if (!trace) return;
            assert(@enumToInt(reason) <= @enumToInt(Damage.Confusion));
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Damage), ident });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(reason) });
        }

        pub fn damageOf(
            self: Self,
            ident: u8,
            pokemon: *const Pokemon,
            reason: Damage,
            source: u8,
        ) !void {
            if (!trace) return;
            assert(@enumToInt(reason) >= @enumToInt(Damage.PoisonOf));
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Damage), ident });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(reason), source });
        }

        pub fn heal(self: Self, ident: u8, pokemon: *const Pokemon, reason: Heal) !void {
            if (!trace) return;
            assert(reason != .Drain);
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Heal), ident });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(reason) });
        }

        pub fn drain(self: Self, source: u8, pokemon: *const Pokemon, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Heal), source });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(Heal.Drain), target });
        }

        pub fn status(self: Self, ident: u8, value: u8, reason: Status) !void {
            if (!trace) return;
            assert(reason != .From);
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Status),
                ident,
                value,
                @enumToInt(reason),
            });
        }

        pub fn statusFrom(self: Self, ident: u8, value: u8, m: Move) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Status),
                ident,
                value,
                @enumToInt(Status.From),
                @enumToInt(m),
            });
        }

        pub fn curestatus(self: Self, ident: u8, value: u8, reason: CureStatus) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.CureStatus),
                ident,
                value,
                @enumToInt(reason),
            });
        }

        pub fn boost(self: Self, ident: u8, reason: Boost, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Boost),
                ident,
                @enumToInt(reason),
                num,
            });
        }

        pub fn unboost(self: Self, ident: u8, reason: Boost, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Unboost),
                ident,
                @enumToInt(reason),
                num,
            });
        }

        pub fn clearallboost(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.ClearAllBoost)});
        }

        pub fn fail(self: Self, ident: u8, reason: Fail) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Fail), ident, @enumToInt(reason) });
        }

        pub fn miss(self: Self, source: u8, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Miss), source, target });
        }

        pub fn hitcount(self: Self, ident: u8, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.HitCount), ident, num });
        }

        pub fn prepare(self: Self, source: u8, m: Move) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Prepare),
                source,
                @enumToInt(m),
            });
        }

        pub fn mustrecharge(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.MustRecharge), ident });
        }

        pub fn activate(self: Self, ident: u8, reason: Activate) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Activate),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn fieldactivate(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.FieldActivate)});
        }

        pub fn start(self: Self, ident: u8, reason: Start) !void {
            if (!trace) return;
            assert(@enumToInt(reason) < @enumToInt(Start.TypeChange));
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn typechange(self: Self, ident: u8, types: Types) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(Start.TypeChange),
                @bitCast(u8, types),
            });
        }

        pub fn startEffect(self: Self, ident: u8, reason: Start, m: Move) !void {
            if (!trace) return;
            assert(@enumToInt(reason) > @enumToInt(Start.TypeChange));
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(reason),
                @enumToInt(m),
            });
        }

        pub fn end(self: Self, ident: u8, reason: End) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.End), ident, @enumToInt(reason) });
        }

        pub fn ohko(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.OHKO)});
        }

        pub fn crit(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Crit), ident });
        }

        pub fn supereffective(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.SuperEffective), ident });
        }

        pub fn resisted(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Resisted), ident });
        }

        pub fn immune(self: Self, ident: u8, reason: Immune) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Immune),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn transform(self: Self, source: u8, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Transform), source, target });
        }

        pub fn laststill(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.LastStill)});
        }

        pub fn lastmiss(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.LastMiss)});
        }
    };
}

const endian = builtin.target.cpu.arch.endian();

fn N(e: anytype) u8 {
    return @enumToInt(e);
}

var buf: [100]u8 = undefined;
var stream = std.io.fixedBufferStream(&buf);
var log: Log(std.io.FixedBufferStream([]u8).Writer) = .{ .writer = stream.writer() };

const p1 = Player.P1;
const p2 = Player.P2;

test "|move|" {
    try log.move(p2.ident(4), .Thunderbolt, p1.ident(5), .None);
    try expectLog(
        &[_]u8{ N(ArgType.Move), 0b1100, N(Move.Thunderbolt), 0b0101, N(protocol.Move.None) },
        buf[0..5],
    );
    stream.reset();

    try log.move(p2.ident(4), .None, p1.ident(5), .Recharge);
    try expectLog(
        &[_]u8{ N(ArgType.Move), 0b1100, 0, 0b0101, N(protocol.Move.Recharge) },
        buf[0..5],
    );
    stream.reset();

    try log.moveFrom(p2.ident(4), .Wrap, p1.ident(5), .Wrap);
    const wrap = N(Move.Wrap);
    try expectLog(
        &[_]u8{ N(ArgType.Move), 0b1100, wrap, 0b0101, N(protocol.Move.From), wrap },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), .WaterGun, p1.ident(5), .None);
    try log.laststill();
    try expectLog(
        &[_]u8{
            N(ArgType.Move),
            0b1100,
            N(Move.WaterGun),
            0b0101,
            N(protocol.Move.None),
            N(ArgType.LastStill),
        },
        buf[0..6],
    );
    stream.reset();

    try log.move(p2.ident(4), .Tackle, p1.ident(5), .None);
    try log.lastmiss();
    try expectLog(
        &[_]u8{
            N(ArgType.Move),
            0b1100,
            N(Move.Tackle),
            0b0101,
            N(protocol.Move.None),
            N(ArgType.LastMiss),
        },
        buf[0..6],
    );
    stream.reset();
}

test "|switch|" {
    var snorlax = helpers.Pokemon.init(.{ .species = .Snorlax, .moves = &.{.Splash} });
    snorlax.level = 91;
    snorlax.hp = 200;
    snorlax.stats.hp = 400;
    snorlax.status = data.Status.init(.PAR);
    try log.switched(p2.ident(3), &snorlax);
    const par = 0b1000000;
    var expected: []const u8 = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(Species.Snorlax), 91, 0, 200, 1, 144, par },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(Species.Snorlax), 91, 200, 0, 144, 1, par },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();

    snorlax.level = 100;
    snorlax.hp = 0;
    snorlax.status = 0;
    try log.switched(p2.ident(3), &snorlax);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(Species.Snorlax), 100, 0, 0, 1, 144, 0 },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(Species.Snorlax), 100, 0, 0, 144, 1, 0 },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();

    snorlax.hp = 400;
    try log.switched(p2.ident(3), &snorlax);
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Switch), 0b1011, N(Species.Snorlax), 100, 1, 144, 1, 144, 0 },
        .Little => &.{ N(ArgType.Switch), 0b1011, N(Species.Snorlax), 100, 144, 1, 144, 1, 0 },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();
}

test "|cant|" {
    try log.cant(p2.ident(6), .Trapped);
    try expectLog(&[_]u8{ N(ArgType.Cant), 0b1110, N(Cant.Trapped) }, buf[0..3]);
    stream.reset();

    try log.disabled(p1.ident(2), .Earthquake);
    try expectLog(&[_]u8{ N(ArgType.Cant), 2, N(Cant.Disable), N(Move.Earthquake) }, buf[0..4]);
    stream.reset();
}

test "|faint|" {
    try log.faint(p2.ident(2), false);
    try expectLog(&[_]u8{ N(ArgType.Faint), 0b1010 }, buf[0..2]);
    stream.reset();

    try log.faint(p2.ident(2), true);
    try expectLog(&[_]u8{ N(ArgType.Faint), 0b1010, N(ArgType.None) }, buf[0..3]);
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
    try expectLog(&[_]u8{ N(ArgType.Win), 1, N(ArgType.None) }, buf[0..3]);
    stream.reset();
}

test "|tie|" {
    try log.tie();
    try expectLog(&[_]u8{ N(ArgType.Tie), N(ArgType.None) }, buf[0..2]);
    stream.reset();
}

test "|-damage|" {
    var chansey = helpers.Pokemon.init(.{ .species = .Chansey, .moves = &.{.Splash} });
    chansey.hp = 612;
    chansey.status = data.Status.slp(1);
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

    chansey.status = data.Status.init(.PSN);
    try log.damageOf(p2.ident(2), &chansey, .PoisonOf, p1.ident(1));
    expected = switch (endian) {
        .Big => &.{ N(ArgType.Damage), 0b1010, 0, 100, 1, 0, 0b1000, N(Damage.PoisonOf), 1 },
        .Little => &.{ N(ArgType.Damage), 0b1010, 100, 0, 0, 1, 0b1000, N(Damage.PoisonOf), 1 },
    };
    try expectLog(expected, buf[0..9]);
    stream.reset();
}

test "|-heal|" {
    var chansey = helpers.Pokemon.init(.{ .species = .Chansey, .moves = &.{.Splash} });
    chansey.hp = 612;
    chansey.status = data.Status.slp(1);
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
    try log.status(p2.ident(6), data.Status.init(.BRN), .None);
    try expectLog(&[_]u8{ N(ArgType.Status), 0b1110, 0b10000, N(Status.None) }, buf[0..4]);
    stream.reset();

    try log.status(p1.ident(2), data.Status.init(.FRZ), .Silent);
    try expectLog(&[_]u8{ N(ArgType.Status), 0b0010, 0b100000, N(Status.Silent) }, buf[0..4]);
    stream.reset();

    try log.statusFrom(p1.ident(1), data.Status.init(.PAR), .BodySlam);
    try expectLog(
        &[_]u8{ N(ArgType.Status), 0b0001, 0b1000000, N(Status.From), N(Move.BodySlam) },
        buf[0..5],
    );
    stream.reset();
}

test "|-curestatus|" {
    try log.curestatus(p2.ident(6), data.Status.slp(7), .None);
    try expectLog(&[_]u8{ N(ArgType.CureStatus), 0b1110, 0b111, N(CureStatus.None) }, buf[0..4]);
    stream.reset();

    try log.curestatus(p1.ident(2), data.Status.init(.PSN), .Silent);
    try expectLog(&[_]u8{ N(ArgType.CureStatus), 0b0010, 0b1000, N(CureStatus.Silent) }, buf[0..4]);
    stream.reset();
}

test "|-boost|" {
    try log.boost(p2.ident(6), .Speed, 2);
    try expectLog(&[_]u8{ N(ArgType.Boost), 0b1110, N(Boost.Speed), 2 }, buf[0..4]);
    stream.reset();

    try log.boost(p1.ident(2), .Rage, 1);
    try expectLog(&[_]u8{ N(ArgType.Boost), 0b0010, N(Boost.Rage), 1 }, buf[0..4]);
    stream.reset();
}

test "|-unboost|" {
    try log.unboost(p2.ident(3), .Defense, 2);
    try expectLog(&[_]u8{ N(ArgType.Unboost), 0b1011, N(Boost.Defense), 2 }, buf[0..4]);
    stream.reset();
}

test "|-clearallboost|" {
    try log.clearallboost();
    try expectLog(&[_]u8{N(ArgType.ClearAllBoost)}, buf[0..1]);
    stream.reset();
}

test "|-fail|" {
    try log.fail(p2.ident(6), .None);
    try expectLog(&[_]u8{ N(ArgType.Fail), 0b1110, N(Fail.None) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Sleep);
    try expectLog(&[_]u8{ N(ArgType.Fail), 0b1110, N(Fail.Sleep) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Substitute);
    try expectLog(&[_]u8{ N(ArgType.Fail), 0b1110, N(Fail.Substitute) }, buf[0..3]);
    stream.reset();

    try log.fail(p2.ident(6), .Weak);
    try expectLog(&[_]u8{ N(ArgType.Fail), 0b1110, N(Fail.Weak) }, buf[0..3]);
    stream.reset();
}

test "|-miss|" {
    try log.miss(p2.ident(4), p1.ident(5));
    try expectLog(&[_]u8{ N(ArgType.Miss), 0b1100, 0b0101 }, buf[0..3]);
    stream.reset();
}
test "|-hitcount|" {
    try log.hitcount(p2.ident(1), 5);
    try expectLog(&[_]u8{ N(ArgType.HitCount), 0b1001, 5 }, buf[0..3]);
    stream.reset();
}

test "|-prepare|" {
    try log.prepare(p2.ident(2), .Dig);
    try expectLog(&[_]u8{ N(ArgType.Prepare), 0b1010, N(Move.Dig) }, buf[0..3]);
    stream.reset();
}

test "|-mustrecharge|" {
    try log.mustrecharge(p1.ident(6));
    try expectLog(&[_]u8{ N(ArgType.MustRecharge), 0b0110 }, buf[0..2]);
    stream.reset();
}

test "|-activate|" {
    try log.activate(p1.ident(2), .Struggle);
    try expectLog(&[_]u8{ N(ArgType.Activate), 0b0010, N(Activate.Struggle) }, buf[0..3]);
    stream.reset();

    try log.activate(p2.ident(6), .Substitute);
    try expectLog(&[_]u8{ N(ArgType.Activate), 0b1110, N(Activate.Substitute) }, buf[0..3]);
    stream.reset();

    try log.activate(p1.ident(2), .Splash);
    try expectLog(&[_]u8{ N(ArgType.Activate), 0b0010, N(Activate.Splash) }, buf[0..3]);
    stream.reset();
}

test "|-fieldactivate|" {
    try log.fieldactivate();
    try expectLog(&[_]u8{N(ArgType.FieldActivate)}, buf[0..1]);
    stream.reset();
}

test "|-start|" {
    try log.start(p2.ident(6), .Bide);
    try expectLog(&[_]u8{ N(ArgType.Start), 0b1110, N(Start.Bide) }, buf[0..3]);
    stream.reset();

    try log.start(p1.ident(2), .ConfusionSilent);
    try expectLog(&[_]u8{ N(ArgType.Start), 0b0010, N(Start.ConfusionSilent) }, buf[0..3]);
    stream.reset();

    try log.typechange(p2.ident(6), .{ .type1 = .Fire, .type2 = .Fire });
    try expectLog(&[_]u8{ N(ArgType.Start), 0b1110, N(Start.TypeChange), 0b1000_1000 }, buf[0..4]);
    stream.reset();

    try log.typechange(p1.ident(2), .{ .type1 = .Bug, .type2 = .Poison });
    try expectLog(&[_]u8{ N(ArgType.Start), 0b0010, N(Start.TypeChange), 0b0011_0110 }, buf[0..4]);
    stream.reset();

    try log.startEffect(p1.ident(2), .Disable, .Surf);
    try expectLog(&[_]u8{ N(ArgType.Start), 0b0010, N(Start.Disable), N(Move.Surf) }, buf[0..4]);
    stream.reset();

    try log.startEffect(p1.ident(2), .Mimic, .Surf);
    try expectLog(&[_]u8{ N(ArgType.Start), 0b0010, N(Start.Mimic), N(Move.Surf) }, buf[0..4]);
    stream.reset();
}

test "|-end|" {
    try log.end(p2.ident(6), .Bide);
    try expectLog(&[_]u8{ N(ArgType.End), 0b1110, N(End.Bide) }, buf[0..3]);
    stream.reset();

    try log.end(p1.ident(2), .ConfusionSilent);
    try expectLog(&[_]u8{ N(ArgType.End), 0b0010, N(End.ConfusionSilent) }, buf[0..3]);
    stream.reset();
}

test "|-ohko|" {
    try log.ohko();
    try expectLog(&[_]u8{N(ArgType.OHKO)}, buf[0..1]);
    stream.reset();
}
test "|-crit|" {
    try log.crit(p2.ident(5));
    try expectLog(&[_]u8{ N(ArgType.Crit), 0b1101 }, buf[0..2]);
    stream.reset();
}
test "|-supereffective|" {
    try log.supereffective(p1.ident(1));
    try expectLog(&[_]u8{ N(ArgType.SuperEffective), 0b0001 }, buf[0..2]);
    stream.reset();
}
test "|-resisted|" {
    try log.resisted(p2.ident(2));
    try expectLog(&[_]u8{ N(ArgType.Resisted), 0b1010 }, buf[0..2]);
    stream.reset();
}
test "|-immune|" {
    try log.immune(p1.ident(3), .None);
    try expectLog(&[_]u8{ N(ArgType.Immune), 0b0011, N(Immune.None) }, buf[0..3]);
    stream.reset();

    try log.immune(p2.ident(2), .OHKO);
    try expectLog(&[_]u8{ N(ArgType.Immune), 0b1010, N(Immune.OHKO) }, buf[0..3]);
    stream.reset();
}
test "|-transform|" {
    try log.transform(p2.ident(4), p1.ident(5));
    try expectLog(&[_]u8{ N(ArgType.Transform), 0b1100, 0b0101 }, buf[0..3]);
    stream.reset();
}
