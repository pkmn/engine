const std = @import("std");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");
const helpers = @import("helpers.zig");

const ArrayList = std.ArrayList;

const assert = std.debug.assert;

const stream = std.io.fixedBufferStream;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Player = common.Player;
const Result = common.Result;
const Choice = common.Choice;

const showdown = options.showdown;
const trace = options.trace;

const ArgType = protocol.ArgType;
const FixedLog = protocol.FixedLog;
const Log = protocol.Log;

const Move = data.Move;
const Species = data.Species;
const Status = data.Status;
const Type = data.Type;
const Types = data.Types;

const Battle = helpers.Battle;
const Side = helpers.Side;
const Pokemon = helpers.Pokemon;
const move = helpers.move;
const swtch = helpers.swtch;

const OPTIONS_SIZE = data.OPTIONS_SIZE;

const U = if (showdown) u32 else u8;
const MIN: U = 0;
const MAX: U = std.math.maxInt(U);

const NOP = MIN;
const HIT = MIN;
const CRIT = MIN;
const MIN_DMG = if (showdown) MIN else 179;
const MAX_DMG = MAX;

// TODO: inline Status.init(...) when Zig no longer causes SIGBUS
const BRN = 0b10000;
const PAR = 0b1000000;

comptime {
    assert(showdown or std.math.rotr(u8, MIN_DMG, 1) == 217);
    assert(showdown or std.math.rotr(u8, MAX_DMG, 1) == 255);
}

fn ranged(comptime n: u8, comptime d: u9) U {
    return if (showdown) @as(U, n) * (@as(u64, 0x100000000) / @as(U, d)) else n;
}

const P1 = Player.P1;
const P2 = Player.P2;

var choices: [OPTIONS_SIZE]Choice = undefined;

// General

test "start (first fainted)" {
    if (showdown) return;
    var t = Test(.{}).init(
        &.{
            .{ .species = .Pikachu, .hp = 0, .moves = &.{.ThunderShock} },
            .{ .species = .Bulbasaur, .moves = &.{.Tackle} },
        },
        &.{
            .{ .species = .Charmander, .hp = 0, .moves = &.{.Scratch} },
            .{ .species = .Squirtle, .moves = &.{.Tackle} },
        },
    );
    defer t.deinit();

    try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.turn(1);

    try expectEqual(Result.Default, try t.battle.actual.update(.{}, .{}, t.log.actual));
    try t.verify();
}

test "start (all fainted)" {
    if (showdown) return;
    // Win
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Bulbasaur, .moves = &.{.Tackle} }},
            &.{.{ .species = .Charmander, .hp = 0, .moves = &.{.Scratch} }},
        );
        defer t.deinit();

        try expectEqual(Result.Win, try t.battle.actual.update(.{}, .{}, t.log.actual));
        try t.verify();
    }
    // Lose
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Bulbasaur, .hp = 0, .moves = &.{.Tackle} }},
            &.{.{ .species = .Charmander, .moves = &.{.Scratch} }},
        );
        defer t.deinit();

        try expectEqual(Result.Lose, try t.battle.actual.update(.{}, .{}, t.log.actual));
        try t.verify();
    }
    // Tie
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Bulbasaur, .hp = 0, .moves = &.{.Tackle} }},
            &.{.{ .species = .Charmander, .hp = 0, .moves = &.{.Scratch} }},
        );
        defer t.deinit();

        try expectEqual(Result.Tie, try t.battle.actual.update(.{}, .{}, t.log.actual));
        try t.verify();
    }
}

test "switching (order)" {
    var battle = Battle.init(
        0x12345678,
        &[_]Pokemon{.{ .species = .Abra, .moves = &.{.Teleport} }} ** 6,
        &[_]Pokemon{.{ .species = .Gastly, .moves = &.{.Lick} }} ** 6,
    );
    battle.turn = 1;
    const p1 = battle.side(.P1);
    const p2 = battle.side(.P2);

    try expectEqual(Result.Default, try battle.update(swtch(3), swtch(2), null));
    try expectOrder(p1, &.{ 3, 2, 1, 4, 5, 6 }, p2, &.{ 2, 1, 3, 4, 5, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(5), swtch(5), null));
    try expectOrder(p1, &.{ 5, 2, 1, 4, 3, 6 }, p2, &.{ 5, 1, 3, 4, 2, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(6), swtch(3), null));
    try expectOrder(p1, &.{ 6, 2, 1, 4, 3, 5 }, p2, &.{ 3, 1, 5, 4, 2, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(3), swtch(3), null));
    try expectOrder(p1, &.{ 1, 2, 6, 4, 3, 5 }, p2, &.{ 5, 1, 3, 4, 2, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(2), swtch(4), null));
    try expectOrder(p1, &.{ 2, 1, 6, 4, 3, 5 }, p2, &.{ 4, 1, 3, 5, 2, 6 });

    var expected_buf: [22]u8 = undefined;
    var actual_buf: [22]u8 = undefined;

    var expected = FixedLog{ .writer = stream(&expected_buf).writer() };
    var actual = FixedLog{ .writer = stream(&actual_buf).writer() };

    try expected.switched(P1.ident(3), p1.pokemon[2]);
    try expected.switched(P2.ident(2), p2.pokemon[1]);
    try expected.turn(7);

    try expectEqual(Result.Default, try battle.update(swtch(5), swtch(5), actual));
    try expectOrder(p1, &.{ 3, 1, 6, 4, 2, 5 }, p2, &.{ 2, 1, 3, 5, 4, 6 });
    try expectLog(&expected_buf, &actual_buf);
}

fn expectOrder(p1: anytype, o1: []const u8, p2: anytype, o2: []const u8) !void {
    try expectEqualSlices(u8, o1, &p1.order);
    try expectEqualSlices(u8, o2, &p2.order);
}

test "switching (reset)" {
    var t = Test(.{}).init(
        &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
        &.{
            .{ .species = .Charmander, .moves = &.{.Scratch} },
            .{ .species = .Squirtle, .moves = &.{.Tackle} },
        },
    );
    defer t.deinit();
    try t.start();

    var p1 = &t.actual.p1.active;
    p1.volatiles.Reflect = true;

    t.actual.p2.last_used_move = .Scratch;
    var p2 = &t.actual.p2.active;
    p2.boosts.atk = 1;
    p2.volatiles.LightScreen = true;
    t.actual.p2.get(1).status = Status.init(.PAR);

    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.move(P1.ident(1), Move.Teleport, P1.ident(1), null);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try expect(p1.volatiles.Reflect);

    try expectEqual(data.Volatiles{}, p2.volatiles);
    try expectEqual(data.Boosts{}, p2.boosts);
    try expectEqual(@as(u8, 0), t.actual.p2.get(1).status);
    try expectEqual(Status.init(.PAR), t.actual.p2.get(2).status);

    try expectEqual(Move.Teleport, t.actual.p1.last_used_move);
    try expectEqual(Move.None, t.actual.p2.last_used_move);

    try t.verify();
}

test "switching (brn/par)" {
    var t = Test(.{}).init(
        &.{
            .{ .species = .Pikachu, .moves = &.{.ThunderShock} },
            .{ .species = .Bulbasaur, .status = BRN, .moves = &.{.Tackle} },
        },
        &.{
            .{ .species = .Charmander, .moves = &.{.Scratch} },
            .{ .species = .Squirtle, .status = PAR, .moves = &.{.Tackle} },
        },
    );
    defer t.deinit();

    try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
    t.expected.p1.get(2).hp -= 18;
    try t.log.expected.damage(P1.ident(2), t.expected.p1.get(2), .Burn);
    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));

    try expectEqual(@as(u16, 98), t.actual.p1.active.stats.atk);
    try expectEqual(@as(u16, 196), t.actual.p1.stored().stats.atk);
    try expectEqual(@as(u16, 46), t.actual.p2.active.stats.spe);
    try expectEqual(@as(u16, 184), t.actual.p2.stored().stats.spe);

    try t.verify();
}

test "turn order (priority)" {
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            NOP, NOP, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            NOP, NOP, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            NOP, NOP, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            NOP, NOP, NOP, HIT, ~CRIT, MIN_DMG, HIT,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Raticate, .moves = &.{ .Tackle, .QuickAttack, .Counter } }},
        &.{.{ .species = .Chansey, .moves = &.{ .Tackle, .QuickAttack, .Counter } }},
    );
    defer t.deinit();

    t.expected.p1.get(1).hp -= 20;
    t.expected.p2.get(1).hp -= 91;

    try t.log.expected.move(P1.ident(1), Move.Tackle, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.Tackle, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.turn(2);

    // Raticate > Chansey
    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    t.expected.p1.get(1).hp -= 22;
    t.expected.p2.get(1).hp -= 91;

    try t.log.expected.move(P2.ident(1), Move.QuickAttack, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.move(P1.ident(1), Move.Tackle, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.turn(3);

    // Chansey > Raticate
    try expectEqual(Result.Default, try t.update(move(1), move(2)));

    t.expected.p1.get(1).hp -= 22;
    t.expected.p2.get(1).hp -= 104;

    try t.log.expected.move(P1.ident(1), Move.QuickAttack, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.QuickAttack, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.turn(4);

    // Raticate > Chansey
    try expectEqual(Result.Default, try t.update(move(2), move(2)));

    t.expected.p1.get(1).hp -= 20;
    t.expected.p2.get(1).hp -= 40;

    try t.log.expected.move(P2.ident(1), Move.Tackle, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.move(P1.ident(1), Move.Counter, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.turn(5);

    // Chansey > Raticate
    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    try t.verify();
}

test "turn order (basic speed tie)" {
    return error.SkipZigTest;
}

test "turn order (complex speed tie)" {
    return error.SkipZigTest;
}

test "turn order (switch vs. move)" {
    var t = Test(if (showdown)
        (.{ NOP, HIT, ~CRIT, MIN_DMG, NOP, HIT, ~CRIT, MIN_DMG })
    else
        (.{ ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
        &.{
            .{ .species = .Raticate, .moves = &.{.QuickAttack} },
            .{ .species = .Rattata, .moves = &.{.QuickAttack} },
        },
        &.{
            .{ .species = .Ninetales, .moves = &.{.QuickAttack} },
            .{ .species = .Vulpix, .moves = &.{.QuickAttack} },
        },
    );
    defer t.deinit();

    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.move(P1.ident(1), Move.QuickAttack, P2.ident(2), null);
    t.expected.p2.get(2).hp -= 64;
    try t.log.expected.damage(P2.ident(2), t.expected.p2.get(2), .None);
    try t.log.expected.turn(2);

    // Switch > Quick Attack
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));

    try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
    try t.log.expected.move(P2.ident(2), Move.QuickAttack, P1.ident(2), null);
    t.expected.p1.get(2).hp -= 32;
    try t.log.expected.damage(P1.ident(2), t.expected.p1.get(2), .None);
    try t.log.expected.turn(3);

    // Switch > Quick Attack
    try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
    try t.verify();
}

test "PP deduction" {
    var t = Test(.{}).init(
        &.{.{ .species = .Alakazam, .moves = &.{.Teleport} }},
        &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
    );
    defer t.deinit();
    try t.start();

    try expectEqual(@as(u8, 32), t.actual.p1.active.move(1).pp);
    try expectEqual(@as(u8, 32), t.actual.p1.stored().move(1).pp);
    try expectEqual(@as(u8, 32), t.actual.p2.active.move(1).pp);
    try expectEqual(@as(u8, 32), t.actual.p2.stored().move(1).pp);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try expectEqual(@as(u8, 31), t.actual.p1.active.move(1).pp);
    try expectEqual(@as(u8, 31), t.actual.p1.stored().move(1).pp);
    try expectEqual(@as(u8, 31), t.actual.p2.active.move(1).pp);
    try expectEqual(@as(u8, 31), t.actual.p2.stored().move(1).pp);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try expectEqual(@as(u8, 30), t.actual.p1.active.move(1).pp);
    try expectEqual(@as(u8, 30), t.actual.p1.stored().move(1).pp);
    try expectEqual(@as(u8, 30), t.actual.p2.active.move(1).pp);
    try expectEqual(@as(u8, 30), t.actual.p2.stored().move(1).pp);
}

test "accuracy (normal)" {
    const hit = comptime ranged(85 * 255 / 100, 256) - 1;
    const miss = hit + 1;
    var t = Test(if (showdown)
        (.{ NOP, NOP, hit, CRIT, MAX_DMG, miss })
    else
        (.{ CRIT, MAX_DMG, hit, ~CRIT, MIN_DMG, miss })).init(
        &.{.{ .species = .Hitmonchan, .moves = &.{.MegaPunch} }},
        &.{.{ .species = .Machamp, .moves = &.{.MegaPunch} }},
    );
    defer t.deinit();

    t.expected.p2.get(1).hp -= 159;

    try t.log.expected.move(P1.ident(1), Move.MegaPunch, P2.ident(1), null);
    try t.log.expected.crit(P2.ident(1));
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.MegaPunch, P1.ident(1), null);
    try t.log.expected.lastmiss();
    try t.log.expected.miss(P2.ident(1));
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

test "damage calc" {
    return error.SkipZigTest;
}

test "fainting (single)" {
    // Switch
    {
        var t = Test(if (showdown)
            (.{ NOP, NOP, HIT, HIT, ~CRIT, MAX_DMG })
        else
            (.{ HIT, ~CRIT, MAX_DMG, HIT })).init(
            &.{.{ .species = .Venusaur, .moves = &.{.LeechSeed} }},
            &.{
                .{ .species = .Slowpoke, .hp = 1, .moves = &.{.WaterGun} },
                .{ .species = .Dratini, .moves = &.{.DragonRage} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(P1.ident(1), Move.LeechSeed, P2.ident(1), null);
        try t.log.expected.start(P2.ident(1), .LeechSeed);
        try t.log.expected.move(P2.ident(1), Move.WaterGun, P1.ident(1), null);
        try t.log.expected.resisted(P1.ident(1));
        t.expected.p1.get(1).hp -= 15;
        try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .LeechSeed);
        t.expected.p1.get(1).hp += 15;
        try t.log.expected.heal(P1.ident(1), t.expected.p1.get(1), .Silent);
        try t.log.expected.faint(P2.ident(1), true);

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(1), move(1)));

        var n = t.battle.actual.choices(.P1, .Pass, &choices);
        try expectEqualSlices(Choice, &[_]Choice{.{}}, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Switch, &choices);
        try expectEqualSlices(Choice, &[_]Choice{swtch(2)}, choices[0..n]);

        try t.verify();
    }
    // Win
    {
        var t = Test(if (showdown) .{ NOP, NOP, HIT } else .{HIT}).init(
            &.{.{ .species = .Dratini, .hp = 1, .status = BRN, .moves = &.{.DragonRage} }},
            &.{.{ .species = .Slowpoke, .hp = 1, .moves = &.{.WaterGun} }},
        );
        defer t.deinit();

        t.expected.p2.get(1).hp = 0;

        try t.log.expected.move(P1.ident(1), Move.DragonRage, P2.ident(1), null);
        try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
        try t.log.expected.faint(P2.ident(1), true);
        try t.log.expected.win(.P1);

        try expectEqual(Result.Win, try t.update(move(1), move(1)));
        try t.verify();
    }
    // Lose
    {
        var t = Test(if (showdown)
            (.{ NOP, NOP, NOP, ~CRIT, MIN_DMG, HIT })
        else
            (.{ ~CRIT, MIN_DMG, HIT })).init(
            &.{.{ .species = .Jolteon, .hp = 1, .moves = &.{.Swift} }},
            &.{.{ .species = .Dratini, .status = BRN, .moves = &.{.DragonRage} }},
        );
        defer t.deinit();

        t.expected.p1.get(1).hp = 0;
        t.expected.p2.get(1).hp -= 53;

        try t.log.expected.move(P1.ident(1), Move.Swift, P2.ident(1), null);
        try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
        try t.log.expected.move(P2.ident(1), Move.DragonRage, P1.ident(1), null);
        try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
        try t.log.expected.faint(P1.ident(1), true);
        try t.log.expected.win(.P2);

        try expectEqual(Result.Lose, try t.update(move(1), move(1)));
        try t.verify();
    }
}

test "fainting (double)" {
    // Switch
    {
        var t = Test(if (showdown)
            (.{ NOP, NOP, HIT, CRIT, MAX_DMG })
        else
            (.{ CRIT, MAX_DMG, HIT })).init(
            &.{
                .{ .species = .Weezing, .hp = 1, .moves = &.{.Explosion} },
                .{ .species = .Koffing, .moves = &.{.SelfDestruct} },
            },
            &.{
                .{ .species = .Weedle, .hp = 1, .moves = &.{.PoisonSting} },
                .{ .species = .Caterpie, .moves = &.{.StringShot} },
            },
        );
        defer t.deinit();

        t.expected.p1.get(1).hp = 0;
        t.expected.p2.get(1).hp = 0;

        try t.log.expected.move(P1.ident(1), Move.Explosion, P2.ident(1), null);
        try t.log.expected.crit(P2.ident(1));
        try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
        try t.log.expected.faint(P2.ident(1), false);
        try t.log.expected.faint(P1.ident(1), true);

        try expectEqual(Result{ .p1 = .Switch, .p2 = .Switch }, try t.update(move(1), move(1)));
        try t.verify();
    }
    // Tie
    {
        var t = Test(if (showdown)
            (.{ NOP, NOP, HIT, CRIT, MAX_DMG })
        else
            (.{ CRIT, MAX_DMG, HIT })).init(
            &.{.{ .species = .Weezing, .hp = 1, .moves = &.{.Explosion} }},
            &.{.{ .species = .Weedle, .hp = 1, .moves = &.{.PoisonSting} }},
        );
        defer t.deinit();

        t.expected.p1.get(1).hp = 0;
        t.expected.p2.get(1).hp = 0;

        try t.log.expected.move(P1.ident(1), Move.Explosion, P2.ident(1), null);
        try t.log.expected.crit(P2.ident(1));
        try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
        try t.log.expected.faint(P2.ident(1), false);
        try t.log.expected.faint(P1.ident(1), false);
        try t.log.expected.tie();

        try expectEqual(Result.Tie, try t.update(move(1), move(1)));
        try t.verify();
    }
}

test "end turn (turn limit)" {
    var t = Test(.{}).init(
        &.{
            .{ .species = .Bulbasaur, .hp = 1, .moves = &.{.Tackle} },
            .{ .species = .Charmander, .moves = &.{.Scratch} },
        },
        &.{
            .{ .species = .Squirtle, .hp = 1, .moves = &.{.Tackle} },
            .{ .species = .Pikachu, .moves = &.{.ThunderShock} },
        },
    );
    defer t.deinit();

    var max: u16 = if (showdown) 1000 else 65535;
    var i: usize = 0;
    while (i < max - 1) : (i += 1) {
        try expectEqual(Result.Default, try t.battle.actual.update(swtch(2), swtch(2), null));
    }
    try expectEqual(max - 1, t.battle.actual.turn);

    const size = if (showdown) 20 else 18;
    var expected_buf: [size]u8 = undefined;
    var actual_buf: [size]u8 = undefined;

    var expected = FixedLog{ .writer = stream(&expected_buf).writer() };
    var actual = FixedLog{ .writer = stream(&actual_buf).writer() };

    const slot = if (showdown) 2 else 1;
    try expected.switched(P1.ident(slot), t.expected.p1.get(slot));
    try expected.switched(P2.ident(slot), t.expected.p2.get(slot));
    if (showdown) try expected.tie();

    const result = if (showdown) Result.Tie else Result.Error;
    try expectEqual(result, try t.battle.actual.update(swtch(2), swtch(2), actual));
    try expectEqual(max, t.battle.actual.turn);
    try expectLog(&expected_buf, &actual_buf);
}

test "Endless Battle Clause (initial)" {
    if (!showdown) return;

    var t = Test(.{}).init(
        &.{.{ .species = .Gengar, .moves = &.{.Tackle} }},
        &.{.{ .species = .Gengar, .moves = &.{.Tackle} }},
    );
    defer t.deinit();

    t.expected.p1.get(1).move(1).pp = 0;
    t.expected.p2.get(1).move(1).pp = 0;

    t.actual.p1.get(1).move(1).pp = 0;
    t.actual.p2.get(1).move(1).pp = 0;

    try t.log.expected.switched(P1.ident(1), t.expected.p1.get(1));
    try t.log.expected.switched(P2.ident(1), t.expected.p2.get(1));
    try t.log.expected.tie();

    try expectEqual(Result.Tie, try t.battle.actual.update(.{}, .{}, t.log.actual));
    try t.verify();
}

test "Endless Battle Clause (basic)" {
    if (!showdown) return;
    return error.SkipZigTest;
}

test "choices" {
    var random = rng.PSRNG.init(0x27182818);
    var battle = Battle.random(&random, false);

    var n = battle.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{
        swtch(2), swtch(3), swtch(4), swtch(5), swtch(6),
        move(1),  move(2),  move(3),  move(4),
    }, choices[0..n]);

    n = battle.choices(.P1, .Switch, &choices);
    try expectEqualSlices(Choice, &[_]Choice{
        swtch(2), swtch(3), swtch(4), swtch(5), swtch(6),
    }, choices[0..n]);

    n = battle.choices(.P1, .Pass, &choices);
    try expectEqualSlices(Choice, &[_]Choice{.{}}, choices[0..n]);
}
// Moves

// Move.{KarateChop,RazorLeaf,Crabhammer,Slash}
test "HighCritical effect" {
    // Has a higher chance for a critical hit.
    const no_crit = if (showdown) comptime ranged(Species.chance(.Machop), 256) else 3;
    var t = Test(if (showdown)
        (.{ NOP, NOP, HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG })
    else
        (.{ no_crit, MIN_DMG, HIT, no_crit, MIN_DMG, HIT })).init(
        &.{.{ .species = .Machop, .moves = &.{.KarateChop} }},
        &.{.{ .species = .Machop, .level = 99, .moves = &.{.Strength} }},
    );
    defer t.deinit();

    t.expected.p1.get(1).hp -= 73;
    t.expected.p2.get(1).hp -= 92;

    try t.log.expected.move(P1.ident(1), Move.KarateChop, P2.ident(1), null);
    try t.log.expected.crit(P2.ident(1));
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.Strength, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.FocusEnergy
test "FocusEnergy effect" {
    // While the user remains active, its chance for a critical hit is quartered. Fails if the user
    // already has the effect. If any Pokemon uses Haze, this effect ends.
    const crit = if (showdown) comptime ranged(Species.chance(.Machoke), 256) - 1 else 2;
    var t = Test(if (showdown)
        (.{ NOP, HIT, crit, MIN_DMG, NOP, HIT, crit, MIN_DMG })
    else
        (.{ ~CRIT, crit, MIN_DMG, HIT, crit, MIN_DMG, HIT, ~CRIT })).init(
        &.{.{ .species = .Machoke, .moves = &.{ .FocusEnergy, .Strength } }},
        &.{.{ .species = .Koffing, .moves = &.{ .DoubleTeam, .Haze } }},
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.FocusEnergy, P1.ident(1), null);
    try t.log.expected.start(P1.ident(1), .FocusEnergy);
    try t.log.expected.move(P2.ident(1), Move.DoubleTeam, P2.ident(1), null);
    try t.log.expected.boost(P2.ident(1), .Evasion, 1);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    t.expected.p2.get(1).hp -= 60;

    try t.log.expected.move(P1.ident(1), Move.Strength, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.Haze, P2.ident(1), null);
    try t.log.expected.activate(P2.ident(1), .Haze);
    try t.log.expected.clearallboost();
    try t.log.expected.end(P1.ident(1), .FocusEnergy);
    try t.log.expected.turn(3);

    // No crit after Focus Energy (https://pkmn.cc/bulba-glitch-1#Critical_hit_ratio_error)
    try expectEqual(Result.Default, try t.update(move(2), move(2)));

    t.expected.p2.get(1).hp -= 115;

    try t.log.expected.move(P1.ident(1), Move.Strength, P2.ident(1), null);
    try t.log.expected.crit(P2.ident(1));
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.DoubleTeam, P2.ident(1), null);
    try t.log.expected.boost(P2.ident(1), .Evasion, 1);
    try t.log.expected.turn(4);

    // Crit once Haze removes Focus Energy
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.verify();
}

// Move.{DoubleSlap,CometPunch,FuryAttack,PinMissile,SpikeCannon,Barrage,FurySwipes}
test "MultiHit effect" {
    // Hits two to five times. Has a 3/8 chance to hit two or three times, and a 1/8 chance to hit
    // four or five times. Damage is calculated once for the first hit and used for every hit. If
    // one of the hits breaks the target's substitute, the move ends.
    return error.SkipZigTest;
}

// Move.{DoubleKick,Bonemerang}
test "DoubleHit effect" {
    // Hits twice. Damage is calculated once for the first hit and used for both hits. If the first
    // hit breaks the target's substitute, the move ends.
    return error.SkipZigTest;
}

// Move.Twineedle
test "Twineedle effect" {
    // Hits twice, with the second hit having a 20% chance to poison the target. If the first hit
    // breaks the target's substitute, the move ends.
    return error.SkipZigTest;
}

// Move.Toxic
// Move.{PoisonPowder,PoisonGas}
test "Poison effect" {
    // (Badly) Poisons the target.
    return error.SkipZigTest;
}

// Move.PoisonSting
// Move.{Smog,Sludge}
test "PoisonChance effect" {
    // Has a X% chance to poison the target.
    return error.SkipZigTest;
}

// Move.{FirePunch,Ember,Flamethrower}: BurnChance1
// Move.FireBlast: BurnChance2
test "BurnChance effect" {
    // Has a X% chance to burn the target.
    return error.SkipZigTest;
}

// Move.{IcePunch,IceBeam,Blizzard}: FreezeChance
test "FreezeChance effect" {
    // Has a 10% chance to freeze the target.
    return error.SkipZigTest;
}

// Move.{ThunderWave,StunSpore,Glare}
test "Paralyze effect" {
    // Paralyzes the target.
    const PROC = comptime ranged(63, 256) - 1;
    const NO_PROC = PROC + 1;
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            NOP, NOP, ~HIT, HIT, NOP,
            NOP, NOP, HIT, NO_PROC, HIT, NOP,
            NOP, PROC,
            NOP, NOP, HIT, NO_PROC, HIT, NOP,
            NOP, NO_PROC,
            NOP, NO_PROC, HIT, NOP,
        } else .{
            ~HIT, HIT,
            NO_PROC, HIT,
            PROC,
            NO_PROC, HIT,
            NO_PROC,
            NO_PROC, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Arbok, .moves = &.{.Glare} },
            .{ .species = .Dugtrio, .moves = &.{ .Earthquake, .Substitute } },
        },
        &.{
            .{ .species = .Magneton, .moves = &.{.ThunderWave} },
            .{ .species = .Gengar, .moves = &.{ .Toxic, .ThunderWave, .Glare } },
        },
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.Glare, P2.ident(1), null);
    try t.log.expected.lastmiss();
    try t.log.expected.miss(P1.ident(1));
    try t.log.expected.move(P2.ident(1), Move.ThunderWave, P1.ident(1), null);
    try t.log.expected.status(P1.ident(1), Status.init(.PAR), .None);
    try t.log.expected.turn(2);

    // Glare can miss
    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try t.log.expected.move(P2.ident(1), Move.ThunderWave, P1.ident(1), null);
    try t.log.expected.fail(P1.ident(1), .Paralysis);
    try t.log.expected.move(P1.ident(1), Move.Glare, P2.ident(1), null);
    try t.log.expected.status(P2.ident(1), Status.init(.PAR), .None);
    try t.log.expected.turn(3);

    // Electric-type Pokémon can be paralyzed
    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.cant(P1.ident(1), .Paralysis);
    try t.log.expected.turn(4);

    // Can be fully paralyzed
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));

    try t.log.expected.move(P2.ident(2), Move.Toxic, P1.ident(1), null);
    try t.log.expected.fail(P1.ident(1), .None);
    try t.log.expected.move(P1.ident(1), Move.Glare, P2.ident(2), null);
    try t.log.expected.status(P2.ident(2), Status.init(.PAR), .None);
    try t.log.expected.turn(5);

    // Glare ignores type immunity
    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
    try t.log.expected.move(P2.ident(2), Move.ThunderWave, P1.ident(2), null);
    try t.log.expected.immune(P1.ident(2), .None);
    try t.log.expected.turn(6);

    // Thunder Wave does not ignore type immunity
    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));

    t.expected.p1.get(2).hp -= 68;

    try t.log.expected.move(P1.ident(2), Move.Substitute, P1.ident(2), null);
    try t.log.expected.start(P1.ident(2), .Substitute);
    try t.log.expected.damage(P1.ident(2), t.expected.p1.get(2), .None);
    try t.log.expected.move(P2.ident(2), Move.Glare, P1.ident(2), null);
    try t.log.expected.status(P1.ident(2), Status.init(.PAR), .None);
    try t.log.expected.turn(7);

    // Primary paralysis ignores Substitute
    try expectEqual(Result.Default, try t.update(move(2), move(3)));

    // // Paralysis lowers speed
    try expectEqual(Status.init(.PAR), t.actual.p2.stored().status);
    try expectEqual(@as(u16, 79), t.actual.p2.active.stats.spe);
    try expectEqual(@as(u16, 318), t.actual.p2.stored().stats.spe);

    try t.verify();
}

// Move.{ThunderPunch,ThunderShock,Thunderbolt,Thunder}: ParalyzeChance1
// Move.{BodySlam,Lick}: ParalyzeChance2
test "ParalyzeChance effect" {
    // Has a X% chance to paralyze the target.
    return error.SkipZigTest;
}

// Move.{Sing,SleepPowder,Hypnosis,LovelyKiss,Spore}
test "Sleep effect" {
    // Causes the target to fall asleep.
    return error.SkipZigTest;
}

// Move.{Supersonic,ConfuseRay}
test "Confusion effect" {
    // Causes the target to become confused.
    return error.SkipZigTest;
}

// Move.{Psybeam,Confusion}: ConfusionChance
test "ConfusionChance effect" {
    // Has a 10% chance to confuse the target.
    return error.SkipZigTest;
}

// Move.{Bite,BoneClub,HyperFang}: FlinchChance1
// Move.{Stomp,RollingKick,Headbutt,LowKick}: FlinchChance2
test "FlinchChance effect" {
    // Has a X% chance to flinch the target.
    return error.SkipZigTest;
}

// Move.Growl: AttackDown1
// Move.{TailWhip,Leer}: DefenseDown1
// Move.StringShot: SpeedDown1
// Move.{SandAttack,Smokescreen,Kinesis,Flash}: AccuracyDown1
// Move.Screech: DefenseDown2
test "StatDown effect" {
    // Lowers the target's X by Y stage(s).
    return error.SkipZigTest;
}

// Move.AuroraBeam: AttackDownChance
// Move.Acid: DefenseDownChance
// Move.{BubbleBeam,Constrict,Bubble}: SpeedDownChance
// Move.Psychic: SpecialDownChance
test "StatDownChance effect" {
    // Has a 33% chance to lower the target's X by 1 stage.
    return error.SkipZigTest;
}

// Move.{Meditate,Sharpen}: AttackUp1
// Move.{Harden,Withdraw,DefenseCurl}: DefenseUp1
// Move.Growth: SpecialUp1
// Move.{DoubleTeam,Minimize}: EvasionUp1
// Move.SwordsDance: AttackUp2
// Move.{Barrier,AcidArmor}: DefenseUp2
// Move.Agility: SpeedUp2
// Move.Amnesia: SpecialUp2
test "StatUp effect" {
    // Raises the target's X by Y stage(s).
    return error.SkipZigTest;
}

// Move.{Guillotine,HornDrill,Fissure}
test "OHKO effect" {
    // Deals 65535 damage to the target. Fails if the target's Speed is greater than the user's.
    var t = Test(if (showdown)
        (.{ NOP, NOP, ~HIT, NOP, NOP, HIT })
    else
        (.{ ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, HIT })).init(
        &.{
            .{ .species = .Kingler, .moves = &.{.Guillotine} },
            .{ .species = .Tauros, .moves = &.{.HornDrill} },
        },
        &.{.{ .species = .Dugtrio, .moves = &.{.Fissure} }},
    );
    defer t.deinit();

    try t.log.expected.move(P2.ident(1), Move.Fissure, P1.ident(1), null);
    try t.log.expected.lastmiss();
    try t.log.expected.miss(P2.ident(1));
    try t.log.expected.move(P1.ident(1), Move.Guillotine, P2.ident(1), null);
    try t.log.expected.immune(P2.ident(1), .OHKO);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    t.expected.p1.get(1).hp = 0;

    try t.log.expected.move(P2.ident(1), Move.Fissure, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.ohko();
    try t.log.expected.faint(P1.ident(1), true);

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.{RazorWind,SolarBeam,SkullBash,SkyAttack}
test "Charge effect" {
    // This attack charges on the first turn and executes on the second.
    return error.SkipZigTest;
}

// Move.{Fly,Dig}
test "Fly / Dig effect" {
    // This attack charges on the first turn and executes on the second. On the first turn, the user
    // avoids all attacks other than Bide, Swift, and Transform. If the user is fully paralyzed on
    // the second turn, it continues avoiding attacks until it switches out or successfully executes
    // the second turn of this move or {Fly,Dig}.
    return error.SkipZigTest;
}

// Move.{Whirlwind,Roar,Teleport}
test "SwitchAndTeleport effect" {
    // No competitive use.
    var t = Test(if (showdown) .{ NOP, HIT, NOP, ~HIT } else .{}).init(
        &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
        &.{.{ .species = .Pidgey, .moves = &.{.Whirlwind} }},
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.Teleport, P1.ident(1), null);
    try t.log.expected.move(P2.ident(1), Move.Whirlwind, P1.ident(1), null);
    try t.log.expected.turn(2);
    try t.log.expected.move(P1.ident(1), Move.Teleport, P1.ident(1), null);
    try t.log.expected.move(P2.ident(1), Move.Whirlwind, P1.ident(1), null);
    if (showdown) {
        try t.log.expected.lastmiss();
        try t.log.expected.miss(P2.ident(1));
    }
    try t.log.expected.turn(3);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.Splash
test "Splash effect" {
    // No competitive use.
    var t = Test(.{}).init(
        &.{.{ .species = .Gyarados, .moves = &.{.Splash} }},
        &.{.{ .species = .Magikarp, .moves = &.{.Splash} }},
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.Splash, P1.ident(1), null);
    try t.log.expected.activate(P1.ident(1), .Splash);
    try t.log.expected.move(P2.ident(1), Move.Splash, P2.ident(1), null);
    try t.log.expected.activate(P2.ident(1), .Splash);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.{Bind,Wrap,FireSpin,Clamp}
test "Trapping effect" {
    // The user spends two to five turns using this move. Has a 3/8 chance to last two or three
    // turns, and a 1/8 chance to last four or five turns. The damage calculated for the first turn
    // is used for every other turn. The user cannot select a move and the target cannot execute a
    // move during the effect, but both may switch out. If the user switches out, the target remains
    // unable to execute a move during that turn. If the target switches out, the user uses this
    // move again automatically, and if it had 0 PP at the time, it becomes 63. If the user or the
    // target switch out, or the user is prevented from moving, the effect ends. This move can
    // prevent the target from moving even if it has type immunity, but will not deal damage.
    return error.SkipZigTest;
}

// Move.{JumpKick,HighJumpKick}
test "JumpKick effect" {
    // If this attack misses the target, the user takes 1 HP of crash damage. If the user has a
    // substitute, the crash damage is dealt to the target's substitute if it has one, otherwise no
    // crash damage is dealt.
    return error.SkipZigTest;
}

// Move.{TakeDown,DoubleEdge,Submission}
test "Recoil effect" {
    // If the target lost HP, the user takes recoil damage equal to 1/4 the HP lost by the target,
    // rounded down, but not less than 1 HP. If this move breaks the target's substitute, the user
    // does not take any recoil damage.
    return error.SkipZigTest;
}

// Move.Struggle
test "Struggle effect" {
    // Deals Normal-type damage. If this move was successful, the user takes damage equal to 1/2 the
    // HP lost by the target, rounded down, but not less than 1 HP. This move is automatically used
    // if none of the user's known moves can be selected.
    return error.SkipZigTest;
}

// Move.{Thrash,PetalDance}
test "Thrashing effect" {
    // Whether or not this move is successful, the user spends three or four turns locked into this
    // move and becomes confused immediately after its move on the last turn of the effect, even if
    // it is already confused. If the user is prevented from moving, the effect ends without causing
    // confusion. During the effect, this move's accuracy is overwritten every turn with the current
    // calculated accuracy including stat stage changes, but not to less than 1/256 or more than
    // 255/256.
    return error.SkipZigTest;
}

// Move.{SonicBoom,DragonRage}
test "FixedDamage effect" {
    // Deals X HP of damage to the target. This move ignores type immunity.
    var t = Test(if (showdown) .{ NOP, NOP, HIT, HIT, NOP } else .{ HIT, HIT, HIT }).init(
        &.{.{ .species = .Voltorb, .moves = &.{.SonicBoom} }},
        &.{
            .{ .species = .Dratini, .moves = &.{.DragonRage} },
            .{ .species = .Gastly, .moves = &.{.NightShade} },
        },
    );
    defer t.deinit();

    t.expected.p1.get(1).hp -= 40;
    t.expected.p2.get(1).hp -= 20;

    try t.log.expected.move(P1.ident(1), Move.SonicBoom, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.DragonRage, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.move(P1.ident(1), Move.SonicBoom, P2.ident(2), null);
    if (showdown) {
        try t.log.expected.immune(P2.ident(2), .None);
    } else {
        t.expected.p2.get(2).hp -= 20;
        try t.log.expected.damage(P2.ident(2), t.expected.p2.get(2), .None);
    }
    try t.log.expected.turn(3);

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.verify();
}

// Move.{SeismicToss,NightShade}
test "LevelDamage effect" {
    // Deals damage to the target equal to the user's level. This move ignores type immunity.
    var t = Test((if (showdown) .{ NOP, NOP, HIT, HIT } else .{ HIT, HIT })).init(
        &.{.{ .species = .Gastly, .level = 22, .moves = &.{.NightShade} }},
        &.{.{ .species = .Clefairy, .level = 16, .moves = &.{.SeismicToss} }},
    );
    defer t.deinit();

    t.expected.p1.get(1).hp -= 16;
    t.expected.p2.get(1).hp -= 22;

    try t.log.expected.move(P1.ident(1), Move.NightShade, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.SeismicToss, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.Psywave
test "Psywave effect" {
    // Deals damage to the target equal to a random number from 1 to (user's level * 1.5 - 1),
    // rounded down, but not less than 1 HP.
    var t = Test((if (showdown)
        (.{ NOP, NOP, HIT, MAX_DMG, HIT, MIN_DMG })
    else
        (.{ HIT, 88, 87, HIT, 255, 0 }))).init(
        &.{.{ .species = .Gengar, .level = 59, .moves = &.{.Psywave} }},
        &.{.{ .species = .Clefable, .level = 42, .moves = &.{.Psywave} }},
    );
    defer t.deinit();

    t.expected.p2.get(1).hp -= 87;

    try t.log.expected.move(P1.ident(1), Move.Psywave, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.Psywave, P1.ident(1), null);

    // https://pkmn.cc/bulba-glitch-1#Psywave_desynchronization
    // https://glitchcity.wiki/Psywave_desync_glitch
    const result = if (showdown) Result.Default else Result.Error;
    if (showdown) try t.log.expected.turn(2);

    try expectEqual(result, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.SuperFang
test "SuperFang effect" {
    // Deals damage to the target equal to half of its current HP, rounded down, but not less than 1
    // HP. This move ignores type immunity.
    var t = Test((if (showdown)
        (.{ NOP, NOP, HIT, HIT, NOP, NOP, HIT })
    else
        (.{ HIT, HIT, ~CRIT, MIN_DMG, HIT }))).init(
        &.{
            .{ .species = .Raticate, .hp = 1, .moves = &.{.SuperFang} },
            .{ .species = .Haunter, .moves = &.{.DreamEater} },
        },
        &.{.{ .species = .Rattata, .moves = &.{.SuperFang} }},
    );
    defer t.deinit();

    t.expected.p1.get(1).hp -= 1;
    t.expected.p2.get(1).hp -= 131;

    try t.log.expected.move(P1.ident(1), Move.SuperFang, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.SuperFang, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    try t.log.expected.faint(P1.ident(1), true);

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));

    try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));

    t.expected.p1.get(2).hp -= 146;

    try t.log.expected.move(P1.ident(2), Move.DreamEater, P2.ident(1), null);
    try t.log.expected.immune(P2.ident(1), .None);
    try t.log.expected.move(P2.ident(1), Move.SuperFang, P1.ident(2), null);
    try t.log.expected.damage(P1.ident(2), t.expected.p1.get(2), .None);
    try t.log.expected.turn(3);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.Disable
test "Disable effect" {
    // For 0 to 7 turns, one of the target's known moves that has at least 1 PP remaining becomes
    // disabled, at random. Fails if one of the target's moves is already disabled, or if none of
    // the target's moves have PP remaining. If any Pokemon uses Haze, this effect ends. Whether or
    // not this move was successful, it counts as a hit for the purposes of the opponent's use of
    // Rage.
    return error.SkipZigTest;
}

// Move.Mist
test "Mist effect" {
    // While the user remains active, it is protected from having its stat stages lowered by other
    // Pokemon, unless caused by the secondary effect of a move. Fails if the user already has the
    // effect. If any Pokemon uses Haze, this effect ends.
    return error.SkipZigTest;
}

// Move.HyperBeam
test "HyperBeam effect" {
    // If this move is successful, the user must recharge on the following turn and cannot select a
    // move, unless the target or its substitute was knocked out by this move.
    return error.SkipZigTest;
}

// Move.Counter
test "Counter effect" {
    // Deals damage to the opposing Pokemon equal to twice the damage dealt by the last move used in
    // the battle. This move ignores type immunity. Fails if the user moves first, or if the
    // opposing side's last move was Counter, had 0 power, or was not Normal or Fighting type. Fails
    // if the last move used by either side did 0 damage and was not Confuse Ray, Conversion, Focus
    // Energy, Glare, Haze, Leech Seed, Light Screen, Mimic, Mist, Poison Gas, Poison Powder,
    // Recover, Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Teleport,
    // Thunder Wave, Toxic, or Transform.
    return error.SkipZigTest;
}

// Move.{Recover,SoftBoiled}
test "Heal effect" {
    // The user restores 1/2 of its maximum HP, rounded down. Fails if (user's maximum HP - user's
    // current HP + 1) is divisible by 256.
    // https://pkmn.cc/bulba-glitch-1#HP_recovery_move_failure
    return error.SkipZigTest;
}

// Move.Rest
test "Heal (Rest) effect" {
    // The user falls asleep for the next two turns and restores all of its HP, curing itself of any
    // non-volatile status condition in the process. This does not remove the user's stat penalty
    // for burn or paralysis. Fails if the user has full HP.
    // https://pkmn.cc/bulba-glitch-1#HP_recovery_move_failure
    return error.SkipZigTest;
}

// Move.{Absorb,MegaDrain,LeechLife}
test "DrainHP effect" {
    // The user recovers 1/2 the HP lost by the target, rounded down.
    return error.SkipZigTest;
}

// Move.DreamEater
test "DreamEater effect" {
    // The target is unaffected by this move unless it is asleep. The user recovers 1/2 the HP lost
    // by the target, rounded down, but not less than 1 HP. If this move breaks the target's
    // substitute, the user does not recover any HP.
    return error.SkipZigTest;
}

// Move.LeechSeed
test "LeechSeed effect" {
    // At the end of each of the target's turns, The Pokemon at the user's position steals 1/16 of
    // the target's maximum HP, rounded down and multiplied by the target's current Toxic counter if
    // it has one, even if the target currently has less than that amount of HP remaining. If the
    // target switches out or any Pokemon uses Haze, this effect ends. Grass-type Pokemon are immune
    // to this move.
    var t = Test((if (showdown)
        (.{ NOP, NOP, ~HIT, NOP, HIT, NOP, NOP, HIT, HIT, NOP, HIT })
    else
        (.{ HIT, ~HIT, HIT, HIT, HIT, HIT }))).init(
        &.{
            .{ .species = .Venusaur, .moves = &.{.LeechSeed} },
            .{ .species = .Exeggutor, .moves = &.{ .LeechSeed, .Teleport } },
        },
        &.{
            .{ .species = .Gengar, .moves = &.{ .LeechSeed, .Substitute, .NightShade } },
            .{ .species = .Slowbro, .hp = 1, .moves = &.{.Teleport} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(P2.ident(1), Move.LeechSeed, P1.ident(1), null);
    if (showdown) {
        try t.log.expected.immune(P1.ident(1), .None);
    } else {
        try t.log.expected.lastmiss();
        try t.log.expected.miss(P2.ident(1));
    }
    try t.log.expected.move(P1.ident(1), Move.LeechSeed, P2.ident(1), null);
    try t.log.expected.lastmiss();
    try t.log.expected.miss(P1.ident(1));
    try t.log.expected.turn(2);

    // Leed Seed can miss / Grass-type Pokémon are immune
    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    t.expected.p2.get(1).hp -= 80;

    try t.log.expected.move(P2.ident(1), Move.Substitute, P2.ident(1), null);
    try t.log.expected.start(P2.ident(1), .Substitute);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.move(P1.ident(1), Move.LeechSeed, P2.ident(1), null);
    try t.log.expected.start(P2.ident(1), .LeechSeed);
    try t.log.expected.turn(3);

    // Leech Seed ignores Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(2)));

    try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
    try t.log.expected.move(P2.ident(1), Move.Substitute, P2.ident(1), null);
    try t.log.expected.fail(P2.ident(1), .Substitute);
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .LeechSeed);
    try t.log.expected.turn(4);

    // Leech Seed does not |-heal| when at full health
    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));

    try t.log.expected.move(P2.ident(1), Move.NightShade, P1.ident(2), null);
    t.expected.p1.get(2).hp -= 100;
    try t.log.expected.damage(P1.ident(2), t.expected.p1.get(2), .None);
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .LeechSeed);
    t.expected.p1.get(2).hp += 20;
    try t.log.expected.heal(P1.ident(2), t.expected.p1.get(2), .Silent);
    try t.log.expected.move(P1.ident(2), Move.LeechSeed, P2.ident(1), null);
    if (!showdown) {
        try t.log.expected.lastmiss();
        try t.log.expected.miss(P1.ident(2));
    }
    try t.log.expected.turn(5);

    // Leech Seed fails if already seeded / heals back damage
    try expectEqual(Result.Default, try t.update(move(1), move(3)));

    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.move(P1.ident(2), Move.LeechSeed, P2.ident(2), null);
    try t.log.expected.start(P2.ident(2), .LeechSeed);
    try t.log.expected.turn(6);

    // Switching breaks Leech Seed
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));

    try t.log.expected.move(P1.ident(2), Move.Teleport, P1.ident(2), null);
    try t.log.expected.move(P2.ident(2), Move.Teleport, P2.ident(2), null);
    t.expected.p2.get(2).hp = 0;
    try t.log.expected.damage(P2.ident(2), t.expected.p2.get(2), .LeechSeed);
    t.expected.p1.get(2).hp += 24;
    try t.log.expected.heal(P1.ident(2), t.expected.p1.get(2), .Silent);
    try t.log.expected.faint(P2.ident(2), true);

    // // Leech Seed's uncapped damage is added back
    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(2), move(1)));
    try t.verify();
}

// Move.PayDay
test "PayDay effect" {
    // "Scatters coins"
    return error.SkipZigTest;
}

// Move.Rage
test "Rage effect" {
    // Once this move is successfully used, the user automatically uses this move every turn and can
    // no longer switch out. During the effect, the user's Attack is raised by 1 stage every time it
    // is hit by the opposing Pokemon, and this move's accuracy is overwritten every turn with the
    // current calculated accuracy including stat stage changes, but not to less than 1/256 or more
    // than 255/256.
    return error.SkipZigTest;
}

// Move.Mimic
test "Mimic effect" {
    // While the user remains active, this move is replaced by a random move known by the target,
    // even if the user already knows that move. The copied move keeps the remaining PP for this
    // move, regardless of the copied move's maximum PP. Whenever one PP is used for a copied move,
    // one PP is used for this move.
    return error.SkipZigTest;
}

// Move.LightScreen
test "LightScreen effect" {
    // While the user remains active, its Special is doubled when taking damage. Critical hits
    // ignore this effect. If any Pokemon uses Haze, this effect ends.
    return error.SkipZigTest;
}

// Move.Reflect
test "Reflect effect" {
    // While the user remains active, its Defense is doubled when taking damage. Critical hits
    // ignore this protection. This effect can be removed by Haze.
    return error.SkipZigTest;
}

// Move.Haze
test "Haze effect" {
    // Resets the stat stages of both Pokemon to 0 and removes stat reductions due to burn and
    // paralysis. Resets Toxic counters to 0 and removes the effect of confusion, Disable, Focus
    // Energy, Leech Seed, Light Screen, Mist, and Reflect from both Pokemon. Removes the opponent's
    // non-volatile status condition.
    return error.SkipZigTest;
}

// Move.Bide
test "Bide effect" {
    // The user spends two or three turns locked into this move and then, on the second or third
    // turn after using this move, the user attacks the opponent, inflicting double the damage in HP
    // it lost during those turns. This move ignores type immunity and cannot be avoided even if the
    // target is using Dig or Fly. The user can choose to switch out during the effect. If the user
    // switches out or is prevented from moving during this move's use, the effect ends. During the
    // effect, if the opposing Pokemon switches out or uses Confuse Ray, Conversion, Focus Energy,
    // Glare, Haze, Leech Seed, Light Screen, Mimic, Mist, Poison Gas, Poison Powder, Recover,
    // Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Teleport, Thunder
    // Wave, Toxic, or Transform, the previous damage dealt to the user will be added to the total.

    // TODO subsequent turn don't decrement PP
    return error.SkipZigTest;
}

// Move.Metronome
test "Metronome effect" {
    // A random move is selected for use, other than Metronome or Struggle.
    return error.SkipZigTest;
}

// Move.MirrorMove
test "MirrorMove effect" {
    // The user uses the last move used by the target. Fails if the target has not made a move, or
    // if the last move used was Mirror Move.
    return error.SkipZigTest;
}

// Move.{SelfDestruct,Explosion}
test "Explode effect" {
    // The user faints after using this move, unless the target's substitute was broken by the
    // damage. The target's Defense is halved during damage calculation.
    return error.SkipZigTest;
}

// Move.Swift
test "Swift effect" {
    // This move does not check accuracy and hits even if the target is using Dig or Fly.
    var t = Test(if (showdown)
        (.{ NOP, NOP, NOP, ~CRIT, MIN_DMG, NOP, NOP }) // FIXME: SSR
    else
        (.{ ~CRIT, MIN_DMG })).init(
        &.{.{ .species = .Eevee, .moves = &.{.Swift} }},
        &.{.{ .species = .Diglett, .moves = &.{.Dig} }},
    );
    defer t.deinit();

    t.expected.p2.get(1).hp -= 91;

    try t.log.expected.move(P2.ident(1), Move.Dig, .{}, null);
    try t.log.expected.prepare(P2.ident(1), Move.Dig);
    try t.log.expected.move(P1.ident(1), Move.Swift, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.Transform
test "Transform effect" {
    // The user transforms into the target. The target's current stats, stat stages, types, moves,
    // DVs, species, and sprite are copied. The user's level and HP remain the same and each copied
    // move receives only 5 PP. This move can hit a target using Dig or Fly.
    return error.SkipZigTest;
}

// Move.Conversion
test "Conversion effect" {
    // Causes the user's types to become the same as the current types of the target.
    var t = Test(if (showdown) .{NOP} else .{}).init(
        &.{.{ .species = .Porygon, .moves = &.{.Conversion} }},
        &.{.{ .species = .Slowbro, .moves = &.{.Teleport} }},
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.Conversion, P2.ident(1), null);
    try t.log.expected.typechange(P1.ident(1), Types{ .type1 = .Water, .type2 = .Psychic });
    try t.log.expected.move(P2.ident(1), Move.Teleport, P2.ident(1), null);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

// Move.Substitute
test "Substitute effect" {
    // The user takes 1/4 of its maximum HP, rounded down, and puts it into a substitute to take its
    // place in battle. The substitute has 1 HP plus the HP used to create it, and is removed once
    // enough damage is inflicted on it or 255 damage is inflicted at once, or if the user switches
    // out or faints. Until the substitute is broken, it receives damage from all attacks made by
    // the opposing Pokemon and shields the user from status effects and stat stage changes caused
    // by the opponent, unless the effect is Disable, Leech Seed, sleep, primary paralysis, or
    // secondary confusion and the user's substitute did not break. The user still takes normal
    // damage from status effects while behind its substitute, unless the effect is confusion
    // damage, which is applied to the opposing Pokemon's substitute instead. If the substitute
    // breaks during a multi-hit attack, the attack ends. Fails if the user does not have enough HP
    // remaining to create a substitute, or if it already has a substitute. The user will create a
    // substitute and then faint if its current HP is exactly 1/4 of its maximum HP.
    return error.SkipZigTest;
}

// Pokémon Showdown Bugs

test "Bide + Substitute bug" {
    return error.SkipZigTest;
}

test "Counter + Substitute bug" {
    // https://www.youtube.com/watch?v=_cEVqYFoBhE
    return error.SkipZigTest;
}

test "Counter + sleep = Desync Clause Mod bug" {
    // TODO
    return error.SkipZigTest;
}

test "Disable duration bug" {
    return error.SkipZigTest;
}

test "Hyper Beam + Substitute bug" {
    return error.SkipZigTest;
}

test "Mimic infinite PP bug" {
    // TODO
    return error.SkipZigTest;
}

test "Mirror Move + Wrap bug" {
    // TODO
    return error.SkipZigTest;
}

test "Mirror Move recharge bug" {
    // TODO
    return error.SkipZigTest;
}

test "Wrap locking + KOs bug" {
    // TODO
    return error.SkipZigTest;
}

// Glitches

test "0 damage glitch" {
    // https://pkmn.cc/bulba-glitch-1#0_damage_glitch
    // https://www.youtube.com/watch?v=fxNzPeLlPTU
    var t = Test(if (showdown)
        (.{ NOP, NOP, NOP, HIT, HIT, ~CRIT, NOP, NOP, HIT, NOP, NOP, NOP, HIT, HIT, ~CRIT })
    else
        (.{ ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT })).init(
        &.{.{ .species = .Bulbasaur, .moves = &.{.Growl} }},
        &.{
            .{ .species = .Bellsprout, .level = 2, .stats = .{}, .moves = &.{.VineWhip} },
            .{ .species = .Chansey, .level = 2, .stats = .{}, .moves = &.{.VineWhip} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.Growl, P2.ident(1), null);
    try t.log.expected.unboost(P2.ident(1), .Attack, 1);
    try t.log.expected.move(P2.ident(1), Move.VineWhip, P1.ident(1), null);
    if (showdown) {
        try t.log.expected.resisted(P1.ident(1));
        t.expected.p1.get(1).hp -= 1;
        try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    } else {
        try t.log.expected.lastmiss();
        try t.log.expected.miss(P2.ident(1));
    }
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));

    try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
    try t.log.expected.move(P1.ident(1), Move.Growl, P2.ident(2), null);
    try t.log.expected.unboost(P2.ident(2), .Attack, 1);
    try t.log.expected.turn(3);

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));

    try t.log.expected.move(P1.ident(1), Move.Growl, P2.ident(2), null);
    try t.log.expected.unboost(P2.ident(2), .Attack, 1);
    try t.log.expected.move(P2.ident(2), Move.VineWhip, P1.ident(1), null);
    if (showdown) {
        try t.log.expected.resisted(P1.ident(1));
        try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
    } else {
        try t.log.expected.lastmiss();
        try t.log.expected.miss(P2.ident(2));
    }
    try t.log.expected.turn(4);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

test "1/256 miss glitch" {
    // https://pkmn.cc/bulba-glitch-1#1.2F256_miss_glitch
    var t = Test(if (showdown)
        (.{ NOP, NOP, ~HIT, ~HIT })
    else
        (.{ CRIT, MAX_DMG, ~HIT, CRIT, MAX_DMG, ~HIT })).init(
        &.{.{ .species = .Jigglypuff, .moves = &.{.Pound} }},
        &.{.{ .species = .NidoranF, .moves = &.{.Scratch} }},
    );
    defer t.deinit();

    try t.log.expected.move(P2.ident(1), Move.Scratch, P1.ident(1), null);
    try t.log.expected.lastmiss();
    try t.log.expected.miss(P2.ident(1));
    try t.log.expected.move(P1.ident(1), Move.Pound, P2.ident(1), null);
    try t.log.expected.lastmiss();
    try t.log.expected.miss(P1.ident(1));
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.verify();
}

test "Bide errors" {
    // https://pkmn.cc/bulba-glitch-1#Bide_errors
    // https://glitchcity.wiki/Bide_fainted_Pokémon_damage_accumulation_glitch
    // https://glitchcity.wiki/Bide_non-damaging_move/action_damage_accumulation_glitch
    // https://www.youtube.com/watch?v=IVxHGyNDW4g
    return error.SkipZigTest;
}

test "Counter glitches" {
    // https://glitchcity.wiki/Counter_glitches_(Generation_I)
    // https://glitchcity.wiki/Counter_glitches_(Generation_I)
    // https://www.youtube.com/watch?v=ftTalHMjPRY
    return error.SkipZigTest;
}

test "Freeze top move selection glitch" {
    // https://glitchcity.wiki/Freeze_top_move_selection_glitch
    return error.SkipZigTest;
}

test "Haze glitch" {
    // https://glitchcity.wiki/Haze_glitch
    // https://www.youtube.com/watch?v=gXQlct-DvVg
    return error.SkipZigTest;
}

test "Toxic counter glitches" {
    // https://pkmn.cc/bulba-glitch-1#Toxic_counter_glitches
    // https://glitchcity.wiki/Leech_Seed_and_Toxic_stacking
    const brn = comptime ranged(77, 256) - 1;
    var t = Test(if (showdown)
        (.{ NOP, HIT, NOP, NOP, NOP, NOP, HIT, NOP, HIT, ~CRIT, MIN_DMG, brn, NOP })
    else
        (.{ HIT, HIT, ~CRIT, MIN_DMG, HIT, brn })).init(
        &.{.{ .species = .Venusaur, .moves = &.{ .Toxic, .LeechSeed, .Teleport, .FireBlast } }},
        &.{.{ .species = .Clefable, .hp = 392, .moves = &.{ .Teleport, .Rest } }},
    );
    defer t.deinit();

    try t.log.expected.move(P1.ident(1), Move.Toxic, P2.ident(1), null);
    try t.log.expected.status(P2.ident(1), Status.init(.PSN), .None);
    try t.log.expected.move(P2.ident(1), Move.Rest, P2.ident(1), null);
    try t.log.expected.statusFrom(P2.ident(1), Status.slf(2), Move.Rest);
    t.expected.p2.get(1).hp += 1;
    t.expected.p2.get(1).status = Status.slf(2);
    try t.log.expected.heal(P2.ident(1), t.expected.p2.get(1), .Silent);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try expectEqual(@as(u4, 0), t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(P1.ident(1), Move.Teleport, P1.ident(1), null);
    try t.log.expected.cant(P2.ident(1), .Sleep);
    try t.log.expected.turn(3);

    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    try expectEqual(@as(u4, 0), t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(P1.ident(1), Move.LeechSeed, P2.ident(1), null);
    try t.log.expected.start(P2.ident(1), .LeechSeed);
    // BUG: Showdown is missing onAfterMoveSelfPriority on sleep condition
    // if (showdown) {
    //     t.expected.p2.get(1).hp -= 24;
    //     try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .LeechSeed);
    //     t.expected.p2.get(1).status = 0;
    //     try t.log.expected.curestatus(P2.ident(1), Status.slp(1), .Message);
    // } else {
    t.expected.p2.get(1).status = 0;
    try t.log.expected.curestatus(P2.ident(1), Status.slf(1), .Message);
    t.expected.p2.get(1).hp -= 24;
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .LeechSeed);
    // }
    try t.log.expected.turn(4);

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try expectEqual(@as(u4, 1), t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(P1.ident(1), Move.FireBlast, P2.ident(1), null);
    t.expected.p2.get(1).hp -= 96;
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
    t.expected.p2.get(1).status = Status.init(.BRN);
    try t.log.expected.status(P2.ident(1), Status.init(.BRN), .None);
    try t.log.expected.move(P2.ident(1), Move.Teleport, P2.ident(1), null);
    t.expected.p2.get(1).hp -= 48;
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .Burn);
    t.expected.p2.get(1).hp -= 72;
    try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .LeechSeed);
    try t.log.expected.turn(5);

    try expectEqual(Result.Default, try t.update(move(4), move(1)));
    try expectEqual(@as(u4, 3), t.actual.p2.active.volatiles.toxic);

    try t.verify();
}

test "Defrost move forcing" {
    // https://pkmn.cc/bulba-glitch-1#Defrost_move_forcing
    return error.SkipZigTest;
}

test "Division by 0" {
    // https://pkmn.cc/bulba-glitch-1#Division_by_0
    return error.SkipZigTest;
}

test "Hyper Beam + Freeze permanent helplessness" {
    // https://pkmn.cc/bulba-glitch-1#Hyper_Beam_.2B_Freeze_permanent_helplessness
    return error.SkipZigTest;
}

test "Hyper Beam + Sleep move glitch" {
    // https://pkmn.cc/bulba-glitch-1#Hyper_Beam_.2B_Sleep_move_glitch
    // https://glitchcity.wiki/Hyper_Beam_sleep_move_glitch
    return error.SkipZigTest;
}

test "Hyper Beam automatic selection glitch" {
    // https://glitchcity.wiki/Hyper_Beam_automatic_selection_glitch
    return error.SkipZigTest;
}

test "Invulnerability glitch" {
    // https://pkmn.cc/bulba-glitch-1#Invulnerability_glitch
    // https://glitchcity.wiki/Invulnerability_glitch
    return error.SkipZigTest;
}

test "Stat modification errors" {
    // https://pkmn.cc/bulba-glitch-1#Stat_modification_errors
    // https://glitchcity.wiki/Stat_modification_glitches
    return error.SkipZigTest;
}

test "Stat down modifier overflow glitch" {
    // https://www.youtube.com/watch?v=y2AOm7r39Jg
}

test "Struggle bypassing / Switch PP underflow" {
    // https://pkmn.cc/bulba-glitch-1#Struggle_bypassing
    // https://glitchcity.wiki/Switch_PP_underflow_glitch
    return error.SkipZigTest;
}

test "Trapping sleep glitch" {
    // https://pkmn.cc/bulba-glitch-1#Trapping_sleep_glitch
    return error.SkipZigTest;
}

test "Partial trapping move Mirror Move glitch" {
    // https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch
    // https://pkmn.cc/bulba-glitch-1##Mirror_Move_glitch
    return error.SkipZigTest;
}

test "Rage and Thrash / Petal Dance accuracy bug" {
    // https://www.youtube.com/watch?v=NC5gbJeExbs
    return error.SkipZigTest;
}

test "Substitute HP drain bug" {
    // https://pkmn.cc/bulba-glitch-1#Substitute_HP_drain_bug
    // https://glitchcity.wiki/Substitute_drain_move_not_missing_glitch
    return error.SkipZigTest;
}

test "Substitute 1/4 HP glitch" {
    // https://glitchcity.wiki/Substitute_%C2%BC_HP_glitch
    return error.SkipZigTest;
}

test "Substitute + Confusion glitch" {
    // https://pkmn.cc/bulba-glitch-1#Substitute_.2B_Confusion_glitch
    // https://glitchcity.wiki/Confusion_and_Substitute_glitch
    return error.SkipZigTest;
}

test "Psywave infinite loop" {
    // https://pkmn.cc/bulba-glitch-1#Psywave_infinite_loop
    var t = Test((if (showdown)
        (.{ NOP, NOP, NOP, HIT, HIT, MAX_DMG })
    else
        (.{ ~CRIT, HIT, HIT }))).init(
        &.{.{ .species = .Charmander, .level = 1, .moves = &.{.Psywave} }},
        &.{.{ .species = .Rattata, .level = 3, .moves = &.{.TailWhip} }},
    );
    defer t.deinit();

    try t.log.expected.move(P2.ident(1), Move.TailWhip, P1.ident(1), null);
    try t.log.expected.unboost(P1.ident(1), .Defense, 1);
    try t.log.expected.move(P1.ident(1), Move.Psywave, P2.ident(1), null);

    const result = if (showdown) Result.Default else Result.Error;
    if (showdown) try t.log.expected.turn(2);

    try expectEqual(result, try t.update(move(1), move(1)));
    try t.verify();
}

// Miscellaneous

// test "MAX_LOGS" {
//     if (showdown) return;

//     const MIRROR_MOVE = @enumToInt(Move.MirrorMove);
//     const CFZ = comptime ranged(128, 256);
//     const NO_CFZ = CFZ - 1;
//     // TODO: replace this with a handcrafted actual seed instead of using the fixed RNG
//     var battle = Battle.fixed(
//         // zig fmt: off
//         .{
//             // Set up
//             HIT,
//             ~CRIT, @enumToInt(Move.LeechSeed), HIT,
//             HIT, 3, NO_CFZ, HIT, 3,
//             NO_CFZ, NO_CFZ, ~CRIT, @enumToInt(Move.SolarBeam),
//             // Scenario
//             NO_CFZ,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, MIRROR_MOVE, ~CRIT,
//             ~CRIT, @enumToInt(Move.PinMissile), CRIT, MIN_DMG, HIT, 3, 3,
//             NO_CFZ, CRIT, MIN_DMG, HIT,
//         },
//          // zig fmt: on
//         &.{
//             .{
//                 .species = .Bulbasaur,
//                 .moves = &.{.LeechSeed},
//             },
//             .{
//                 .species = .Gengar,
//                 .hp = 224,
//                 .status = BRN,
//                 .moves = &.{ .Metronome, .ConfuseRay, .Toxic },
//             },
//         },
//         &.{
//             .{
//                 .species = .Bulbasaur,
//                 .moves = &.{.LeechSeed},
//             },
//             .{
//                 .species = .Gengar,
//                 .status = BRN,
//                 .moves = &.{ .Metronome, .ConfuseRay },
//             },
//         },
//     );
//     battle.side(.P2).get(2).stats.spe = 317; // make P2 slower to avoid speed ties

//     try expectEqual(Result.Default, try battle.update(.{}, .{}, null));
//     // P1 switches into Leech Seed
//     try expectEqual(Result.Default, try battle.update(swtch(2), move(1), null));
//     // P2 switches into to P1's Metronome -> Leech Seed
//     try expectEqual(Result.Default, try battle.update(move(1), swtch(2), null));
//     // P1 and P2 confuse each other
//     try expectEqual(Result.Default, try battle.update(move(2), move(2), null));
//     // P1 uses Toxic to noop while P2 uses Metronome -> Solar Beam
//     try expectEqual(Result.Default, try battle.update(move(3), move(1), null));

//     try expectEqual(Move.SolarBeam, battle.side(.P2).last_selected_move);
//     try expectEqual(Move.Metronome, battle.side(.P2).last_used_move);

//     // BUG: data.MAX_LOGS not enough?
//     var buf: [data.MAX_LOGS * 100]u8 = undefined;
//     var log = FixedLog{ .writer = stream(&buf).writer() };
//     // P1 uses Metronome -> Mirror Move -> ... -> Pin Missile, P2 -> Solar Beam
//     try expectEqual(
//         Result{ .p1 = .Switch, .p2 = .Pass }, try battle.update(move(1), move(0), log));
//     try expect(battle.rng.exhausted());
// }

fn Test(comptime rolls: anytype) type {
    return struct {
        const Self = @This();

        battle: struct {
            expected: data.Battle(rng.FixedRNG(1, rolls.len)),
            actual: data.Battle(rng.FixedRNG(1, rolls.len)),
        },
        buf: struct {
            expected: ArrayList(u8),
            actual: ArrayList(u8),
        },
        log: struct {
            expected: Log(ArrayList(u8).Writer),
            actual: Log(ArrayList(u8).Writer),
        },

        expected: struct {
            p1: *data.Side,
            p2: *data.Side,
        },
        actual: struct {
            p1: *data.Side,
            p2: *data.Side,
        },

        pub fn init(
            pokemon1: []const Pokemon,
            pokemon2: []const Pokemon,
        ) *Self {
            var t = std.testing.allocator.create(Self) catch unreachable;

            t.battle.expected = Battle.fixed(rolls, pokemon1, pokemon2);
            t.battle.actual = t.battle.expected;
            t.buf.expected = std.ArrayList(u8).init(std.testing.allocator);
            t.buf.actual = std.ArrayList(u8).init(std.testing.allocator);
            t.log.expected = Log(ArrayList(u8).Writer){ .writer = t.buf.expected.writer() };
            t.log.actual = Log(ArrayList(u8).Writer){ .writer = t.buf.actual.writer() };

            t.expected.p1 = t.battle.expected.side(.P1);
            t.expected.p2 = t.battle.expected.side(.P2);
            t.actual.p1 = t.battle.actual.side(.P1);
            t.actual.p2 = t.battle.actual.side(.P2);

            return t;
        }

        pub fn deinit(self: *Self) void {
            self.buf.expected.deinit();
            self.buf.actual.deinit();
            std.testing.allocator.destroy(self);
        }

        pub fn start(self: *Self) !void {
            var expected_buf: [22]u8 = undefined;
            var actual_buf: [22]u8 = undefined;

            var expected = FixedLog{ .writer = stream(&expected_buf).writer() };
            var actual = FixedLog{ .writer = stream(&actual_buf).writer() };

            try expected.switched(P1.ident(1), self.actual.p1.get(1));
            try expected.switched(P2.ident(1), self.actual.p2.get(1));
            try expected.turn(1);

            try expectEqual(Result.Default, try self.battle.actual.update(.{}, .{}, actual));
            try expectLog(&expected_buf, &actual_buf);
        }

        pub fn update(self: *Self, c1: Choice, c2: Choice) !Result {
            if (self.battle.actual.turn == 0) try self.start();
            return self.battle.actual.update(c1, c2, self.log.actual);
        }

        pub fn verify(t: *Self) !void {
            for (t.expected.p1.pokemon) |p, i| try expectEqual(p.hp, t.actual.p1.pokemon[i].hp);
            for (t.expected.p2.pokemon) |p, i| try expectEqual(p.hp, t.actual.p2.pokemon[i].hp);
            try expect(t.battle.actual.rng.exhausted());
            if (trace) try expectLog(t.buf.expected.items, t.buf.actual.items);
        }
    };
}

fn expectLog(expected: []const u8, actual: []const u8) !void {
    return protocol.expectLog(formatter, expected, actual);
}

fn formatter(kind: protocol.Kind, byte: u8) []const u8 {
    return switch (kind) {
        .Move => @tagName(@intToEnum(Move, byte)),
        .Species => @tagName(@intToEnum(Species, byte)),
        .Type => @tagName(@intToEnum(Type, byte)),
        .Status => Status.name(byte),
    };
}

comptime {
    _ = @import("data.zig");
    _ = @import("mechanics.zig");
}
