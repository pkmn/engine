const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rational = @import("../common/rational.zig");
const rng = @import("../common/rng.zig");

const calc = @import("calc.zig");
const chance = @import("chance.zig");
const data = @import("data.zig");
const helpers = @import("helpers.zig");

const ArrayList = std.ArrayList;

const assert = std.debug.assert;
const print = std.debug.print;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const showdown = pkmn.options.showdown;
const log = pkmn.options.log;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const ByteStream = protocol.ByteStream;
const FixedLog = protocol.FixedLog;
const Log = protocol.Log;

const Rational = rational.Rational;

const Calc = calc.Calc;
const Chance = chance.Chance;

const Move = data.Move;
const Species = data.Species;
const Status = data.Status;
const Type = data.Type;
const Types = data.Types;
const NULL = data.NULL;

const Battle = helpers.Battle;
const EXP = helpers.EXP;
const move = helpers.move;
const Pokemon = helpers.Pokemon;
const Side = helpers.Side;
const swtch = helpers.swtch;

const CHOICES_SIZE = data.CHOICES_SIZE;

const U = if (showdown) u32 else u8;
const MIN: U = 0;
const MAX: U = std.math.maxInt(U);

const NOP = MIN;
const HIT = MIN;
const CRIT = MIN;
const MIN_DMG = if (showdown) MIN else 179;
const MAX_DMG = MAX;

comptime {
    assert(showdown or std.math.rotr(u8, MIN_DMG, 1) == 217);
    assert(showdown or std.math.rotr(u8, MAX_DMG, 1) == 255);
}

fn ranged(comptime n: u8, comptime d: u9) U {
    return if (showdown) @as(U, n) * (@as(u64, 0x100000000) / @as(U, d)) else n;
}

const P1 = Player.P1;
const P2 = Player.P2;

var choices: [CHOICES_SIZE]Choice = undefined;
const forced = move(@intFromBool(showdown));

// General

test "start (first fainted)" {
    if (showdown) return error.SkipZigTest;

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

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.turn(.{1});

    try expectEqual(Result.Default, try t.battle.actual.update(.{}, .{}, &t.options));
    try t.verify();
}

test "start (all fainted)" {
    if (showdown) return error.SkipZigTest;
    // Win
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Bulbasaur, .moves = &.{.Tackle} }},
            &.{.{ .species = .Charmander, .hp = 0, .moves = &.{.Scratch} }},
        );
        defer t.deinit();

        try expectEqual(Result.Win, try t.battle.actual.update(.{}, .{}, &t.options));
        try t.verify();
    }
    // Lose
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Bulbasaur, .hp = 0, .moves = &.{.Tackle} }},
            &.{.{ .species = .Charmander, .moves = &.{.Scratch} }},
        );
        defer t.deinit();

        try expectEqual(Result.Lose, try t.battle.actual.update(.{}, .{}, &t.options));
        try t.verify();
    }
    // Tie
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Bulbasaur, .hp = 0, .moves = &.{.Tackle} }},
            &.{.{ .species = .Charmander, .hp = 0, .moves = &.{.Scratch} }},
        );
        defer t.deinit();

        try expectEqual(Result.Tie, try t.battle.actual.update(.{}, .{}, &t.options));
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

    try expectEqual(Result.Default, try battle.update(swtch(3), swtch(2), &NULL));
    try expectOrder(p1, &.{ 3, 2, 1, 4, 5, 6 }, p2, &.{ 2, 1, 3, 4, 5, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(5), swtch(5), &NULL));
    try expectOrder(p1, &.{ 5, 2, 1, 4, 3, 6 }, p2, &.{ 5, 1, 3, 4, 2, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(6), swtch(3), &NULL));
    try expectOrder(p1, &.{ 6, 2, 1, 4, 3, 5 }, p2, &.{ 3, 1, 5, 4, 2, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(3), swtch(3), &NULL));
    try expectOrder(p1, &.{ 1, 2, 6, 4, 3, 5 }, p2, &.{ 5, 1, 3, 4, 2, 6 });
    try expectEqual(Result.Default, try battle.update(swtch(2), swtch(4), &NULL));
    try expectOrder(p1, &.{ 2, 1, 6, 4, 3, 5 }, p2, &.{ 4, 1, 3, 5, 2, 6 });

    var expected_buf: [22]u8 = undefined;
    var actual_buf: [22]u8 = undefined;

    var expected_stream: ByteStream = .{ .buffer = &expected_buf };
    var actual_stream: ByteStream = .{ .buffer = &actual_buf };

    const expected: FixedLog = .{ .writer = expected_stream.writer() };
    const actual: FixedLog = .{ .writer = actual_stream.writer() };

    try expected.switched(.{ P1.ident(3), &p1.pokemon[2] });
    try expected.switched(.{ P2.ident(2), &p2.pokemon[1] });
    try expected.turn(.{7});

    var options = pkmn.battle.options(actual, chance.NULL, calc.NULL);
    try expectEqual(Result.Default, try battle.update(swtch(5), swtch(5), &options));
    try expectOrder(p1, &.{ 3, 1, 6, 4, 2, 5 }, p2, &.{ 2, 1, 3, 5, 4, 6 });
    try expectLog(&expected_buf, &actual_buf);
}

fn expectOrder(p1: anytype, o1: []const u8, p2: anytype, o2: []const u8) !void {
    try expectEqualSlices(u8, o1, &p1.order);
    try expectEqualSlices(u8, o2, &p2.order);
}

test "switching (reset)" {
    var t = Test(.{}).init(
        &.{.{ .species = .Abra, .moves = &.{.Splash} }},
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

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try expect(p1.volatiles.Reflect);

    try expectEqual(data.Volatiles{}, p2.volatiles);
    try expectEqual(data.Boosts{}, p2.boosts);
    try expectEqual(0, t.actual.p2.get(1).status);
    try expectEqual(Status.init(.PAR), t.actual.p2.get(2).status);

    try expectEqual(Move.Splash, t.actual.p1.last_used_move);
    try expectEqual(Move.None, t.actual.p2.last_used_move);

    try t.verify();
}

test "switching (brn/par)" {
    var t = Test(.{}).init(
        &.{
            .{ .species = .Pikachu, .moves = &.{.ThunderShock} },
            .{ .species = .Bulbasaur, .status = Status.init(.BRN), .moves = &.{.Tackle} },
        },
        &.{
            .{ .species = .Charmander, .moves = &.{.Scratch} },
            .{ .species = .Squirtle, .status = Status.init(.PAR), .moves = &.{.Tackle} },
        },
    );
    defer t.deinit();

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    t.expected.p1.get(2).hp -= 18;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .Burn });
    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));

    try expectEqual(98, t.actual.p1.active.stats.atk);
    try expectEqual(196, t.actual.p1.stored().stats.atk);
    try expectEqual(46, t.actual.p2.active.stats.spe);
    try expectEqual(184, t.actual.p2.stored().stats.spe);

    try t.verify();
}

test "turn order (priority)" {
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT,
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

    try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 20;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    // Raticate > Chansey
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (242/256) ** 2 * (208/256) * (231/256) * (1/39) ** 2
    try t.expectProbability(1127357, 2617245696);

    try t.log.expected.move(.{ P2.ident(1), Move.QuickAttack, P1.ident(1) });
    t.expected.p1.get(1).hp -= 22;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{3});

    // Chansey > Raticate
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    // (255/256) * (242/256) * (208/256) * (231/256) * (1/39) ** 2
    try t.expectProbability(791945, 1744830464);

    try t.log.expected.move(.{ P1.ident(1), Move.QuickAttack, P2.ident(1) });
    t.expected.p2.get(1).hp -= 104;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.QuickAttack, P1.ident(1) });
    t.expected.p1.get(1).hp -= 22;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{4});

    // Raticate > Chansey
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (255/256) ** 2 * (208/256) * (231/256) * (1/39) ** 2
    try t.expectProbability(1668975, 3489660928);

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 20;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Counter, P2.ident(1) });
    t.expected.p2.get(1).hp -= 40;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{5});

    // Chansey > Raticate
    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    // (242/256) * (255/256) * (231/256) * (1/39)
    try t.expectProbability(2375835, 109051904);
    try t.verify();
}

test "turn order (basic speed tie)" {
    const TIE_1 = MIN;
    const TIE_2 = MAX;
    // Start
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Tauros, .moves = &.{.HyperBeam} }},
            &.{.{ .species = .Tauros, .moves = &.{.HyperBeam} }},
        );
        defer t.deinit();

        try t.log.expected.switched(.{ P1.ident(1), t.actual.p1.get(1) });
        try t.log.expected.switched(.{ P2.ident(1), t.actual.p2.get(1) });
        try t.log.expected.turn(.{1});

        try expectEqual(Result.Default, try t.battle.actual.update(.{}, .{}, &t.options));
        try t.expectProbability(1, 1);

        try t.verify();
    }
    // Move vs. Move
    {
        var t = Test(if (showdown)
            .{ TIE_1, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MAX_DMG }
        else
            .{ TIE_1, ~CRIT, MIN_DMG, HIT, ~CRIT, MAX_DMG, HIT }).init(
            &.{.{ .species = .Tauros, .moves = &.{.HyperBeam} }},
            &.{.{ .species = .Tauros, .moves = &.{.HyperBeam} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
        t.expected.p2.get(1).hp -= 166;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.mustrecharge(.{P1.ident(1)});
        try t.log.expected.move(.{ P2.ident(1), Move.HyperBeam, P1.ident(1) });
        t.expected.p1.get(1).hp -= 196;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.mustrecharge(.{P2.ident(1)});
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        // 1/2 * (229/256) ** 2 * (201/256) ** 2 * (1/39) ** 2
        try t.expectProbability(235407649, 1451698946048);

        try t.verify();
    }
    // Faint vs. Pass
    {
        var t = Test(if (showdown)
            .{ TIE_1, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MAX_DMG }
        else
            .{ TIE_1, ~CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, HIT }).init(
            &.{
                .{ .species = .Tauros, .moves = &.{.HyperBeam} },
                .{ .species = .Tauros, .moves = &.{.HyperBeam} },
            },
            &.{.{ .species = .Tauros, .moves = &.{.HyperBeam} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
        t.expected.p2.get(1).hp -= 166;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.mustrecharge(.{P1.ident(1)});
        try t.log.expected.move(.{ P2.ident(1), Move.HyperBeam, P1.ident(1) });
        try t.log.expected.crit(.{P1.ident(1)});
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.faint(.{ P1.ident(1), true });

        try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
        // 1/2 * (229/256) ** 2 * (201/256) * (55/256) * (1/39) ** 2
        try t.expectProbability(193245085, 4355096838144);

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(swtch(2), .{}));
        try t.expectProbability(1, 1);

        try t.verify();
    }
    // Switch vs. Switch
    {
        var t = Test((if (showdown) .{TIE_2} else .{})).init(
            &.{
                .{ .species = .Zapdos, .moves = &.{.DrillPeck} },
                .{ .species = .Dodrio, .moves = &.{.FuryAttack} },
            },
            &.{
                .{ .species = .Raichu, .moves = &.{.Thunderbolt} },
                .{ .species = .Mew, .moves = &.{.Psychic} },
            },
        );
        defer t.deinit();

        if (showdown) {
            try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
            try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        } else {
            try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
            try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        }
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
        try t.expectProbability(1, if (showdown) 2 else 1);

        try t.verify();
    }
    // Move vs. Switch
    {
        var t = Test(if (showdown) .{ HIT, ~CRIT, MIN_DMG } else .{ ~CRIT, MIN_DMG, HIT }).init(
            &.{
                .{ .species = .Tauros, .moves = &.{.HyperBeam} },
                .{ .species = .Starmie, .moves = &.{.Surf} },
            },
            &.{
                .{ .species = .Tauros, .moves = &.{.HyperBeam} },
                .{ .species = .Alakazam, .moves = &.{.Psychic} },
            },
        );
        defer t.deinit();

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(2) });
        t.expected.p2.get(2).hp -= 255;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.mustrecharge(.{P1.ident(1)});
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
        try t.expectProbability(15343, 851968); // (229/256) * (201/256) * (1/39)

        try t.verify();
    }
}

test "turn order (complex speed tie)" {
    const TIE_1 = MIN;
    const TIE_2 = MAX;
    {
        const fly = comptime metronome(.Fly);
        const dig = comptime metronome(.Dig);
        const swift = comptime metronome(.Swift);
        const petal_dance = comptime metronome(.PetalDance);
        const THRASH_3 = if (showdown) comptime ranged(1, 4 - 2) - 1 else MIN;

        var t = Test(
        // zig fmt: off
            if (showdown) .{
                TIE_2, fly, dig, TIE_1, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
                swift, ~CRIT, MIN_DMG, petal_dance, THRASH_3, HIT, ~CRIT, MIN_DMG,
            } else .{
                TIE_2, ~CRIT, fly, ~CRIT, dig,
                TIE_1, ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, HIT,
                ~CRIT, MIN_DMG, HIT, ~CRIT, swift, ~CRIT, MIN_DMG,
                ~CRIT, petal_dance, THRASH_3, ~CRIT, MIN_DMG, HIT,
            }
        // zig fmt: on
        ).init(
            &.{.{ .species = .Clefable, .moves = &.{ .Metronome, .QuickAttack } }},
            &.{
                .{ .species = .Clefable, .moves = &.{.Metronome} },
                .{ .species = .Farfetchd, .moves = &.{.Metronome} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Fly, ID{}, Move.Metronome });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P2.ident(1), Move.Fly });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Dig, ID{}, Move.Metronome });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P1.ident(1), Move.Dig });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 53138); // (1/2) * (1/163) * (1/163)

        try t.log.expected.move(.{ P1.ident(1), Move.Dig, P2.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(1)});
        try t.log.expected.move(.{ P2.ident(1), Move.Fly, P1.ident(1) });
        t.expected.p1.get(1).hp -= 50;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, forced));
        try t.expectProbability(13673, 1277952); // (1/2) * (226/256) * (242/256) * (1/39)

        try t.log.expected.move(.{ P1.ident(1), Move.QuickAttack, P2.ident(1) });
        t.expected.p2.get(1).hp -= 43;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Swift, P1.ident(1), Move.Metronome });
        t.expected.p1.get(1).hp -= 64;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        // (1/163) * (255/256) * (226/256) ** 2 * (1/39) ** 2
        try t.expectProbability(1085365, 346621476864);

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.PetalDance, P2.ident(2), Move.Metronome });
        try t.log.expected.resisted(.{P2.ident(2)});
        t.expected.p2.get(2).hp -= 32;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
        try t.expectProbability(9605, 69435392); // (1/163) * (255/256) * (226/256) * (1/39)

        try t.verify();
    }
    // beforeTurnMove
    {
        var t = Test(if (showdown) .{ NOP, TIE_1, HIT, HIT } else .{ TIE_1, ~CRIT, ~CRIT }).init(
            &.{.{ .species = .Chansey, .moves = &.{.Counter} }},
            &.{.{ .species = .Chansey, .moves = &.{.Counter} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Counter, P2.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 2);

        try t.verify();
    }
}

test "turn order (switch vs. move)" {
    var t = Test(if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT }).init(
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

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.QuickAttack, P2.ident(2) });
    t.expected.p2.get(2).hp -= 64;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.turn(.{2});

    // Switch > Quick Attack
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(85, 4096); // (255/256) * (208/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(2), Move.QuickAttack, P1.ident(2) });
    t.expected.p1.get(2).hp -= 32;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.turn(.{3});

    // Switch > Quick Attack
    try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
    try t.expectProbability(595, 26624); // (255/256) * (224/256) * (1/39)
    try t.verify();
}

test "PP deduction" {
    var t = Test(.{}).init(
        &.{.{ .species = .Alakazam, .moves = &.{.Teleport} }},
        &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
    );
    defer t.deinit();
    try t.start();

    try expectEqual(32, t.actual.p1.active.move(1).pp);
    try expectEqual(32, t.actual.p1.stored().move(1).pp);
    try expectEqual(32, t.actual.p2.active.move(1).pp);
    try expectEqual(32, t.actual.p2.stored().move(1).pp);

    try expectEqual(Result.Default, try t.battle.actual.update(move(1), move(1), &NULL));

    try expectEqual(31, t.actual.p1.active.move(1).pp);
    try expectEqual(31, t.actual.p1.stored().move(1).pp);
    try expectEqual(31, t.actual.p2.active.move(1).pp);
    try expectEqual(31, t.actual.p2.stored().move(1).pp);

    try expectEqual(Result.Default, try t.battle.actual.update(move(1), move(1), &NULL));

    try expectEqual(30, t.actual.p1.active.move(1).pp);
    try expectEqual(30, t.actual.p1.stored().move(1).pp);
    try expectEqual(30, t.actual.p2.active.move(1).pp);
    try expectEqual(30, t.actual.p2.stored().move(1).pp);
}

test "accuracy (normal)" {
    const hit = comptime ranged(85 * 255 / 100, 256) - 1;
    const miss = hit + 1;

    var t = Test(if (showdown)
        .{ hit, CRIT, MAX_DMG, miss }
    else
        .{ CRIT, MAX_DMG, hit, ~CRIT, MIN_DMG, miss }).init(
        &.{.{ .species = .Hitmonchan, .moves = &.{.MegaPunch} }},
        &.{.{ .species = .Machamp, .moves = &.{.MegaPunch} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.MegaPunch, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 159;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.MegaPunch, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(855, 1703936); // (216/256) * (40/256) * (38/256) * (1/39)
    try t.verify();
}

test "damage calc" {
    const NO_BRN = MAX;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, NO_BRN, HIT, ~CRIT, MIN_DMG
        } else .{
            ~CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, HIT, NO_BRN, ~CRIT, HIT, ~CRIT, MIN_DMG, HIT
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Starmie, .moves = &.{ .WaterGun, .Thunderbolt } }},
        &.{.{ .species = .Golem, .moves = &.{ .FireBlast, .Strength } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.WaterGun, P2.ident(1) });
    try t.log.expected.supereffective(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 248;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.FireBlast, P1.ident(1) });
    try t.log.expected.crit(.{P1.ident(1)});
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 70;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    // STAB super effective non-critical min damage vs. non-STAB resisted critical max damage
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) * (216/256) * (199/256) * (22/256) * (1/39) ** 2 * (179/256)
    try t.expectProbability(299750715, 11613591568384);

    try t.log.expected.move(.{ P1.ident(1), Move.Thunderbolt, P2.ident(1) });
    try t.log.expected.immune(.{ P2.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Strength, P1.ident(1) });
    t.expected.p1.get(1).hp -= 68;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    // immune vs. normal
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(765, 32768); // (255/256) * (234/256) * (1/39)
    try t.verify();
}

test "type precedence" {
    const NO_PROC = MAX;
    var t = Test((if (showdown)
        .{ HIT, HIT, ~CRIT, MAX_DMG, NO_PROC }
    else
        .{ ~CRIT, HIT, ~CRIT, MAX_DMG, HIT })).init(
        &.{.{ .species = .Sandshrew, .moves = &.{.PoisonSting} }},
        &.{.{ .species = .Weedle, .moves = &.{.StringShot} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.StringShot, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, -1 });
    try t.log.expected.move(.{ P1.ident(1), Move.PoisonSting, P2.ident(1) });
    t.expected.p2.get(1).hp -= if (showdown) 21 else 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(606815, 27262976); // (242/256) * (255/256) * (236/256) * (1/39)
    try t.verify();
}

test "fainting (single)" {
    const BRN = Status.init(.BRN);
    // Switch
    {
        var t = Test(if (showdown)
            .{ HIT, HIT, ~CRIT, MAX_DMG }
        else
            .{ HIT, ~CRIT, MAX_DMG, HIT }).init(
            &.{.{ .species = .Venusaur, .moves = &.{.LeechSeed} }},
            &.{
                .{ .species = .Slowpoke, .hp = 1, .moves = &.{.WaterGun} },
                .{ .species = .Dratini, .moves = &.{.DragonRage} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
        try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
        try t.log.expected.resisted(.{P1.ident(1)});
        t.expected.p1.get(1).hp -= 15;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
        t.expected.p1.get(1).hp += 15;
        try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(1), move(1)));
        try t.expectProbability(4846785, 218103808); // (229/256) * (255/256) * (249/256) * (1/39)

        var n = t.battle.actual.choices(.P1, .Pass, &choices);
        try expectEqualSlices(Choice, &[_]Choice{.{}}, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Switch, &choices);
        try expectEqualSlices(Choice, &[_]Choice{swtch(2)}, choices[0..n]);

        try t.verify();
    }
    // Win
    {
        var t = Test(.{HIT}).init(
            &.{.{ .species = .Dratini, .hp = 1, .status = BRN, .moves = &.{.DragonRage} }},
            &.{.{ .species = .Slowpoke, .hp = 1, .moves = &.{.WaterGun} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.DragonRage, P2.ident(1) });
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.faint(.{ P2.ident(1), false });
        try t.log.expected.win(.{.P1});

        try expectEqual(Result.Win, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);
        try t.verify();
    }
    // Lose
    {
        var t = Test(.{ ~CRIT, MIN_DMG, HIT }).init(
            &.{.{ .species = .Jolteon, .hp = 1, .moves = &.{.Swift} }},
            &.{.{ .species = .Dratini, .status = BRN, .moves = &.{.DragonRage} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Swift, P2.ident(1) });
        t.expected.p2.get(1).hp -= 53;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.DragonRage, P1.ident(1) });
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.faint(.{ P1.ident(1), false });
        try t.log.expected.win(.{.P2});

        try expectEqual(Result.Lose, try t.update(move(1), move(1)));
        try t.expectProbability(16235, 851968); // (255/256) * (191/256) * (1/39)
        try t.verify();
    }
}

test "fainting (double)" {
    // Switch
    {
        var t = Test(if (showdown) .{ HIT, CRIT, MAX_DMG } else .{ CRIT, MAX_DMG, HIT }).init(
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

        try t.log.expected.move(.{ P1.ident(1), Move.Explosion, P2.ident(1) });
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.crit(.{P2.ident(1)});
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.faint(.{ P2.ident(1), false });
        try t.log.expected.faint(.{ P1.ident(1), true });

        try expectEqual(Result{ .p1 = .Switch, .p2 = .Switch }, try t.update(move(1), move(1)));
        try t.expectProbability(1275, 425984); // (255/256) * (30/256) * (1/39)

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
        try t.expectProbability(1, 1);
        try t.verify();
    }
    // Switch (boosted)
    {
        var t = Test(if (showdown)
            .{ HIT, ~CRIT, MAX_DMG }
        else
            .{ ~CRIT, ~CRIT, MAX_DMG, HIT }).init(
            &.{
                .{ .species = .Farfetchd, .moves = &.{ .Agility, .Splash } },
                .{ .species = .Cubone, .moves = &.{.BoneClub} },
            },
            &.{
                .{ .species = .Charmeleon, .moves = &.{ .Splash, .Explosion } },
                .{ .species = .Pikachu, .moves = &.{.Surf} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(2, t.actual.p1.active.boosts.spe);

        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.move(.{ P2.ident(1), Move.Explosion, P1.ident(1) });
        t.expected.p2.get(1).hp = 0;
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.faint(.{ P1.ident(1), false });
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Switch, .p2 = .Switch }, try t.update(move(2), move(2)));
        try t.expectProbability(2295, 106496); // (255/256) * (216/256) * (1/39)

        if (showdown) {
            try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
            try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        } else {
            try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
            try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        }
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
        try t.expectProbability(1, 1);
        try t.verify();
    }
    // Switch (paralyzed)
    {
        const PAR_CAN = MAX;
        var t = Test(if (showdown)
            .{ HIT, PAR_CAN, HIT, ~CRIT, MAX_DMG }
        else
            .{ HIT, PAR_CAN, ~CRIT, MAX_DMG, HIT }).init(
            &.{
                .{ .species = .Farfetchd, .moves = &.{ .ThunderWave, .Splash } },
                .{ .species = .Cubone, .moves = &.{.BoneClub} },
            },
            &.{
                .{ .species = .Charmeleon, .moves = &.{ .Splash, .Explosion } },
                .{ .species = .Pikachu, .moves = &.{.Surf} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.ThunderWave, P2.ident(1) });
        t.expected.p2.get(1).status = Status.init(.PAR);
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);
        try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.move(.{ P2.ident(1), Move.Explosion, P1.ident(1) });
        t.expected.p2.get(1).status = 0;
        t.expected.p2.get(1).hp = 0;
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.faint(.{ P1.ident(1), false });
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Switch, .p2 = .Switch }, try t.update(move(2), move(2)));
        try t.expectProbability(6885, 425984); // (3/4) * (255/256) * (216/256) * (1/39)

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
        try t.expectProbability(1, 1);
        try t.verify();
    }
    // Tie
    {
        var t = Test(if (showdown) .{ HIT, CRIT, MAX_DMG } else .{ CRIT, MAX_DMG, HIT }).init(
            &.{.{ .species = .Weezing, .hp = 1, .moves = &.{.Explosion} }},
            &.{.{ .species = .Weedle, .hp = 1, .moves = &.{.PoisonSting} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Explosion, P2.ident(1) });
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.crit(.{P2.ident(1)});
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.faint(.{ P2.ident(1), false });
        try t.log.expected.faint(.{ P1.ident(1), false });
        try t.log.expected.tie(.{});

        try expectEqual(Result.Tie, try t.update(move(1), move(1)));
        try t.expectProbability(1275, 425984); // (255/256) * (30/256) * (1/39)
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

    const max: u16 = if (showdown) 1000 else 65535;
    for (0..(max - 1)) |_| {
        try expectEqual(Result.Default, try t.battle.actual.update(swtch(2), swtch(2), &NULL));
    }
    try expectEqual(max - 1, t.battle.actual.turn);

    const size = if (showdown) 20 else 18;
    var expected_buf: [size]u8 = undefined;
    var actual_buf: [size]u8 = undefined;

    var expected_stream: ByteStream = .{ .buffer = &expected_buf };
    var actual_stream: ByteStream = .{ .buffer = &actual_buf };

    const expected: FixedLog = .{ .writer = expected_stream.writer() };
    const actual: FixedLog = .{ .writer = actual_stream.writer() };

    const slot = if (showdown) 2 else 1;
    try expected.switched(.{ P1.ident(slot), t.expected.p1.get(slot) });
    try expected.switched(.{ P2.ident(slot), t.expected.p2.get(slot) });
    if (showdown) try expected.tie(.{});

    const result = if (showdown) Result.Tie else Result.Error;
    var options = pkmn.battle.options(actual, chance.NULL, calc.NULL);
    try expectEqual(result, try t.battle.actual.update(swtch(2), swtch(2), &options));
    try expectEqual(max, t.battle.actual.turn);
    try expectLog(&expected_buf, &actual_buf);
}

test "Endless Battle Clause (initial)" {
    if (!showdown) return error.SkipZigTest;

    var t = Test(.{}).init(
        &.{.{ .species = .Gengar, .moves = &.{.Tackle} }},
        &.{.{ .species = .Gengar, .moves = &.{.Tackle} }},
    );
    defer t.deinit();

    t.actual.p1.get(1).move(1).pp = 0;
    t.actual.p2.get(1).move(1).pp = 0;

    try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
    try t.log.expected.switched(.{ P2.ident(1), t.expected.p2.get(1) });
    try t.log.expected.tie(.{});

    try expectEqual(Result.Tie, try t.battle.actual.update(.{}, .{}, &t.options));
    try t.verify();
}

test "Endless Battle Clause (basic)" {
    if (!showdown) return error.SkipZigTest;
    {
        var t = Test(.{}).init(
            &.{.{ .species = .Mew, .moves = &.{.Transform} }},
            &.{.{ .species = .Ditto, .moves = &.{.Transform} }},
        );
        defer t.deinit();

        t.expected.p1.get(1).move(1).pp = 0;
        t.expected.p2.get(1).move(1).pp = 0;

        t.actual.p1.get(1).move(1).pp = 0;
        t.actual.p2.get(1).move(1).pp = 0;

        try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
        try t.log.expected.switched(.{ P2.ident(1), t.expected.p2.get(1) });
        try t.log.expected.tie(.{});

        try expectEqual(Result.Tie, try t.battle.actual.update(.{}, .{}, &t.options));
        try t.verify();
    }
    {
        var t = Test(.{}).init(
            &.{
                .{ .species = .Mew, .moves = &.{.Transform} },
                .{ .species = .Muk, .moves = &.{.Pound} },
            },
            &.{.{ .species = .Ditto, .moves = &.{.Transform} }},
        );
        defer t.deinit();

        try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
        try t.log.expected.switched(.{ P2.ident(1), t.expected.p2.get(1) });
        try t.log.expected.turn(.{1});

        try expectEqual(Result.Default, try t.battle.actual.update(.{}, .{}, &t.options));

        t.expected.p1.get(2).hp = 0;
        t.actual.p1.get(2).hp = 0;

        try t.log.expected.move(.{ P1.ident(1), Move.Transform, P2.ident(1) });
        try t.log.expected.transform(.{ P1.ident(1), P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Transform, P1.ident(1) });
        try t.log.expected.transform(.{ P2.ident(1), P1.ident(1) });
        try t.log.expected.tie(.{});

        try expectEqual(Result.Tie, try t.update(move(1), move(1)));
        try t.verify();
    }
}

test "choices" {
    var random = rng.PSRNG.init(0x27182818);
    var battle = Battle.random(&random, .{});
    try expectEqual(Result.Default, try battle.update(.{}, .{}, &NULL));

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
        .{ HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG }
    else
        .{ no_crit, MIN_DMG, HIT, no_crit, MIN_DMG, HIT }).init(
        &.{.{ .species = .Machop, .moves = &.{.KarateChop} }},
        &.{.{ .species = .Machop, .level = 99, .moves = &.{.Strength} }},
    );
    defer t.deinit();

    t.expected.p1.get(1).hp -= 73;
    t.expected.p2.get(1).hp -= 92;

    try t.log.expected.move(.{ P1.ident(1), Move.KarateChop, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Strength, P1.ident(1) });
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (136/256) * (239/256) * (1/39) ** 2
    try t.expectProbability(29355175, 90731184128);
    try t.verify();
}

// Move.FocusEnergy
test "FocusEnergy effect" {
    // While the user remains active, its chance for a critical hit is quartered. Fails if the user
    // already has the effect. If any Pokemon uses Haze, this effect ends.
    const crit = if (showdown) comptime ranged(Species.chance(.Machoke), 256) - 1 else 2;

    var t = Test(if (showdown)
        .{ HIT, crit, MIN_DMG, HIT, crit, MIN_DMG }
    else
        .{ ~CRIT, crit, MIN_DMG, HIT, crit, MIN_DMG, HIT, ~CRIT }).init(
        &.{.{ .species = .Machoke, .moves = &.{ .FocusEnergy, .Strength } }},
        &.{.{ .species = .Koffing, .moves = &.{ .DoubleTeam, .Haze } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.FocusEnergy, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .FocusEnergy });
    try t.log.expected.move(.{ P2.ident(1), Move.DoubleTeam, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Evasion, 1 });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.Strength, P2.ident(1) });
    t.expected.p2.get(1).hp -= 60;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Haze, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    try t.log.expected.end(.{ P1.ident(1), .FocusEnergySilent });
    try t.log.expected.turn(.{3});

    // No crit after Focus Energy (https://pkmn.cc/bulba-glitch-1#Critical_hit_ratio_error)
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(1757, 106496); // (168/256) * (251/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Strength, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 115;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.DoubleTeam, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Evasion, 1 });
    try t.log.expected.turn(.{4});

    // Crit once Haze removes Focus Energy
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(935, 425984); // (255/256) * (22/256) * (1/39)
    try t.verify();
}

// Move.{DoubleSlap,CometPunch,FuryAttack,PinMissile,SpikeCannon,Barrage,FurySwipes}
test "MultiHit effect" {
    // Hits two to five times. Has a 3/8 chance to hit two or three times, and a 1/8 chance to hit
    // four or five times. Damage is calculated once for the first hit and used for every hit. If
    // one of the hits breaks the target's substitute, the move ends.
    const hit3 = if (showdown) 0x60000000 else 1;
    const hit5 = MAX;

    var t = Test(if (showdown)
        .{ HIT, hit3, ~CRIT, MAX_DMG, HIT, hit5, ~CRIT, MAX_DMG }
    else
        .{ ~CRIT, MAX_DMG, HIT, hit3, ~CRIT, MAX_DMG, HIT, hit5, hit5 }).init(
        &.{.{ .species = .Kangaskhan, .moves = &.{.CometPunch} }},
        &.{.{ .species = .Slowpoke, .moves = &.{ .Substitute, .Splash } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.CometPunch, P2.ident(1) });
    t.expected.p2.get(1).hp -= 31;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 31;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 31;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.hitcount(.{ P2.ident(1), 3 });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 95;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(5697, 851968); // (216/256) * (211/256) * (1/39) * (3/8)

    try t.log.expected.move(.{ P1.ident(1), Move.CometPunch, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.hitcount(.{ P2.ident(1), 4 });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    // Breaking a target's Substitute ends the move
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(1899, 851968); // (216/256) * (211/256) * (1/39) * (1/8)
    try t.verify();
}

// Move.{DoubleKick,Bonemerang}
test "DoubleHit effect" {
    // Hits twice. Damage is calculated once for the first hit and used for both hits. If the first
    // hit breaks the target's substitute, the move ends.
    var t = Test(if (showdown)
        .{ HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG }
    else
        .{ ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT }).init(
        &.{.{ .species = .Marowak, .moves = &.{.Bonemerang} }},
        &.{.{ .species = .Slowpoke, .level = 80, .moves = &.{ .Substitute, .Splash } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Bonemerang, P2.ident(1) });
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.hitcount(.{ P2.ident(1), 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 77;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(687, 32768); // (229/256) * (234/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Bonemerang, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.hitcount(.{ P2.ident(1), 1 });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    // Breaking a target's Substitute ends the move
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(687, 32768); // (229/256) * (234/256) * (1/39)
    try t.verify();
}

// Move.Twineedle
test "Twineedle effect" {
    // Hits twice, with the second hit having a 20% chance to poison the target. If the first hit
    // breaks the target's substitute, the move ends.
    const PROC = comptime ranged(52, 256) - 1;
    const NO_PROC = PROC + 1;
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, CRIT, MAX_DMG,
            HIT, ~CRIT, MIN_DMG, NO_PROC,
            HIT, ~CRIT, MIN_DMG, PROC,
            HIT, ~CRIT, MIN_DMG, PROC,
        } else .{
            CRIT, MAX_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, NO_PROC,
            ~CRIT, MIN_DMG, HIT, PROC,
            ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Beedrill, .moves = &.{.Twineedle} }},
        &.{
            .{ .species = .Voltorb, .moves = &.{ .Substitute, .Splash } },
            .{ .species = .Weezing, .moves = &.{.Explosion} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 70;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Twineedle, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.hitcount(.{ P2.ident(1), 1 });
    try t.log.expected.turn(.{2});

    // Breaking a target's Substitute ends the move
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(3145, 851968); // (255/256) * (37/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.move(.{ P1.ident(1), Move.Twineedle, P2.ident(1) });
    t.expected.p2.get(1).hp -= 36;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 36;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.hitcount(.{ P2.ident(1), 2 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(949365, 54525952); // (255/256) * (219/256) * (1/39) * (204/256)
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.move(.{ P1.ident(1), Move.Twineedle, P2.ident(1) });
    t.expected.p2.get(1).hp -= 36;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 36;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.PSN);
    if (showdown) {
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.hitcount(.{ P2.ident(1), 2 });
    } else {
        try t.log.expected.hitcount(.{ P2.ident(1), 2 });
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    }
    try t.log.expected.turn(.{4});

    // The second hit can always poison the target
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(18615, 4194304); // (255/256) * (219/256) * (1/39) * (52/256)
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.Twineedle, P2.ident(2) });
    try t.log.expected.supereffective(.{P2.ident(2)});
    t.expected.p2.get(2).hp -= 45;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    t.expected.p2.get(2).hp -= 45;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.hitcount(.{ P2.ident(2), 2 });
    try t.log.expected.turn(.{5});

    // Poison types cannot be poisoned
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(18615, 851968); // (255/256) * (219/256) * (1/39)
    try t.verify();
}

// Move.Toxic
// Move.{PoisonPowder,PoisonGas}
test "Poison effect" {
    // (Badly) Poisons the target.
    {
        var t = Test((if (showdown) .{ HIT, HIT, HIT, HIT } else .{ HIT, HIT })).init(
            &.{
                .{ .species = .Jolteon, .moves = &.{ .Toxic, .Substitute } },
                .{ .species = .Abra, .moves = &.{.Splash} },
            },
            &.{
                .{ .species = .Venomoth, .moves = &.{ .Splash, .Toxic } },
                .{ .species = .Drowzee, .moves = &.{ .PoisonGas, .Splash } },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
        try t.log.expected.immune(.{ P2.ident(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.turn(.{2});

        // Poison-type Pokémon cannot be poisoned
        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Substitute });
        t.expected.p1.get(1).hp -= 83;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Toxic, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{3});

        // Substitute blocks poison
        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try expectEqual(0, t.actual.p1.get(1).status);
        try t.expectProbability(1, 1);

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(2) });
        t.expected.p2.get(2).status = if (showdown) Status.TOX else Status.init(.PSN);
        try t.log.expected.status(.{ P2.ident(2), t.expected.p2.get(2).status, .None });
        try t.log.expected.turn(.{4});

        // Toxic damage increases each turn
        try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
        try expectEqual(t.expected.p2.get(2).status, t.actual.p2.get(1).status);
        try t.expectProbability(27, 32); // (216/256)
        try expect(t.actual.p2.active.volatiles.Toxic);

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.move(.{ P2.ident(2), Move.PoisonGas, P1.ident(2) });
        t.expected.p1.get(2).status = Status.init(.PSN);
        try t.log.expected.status(.{ P1.ident(2), t.expected.p1.get(2).status, .None });
        t.expected.p2.get(2).hp -= 20;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .Poison });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
        try t.expectProbability(35, 64);
        try expectEqual(t.expected.p1.get(2).status, t.actual.p1.get(1).status);

        try t.log.expected.move(.{ P1.ident(2), Move.Splash, P1.ident(2) });
        try t.log.expected.activate(.{ P1.ident(2), .Splash });
        t.expected.p1.get(2).hp -= 15;
        try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .Poison });
        try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
        try t.log.expected.activate(.{ P2.ident(2), .Splash });
        t.expected.p2.get(2).hp -= 40;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .Poison });
        try t.log.expected.turn(.{6});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P1.ident(2), Move.Splash, P1.ident(2) });
        try t.log.expected.activate(.{ P1.ident(2), .Splash });
        t.expected.p1.get(2).hp -= 15;
        try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .Poison });
        try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
        try t.log.expected.activate(.{ P2.ident(2), .Splash });
        t.expected.p2.get(2).hp -= 60;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .Poison });
        try t.log.expected.turn(.{7});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(1, 1);
        try t.verify();
    }
    {
        var battle = Battle.fixed(
            .{ HIT, HIT },
            &.{.{ .species = .Clefable, .moves = &.{ .Toxic, .Recover } }},
            &.{.{
                .species = .Diglett,
                .level = 14,
                .stats = .{},
                .moves = &.{ .LeechSeed, .Recover },
            }},
        );
        try expectEqual(Result.Default, try battle.update(.{}, .{}, &NULL));
        try expectEqual(31, battle.side(.P2).active.stats.hp);

        try expectEqual(Result.Default, try battle.update(move(1), move(1), &NULL));
        for (0..29) |_| try expectEqual(Result.Default, try battle.update(move(2), move(2), &NULL));
        try expectEqual(30, battle.side(.P2).active.volatiles.toxic);

        try expectEqual(Result.Win, try battle.update(move(2), move(2), &NULL));
        try expect(battle.rng.exhausted());
    }
}

// Move.PoisonSting
// Move.{Smog,Sludge}
test "PoisonChance effect" {
    // Has a X% chance to poison the target.
    const LO_PROC = comptime ranged(52, 256) - 1;
    const HI_PROC = comptime ranged(103, 256) - 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, LO_PROC, HIT, ~CRIT, MIN_DMG, HI_PROC,
            HIT, ~CRIT, MAX_DMG,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, LO_PROC,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, LO_PROC,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, HI_PROC,
            ~CRIT, MAX_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, LO_PROC,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Tentacruel, .moves = &.{ .PoisonSting, .Sludge } }},
        &.{.{ .species = .Persian, .moves = &.{ .Substitute, .PoisonSting, .Scratch } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.PoisonSting, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 5;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.PoisonSting, P2.ident(1) });
    t.expected.p2.get(1).hp -= 18;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    // Can't poison Poison-types / moves have different poison chances
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    // (255/256) ** 2 * (199/256) * (206/256) * (1/39) ** 2 * (204/256)
    try t.expectProbability(7552632075, 23227183136768);
    try expectEqual(0, t.actual.p1.get(1).status);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 83;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Sludge, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{3});

    // Substitute prevents poison chance
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (255/256) * (206/256) * (1/39)
    try t.expectProbability(8755, 425984);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Scratch, P1.ident(1) });
    t.expected.p1.get(1).hp -= 46;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.PoisonSting, P2.ident(1) });
    t.expected.p2.get(1).hp -= 18;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.PSN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    // (255/256) ** 2 * (199/256) * (206/256) * (1/39) ** 2 * (52/256)
    try t.expectProbability(148090825, 1786706395136);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Scratch, P1.ident(1) });
    t.expected.p1.get(1).hp -= 46;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.move(.{ P1.ident(1), Move.PoisonSting, P2.ident(1) });
    t.expected.p2.get(1).hp -= 18;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{5});

    // Can't poison already poisoned Pokémon / poison causes residual damage
    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    // (255/256) ** 2 * (199/256) * (206/256) * (1/39) ** 2
    try t.expectProbability(148090825, 362924736512);
    try t.verify();
}

// Move.{FirePunch,Ember,Flamethrower}: BurnChance1
// Move.FireBlast: BurnChance2
test "BurnChance effect" {
    // Has a X% chance to burn the target.
    const LO_PROC = comptime ranged(26, 256) - 1;
    const HI_PROC = comptime ranged(77, 256) - 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HI_PROC,
            HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, LO_PROC,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, LO_PROC,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, HI_PROC,
            ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, LO_PROC,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Charizard, .moves = &.{ .Ember, .FireBlast } }},
        &.{.{ .species = .Tauros, .moves = &.{ .Substitute, .FireBlast, .Tackle } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.FireBlast, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 38;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Ember, P2.ident(1) });
    t.expected.p2.get(1).hp -= 51;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    // Can't burn Fire-types / moves have different burn chances
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    // (216/256) * (255/256) * (201/256) * (206/256) * (1/39) ** 2 * (230/256)
    try t.expectProbability(1821346425, 5806795784192);
    try expectEqual(0, t.actual.p1.get(1).status);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 88;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.FireBlast, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{3});

    // Substitute prevents burn chance
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (216/256) * (206/256) * (1/39)
    try t.expectProbability(927, 53248);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 45;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Ember, P2.ident(1) });
    t.expected.p2.get(1).hp -= 51;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.BRN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    // (242/256) * (255/256) * (201/256) * (206/256) * (1/39) ** 2 * (26/256)
    try t.expectProbability(70976785, 1786706395136);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 23;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    try t.log.expected.move(.{ P1.ident(1), Move.Ember, P2.ident(1) });
    t.expected.p2.get(1).hp -= 51;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{5});

    // Can't burn already burnt Pokémon / Burn lowers attack and causes residual damage
    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    // (242/256) * (255/256) * (201/256) * (206/256) * (1/39) ** 2
    try t.expectProbability(70976785, 181462368256);
    try t.verify();
}

// Move.{IcePunch,IceBeam,Blizzard}: FreezeChance
test "FreezeChance effect" {
    // Has a 10% chance to freeze the target.
    const FRZ = comptime ranged(26, 256) - 1;
    const PAR_CANT = MIN;
    const MIN_WRAP = MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT,
            HIT, ~CRIT, MIN_DMG, FRZ, PAR_CANT,
            HIT, ~CRIT, MIN_DMG, FRZ,
            HIT,
            HIT, ~CRIT, MIN_DMG, FRZ,
            HIT, ~CRIT, MIN_DMG, MIN_WRAP,
            HIT, ~CRIT, MIN_DMG, ~HIT,
            ~HIT,
            HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, MIN_DMG, HIT, HIT,
            ~CRIT, MIN_DMG, HIT, PAR_CANT,
            ~CRIT, MIN_DMG, HIT, FRZ,
            ~CRIT, MIN_DMG, HIT, FRZ,
            MIN_WRAP, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, ~HIT,
            ~CRIT, MIN_DMG, ~HIT,
            ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Starmie, .moves = &.{.IceBeam} },
            .{ .species = .Magmar, .moves = &.{ .IceBeam, .Flamethrower, .Substitute } },
            .{ .species = .Lickitung, .moves = &.{.Slam} },
        },
        &.{.{
            .species = .Jynx,
            .moves = &.{ .ThunderWave, .Blizzard, .FireSpin, .Flamethrower },
        }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.IceBeam, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 35;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(1) });
    t.expected.p1.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.turn(.{2});

    // Can't freeze Ice-types
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(4313325, 218103808); // (255/256) ** 2 * (199/256) * (1/39)
    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 63;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
    try t.log.expected.turn(.{3});

    // Can't freeze a Pokémon which is already statused
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(47861, 10223616); // (229/256) * (209/256) * (1/39) * (1/4)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(2) });
    t.expected.p1.get(2).hp -= 140;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    t.expected.p1.get(2).status = Status.init(.FRZ);
    try t.log.expected.status(.{ P1.ident(2), t.expected.p1.get(2).status, .None });
    try t.log.expected.turn(.{4});

    // Can freeze Fire types
    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));
    try t.expectProbability(47861, 25165824); // (229/256) * (209/256) * (1/39) * (26/256)
    try expectEqual(t.expected.p1.get(2).status, t.actual.p1.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(2) });
    try t.log.expected.fail(.{ P1.ident(2), .None });
    try t.log.expected.cant(.{ P1.ident(2), .Freeze });
    try t.log.expected.turn(.{5});

    // Freezing prevents action
    try expectEqual(Result.Default, try t.update(forced, move(1)));
    try t.expectProbability(1, 1);

    // ...Pokémon Showdown still lets you choose whatever
    const n = t.battle.actual.choices(.P1, .Move, &choices);
    if (showdown) {
        try expectEqualSlices(
            Choice,
            &[_]Choice{ swtch(2), swtch(3), move(1), move(2), move(3) },
            choices[0..n],
        );
    } else {
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), swtch(3), move(0) }, choices[0..n]);
    }

    try t.log.expected.switched(.{ P1.ident(3), t.expected.p1.get(3) });
    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(3) });
    t.expected.p1.get(3).hp -= 173;
    try t.log.expected.damage(.{ P1.ident(3), t.expected.p1.get(3), .None });
    if (showdown) {
        t.expected.p1.get(3).status = 0;
    } else {
        t.expected.p1.get(3).status = Status.init(.FRZ);
        try t.log.expected.status(.{ P1.ident(3), t.expected.p1.get(3).status, .None });
    }
    try t.log.expected.turn(.{6});

    // Freeze Clause Mod prevents multiple Pokémon from being frozen
    try expectEqual(Result.Default, try t.update(swtch(3), move(2)));
    try t.expectProbability(47861, 25165824); // (229/256) * (209/256) * (1/39) * (26/256)
    try expectEqual(t.expected.p1.get(3).status, t.actual.p1.get(1).status);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.FireSpin, P1.ident(2) });
    try t.log.expected.resisted(.{P1.ident(2)});
    t.expected.p1.get(2).hp -= 5;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.turn(.{7});

    // Fire Spin does not thaw frozen Pokémon
    try expectEqual(Result.Default, try t.update(swtch(3), move(3)));
    try t.expectProbability(18601, 1277952); // (178/256) * (209/256) * (1/39)x
    try expectEqual(t.expected.p1.get(2).status, t.actual.p1.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.FireSpin, P1.ident(2) });
    t.expected.p1.get(2).hp -= 5;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.cant(.{ P1.ident(2), .Freeze });
    try t.log.expected.turn(.{8});

    try expectEqual(Result.Default, try t.update(forced, move(if (showdown) 3 else 0)));
    try t.expectProbability(3, 8);

    try t.log.expected.move(.{ P2.ident(1), Move.Flamethrower, P1.ident(2) });
    try t.log.expected.resisted(.{P1.ident(2)});
    t.expected.p1.get(2).hp -= 36;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.curestatus(.{ P1.ident(2), t.expected.p1.get(2).status, .Message });
    t.expected.p1.get(2).status = 0;
    try t.log.expected.move(.{ P1.ident(2), Move.IceBeam, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(2)});
    try t.log.expected.turn(.{9});

    // Other Fire moves thaw frozen Pokémon
    try expectEqual(Result.Default, try t.update(forced, move(4)));
    try t.expectProbability(17765, 218103808); // (255/256) * (209/256) * (1/39) * (1/256)
    try expectEqual(t.expected.p1.get(2).status, t.actual.p1.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(2) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.move(.{ P1.ident(2), Move.Substitute, P1.ident(2) });
    try t.log.expected.start(.{ P1.ident(2), .Substitute });
    t.expected.p1.get(2).hp -= 83;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.turn(.{10});

    try expectEqual(Result.Default, try t.update(move(3), move(2)));
    try t.expectProbability(27, 256);
    try expectEqual(t.expected.p1.get(2).status, t.actual.p1.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(2) });
    try t.log.expected.end(.{ P1.ident(2), .Substitute });
    try t.log.expected.move(.{ P1.ident(2), Move.Substitute, P1.ident(2) });
    try t.log.expected.fail(.{ P1.ident(2), .Weak });
    try t.log.expected.turn(.{11});

    // Substitute blocks Freeze
    try expectEqual(Result.Default, try t.update(move(3), move(2)));
    try t.expectProbability(47861, 2555904); // (229/256) * (209/256) * (1/39)
    try expectEqual(t.expected.p1.get(2).status, t.actual.p1.get(1).status);

    try t.verify();
}

// Move.{ThunderWave,StunSpore,Glare}
test "Paralyze effect" {
    // Paralyzes the target.
    const PROC = comptime ranged(63, 256) - 1;
    const NO_PROC = PROC + 1;
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            ~HIT, HIT,
            HIT, NO_PROC, HIT,
            PROC,
            HIT, NO_PROC, HIT,
            NO_PROC,
            NO_PROC, HIT,
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

    try t.log.expected.move(.{ P1.ident(1), Move.Glare, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(1) });
    try t.log.expected.status(.{ P1.ident(1), Status.init(.PAR), .None });
    try t.log.expected.turn(.{2});

    // Glare can miss
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(16575, 65536); // (65/256) * (255/256)

    try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .Paralysis });
    try t.log.expected.move(.{ P1.ident(1), Move.Glare, P2.ident(1) });
    try t.log.expected.status(.{ P2.ident(1), Status.init(.PAR), .None });
    try t.log.expected.turn(.{3});

    // Electric-type Pokémon can be paralyzed
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(573, 1024); // (3/4) * (191/256)

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
    try t.log.expected.turn(.{4});

    // Can be fully paralyzed
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(1, 4);

    try t.log.expected.move(.{ P2.ident(2), Move.Toxic, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Glare, P2.ident(2) });
    try t.log.expected.status(.{ P2.ident(2), Status.init(.PAR), .None });
    try t.log.expected.turn(.{5});

    // Glare ignores type immunity
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(573, 1024); // (3/4) * (191/256)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(2), Move.ThunderWave, P1.ident(2) });
    try t.log.expected.immune(.{ P1.ident(2), .None });
    try t.log.expected.turn(.{6});

    // Thunder Wave does not ignore type immunity
    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));
    try t.expectProbability(3, 4);

    try t.log.expected.move(.{ P1.ident(2), Move.Substitute, P1.ident(2) });
    try t.log.expected.start(.{ P1.ident(2), .Substitute });
    t.expected.p1.get(2).hp -= 68;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.move(.{ P2.ident(2), Move.Glare, P1.ident(2) });
    try t.log.expected.status(.{ P1.ident(2), Status.init(.PAR), .None });
    try t.log.expected.turn(.{7});

    // Primary paralysis ignores Substitute
    try expectEqual(Result.Default, try t.update(move(2), move(3)));
    try t.expectProbability(573, 1024); // (3/4) * (191/256)

    // Paralysis lowers speed
    try expectEqual(Status.init(.PAR), t.actual.p2.stored().status);
    try expectEqual(79, t.actual.p2.active.stats.spe);
    try expectEqual(318, t.actual.p2.stored().stats.spe);

    try t.verify();
}

// Move.{ThunderPunch,ThunderShock,Thunderbolt,Thunder}: ParalyzeChance1
// Move.{BodySlam,Lick}: ParalyzeChance2
test "ParalyzeChance effect" {
    // Has a X% chance to paralyze the target.
    const HI_PROC = comptime ranged(77, 256) - 1;
    const PAR_CAN = MAX;
    const PAR_CANT = MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HI_PROC, HIT, ~CRIT, MIN_DMG, HI_PROC,
            PAR_CAN, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HI_PROC, PAR_CANT,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, HI_PROC, ~CRIT, MIN_DMG, HIT, HI_PROC,
            PAR_CAN, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, PAR_CANT, ~CRIT, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Jolteon, .moves = &.{ .BodySlam, .ThunderShock } },
            .{ .species = .Dugtrio, .moves = &.{.Earthquake} },
        },
        &.{.{ .species = .Raticate, .moves = &.{ .BodySlam, .Thunderbolt, .Substitute } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.BodySlam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 64;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Thunderbolt, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 21;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    // Cannot paralyze a Pokémon of the same type as the move
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    // (255/256) ** 2 * (191/256) * (208/256) * (1/39) ** 2
    try t.expectProbability(1379975, 3489660928);
    try expectEqual(0, t.actual.p1.get(1).status);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P1.ident(1), Move.ThunderShock, P2.ident(1) });
    t.expected.p2.get(1).hp -= 71;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.BodySlam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 110;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p1.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.turn(.{3});

    //  Moves have different paralysis rates / Electric-type Pokémon can be paralyzed
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (255/256) ** 2 * (191/256) * (208/256) * (1/39) ** 2 * (230/256) * (77/256)
    try t.expectProbability(12219678625, 114349209288704);

    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 78;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.ThunderShock, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{4});

    // Paralysis lowers speed / Substitute block paralysis chance
    try expectEqual(Result.Default, try t.update(move(2), move(3)));
    // (3/4) * (255/256) * (191/256) * (1/39)
    try t.expectProbability(48705, 3407872);
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P2.ident(1), Move.BodySlam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 110;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
    try t.log.expected.turn(.{5});

    // Doesn't work if already statused / paralysis can prevent action
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (255/256) * (208/256) * (1/39) * (1/4)
    try t.expectProbability(85, 16384);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Thunderbolt, P1.ident(2) });
    try t.log.expected.immune(.{ P1.ident(2), .None });
    try t.log.expected.turn(.{6});

    // Doesn't trigger if the opponent is immune to the move
    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));
    try t.expectProbability(1, 1);
    try t.verify();
}

// Move.{Sing,SleepPowder,Hypnosis,LovelyKiss,Spore}
test "Sleep effect" {
    // Causes the target to fall asleep.
    const SLP_1 = if (showdown) comptime ranged(1, 8 - 1) else 1;
    const SLP_2 = if (showdown) comptime ranged(2, 8 - 1) else 2;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, SLP_1, HIT, SLP_2, HIT, HIT, HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, HIT, SLP_1, ~CRIT, HIT, SLP_2, ~CRIT, HIT, SLP_2, ~CRIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Parasect, .moves = &.{ .Spore, .Cut } }},
        &.{
            .{ .species = .Geodude, .moves = &.{.Tackle} },
            .{ .species = .Slowpoke, .moves = &.{.WaterGun} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Spore, P2.ident(1) });
    t.expected.p2.get(1).status = Status.slp(1);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .From, Move.Spore });
    try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Message });
    try t.log.expected.turn(.{2});

    // Can wake up immediately but still lose their turn
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(255, 1792); // (255/256) * (1/7)
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P1.ident(1), Move.Spore, P2.ident(1) });
    t.expected.p2.get(1).status = Status.slp(2);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .From, Move.Spore });
    t.expected.p2.get(1).status -= 1;
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{3});

    // Can be put to sleep for multiple turns
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(765, 896); // (255/256) * (6/7)
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.Spore, P2.ident(2) });
    if (showdown) {
        t.expected.p2.get(2).status = 0;
    } else {
        t.expected.p2.get(2).status = Status.slp(2);
        try t.log.expected.status(.{ P2.ident(2), t.expected.p2.get(2).status, .From, Move.Spore });
    }
    try t.log.expected.turn(.{4});

    // Sleep Clause Mod prevents multiple Pokémon from being put to sleep
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(255, 256);
    try expectEqual(t.expected.p2.get(2).status, t.actual.p2.get(1).status);

    try t.log.expected.switched(.{ P2.ident(1), t.expected.p2.get(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Spore, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{5});

    // Can't sleep someone already sleeping, turns only decrement while in battle
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(1, 1);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P1.ident(1), Move.Cut, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Message });
    try t.log.expected.turn(.{6});

    // Eventually wakes up
    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(29161, 7667712); // (241/256) * (1/39) * (242/256) * (1/6)
    try expectEqual(0, t.actual.p2.get(1).status);

    try t.verify();
}

// Move.{Supersonic,ConfuseRay}
test "Confusion effect" {
    // Causes the target to become confused.
    const CFZ_3 = if (showdown) comptime ranged(2, 6 - 2) - 1 else 1;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;
    const CFZ_CANT = if (showdown) CFZ_CAN + 1 else MAX;

    var t = Test((if (showdown)
        .{ HIT, HIT, HIT, CFZ_3, CFZ_CANT, HIT, CFZ_CAN, HIT, HIT }
    else
        .{ HIT, ~CRIT, HIT, CFZ_3, CFZ_CANT, HIT, CFZ_CAN, ~CRIT, HIT, ~CRIT, HIT })).init(
        &.{.{ .species = .Haunter, .moves = &.{ .ConfuseRay, .NightShade } }},
        &.{.{ .species = .Gengar, .moves = &.{ .Substitute, .Agility } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 80;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.ConfuseRay, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{2});

    // Confusion is blocked by Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try expect(!t.actual.p2.active.volatiles.Confusion);

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P1.ident(1), Move.NightShade, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(255, 256);

    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.ConfuseRay, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Confusion });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(255, 256);
    try expect(t.actual.p2.active.volatiles.Confusion);

    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    // Confused Pokémon can hurt themselves in confusion (typeless damage)
    t.expected.p2.get(1).hp -= 37;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Confusion });
    try t.log.expected.move(.{ P1.ident(1), Move.ConfuseRay, P2.ident(1) });
    try t.log.expected.turn(.{5});

    // Can't confuse a Pokémon that already has a confusion
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(255, 512); // (1/2)

    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.NightShade, P2.ident(1) });
    t.expected.p2.get(1).hp -= 100;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{6});

    // Pokémon can still successfully move despite being confused
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(765, 2048); // (3/4) * (1/2) * (255/256)

    try t.log.expected.end(.{ P2.ident(1), .Confusion });
    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.NightShade, P2.ident(1) });
    t.expected.p2.get(1).hp -= 100;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{7});

    // Pokémon snap out of confusion
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(85, 256); // (1/3) * (255/256)
    try expect(!t.actual.p2.active.volatiles.Confusion);

    try t.verify();
}

// Move.{Psybeam,Confusion}: ConfusionChance
test "ConfusionChance effect" {
    // Has a 10% chance to confuse the target.
    const PROC = comptime ranged(25, 256) - 1;
    const NO_PROC = PROC + 1;
    const CFZ_2 = MIN;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MAX_DMG, PROC, CFZ_2, CFZ_CAN,
            HIT, ~CRIT, MAX_DMG,
            HIT, ~CRIT, MAX_DMG, NO_PROC,
        } else .{
            ~CRIT, MAX_DMG, HIT, PROC, CFZ_2, CFZ_CAN, ~CRIT,
            ~CRIT, MAX_DMG, HIT,
            ~CRIT, ~CRIT, MAX_DMG, HIT, NO_PROC
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Venomoth, .moves = &.{ .Psybeam, .Splash } }},
        &.{.{ .species = .Jolteon, .moves = &.{ .Substitute, .Agility } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 83;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Psybeam, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.start(.{ P2.ident(1), .Confusion });
    try t.log.expected.turn(.{2});

    // ConfusionChance works through substitute if it doesn't break
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(448375, 218103808); // (255/256) * (211/256) * (1/39) * (25/256)
    try expect(t.actual.p2.active.volatiles.Confusion);

    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(1, 2);

    try t.log.expected.end(.{ P2.ident(1), .Confusion });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P1.ident(1), Move.Psybeam, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{4});

    // Can't confuse after breaking the substitute
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(17935, 3407872); // (1/4) * (255/256) * (211/256) * (1/39)
    try expect(!t.actual.p2.active.volatiles.Confusion);

    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.Psybeam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 49;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(4142985, 218103808); // (255/256) * (211/256) * (1/39) * (231/256)
    try expect(!t.actual.p2.active.volatiles.Confusion);

    try t.verify();
}

// Move.{Bite,BoneClub,HyperFang}: FlinchChance1
// Move.{Stomp,RollingKick,Headbutt,LowKick}: FlinchChance2
test "FlinchChance effect" {
    // Has a X% chance to flinch the target.
    const LO_PROC = comptime ranged(26, 256) - 1;
    const HI_PROC = comptime ranged(77, 256) - 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HI_PROC,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HI_PROC,
            HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, LO_PROC,
            HIT, ~CRIT, MIN_DMG, LO_PROC,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HI_PROC,
            ~HIT, ~HIT,
        } else .{
            ~CRIT, MIN_DMG, HIT, HI_PROC,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, HI_PROC,
            ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, LO_PROC,
            ~CRIT, MIN_DMG, HIT, LO_PROC,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, HI_PROC,
            ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, ~HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Raticate, .moves = &.{ .HyperFang, .Headbutt, .HyperBeam } }},
        &.{.{ .species = .Marowak, .moves = &.{ .Headbutt, .HyperBeam, .Substitute } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.HyperFang, P2.ident(1) });
    t.expected.p2.get(1).hp -= 72;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 80;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    // Moves have different flinch rates
    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    try t.expectProbability(26335, 1572864); // (229/256) * (208/256) * (1/39) * (230/256)

    try t.log.expected.move(.{ P1.ident(1), Move.Headbutt, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.Headbutt, P1.ident(1) });
    t.expected.p1.get(1).hp -= 60;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    // Substitute blocks flinch, flinch doesn't prevent movement when slower
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (255/256) ** 2 * (208/256) * (234/256) * (1/39) ** 2 * (77/256)
    try t.expectProbability(5006925, 34359738368);

    try t.log.expected.move(.{ P1.ident(1), Move.Headbutt, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.HyperBeam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 128;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.mustrecharge(.{P2.ident(1)});
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (255/256) * (229/256) * (208/256) * (234/256) * (1/39) ** 2
    try t.expectProbability(58395, 134217728);

    try t.log.expected.move(.{ P1.ident(1), Move.HyperFang, P2.ident(1) });
    t.expected.p2.get(1).hp -= 72;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Flinch });
    try t.log.expected.turn(.{5});

    // Flinch prevents movement but counts as recharge turn
    try expectEqual(Result.Default, try t.update(move(1), forced));
    try t.expectProbability(2977, 1572864); // (229/256) * (208/256) * (1/39) * (26/256)

    try t.log.expected.move(.{ P1.ident(1), Move.HyperFang, P2.ident(1) });
    t.expected.p2.get(1).hp -= 72;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Flinch });
    try t.log.expected.turn(.{6});

    // Can prevent movement even without recharge
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(2977, 1572864); // (229/256) * (208/256) * (1/39) * (26/256)

    // (need to artificially recover HP to survive Raticate's Hyper Beam)
    t.actual.p2.get(1).hp = 323;
    t.expected.p2.get(1).hp = 323;

    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 133;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.mustrecharge(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.Headbutt, P1.ident(1) });
    t.expected.p1.get(1).hp -= 60;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{7});

    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    // (229/256) * (255/256) * (208/256) * (234/256) * (1/39) ** 2 (77/256)
    try t.expectProbability(4496415, 34359738368);

    const n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.HyperFang, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.Headbutt, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{8});

    // Flinch should clear recharge
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(27, 65536); // (27/256) * (1/256)
    try t.verify();
}

// Move.Growl: AttackDown1
// Move.{TailWhip,Leer}: DefenseDown1
// Move.StringShot: SpeedDown1
// Move.{SandAttack,Smokescreen,Kinesis,Flash}: AccuracyDown1
// Move.Screech: DefenseDown2
test "StatDown effect" {
    // Lowers the target's X stat by Y stage(s).
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, HIT,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, HIT, ~CRIT, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Ekans, .moves = &.{ .Screech, .Strength } }},
        &.{
            .{ .species = .Caterpie, .moves = &.{ .StringShot, .Tackle } },
            .{ .species = .Gastly, .moves = &.{.NightShade} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Strength, P2.ident(1) });
    t.expected.p2.get(1).hp -= 75;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 22;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (255/256) * (242/256) * (229/256) * (234/256) * (1/39) ** 2
    try t.expectProbability(7065795, 13958643712);

    try t.log.expected.move(.{ P1.ident(1), Move.Screech, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Defense, -2 });
    try t.log.expected.move(.{ P2.ident(1), Move.StringShot, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, -1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(3267, 4096); // (216/256) * (242/256)
    try expectEqual(-1, t.actual.p1.active.boosts.spe);
    try expectEqual(-2, t.actual.p2.active.boosts.def);

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 22;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Strength, P2.ident(1) });
    t.expected.p2.get(1).hp -= 149;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (255/256) * (242/256) * (229/256) * (234/256) * (1/39) ** 2
    try t.expectProbability(7065795, 13958643712);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.Screech, P2.ident(2) });
    try t.log.expected.boost(.{ P2.ident(2), .Defense, -2 });
    try t.log.expected.turn(.{5});

    // Type immunity shouldn't matter
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(27, 32); // (216/256)
    try expectEqual(-2, t.actual.p2.active.boosts.def);

    try t.verify();
}

// Move.AuroraBeam: AttackDownChance
// Move.Acid: DefenseDownChance
// Move.{BubbleBeam,Constrict,Bubble}: SpeedDownChance
// Move.Psychic: SpecialDownChance
test "StatDownChance effect" {
    // Has a 33% chance to lower the target's X stat by 1 stage.
    const PROC = comptime ranged(85, 256) - 1;
    const NO_PROC = PROC + 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, NO_PROC, HIT, ~CRIT, MIN_DMG, PROC,
            HIT, ~CRIT, MIN_DMG, NO_PROC, HIT, ~CRIT, MIN_DMG, PROC,
            HIT, ~CRIT, MIN_DMG, NO_PROC, HIT, ~CRIT, MIN_DMG, NO_PROC,
        } else .{
            ~CRIT, MIN_DMG, HIT, NO_PROC, ~CRIT, MIN_DMG, HIT, PROC,
            ~CRIT, MIN_DMG, HIT, NO_PROC, ~CRIT, MIN_DMG, HIT, PROC,
            ~CRIT, MIN_DMG, HIT, NO_PROC, ~CRIT, MIN_DMG, HIT, NO_PROC,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Alakazam, .moves = &.{.Psychic} }},
        &.{.{ .species = .Starmie, .moves = &.{.BubbleBeam} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 60;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.BubbleBeam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 57;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, -1 });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (196/256) * (199/256) * (1/39) ** 2 * (85/256) * (171/256)
    try t.expectProbability(1024004921625, 11892317766025216);
    try expectEqual(-1, t.actual.p1.active.boosts.spe);

    try t.log.expected.move(.{ P2.ident(1), Move.BubbleBeam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 57;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 60;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, -1 });
    try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, -1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (196/256) * (199/256) * (1/39) ** 2 * (85/256) * (171/256)
    try t.expectProbability(1024004921625, 11892317766025216);
    try expectEqual(-1, t.actual.p2.active.boosts.spc);

    try t.log.expected.move(.{ P2.ident(1), Move.BubbleBeam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 39;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (196/256) * (199/256) * (1/39) ** 2 * (171/256) ** 2
    try t.expectProbability(2060056959975, 11892317766025216);
    try t.verify();
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
    // Raises the target's X stat by Y stage(s).
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, ~CRIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Scyther, .moves = &.{ .SwordsDance, .Cut } }},
        &.{.{ .species = .Slowbro, .moves = &.{ .Withdraw, .WaterGun } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Cut, P2.ident(1) });
    t.expected.p2.get(1).hp -= 37;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    t.expected.p1.get(1).hp -= 54;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (242/256) * (255/256) * (204/256) * (241/256) * (1/39) ** 2
    try t.expectProbability(42137645, 90731184128);

    try t.log.expected.move(.{ P1.ident(1), Move.SwordsDance, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Attack, 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.Withdraw, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Defense, 1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(2, t.actual.p1.active.boosts.atk);
    try expectEqual(1, t.actual.p2.active.boosts.def);

    try t.log.expected.move(.{ P1.ident(1), Move.Cut, P2.ident(1) });
    t.expected.p2.get(1).hp -= 49;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    t.expected.p1.get(1).hp -= 54;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (242/256) * (255/256) * (204/256) * (241/256) * (1/39) ** 2
    try t.expectProbability(42137645, 90731184128);
    try t.verify();
}

// Move.{Guillotine,HornDrill,Fissure}
test "OHKO effect" {
    // Deals 65535 damage to the target. Fails if the target's Speed is greater than the user's.
    var t = Test(if (showdown)
        .{ ~HIT, HIT }
    else
        .{ ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, HIT, ~CRIT, HIT, ~CRIT }).init(
        &.{
            .{ .species = .Kingler, .moves = &.{.Guillotine} },
            .{ .species = .Tauros, .stats = .{}, .moves = &.{.HornDrill} },
        },
        &.{
            .{ .species = .Dugtrio, .moves = &.{.Fissure} },
            .{ .species = .Gengar, .moves = &.{.Dig} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Fissure, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.move(.{ P1.ident(1), Move.Guillotine, P2.ident(1) });
    try t.log.expected.immune(.{ P2.ident(1), .OHKO });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(45, 64);

    try t.log.expected.move(.{ P2.ident(1), Move.Fissure, P1.ident(1) });
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.ohko(.{});
    try t.log.expected.faint(.{ P1.ident(1), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    // (76/256) * (196/256) * (1/39)
    try if (showdown) t.expectProbability(19, 64) else t.expectProbability(931, 159744);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(2), Move.HornDrill, P2.ident(2) });
    try t.log.expected.immune(.{ P2.ident(2), if (showdown) .None else .OHKO });
    try t.log.expected.turn(.{4});

    // Type-immunity trumps OHKO-immunity
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P2.ident(2), Move.Dig, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P2.ident(2), Move.Dig });
    try t.log.expected.move(.{ P1.ident(2), Move.HornDrill, P2.ident(2) });
    if (showdown) {
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(2)});
    } else {
        try t.log.expected.immune(.{ P2.ident(2), .OHKO });
    }
    try t.log.expected.turn(.{5});

    // Invulnerability trumps immunity on Pokémon Showdown
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.verify();
}

// Move.{RazorWind,SolarBeam,SkullBash,SkyAttack}
test "Charge effect" {
    // This attack charges on the first turn and executes on the second.
    const DISABLE_DURATION_2 = comptime ranged(2, 9 - 1) - 1;
    const DISABLE_MOVE_2 = if (showdown) MAX else 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, DISABLE_MOVE_2, DISABLE_DURATION_2, HIT,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, HIT, DISABLE_MOVE_2, DISABLE_DURATION_2, ~CRIT, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Wartortle, .moves = &.{ .WaterGun, .SkullBash } },
            .{ .species = .Ivysaur, .moves = &.{.VineWhip} },
        },
        &.{
            .{ .species = .Psyduck, .moves = &.{ .Scratch, .WaterGun, .Disable } },
            .{ .species = .Horsea, .moves = &.{.Bubble} },
        },
    );

    defer t.deinit();

    const pp = t.expected.p1.get(1).move(2).pp;

    try t.log.expected.move(.{ P1.ident(1), Move.SkullBash, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.SkullBash });
    try t.log.expected.move(.{ P2.ident(1), Move.Scratch, P1.ident(1) });
    t.expected.p1.get(1).hp -= 23;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(19465, 851968); // (255/256) * (229/256) * (1/39)
    try expectEqual(pp, t.actual.p1.active.move(2).pp);

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.SkullBash, P2.ident(1) });
    t.expected.p2.get(1).hp -= 83;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Scratch, P1.ident(1) });
    t.expected.p1.get(1).hp -= 23;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, move(1)));
    // (255/256) ** 2 * (227/256) * (229/256) * (1/39) ** 2
    try t.expectProbability(375577175, 725849473024);
    try expectEqual(pp - 1, t.actual.p1.active.move(2).pp);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.SkullBash, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.SkullBash });
    try t.log.expected.move(.{ P2.ident(1), Move.Disable, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Disable, Move.SkullBash });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(3)));
    try t.expectProbability(35, 128); // (140/256) * (1/2)
    try expectEqual(pp - 1, t.actual.p1.active.move(2).pp);
    try expectEqual(2, t.actual.p1.active.volatiles.disable_move);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.cant(.{ P1.ident(1), .Disable, Move.SkullBash });
    try t.log.expected.move(.{ P2.ident(1), Move.Disable, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(forced, move(3)));
    try t.expectProbability(245, 512); // (7/8) * (140/256)
    try expectEqual(pp - 1, t.actual.p1.active.move(2).pp);

    try t.verify();
}

// Move.{Fly,Dig}
test "Fly/Dig effect" {
    // This attack charges on the first turn and executes on the second. On the first turn, the user
    // avoids all attacks other than Bide, Swift, and Transform. If the user is fully paralyzed on
    // the second turn, it continues avoiding attacks until it switches out or successfully executes
    // the second turn of this move or {Fly,Dig}.

    // normal
    {
        var t = Test((if (showdown)
            .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG }
        else
            .{ ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
            &.{
                .{ .species = .Pidgeot, .moves = &.{ .Fly, .SandAttack } },
                .{ .species = .Metapod, .moves = &.{.Harden} },
            },
            &.{
                .{ .species = .Lickitung, .moves = &.{ .Strength, .Lick } },
                .{ .species = .Bellsprout, .moves = &.{.VineWhip} },
            },
        );
        defer t.deinit();

        const pp = t.expected.p1.get(1).move(1).pp;

        try t.log.expected.move(.{ P1.ident(1), Move.Fly, ID{} });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P1.ident(1), Move.Fly });
        try t.log.expected.move(.{ P2.ident(1), Move.Strength, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(pp, t.actual.p1.active.move(1).pp);

        var n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);

        try t.log.expected.move(.{ P1.ident(1), Move.Fly, P2.ident(1) });
        t.expected.p2.get(1).hp -= 79;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Strength, P1.ident(1) });
        t.expected.p1.get(1).hp -= 74;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, move(1)));
        // (242/256) * (255/256) * (211/256) * (241/256) * (1/39) ** 2
        try t.expectProbability(523002535, 1088774209536);
        try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);

        try t.verify();
    }
    // fainting
    {
        var t = Test((if (showdown)
            .{ HIT, HIT, ~CRIT, MIN_DMG }
        else
            .{ HIT, ~CRIT, MIN_DMG, HIT })).init(
            &.{
                .{ .species = .Seadra, .hp = 31, .moves = &.{.Toxic} },
                .{ .species = .Ninetales, .moves = &.{.Dig} },
            },
            &.{
                .{ .species = .Shellder, .hp = 31, .moves = &.{.Splash} },
                .{ .species = .Arcanine, .moves = &.{.Splash} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
        t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        t.expected.p2.get(1).hp -= 16;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(27, 32); // (216/256)

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P1.ident(2), Move.Dig, ID{} });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P1.ident(2), Move.Dig });
        try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
        try t.log.expected.activate(.{ P2.ident(2), .Splash });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);

        try t.log.expected.switched(.{ P2.ident(1), t.expected.p2.get(1) });
        if (showdown) {
            t.expected.p2.get(1).status = Status.init(.PSN);
            try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .Silent });
        }
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(forced, swtch(2)));
        try t.expectProbability(1, 1);

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(.{}, swtch(2)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P1.ident(2), Move.Dig, P2.ident(2) });
        try t.log.expected.supereffective(.{P2.ident(2)});
        t.expected.p2.get(2).hp -= 141;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
        try t.log.expected.activate(.{ P2.ident(2), .Splash });
        try t.log.expected.turn(.{6});

        try expectEqual(Result.Default, try t.update(forced, move(1)));
        try t.expectProbability(8755, 425984); // (255/256) * (206/256) * (1/39)
        try t.verify();
    }
}

// Move.{Whirlwind,Roar,Teleport}
test "SwitchAndTeleport effect" {
    // No competitive use.
    var t = Test(if (showdown) .{ HIT, ~HIT } else .{}).init(
        &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
        &.{.{ .species = .Pidgey, .moves = &.{.Whirlwind} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Teleport, P1.ident(1) });
    if (!showdown) {
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.laststill(.{});
    }
    try t.log.expected.move(.{ P2.ident(1), Move.Whirlwind, P1.ident(1) });
    if (!showdown) {
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.laststill(.{});
    }
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try if (showdown) t.expectProbability(27, 32) else t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.Teleport, P1.ident(1) });
    if (!showdown) {
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.laststill(.{});
    }
    try t.log.expected.move(.{ P2.ident(1), Move.Whirlwind, P1.ident(1) });
    if (showdown) {
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
    } else {
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.laststill(.{});
    }
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try if (showdown) t.expectProbability(5, 32) else t.expectProbability(1, 1);

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

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try t.verify();
}

// Move.{Bind,Wrap,FireSpin,Clamp}
test "Binding effect" {
    // The user spends two to five turns using this move. Has a 3/8 chance to last two or three
    // turns, and a 1/8 chance to last four or five turns. The damage calculated for the first turn
    // is used for every other turn. The user cannot select a move and the target cannot execute a
    // move during the effect, but both may switch out. If the user switches out, the target remains
    // unable to execute a move during that turn. If the target switches out, the user uses this
    // move again automatically, and if it had 0 PP at the time, it becomes 63. If the user or the
    // target switch out, or the user is prevented from moving, the effect ends. This move can
    // prevent the target from moving even if it has type immunity, but will not deal damage.
    const MIN_WRAP = MIN;
    const MAX_WRAP = MAX;
    const PAR_CAN = MAX;
    const PAR_CANT = MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, MIN_WRAP,
            HIT, ~CRIT, MAX_DMG, MIN_WRAP,
            HIT,
            PAR_CAN, HIT, MAX_WRAP, PAR_CAN,
            PAR_CANT, PAR_CAN,
            HIT, MIN_WRAP,
        } else .{
            MIN_WRAP, ~CRIT, MIN_DMG, HIT,
            MIN_WRAP, ~CRIT, MAX_DMG, HIT,
            ~CRIT, HIT,
            PAR_CAN, MAX_WRAP, MAX_WRAP, ~CRIT, HIT, PAR_CAN,
            PAR_CANT, PAR_CAN, ~CRIT,
            MIN_WRAP, ~CRIT, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Dragonite, .moves = &.{ .Wrap, .Agility } },
            .{ .species = .Moltres, .moves = &.{ .FireSpin, .FireBlast } },
        },
        &.{
            .{ .species = .Cloyster, .moves = &.{ .Clamp, .Surf } },
            .{ .species = .Tangela, .moves = &.{ .Bind, .StunSpore } },
            .{ .species = .Gengar, .moves = &.{ .Splash, .NightShade } },
        },
    );
    defer t.deinit();

    const pp = t.expected.p1.get(1).move(1).pp;

    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 10;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Bound });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(243, 13312); // (216/256) * (216/256) * (1/39)
    try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);

    const p1_choices = &[_]Choice{ swtch(2), forced };
    const all_choices = &[_]Choice{ swtch(2), swtch(3), move(1), move(2) };
    const p2_choices = if (showdown)
        all_choices
    else
        &[_]Choice{ swtch(2), swtch(3), forced };

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, p1_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, p2_choices, choices[0..n]);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(2) });
    t.expected.p2.get(2).hp -= 15;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, swtch(2)));
    try t.expectProbability(243, 13312); // (216/256) * (216/256) * (1/39)
    try expectEqual(pp - 2, t.actual.p1.active.move(1).pp);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, p1_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, p2_choices, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(2) });
    t.expected.p2.get(2).hp -= 15;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.cant(.{ P2.ident(2), .Bound });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(forced, forced));
    try t.expectProbability(3, 8);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, all_choices, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P2.ident(2), Move.StunSpore, P1.ident(1) });
    t.expected.p1.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(191, 256);
    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, all_choices, choices[0..n]);

    try t.log.expected.switched(.{ P2.ident(3), t.expected.p2.get(3) });
    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(3) });
    if (showdown) {
        try t.log.expected.damage(.{ P2.ident(3), t.expected.p2.get(3), .None });
    } else {
        try t.log.expected.immune(.{ P2.ident(3), .None });
    }
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(1), swtch(3)));
    // (3/4) * (216/256)
    try if (showdown) t.expectProbability(81, 128) else t.expectProbability(3, 4);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, p1_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, p2_choices, choices[0..n]);

    try t.log.expected.cant(.{ P2.ident(3), .Bound });
    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(3) });
    if (showdown) try t.log.expected.damage(.{ P2.ident(3), t.expected.p2.get(3), .None });
    try t.log.expected.turn(.{7});

    try expectEqual(Result.Default, try t.update(forced, forced));
    try t.expectProbability(15, 32); // (3/4) * (5/8)

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, p1_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, p2_choices, choices[0..n]);

    try t.log.expected.cant(.{ P2.ident(3), .Bound });
    try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
    try t.log.expected.turn(.{8});

    try expectEqual(Result.Default, try t.update(forced, forced));
    try t.expectProbability(1, 4);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, all_choices, choices[0..n]);

    try t.log.expected.move(.{ P2.ident(3), Move.Splash, P2.ident(3) });
    try t.log.expected.activate(.{ P2.ident(3), .Splash });
    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(3) });
    if (showdown) {
        try t.log.expected.damage(.{ P2.ident(3), t.expected.p2.get(3), .None });
    } else {
        try t.log.expected.immune(.{ P2.ident(3), .None });
    }
    try t.log.expected.turn(.{9});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (3/4) * (216/256)
    try if (showdown) t.expectProbability(81, 128) else t.expectProbability(3, 4);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    if (showdown) try t.log.expected.cant(.{ P2.ident(3), .Bound });
    try t.log.expected.turn(.{10});

    try expectEqual(Result.Default, try t.update(swtch(2), forced));
    try t.expectProbability(1, 1);
    try t.verify();
}

// Move.{JumpKick,HighJumpKick}
test "JumpKick effect" {
    // If this attack misses the target, the user takes 1 HP of crash damage. If the user has a
    // substitute, the crash damage is dealt to the target's substitute if it has one, otherwise no
    // crash damage is dealt.
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            ~HIT, HIT, CRIT, MAX_DMG, ~HIT, ~HIT,
        } else .{
            ~CRIT, MIN_DMG, ~HIT, CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, ~HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Hitmonlee, .moves = &.{ .JumpKick, .Substitute } }},
        &.{.{ .species = .Hitmonlee, .level = 99, .moves = &.{ .HighJumpKick, .Substitute } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Substitute });
    t.expected.p1.get(1).hp -= 75;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 75;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.JumpKick, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.HighJumpKick, P1.ident(1) });
    try t.log.expected.crit(.{P1.ident(1)});
    try t.log.expected.end(.{ P1.ident(1), .Substitute });
    try t.log.expected.turn(.{3});

    // Jump Kick causes crash damage to the opponent's sub if both Pokémon have one
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(68929, 327155712); // (14/256) * (229/256) * (43/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.JumpKick, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 1;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.HighJumpKick, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{4});

    // Jump Kick causes 1 HP crash damage unless only the user who crashed has a Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(189, 32768); // (14/256) * (27/256)
    try t.verify();
}

// Move.{TakeDown,DoubleEdge,Submission}
test "Recoil effect" {
    // If the target lost HP, the user takes recoil damage equal to 1/4 the HP lost by the target,
    // rounded down, but not less than 1 HP. If this move breaks the target's substitute, the user
    // does not take any recoil damage.
    var t = Test(if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG, HIT }).init(
        &.{
            .{ .species = .Slowpoke, .hp = 1, .moves = &.{.Splash} },
            .{ .species = .Rhydon, .moves = &.{ .TakeDown, .Splash } },
        },
        &.{.{ .species = .Tauros, .moves = &.{ .DoubleEdge, .Substitute } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.DoubleEdge, P1.ident(1) });
    t.expected.p1.get(1).hp -= 1;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp -= 1;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .RecoilOf, P1.ident(1) });
    try t.log.expected.faint(.{ P1.ident(1), true });

    // Recoil inflicts at least 1 HP
    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    try t.expectProbability(17085, 851968); // (255/256) * (201/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 88;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(2), Move.TakeDown, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{3});

    // Deals no damage if the move breaks the target's Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(531, 26624); // (216/256) * (236/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.DoubleEdge, P1.ident(2) });
    try t.log.expected.resisted(.{P1.ident(2)});
    t.expected.p1.get(2).hp -= 48;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    t.expected.p2.get(1).hp -= 12;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .RecoilOf, P1.ident(2) });
    try t.log.expected.move(.{ P1.ident(2), Move.Splash, P1.ident(2) });
    try t.log.expected.activate(.{ P1.ident(2), .Splash });
    try t.log.expected.turn(.{4});

    // Inflicts 1/4 of damage dealt to user as recoil
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(17085, 851968); // (255/256) * (201/256) * (1/39)
    try t.verify();
}

// Move.Struggle
test "Struggle effect" {
    // Deals Normal-type damage. If this move was successful, the user takes damage equal to 1/2 the
    // HP lost by the target, rounded down, but not less than 1 HP. This move is automatically used
    // if none of the user's known moves can be selected.
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Abra, .hp = 64, .moves = &.{ .Substitute, .Splash } },
            .{ .species = .Golem, .moves = &.{.Harden} },
        },
        &.{.{ .species = .Arcanine, .moves = &.{.Splash} }},
    );
    defer t.deinit();

    t.actual.p2.get(1).move(1).pp = 1;

    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Substitute });
    t.expected.p1.get(1).hp -= 63;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    // Struggle only becomes an option if the user has no PP left
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(0, t.actual.p2.get(1).move(1).pp);
    const n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{move(0)}, choices[0..n]);

    try t.log.expected.move(.{ P2.ident(1), Move.Struggle, P1.ident(1) });
    try t.log.expected.end(.{ P1.ident(1), .Substitute });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    // Deals no recoil damage if the move breaks the target's Substitute
    try expectEqual(Result.Default, try t.update(move(2), move(0)));
    try t.expectProbability(17765, 851968); // (255/256) * (209/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.Struggle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 1;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp -= 1;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .RecoilOf, P1.ident(1) });
    try t.log.expected.faint(.{ P1.ident(1), true });

    // Struggle recoil inflicts at least 1 HP
    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(2), move(0)));
    try t.expectProbability(17765, 851968); // (255/256) * (209/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P2.ident(1), Move.Struggle, P1.ident(2) });
    try t.log.expected.resisted(.{P1.ident(2)});
    t.expected.p1.get(2).hp -= 16;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    t.expected.p2.get(1).hp -= 8;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .RecoilOf, P1.ident(2) });
    try t.log.expected.move(.{ P1.ident(2), Move.Harden, P1.ident(2) });
    try t.log.expected.boost(.{ P1.ident(2), .Defense, 1 });
    try t.log.expected.turn(.{5});

    // Respects type effectiveness and inflicts 1/2 of damage dealt to user as recoil
    try expectEqual(Result.Default, try t.update(move(1), move(0)));
    try t.expectProbability(17765, 851968); // (255/256) * (209/256) * (1/39)
    try t.verify();
}

// Move.{Thrash,PetalDance}
test "Thrashing effect" {
    // Whether or not this move is successful, the user spends three or four turns locked into this
    // move and becomes confused immediately after its move on the last turn of the effect, even if
    // it is already confused. If the user is prevented from moving, the effect ends without causing
    // confusion. During the effect, this move's accuracy is overwritten every turn with the current
    // calculated accuracy including stat stage changes, but not to less than 1/256 or more than
    // 255/256.
    const THRASH_3 = if (showdown) comptime ranged(1, 4 - 2) - 1 else MIN;
    const CFZ_5 = if (showdown) MAX else 3;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;
    const PAR_CAN = MAX;
    const PAR_CANT = MIN;

    // normal
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                THRASH_3, HIT, ~CRIT, MIN_DMG, HIT, CFZ_5,
                CFZ_CAN, ~HIT, THRASH_3, ~HIT,
                CFZ_CAN, CFZ_5, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
                CFZ_CAN, HIT, PAR_CANT,
                CFZ_CAN, HIT, PAR_CAN, THRASH_3, HIT, ~CRIT, MAX_DMG,
            } else .{
                THRASH_3, ~CRIT, MIN_DMG, HIT, HIT, CFZ_5,
                CFZ_CAN, ~CRIT, MIN_DMG, ~HIT, THRASH_3, ~CRIT, MIN_DMG, ~HIT,
                CFZ_CAN, CFZ_5, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
                CFZ_CAN, HIT, PAR_CANT,
                CFZ_CAN, PAR_CAN, THRASH_3, ~CRIT, MAX_DMG, HIT,
            }
        // zig fmt: on
        ).init(
            &.{
                .{ .species = .Nidoking, .moves = &.{ .Thrash, .ThunderWave } },
                .{ .species = .Nidoqueen, .moves = &.{.PoisonSting} },
            },
            &.{
                .{ .species = .Vileplume, .moves = &.{ .PetalDance, .ConfuseRay } },
                .{ .species = .Victreebel, .moves = &.{.RazorLeaf} },
            },
        );
        defer t.deinit();

        const pp = t.expected.p1.get(1).move(1).pp;

        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        t.expected.p2.get(1).hp -= 68;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.ConfuseRay, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Confusion });
        try t.log.expected.turn(.{2});

        // Thrashing locks user in for 3-4 turns
        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(2319225, 109051904); // (255/256) ** 2 * (214/256) * (1/39)
        try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);
        try expect(t.actual.p1.active.volatiles.Confusion);
        try expectEqual(5, t.actual.p1.active.volatiles.confusion);

        var n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);

        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(1)});
        try t.log.expected.move(.{ P2.ident(1), Move.PetalDance, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.turn(.{3});

        // Thrashing locks you in whether you hit or not
        try expectEqual(Result.Default, try t.update(forced, move(1)));
        try t.expectProbability(1, 131072); // (1/256) * (1/256)
        try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);
        try expect(t.actual.p1.active.volatiles.Confusion);
        try expectEqual(4, t.actual.p1.active.volatiles.confusion);

        n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        if (!showdown) try t.log.expected.start(.{ P1.ident(1), .ConfusionSilent });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        if (showdown) try t.log.expected.start(.{ P1.ident(1), .ConfusionSilent });
        t.expected.p2.get(1).hp -= 68;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.PetalDance, P1.ident(1) });
        t.expected.p1.get(1).hp -= 91;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{4});

        // Thrashing confuses you even if already confused
        try expectEqual(Result.Default, try t.update(forced, forced));
        // (3/4) * (1/2) ** 2 * (255/256) ** 2 * (214/256) * (231/256) * (1/39) ** 2
        try t.expectProbability(535740975, 5806795784192);
        try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);
        try expect(t.actual.p1.active.volatiles.Confusion);
        try expectEqual(5, t.actual.p1.active.volatiles.confusion);

        n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.move(.{ P1.ident(1), Move.ThunderWave, P2.ident(1) });
        t.expected.p2.get(1).status = Status.init(.PAR);
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.cant(.{ P2.ident(1), .Paralysis });
        try t.log.expected.turn(.{5});

        // Thrashing doesn't confuse you if the user is prevented from moving
        try expectEqual(Result.Default, try t.update(move(2), forced));
        try t.expectProbability(255, 2048); // (1/2) * (255/256) * (1/4)
        try expect(!t.actual.p2.active.volatiles.Confusion);

        n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
        n = t.battle.actual.choices(.P2, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);

        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.move(.{ P1.ident(1), Move.ThunderWave, P2.ident(1) });
        try t.log.expected.fail(.{ P2.ident(1), .Paralysis });
        try t.log.expected.move(.{ P2.ident(1), Move.PetalDance, P1.ident(1) });
        t.expected.p1.get(1).hp -= 108;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{6});

        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        // (3/4) ** 2 * (1/2) * (255/256) * (231/256) * (1/39)
        try t.expectProbability(176715, 27262976);

        try t.verify();
    }
    // immune
    {
        var t = Test((if (showdown)
            .{ THRASH_3, HIT, ~CRIT, MIN_DMG, CFZ_5 }
        else
            .{ THRASH_3, ~CRIT, MIN_DMG, HIT, ~CRIT, HIT, CFZ_5, ~CRIT, HIT })).init(
            &.{.{ .species = .Mankey, .moves = &.{ .Thrash, .Scratch } }},
            &.{
                .{ .species = .Scyther, .moves = &.{.Cut} },
                .{ .species = .Goldeen, .moves = &.{.WaterGun} },
                .{ .species = .Gastly, .moves = &.{.Splash} },
            },
        );
        defer t.deinit();

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(2) });
        t.expected.p2.get(2).hp -= 77;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
        try t.expectProbability(1445, 65536); // (255/256) * (221/256) * (1/39)

        try t.log.expected.switched(.{ P2.ident(3), t.expected.p2.get(3) });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(3) });
        try t.log.expected.immune(.{ P2.ident(3), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, swtch(3)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P2.ident(3), Move.Splash, P2.ident(3) });
        try t.log.expected.activate(.{ P2.ident(3), .Splash });
        if (!showdown) try t.log.expected.start(.{ P1.ident(1), .ConfusionSilent });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(3) });
        if (showdown) try t.log.expected.start(.{ P1.ident(1), .ConfusionSilent });
        try t.log.expected.immune(.{ P2.ident(3), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(forced, move(1)));
        try t.expectProbability(1, 2);
        try expect(t.actual.p1.active.volatiles.Confusion);
        try expectEqual(5, t.actual.p1.active.volatiles.confusion);

        try t.verify();
    }
}

// Move.{SonicBoom,DragonRage}
test "FixedDamage effect" {
    // Deals X HP of damage to the target. This move ignores type immunity.
    var t = Test(.{ HIT, HIT, HIT }).init(
        &.{.{ .species = .Voltorb, .moves = &.{.SonicBoom} }},
        &.{
            .{ .species = .Dratini, .moves = &.{.DragonRage} },
            .{ .species = .Gastly, .moves = &.{.NightShade} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.SonicBoom, P2.ident(1) });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.DragonRage, P1.ident(1) });
    t.expected.p1.get(1).hp -= 40;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(58395, 65536); // (255/256) * (229/256)

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.SonicBoom, P2.ident(2) });
    t.expected.p2.get(2).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(229, 256);
    try t.verify();
}

// Move.{SeismicToss,NightShade}
test "LevelDamage effect" {
    // Deals damage to the target equal to the user's level. This move ignores type immunity.
    var t = Test(.{ HIT, HIT }).init(
        &.{.{ .species = .Gastly, .level = 22, .moves = &.{.NightShade} }},
        &.{.{ .species = .Clefairy, .level = 16, .moves = &.{.SeismicToss} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.NightShade, P2.ident(1) });
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.SeismicToss, P1.ident(1) });
    t.expected.p1.get(1).hp -= 16;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(65025, 65536); // (255/256) ** 2
    try t.verify();
}

// Move.Psywave
test "Psywave effect" {
    // Deals damage to the target equal to a random number from 1 to (user's level * 1.5 - 1),
    // rounded down, but not less than 1 HP.
    var t = Test((if (showdown)
        .{ HIT, MAX_DMG, HIT, MIN_DMG }
    else
        .{ HIT, 88, 87, HIT, 255, 0 })).init(
        &.{.{ .species = .Gengar, .level = 59, .moves = &.{.Psywave} }},
        &.{.{ .species = .Clefable, .level = 42, .moves = &.{.Psywave} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Psywave, P2.ident(1) });
    t.expected.p2.get(1).hp -= 87;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Psywave, P1.ident(1) });

    // https://pkmn.cc/bulba-glitch-1#Psywave_desynchronization
    // https://glitchcity.wiki/Psywave_desync_glitch
    const result = if (showdown) Result.Default else Result.Error;
    if (showdown) try t.log.expected.turn(.{2});

    try expectEqual(result, try t.update(move(1), move(1)));
    try t.expectProbability(289, 2523136); // (204/256) ** 2 * (1/88) * (1/63)
    try t.verify();
}

// Move.SuperFang
test "SuperFang effect" {
    // Deals damage to the target equal to half of its current HP, rounded down, but not less than 1
    // HP. This move ignores type immunity.
    var t = Test((if (showdown)
        .{ HIT, HIT, HIT }
    else
        .{ HIT, HIT, ~CRIT, MIN_DMG, HIT })).init(
        &.{
            .{ .species = .Raticate, .hp = 1, .moves = &.{.SuperFang} },
            .{ .species = .Haunter, .moves = &.{.DreamEater} },
        },
        &.{.{ .species = .Rattata, .moves = &.{.SuperFang} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.SuperFang, P2.ident(1) });
    t.expected.p2.get(1).hp -= 131;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.SuperFang, P1.ident(1) });
    t.expected.p1.get(1).hp -= 1;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.faint(.{ P1.ident(1), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    try t.expectProbability(52441, 65536); // (229/256) ** 2

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(2), Move.DreamEater, P2.ident(1) });
    try t.log.expected.immune(.{ P2.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.SuperFang, P1.ident(2) });
    t.expected.p1.get(2).hp -= 146;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(229, 256);
    try t.verify();
}

// Move.Disable
test "Disable effect" {
    // For 0 to 7 turns, one of the target's known moves that has at least 1 PP remaining becomes
    // disabled, at random. Fails if one of the target's moves is already disabled, or if none of
    // the target's moves have PP remaining. If any Pokemon uses Haze, this effect ends. Whether or
    // not this move was successful, it counts as a hit for the purposes of the opponent's use of
    // Rage.
    const NO_FRZ = comptime ranged(26, 256);
    const DISABLE_DURATION_1 = MIN;
    const DISABLE_DURATION_5 = comptime ranged(5, 9 - 1) - 1;
    const DISABLE_MOVE_1 = if (showdown) comptime ranged(1, 4) - 1 else 0;
    // Note move "2: here is actually the 3rd slot (Rest) because slot 2 gets set to 0 PP
    const DISABLE_MOVE_2 = if (showdown) comptime ranged(2, 4) - 1 else 2;
    const DISABLE_MOVE_4 = if (showdown) MAX else 3;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, DISABLE_MOVE_1, DISABLE_DURATION_1, HIT, ~CRIT, MIN_DMG,
            HIT, DISABLE_MOVE_2, DISABLE_DURATION_5, HIT, ~CRIT, MIN_DMG,
            HIT, DISABLE_MOVE_4, DISABLE_DURATION_5,
            HIT, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, NO_FRZ,
        } else .{
            ~CRIT, HIT, DISABLE_MOVE_1, DISABLE_DURATION_1, ~CRIT, MIN_DMG, HIT,
            ~CRIT, HIT, DISABLE_MOVE_2, DISABLE_DURATION_5, ~CRIT, MIN_DMG, HIT,
            ~CRIT, HIT, DISABLE_MOVE_4, DISABLE_DURATION_5,
            ~CRIT, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, NO_FRZ
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Golduck, .moves = &.{ .Disable, .WaterGun } }},
        &.{
            .{ .species = .Vaporeon, .moves = &.{ .WaterGun, .Haze, .Rest, .Blizzard } },
            .{ .species = .Flareon, .moves = &.{.Flamethrower} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Disable, Move.WaterGun });
    try t.log.expected.end(.{ P2.ident(1), .Disable });
    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 27;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    // Disable can end immediately
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (140/256) * (255/256) * (1/4) * (1/8) * (224/256) * (1/39)
    try t.expectProbability(20825, 54525952);
    try expectEqual(0, t.actual.p2.active.volatiles.disable_move);

    var n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(
        Choice,
        &[_]Choice{ swtch(2), move(1), move(2), move(3), move(4) },
        choices[0..n],
    );

    try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Disable, Move.Rest });
    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 27;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    // Should skip over moves which are already out of PP
    t.actual.p2.active.move(2).pp = 0;
    t.actual.p2.get(1).move(2).pp = 0;

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    //  (140/256) * (255/256) * (1/3) * (7/8) * (224/256) * (1/39)
    try t.expectProbability(145775, 40894464);

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(4) }, choices[0..n]);

    t.actual.p2.active.volatiles.disable_duration = 0;
    t.actual.p2.active.volatiles.disable_move = 0;
    t.options.chance.actions.p2.durations.disable = 0;
    t.actual.p2.active.move(2).pp = 1;
    t.actual.p2.get(1).move(2).pp = 1;

    try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Disable, Move.Blizzard });
    try t.log.expected.cant(.{ P2.ident(1), .Disable, Move.Blizzard });
    try t.log.expected.turn(.{4});

    // Can be disabled for many turns
    try expectEqual(Result.Default, try t.update(move(1), move(4)));
    try t.expectProbability(245, 2048); // (140/256) * (1/4) * (7/8)
    try expectEqual(4, t.actual.p2.active.volatiles.disable_duration);

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 27;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{5});

    // Disable fails if a move is already disabled
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(8925, 851968); // (140/256) * (255/256) * (6/7) * (224/256) * (1/39)
    try expectEqual(3, t.actual.p2.active.volatiles.disable_duration);

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.WaterGun, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Haze, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    try t.log.expected.end(.{ P2.ident(1), .DisableSilent });
    try t.log.expected.turn(.{6});

    // Haze clears disable
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(45475, 2555904); //  (255/256) * (214/256) * (1/39) * (5/6)
    try expectEqual(0, t.actual.p2.active.volatiles.disable_move);

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(3), move(4) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.WaterGun, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 53;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{7});

    try expectEqual(Result.Default, try t.update(move(2), move(4)));
    // (255/256) *(229/256) * (214/256) * (224/256) * (1/39) ** 2 * (230/256)
    try t.expectProbability(1676617775, 4355096838144);

    try t.verify();
}

// Move.Mist
test "Mist effect" {
    // While the user remains active, it is protected from having its stat stages lowered by other
    // Pokemon, unless caused by the secondary effect of a move. Fails if the user already has the
    // effect. If any Pokemon uses Haze, this effect ends.
    const PROC = comptime ranged(85, 256) - 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, PROC,
            HIT, ~CRIT, MIN_DMG, HIT,
            HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, HIT,
        } else .{
            ~CRIT, MIN_DMG, HIT, PROC,
            ~CRIT, MIN_DMG, HIT, ~CRIT,
            ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Articuno, .moves = &.{ .Mist, .Peck } }},
        &.{.{ .species = .Vaporeon, .moves = &.{ .AuroraBeam, .Growl, .Haze } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Mist, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Mist });
    try t.log.expected.move(.{ P2.ident(1), Move.AuroraBeam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 42;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
    try t.log.expected.turn(.{2});

    // Mist doesn't protect against secondary effects
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(50575, 6815744); // (255/256) * (224/256) * (1/39) * (85/256)
    try expect(t.actual.p1.active.volatiles.Mist);
    try expectEqual(-1, t.actual.p1.active.boosts.atk);

    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    t.expected.p2.get(1).hp -= 31;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Mist });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.turn(.{3});

    // Mist does protect against primary stat lowering effects
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)
    try expectEqual(-1, t.actual.p1.active.boosts.atk);

    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    t.expected.p2.get(1).hp -= 31;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Haze, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    try t.log.expected.end(.{ P1.ident(1), .MistSilent });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(3)));
    try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    t.expected.p2.get(1).hp -= 48;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
    try t.log.expected.turn(.{5});

    // Haze ends Mist's effect
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(2319225, 109051904); // (255/256) ** 2 * (214/256) * (1/39)
    try expect(!t.actual.p1.active.volatiles.Mist);
    try expectEqual(-1, t.actual.p1.active.boosts.atk);

    try t.verify();
}

// Move.HyperBeam
test "HyperBeam effect" {
    // If this move is successful, the user must recharge on the following turn and cannot select a
    // move, unless the target or its substitute was knocked out by this move.
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, MAX_DMG, HIT, ~CRIT,MAX_DMG, HIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Tauros, .moves = &.{ .HyperBeam, .BodySlam } },
            .{ .species = .Exeggutor, .moves = &.{.SleepPowder} },
        },
        &.{
            .{ .species = .Jolteon, .moves = &.{ .Substitute, .Splash } },
            .{ .species = .Chansey, .moves = &.{ .Splash, .SoftBoiled } },
        },
    );
    defer t.deinit();

    const pp = t.expected.p1.get(1).move(1).pp;

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 83;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{2});

    // Doesn't require a recharge if it knocks out a Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(15343, 851968); // (229/256) * (201/256) * (1/39)
    try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);

    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
    t.expected.p2.get(1).hp = 0;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.faint(.{ P2.ident(1), true });

    // Doesn't require a recharge if it knocks out opponent
    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(1), move(2)));
    try t.expectProbability(15343, 851968); // (229/256) * (201/256) * (1/39)
    try expectEqual(pp - 2, t.actual.p1.active.move(1).pp);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(.{}, swtch(2)));
    try t.expectProbability(1, 1);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(2) });
    t.expected.p2.get(2).hp -= 442;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.mustrecharge(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
    try t.log.expected.activate(.{ P2.ident(2), .Splash });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(15343, 851968); // (229/256) * (201/256) * (1/39)

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2) }, choices[0..n]);

    try t.log.expected.cant(.{ P1.ident(1), .Recharge });
    try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
    try t.log.expected.activate(.{ P2.ident(2), .Splash });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(forced, move(1)));
    try t.expectProbability(1, 1);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2) }, choices[0..n]);

    try t.verify();
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
    const NO_PROC = MAX;
    const MIN_HITS = MIN;
    const SLP_3 = if (showdown) comptime ranged(3, 8 - 1) else 3;
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, NO_PROC, HIT,
            HIT, MIN_HITS, ~CRIT, MIN_DMG, HIT,
            HIT, HIT,
            HIT, HIT,
            HIT, MIN_HITS, ~CRIT, MIN_DMG, HIT,
            HIT,
            HIT,
            HIT, HIT,
            HIT,
            HIT, SLP_3,
        } else .{
            ~CRIT, MIN_DMG, HIT, NO_PROC, ~CRIT,
            ~CRIT, MIN_DMG, HIT, MIN_HITS, ~CRIT, HIT,
            ~CRIT, ~CRIT,
            HIT, ~CRIT, HIT,
            ~CRIT, MIN_DMG, HIT, MIN_HITS, ~CRIT, HIT,
            ~CRIT, HIT,
            ~CRIT, HIT,
            ~CRIT, HIT,
            ~CRIT, HIT,
            ~CRIT, HIT, SLP_3,
        }
    // zig fmt: on
    ).init(
        &.{
            .{
                .species = .Voltorb,
                .moves = &.{ .Thunderbolt, .DoubleSlap, .Counter, .SonicBoom },
            },
            .{ .species = .Gengar, .moves = &.{ .Teleport, .SeismicToss } },
            .{ .species = .Snorlax, .moves = &.{ .LovelyKiss, .Reflect } },
        },
        &.{.{ .species = .Chansey, .moves = &.{.Counter} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Thunderbolt, P2.ident(1) });
    t.expected.p2.get(1).hp -= 69;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{2});

    // Fails for moves which are not Normal / Fighting
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1006825, 54525952); // (255/256) * (206/256) * (1/39) * (230/256)

    try t.log.expected.move(.{ P1.ident(1), Move.DoubleSlap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.hitcount(.{ P2.ident(1), 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    t.expected.p1.get(1).hp -= 34;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    // Deals back double damage to target, though only of the last hit of a multi-hit move
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (216/256) * (255/256) * (206/256) * (1/39) * (3/8)
    try t.expectProbability(709155, 109051904);

    try t.log.expected.move(.{ P1.ident(1), Move.Counter, P2.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{4});

    // Cannot Counter an opponent's Counter
    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.SonicBoom, P2.ident(1) });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    t.expected.p1.get(1).hp -= 40;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{5});

    // Works on fixed damage moves including Sonic Boom
    try expectEqual(Result.Default, try t.update(move(4), move(1)));
    try t.expectProbability(58395, 65536); // (229/256) * (255/256)

    try t.log.expected.move(.{ P1.ident(1), Move.DoubleSlap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.hitcount(.{ P2.ident(1), 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    t.expected.p1.get(1).hp -= 34;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (216/256) * (255/256) * (206/256) * (1/39) * (3/8)
    try t.expectProbability(709155, 109051904);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(2) });
    t.expected.p1.get(2).hp -= 68;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.turn(.{7});

    // Ignores type immunity and works across switches
    try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
    try t.expectProbability(255, 256);

    try t.log.expected.move(.{ P1.ident(2), Move.Teleport, P1.ident(2) });
    if (!showdown) {
        try t.log.expected.fail(.{ P1.ident(2), .None });
        try t.log.expected.laststill(.{});
    }
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(2) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{8});

    // Certain zero damage moves like Teleport should not reset it
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(2), Move.SeismicToss, P2.ident(1) });
    t.expected.p2.get(1).hp -= 100;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(2) });
    t.expected.p1.get(2).hp -= 200;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.turn(.{9});

    // Fixed damage works with Seismic Toss
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(65025, 65536); //  (255/256) * (255/256

    try t.log.expected.switched(.{ P1.ident(3), t.expected.p1.get(3) });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(3) });
    t.expected.p1.get(3).hp -= 400;
    try t.log.expected.damage(.{ P1.ident(3), t.expected.p1.get(3), .None });
    try t.log.expected.turn(.{10});

    // Last damage gets updated to the damage Counter inflicted and doubles again
    try expectEqual(Result.Default, try t.update(swtch(3), move(1)));
    try t.expectProbability(255, 256);

    try t.log.expected.move(.{ P1.ident(3), Move.LovelyKiss, P2.ident(1) });
    t.expected.p2.get(1).status = Status.slp(3);
    const from: protocol.Status = .From;
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, from, Move.LovelyKiss });
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{11});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(573, 896); // (191/256) * (6/7)

    try t.log.expected.move(.{ P1.ident(3), Move.Reflect, P1.ident(3) });
    t.expected.p2.get(1).status -= 1;
    try t.log.expected.start(.{ P1.ident(3), .Reflect });
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{12});

    // When slept, Counter's negative priority gets preserved
    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(5, 6);

    try t.verify();
}

// Move.{Recover,SoftBoiled}
test "Heal effect" {
    // The user restores 1/2 of its maximum HP, rounded down. Fails if (user's maximum HP - user's
    // current HP + 1) is divisible by 256.
    // https://pkmn.cc/bulba-glitch-1#HP_re covery_move_failure
    var t = Test((if (showdown)
        .{ HIT, CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG }
    else
        .{ CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
        &.{.{ .species = .Alakazam, .moves = &.{ .Recover, .MegaKick } }},
        &.{.{ .species = .Chansey, .hp = 448, .moves = &.{ .SoftBoiled, .MegaPunch } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.SoftBoiled, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{2});

    // Fails at full health or at specific fractions
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.MegaKick, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 362;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.MegaPunch, P1.ident(1) });
    t.expected.p1.get(1).hp -= 51;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (191/256) * (216/256) * (60/256) * (231/256) * (1/39) ** 2
    try t.expectProbability(1985445, 22682796032);

    try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
    t.expected.p1.get(1).hp += 51;
    try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.SoftBoiled, P2.ident(1) });
    t.expected.p2.get(1).hp += 351;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{4});

    // Heals 1/2 of maximum HP
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try t.verify();
}

// Move.Rest
test "Rest effect" {
    // The user falls asleep for the next two turns and restores all of its HP, curing itself of any
    // non-volatile status condition in the process. This does not remove the user's stat penalty
    // for burn or paralysis. Fails if the user has full HP.
    // https://pkmn.cc/bulba-glitch-1#HP_recovery_move_failure
    const PROC = comptime ranged(63, 256) - 1;
    const NO_PROC = PROC + 1;

    var t = Test((if (showdown)
        .{ HIT, HIT, ~CRIT, MIN_DMG, NO_PROC, NOP, HIT, ~CRIT, MIN_DMG }
    else
        .{ HIT, ~CRIT, MIN_DMG, HIT, NO_PROC, ~CRIT, MIN_DMG, HIT })).init(
        &.{
            .{ .species = .Porygon, .moves = &.{ .ThunderWave, .Tackle, .Rest } },
            .{ .species = .Dragonair, .moves = &.{.Slam} },
        },
        &.{
            .{ .species = .Chansey, .hp = 192, .moves = &.{ .Rest, .Splash } },
            .{ .species = .Jynx, .moves = &.{.Hypnosis} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Rest, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.ThunderWave, P2.ident(1) });
    t.expected.p2.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.turn(.{2});

    // Fails at specific fractions
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(255, 256);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);
    try expectEqual(49, t.actual.p2.active.stats.spe);
    try expectEqual(198, t.actual.p2.get(1).stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
    t.expected.p2.get(1).hp -= 77;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Rest, P2.ident(1) });
    t.expected.p2.get(1).hp += 588;
    t.expected.p2.get(1).status = Status.slf(2);
    try t.log.expected.status(.{ P2.ident(1), Status.slf(2), .From, Move.Rest });
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Silent });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(7139, 425984); // (242/256) * (236/256) * (1/39) * (3/4)
    try expectEqual(Status.slf(2), t.actual.p2.get(1).status);

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2), move(3) }, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    if (showdown) {
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);
    } else {
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(0) }, choices[0..n]);
    }

    try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
    t.expected.p2.get(1).hp -= 77;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status -= 1;
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(7139, 319488); // (242/256) * (236/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Rest, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Message });
    t.expected.p2.get(1).status = 0;
    try t.log.expected.turn(.{5});

    // Fails at full HP / Last two turns but stat penalty still remains after waking
    try expectEqual(Result.Default, try t.update(move(3), forced));
    try t.expectProbability(1, 1);
    try expectEqual(0, t.actual.p2.get(1).status);
    try expectEqual(49, t.actual.p2.active.stats.spe);
    try expectEqual(198, t.actual.p2.get(1).stats.spe);

    try t.verify();
}

// Move.{Absorb,MegaDrain,LeechLife}
test "DrainHP effect" {
    // The user recovers 1/2 the HP lost by the target, rounded down.
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
        &.{
            .{ .species = .Slowpoke, .hp = 1, .moves = &.{.Splash} },
            .{ .species = .Butterfree, .moves = &.{.MegaDrain} },
        },
        &.{.{ .species = .Parasect, .hp = 300, .moves = &.{.LeechLife} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.LeechLife, P1.ident(1) });
    try t.log.expected.supereffective(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 1;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp += 1;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Drain, P1.ident(1) });
    try t.log.expected.faint(.{ P1.ident(1), true });

    // Heals at least 1 HP
    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    try t.expectProbability(20485, 851968); // (255/256) * (241/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(2), Move.MegaDrain, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 6;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.LeechLife, P1.ident(2) });
    try t.log.expected.resisted(.{P1.ident(2)});
    t.expected.p1.get(2).hp -= 16;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    t.expected.p2.get(1).hp += 8;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Drain, P1.ident(2) });
    try t.log.expected.turn(.{3});

    // Heals 1/2 of the damage dealt unless the user is at full health
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (241/256 * (221/256)) * (1/39) ** 2
    try t.expectProbability(29600825, 55834574848);
    try t.verify();
}

// Move.DreamEater
test "DreamEater effect" {
    // The target is unaffected by this move unless it is asleep. The user recovers 1/2 the HP lost
    // by the target, rounded down, but not less than 1 HP. If this move breaks the target's
    // substitute, the user does not recover any HP.
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                HIT, MAX, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, NOP,
            } else .{
                ~CRIT, MIN_DMG, ~CRIT, HIT, MAX, ~CRIT, MIN_DMG, HIT,
                ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            }
        // zig fmt: on
        ).init(
            &.{.{ .species = .Hypno, .hp = 100, .moves = &.{ .DreamEater, .Hypnosis, .Splash } }},
            &.{
                .{ .species = .Wigglytuff, .hp = 182, .moves = &.{.Splash} },
                .{ .species = .Gengar, .moves = &.{ .Substitute, .Rest } },
            },
        );

        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.DreamEater, P2.ident(1) });
        try t.log.expected.immune(.{ P2.ident(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.turn(.{2});

        // Fails unless the target is sleeping
        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P1.ident(1), Move.Hypnosis, P2.ident(1) });
        t.expected.p2.get(1).status = Status.slp(7);
        try t.log.expected.status(.{
            P2.ident(1),
            t.expected.p2.get(1).status,
            .From,
            Move.Hypnosis,
        });
        try t.log.expected.cant(.{ P2.ident(1), .Sleep });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        try t.expectProbability(459, 896); // (153/256) * (6/7)

        try t.log.expected.move(.{ P1.ident(1), Move.DreamEater, P2.ident(1) });
        t.expected.p2.get(1).hp -= 181;
        t.expected.p2.get(1).status -= 1;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        t.expected.p1.get(1).hp += 90;
        try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Drain, P2.ident(1) });
        try t.log.expected.cant(.{ P2.ident(1), .Sleep });
        try t.log.expected.turn(.{4});

        // Heals 1/2 of the damage dealt
        try expectEqual(Result.Default, try t.update(move(1), forced));
        try t.expectProbability(94775, 5111808); // (255/256) * (223/256) * (1/39) * (5/6)

        try t.log.expected.move(.{ P1.ident(1), Move.DreamEater, P2.ident(1) });
        t.expected.p2.get(1).hp -= 1;
        t.expected.p2.get(1).status -= 1;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        t.expected.p1.get(1).hp += 1;
        try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Drain, P2.ident(1) });
        try t.log.expected.faint(.{ P2.ident(1), true });

        // Heals at least 1 HP
        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(1), forced));
        try t.expectProbability(18955, 851968); // (255/256) * (223/256) * (1/39)

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(.{}, swtch(2)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P2.ident(2), Move.Substitute, P2.ident(2) });
        try t.log.expected.start(.{ P2.ident(2), .Substitute });
        t.expected.p2.get(2).hp -= 80;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.turn(.{6});

        try expectEqual(Result.Default, try t.update(move(3), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(81, t.actual.p2.active.volatiles.substitute);

        try t.log.expected.move(.{ P2.ident(2), Move.Rest, P2.ident(2) });
        t.expected.p2.get(2).hp += 80;
        t.expected.p2.get(2).status = Status.slf(2);
        try t.log.expected.status(.{ P2.ident(2), t.expected.p2.get(2).status, .From, Move.Rest });
        try t.log.expected.heal(.{ P2.ident(2), t.expected.p2.get(2), .Silent });
        try t.log.expected.move(.{ P1.ident(1), Move.DreamEater, P2.ident(2) });
        if (showdown) {
            try t.log.expected.immune(.{ P2.ident(2), .None });
        } else {
            try t.log.expected.supereffective(.{P2.ident(2)});
            try t.log.expected.end(.{ P2.ident(2), .Substitute });
        }
        try t.log.expected.turn(.{7});

        // Substitute blocks Dream Eater on Pokémon Showdown
        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        // (255/256) * (223/256) * (1/39)
        try if (showdown) t.expectProbability(1, 1) else t.expectProbability(18955, 851968);
        try expectEqual(if (showdown) 81 else 0, t.actual.p2.active.volatiles.substitute);

        try t.verify();
    }
    // Invulnerable
    {
        var t = Test(if (showdown) .{} else .{ ~CRIT, MIN_DMG }).init(
            &.{.{ .species = .Drowzee, .moves = &.{
                .DreamEater,
            } }},
            &.{.{ .species = .Dugtrio, .moves = &.{.Dig} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Dig, ID{} });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P2.ident(1), Move.Dig });
        try t.log.expected.move(.{ P1.ident(1), Move.DreamEater, P2.ident(1) });
        if (showdown) {
            try t.log.expected.lastmiss(.{});
            try t.log.expected.miss(.{P1.ident(1)});
        } else {
            try t.log.expected.immune(.{ P2.ident(1), .None });
        }
        try t.log.expected.turn(.{2});

        // Missing due to Invulnerability takes precedence on Pokémon Showdown
        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try t.verify();
    }
}

// Move.LeechSeed
test "LeechSeed effect" {
    // At the end of each of the target's turns, The Pokemon at the user's position steals 1/16 of
    // the target's maximum HP, rounded down and multiplied by the target's current Toxic counter if
    // it has one, even if the target currently has less than that amount of HP remaining. If the
    // target switches out or any Pokemon uses Haze, this effect ends. Grass-type Pokemon are immune
    // to this move.
    var t = Test((if (showdown)
        .{ ~HIT, HIT, HIT, HIT, HIT }
    else
        .{ HIT, ~HIT, HIT, HIT, HIT, HIT })).init(
        &.{
            .{ .species = .Venusaur, .moves = &.{.LeechSeed} },
            .{ .species = .Exeggutor, .moves = &.{ .LeechSeed, .Splash } },
        },
        &.{
            .{ .species = .Gengar, .moves = &.{ .LeechSeed, .Substitute, .NightShade } },
            .{ .species = .Slowbro, .hp = 1, .moves = &.{.Splash} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.LeechSeed, P1.ident(1) });
    if (showdown) {
        try t.log.expected.immune(.{ P1.ident(1), .None });
    } else {
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
    }
    try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.turn(.{2});

    // Leed Seed can miss / Grass-type Pokémon are immune
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(27, 256);

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 80;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
    try t.log.expected.turn(.{3});

    // Leech Seed ignores Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(229, 256);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    try t.log.expected.turn(.{4});

    // Leech Seed does not |-heal| when at full health
    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));

    try t.log.expected.move(.{ P2.ident(1), Move.NightShade, P1.ident(2) });
    t.expected.p1.get(2).hp -= 100;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    t.expected.p1.get(2).hp += 20;
    try t.log.expected.heal(.{ P1.ident(2), t.expected.p1.get(2), .Silent });
    try t.log.expected.move(.{ P1.ident(2), Move.LeechSeed, P2.ident(1) });
    if (!showdown) {
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(2)});
    }
    try t.log.expected.turn(.{5});

    // Leech Seed fails if already seeded / heals back damage
    try expectEqual(Result.Default, try t.update(move(1), move(3)));

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(2), Move.LeechSeed, P2.ident(2) });
    try t.log.expected.start(.{ P2.ident(2), .LeechSeed });
    try t.log.expected.turn(.{6});

    // Switching breaks Leech Seed
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));

    try t.log.expected.move(.{ P1.ident(2), Move.Splash, P1.ident(2) });
    try t.log.expected.activate(.{ P1.ident(2), .Splash });
    try t.log.expected.move(.{ P2.ident(2), Move.Splash, P2.ident(2) });
    try t.log.expected.activate(.{ P2.ident(2), .Splash });
    t.expected.p2.get(2).hp = 0;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .LeechSeed });
    t.expected.p1.get(2).hp += 24;
    try t.log.expected.heal(.{ P1.ident(2), t.expected.p1.get(2), .Silent });
    try t.log.expected.faint(.{ P2.ident(2), true });

    // Leech Seed's uncapped damage is added back
    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(2), move(1)));
    try t.verify();
}

// Move.PayDay
test "PayDay effect" {
    // "Scatters coins"
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT, CRIT, MAX_DMG }
    else
        .{ ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT, CRIT, MAX_DMG, HIT })).init(
        &.{.{ .species = .Meowth, .moves = &.{.PayDay} }},
        &.{.{ .species = .Slowpoke, .moves = &.{ .Substitute, .Splash } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.PayDay, P2.ident(1) });
    t.expected.p2.get(1).hp -= 43;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.fieldactivate(.{});
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 95;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(17935, 851968); // (255/256) * (211/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.PayDay, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    if (!showdown) try t.log.expected.fieldactivate(.{});
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(17935, 851968); // (255/256) * (211/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.PayDay, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(3825, 851968); // (255/256) * (45/256) * (1/39)
    try t.verify();
}

// Move.Rage
test "Rage effect" {
    // Once this move is successfully used, the user automatically uses this move every turn and can
    // no longer switch out. During the effect, the user's Attack is raised by 1 stage every time it
    // is hit by the opposing Pokemon, and this move's accuracy is overwritten every turn with the
    // current calculated accuracy including stat stage changes, but not to less than 1/256 or more
    // than 255/256.

    const DISABLE_MOVE_1 = if (showdown) comptime ranged(1, 2) - 1 else 0;
    const DISABLE_DURATION_5 = comptime ranged(5, 9 - 1) - 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, ~HIT,
            HIT, ~CRIT, MIN_DMG, HIT, DISABLE_MOVE_1, DISABLE_DURATION_5,
            ~HIT, HIT, ~CRIT, MAX_DMG,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, ~HIT,
            ~CRIT, MIN_DMG, HIT, ~CRIT, HIT, DISABLE_MOVE_1, DISABLE_DURATION_5,
            ~CRIT, MIN_DMG, ~HIT, ~CRIT, MAX_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Charmeleon, .moves = &.{ .Rage, .Flamethrower } },
            .{ .species = .Doduo, .moves = &.{.DrillPeck} },
        },
        &.{
            .{ .species = .Grimer, .moves = &.{ .Pound, .Disable, .SelfDestruct } },
            .{ .species = .Tentacruel, .moves = &.{.Surf} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Rage, P2.ident(1) });
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Pound, P1.ident(1) });
    t.expected.p1.get(1).hp -= 35;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (216/256) * (244/256) * (1/39) ** 2
    try t.expectProbability(11899575, 22682796032);
    try expectEqual(1, t.actual.p1.active.boosts.atk);

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.Rage, P2.ident(1) });
    t.expected.p2.get(1).hp -= 25;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Disable, P1.ident(1) });
    if (!showdown) try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    if (showdown) try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(66555, 6815744); // (255/256) * (116/256) * (216/256) * (1/39)
    try expectEqual(2, t.actual.p1.active.boosts.atk);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.Rage, P2.ident(1) });
    t.expected.p2.get(1).hp -= 34;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Disable, P1.ident(1) });
    if (!showdown) try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    try t.log.expected.start(.{ P1.ident(1), .Disable, Move.Rage });
    if (showdown) try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(80325, 13631488); // (255/256) *  (140/256) * (216/256) * (1/39) * (1/2)
    try expectEqual(3, t.actual.p1.active.boosts.atk);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.cant(.{ P1.ident(1), .Disable, Move.Rage });
    try t.log.expected.move(.{ P2.ident(1), Move.SelfDestruct, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    t.expected.p2.get(1).hp = 0;
    try t.log.expected.faint(.{ P2.ident(1), true });

    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(forced, move(3)));
    try t.expectProbability(7, 2048); // (7/8) * (1/256)
    try expectEqual(4, t.actual.p1.active.boosts.atk);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(.{}, swtch(2)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P2.ident(2), Move.Surf, P1.ident(1) });
    try t.log.expected.supereffective(.{P1.ident(1)});
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.faint(.{ P1.ident(1), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(forced, move(1)));
    try t.expectProbability(8755, 425984); // (255/256) * (206/256) * (1/39)
    try expectEqual(31, t.actual.p1.active.move(1).pp);

    try t.verify();
}

// Move.Mimic
test "Mimic effect" {
    // While the user remains active, this move is replaced by a random move known by the target,
    // even if the user already knows that move. The copied move keeps the remaining PP for this
    // move, regardless of the copied move's maximum PP. Whenever one PP is used for a copied move,
    // one PP is used for this move.
    var t = Test((if (showdown) .{ HIT, MAX } else .{ HIT, 2 })).init(
        &.{
            .{ .species = .MrMime, .moves = &.{.Mimic} },
            .{ .species = .Abra, .moves = &.{.Splash} },
        },
        &.{.{ .species = .Jigglypuff, .moves = &.{ .Blizzard, .Thunderbolt, .Splash } }},
    );
    defer t.deinit();

    const pp = t.expected.p1.get(1).move(1).pp;

    try expectEqual(Move.Mimic, t.actual.p1.get(1).move(1).id);
    try expectEqual(pp, t.actual.p1.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.Mimic, P2.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Mimic, Move.Splash });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    try t.expectProbability(85, 256); // (255/256) * (1/3)
    try expectEqual(Move.Splash, t.actual.p1.active.move(1).id);
    try expectEqual(pp - 1, t.actual.p1.active.move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    try t.expectProbability(1, 1);
    try expectEqual(Move.Splash, t.actual.p1.active.move(1).id);
    try expectEqual(pp - 2, t.actual.p1.active.move(1).pp);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(swtch(2), move(3)));
    try t.expectProbability(1, 1);

    try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(swtch(2), move(3)));
    try t.expectProbability(1, 1);
    try expectEqual(Move.Mimic, t.actual.p1.active.move(1).id);
    try expectEqual(pp - 2, t.actual.p1.active.move(1).pp);

    try t.verify();
}

// Move.LightScreen
test "LightScreen effect" {
    // While the user remains active, its Special is doubled when taking damage. Critical hits
    // ignore this effect. If any Pokemon uses Haze, this effect ends.
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MIN_DMG }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MIN_DMG, HIT })).init(
        &.{.{ .species = .Chansey, .moves = &.{ .LightScreen, .Splash } }},
        &.{.{ .species = .Vaporeon, .moves = &.{ .WaterGun, .Haze } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    t.expected.p1.get(1).hp -= 45;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.LightScreen, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .LightScreen });
    try t.log.expected.turn(.{2});

    // Water Gun does normal damage before Light Screen
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(595, 26624); // (255/256) * (224/256) * (1/39)
    try expect(t.actual.p1.active.volatiles.LightScreen);

    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    t.expected.p1.get(1).hp -= 23;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    // Water Gun's damage is reduced after Light Screen
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(595, 26624); // (255/256) * (224/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.WaterGun, P1.ident(1) });
    try t.log.expected.crit(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 87;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{4});

    // Critical hits ignore Light Screen
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(85, 26624); // (255/256) * (32/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.Haze, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    try t.log.expected.end(.{ P1.ident(1), .LightScreenSilent });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{5});

    // Haze removes Light Screen
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(1, 1);
    try expect(!t.actual.p1.active.volatiles.LightScreen);

    try t.verify();
}

// Move.Reflect
test "Reflect effect" {
    // While the user remains active, its Defense is doubled when taking damage. Critical hits
    // ignore this protection. This effect can be removed by Haze.
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MIN_DMG }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MIN_DMG, HIT })).init(
        &.{.{ .species = .Chansey, .moves = &.{ .Reflect, .Splash } }},
        &.{.{ .species = .Vaporeon, .moves = &.{ .Tackle, .Haze } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 54;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Reflect });
    try t.log.expected.turn(.{2});

    // Tackle does normal damage before Reflect
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(847, 39936); // (242/256) * (224/256) * (1/39)
    try expect(t.actual.p1.active.volatiles.Reflect);

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    t.expected.p1.get(1).hp -= 28;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    // Tackle's damage is reduced after Reflect
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(847, 39936); // (242/256) * (224/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1) });
    try t.log.expected.crit(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 104;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{4});

    // Critical hits ignore Reflect
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(121, 39936); // (242/256) * (32/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.Haze, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    try t.log.expected.end(.{ P1.ident(1), .ReflectSilent });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{5});

    // Haze removes Reflect
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(1, 1);
    try expect(!t.actual.p1.active.volatiles.Reflect);

    try t.verify();
}

// Move.Haze
test "Haze effect" {
    // Resets the stat stages of both Pokemon to 0 and removes stat reductions due to burn and
    // paralysis. Resets Toxic counters to 0 and removes the effect of confusion, Disable, Focus
    // Energy, Leech Seed, Light Screen, Mist, and Reflect from both Pokemon. Removes the opponent's
    // non-volatile status condition.
    const PAR_CAN = MAX;
    const PROC = MIN;
    const CFZ_5 = if (showdown) MAX else 3;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;

    const haze = comptime metronome(.Haze);
    const ember = comptime metronome(.Ember);

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, HIT,
            HIT, PAR_CAN, HIT, CFZ_5,
            CFZ_CAN, PAR_CAN, haze,
            PAR_CAN, ember, HIT, ~CRIT, MIN_DMG, PROC, PAR_CAN,
        } else .{
            HIT, HIT, ~CRIT, HIT, ~CRIT, PAR_CAN, HIT, CFZ_5,
            CFZ_CAN, PAR_CAN, ~CRIT, haze,
            PAR_CAN, ~CRIT, ember,  ~CRIT, MIN_DMG, HIT, PROC, PAR_CAN, ~CRIT,
        }
    // zig fmt: on
    ).init(
        &.{.{
            .species = .Golbat,
            .moves = &.{ .Toxic, .Agility, .ConfuseRay, .Metronome },
        }},
        &.{.{
            .species = .Exeggutor,
            .moves = &.{ .LeechSeed, .StunSpore, .DoubleTeam, .Splash },
        }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
    t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.LeechSeed, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .LeechSeed });
    t.expected.p2.get(1).hp -= 24;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(6183, 8192); // (216/256) * (229/256)
    try expectEqual(278, t.actual.p1.active.stats.spe);
    try expectEqual(1, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    t.expected.p1.get(1).hp -= 22;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .LeechSeed });
    t.expected.p2.get(1).hp += 22;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Silent });
    try t.log.expected.move(.{ P2.ident(1), Move.StunSpore, P1.ident(1) });
    t.expected.p1.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    t.expected.p2.get(1).hp -= 48;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(191, 256);
    try expectEqual(2, t.actual.p1.active.boosts.spe);
    try expectEqual(139, t.actual.p1.active.stats.spe);
    try expectEqual(2, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P2.ident(1), Move.DoubleTeam, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Evasion, 1 });
    t.expected.p2.get(1).hp -= 72;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.move(.{ P1.ident(1), Move.ConfuseRay, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Confusion });
    t.expected.p1.get(1).hp -= 22;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .LeechSeed });
    t.expected.p2.get(1).hp += 22;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Silent });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(3), move(3)));
    try t.expectProbability(63, 128); // (3/4) * (168/256)
    try expectEqual(1, t.actual.p2.active.boosts.evasion);
    try expect(t.actual.p2.active.volatiles.Confusion);
    try expectEqual(3, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    t.expected.p2.get(1).hp -= 96;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Haze, P1.ident(1), Move.Metronome });
    try t.log.expected.activate(.{ P1.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    if (showdown) {
        try t.log.expected.end(.{ P1.ident(1), .LeechSeedSilent });
        try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Silent });
    } else {
        try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Silent });
        try t.log.expected.end(.{ P1.ident(1), .LeechSeedSilent });
    }
    t.expected.p2.get(1).status = 0;
    try t.log.expected.end(.{ P2.ident(1), .ConfusionSilent });
    if (showdown) try t.log.expected.end(.{ P2.ident(1), .ToxicSilent });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(4), move(4)));
    try t.expectProbability(3, 1304); // (1/2) * (3/4) * (1/163)
    try expect(!t.actual.p1.active.volatiles.LeechSeed);
    try expectEqual(0, t.actual.p1.active.boosts.spe);
    try expectEqual(278, t.actual.p1.active.stats.spe);
    try expectEqual(if (showdown) 0 else 4, t.actual.p2.active.volatiles.toxic);
    try expect(!t.actual.p2.active.volatiles.Confusion);
    try expectEqual(0, t.actual.p2.active.boosts.evasion);

    try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Ember, P2.ident(1), Move.Metronome });
    try t.log.expected.supereffective(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 42;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.BRN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    t.expected.p2.get(1).hp -= 24;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(4), move(4)));
    // (3/4) * (1/163) * (255/256) * (211/256) * (1/39) * (26/256)
    try t.expectProbability(53805, 5469372416);
    try expectEqual(if (showdown) 0 else 4, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    t.expected.p2.get(1).hp -= 24;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    try t.log.expected.turn(.{7});

    const result = Result.Default;
    try expectEqual(result, try t.update(move(2), move(4)));
    try t.expectProbability(3, 4);
    try expectEqual(2, t.actual.p1.active.boosts.spe);
    try expectEqual(556, t.actual.p1.active.stats.spe);

    try t.verify();
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
    // Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Splash, Thunder
    // Wave, Toxic, or Transform, the previous damage dealt to the user will be added to the total.
    {
        const BIDE_3 = MAX;
        const CFZ_3 = if (showdown) comptime ranged(2, 6 - 2) - 1 else 1;
        const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;

        var t = Test(
        // zig fmt: off
        if (showdown) .{
            BIDE_3, HIT, HIT, HIT, ~CRIT, MIN_DMG, BIDE_3, HIT, HIT, CFZ_3, CFZ_CAN,
        } else .{
            ~CRIT, BIDE_3, HIT, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, BIDE_3, HIT, HIT, CFZ_3, CFZ_CAN,
        }
        // zig fmt: on
        ).init(
            &.{
                .{ .species = .Chansey, .moves = &.{ .Bide, .Splash } },
                .{ .species = .Onix, .moves = &.{.Bide} },
            },
            &.{
                .{ .species = .Magnemite, .moves = &.{.SonicBoom} },
                .{ .species = .Dugtrio, .moves = &.{.Dig} },
                .{ .species = .Haunter, .moves = &.{ .NightShade, .ConfuseRay } },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Bide, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Bide });
        try t.log.expected.move(.{ P2.ident(1), Move.SonicBoom, P1.ident(1) });
        t.expected.p1.get(1).hp -= 20;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(229, 256);

        var n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), forced }, choices[0..n]);

        try t.log.expected.activate(.{ P1.ident(1), .Bide });
        try t.log.expected.move(.{ P2.ident(1), Move.SonicBoom, P1.ident(1) });
        t.expected.p1.get(1).hp -= 20;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, move(1)));
        try t.expectProbability(229, 256);

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.activate(.{ P1.ident(1), .Bide });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(forced, swtch(2)));
        try t.expectProbability(1, 2);

        try t.log.expected.move(.{ P2.ident(2), Move.Dig, ID{} });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P2.ident(2), Move.Dig });
        try t.log.expected.end(.{ P1.ident(1), .Bide });
        t.expected.p2.get(2).hp -= 120;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(forced, move(1)));
        try t.expectProbability(1, 1);

        n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), move(2) }, choices[0..n]);

        try t.log.expected.move(.{ P2.ident(2), Move.Dig, P1.ident(1) });
        t.expected.p1.get(1).hp -= 256;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Bide, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Bide });
        try t.log.expected.turn(.{6});

        try expectEqual(Result.Default, try t.update(move(1), forced));
        try t.expectProbability(4165, 212992); // (255/256) * (196/256) * (1/39)

        try t.log.expected.switched(.{ P2.ident(3), t.expected.p2.get(3) });
        try t.log.expected.activate(.{ P1.ident(1), .Bide });
        try t.log.expected.turn(.{7});

        try expectEqual(Result.Default, try t.update(forced, swtch(3)));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P2.ident(3), Move.NightShade, P1.ident(1) });
        t.expected.p1.get(1).hp -= 100;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.activate(.{ P1.ident(1), .Bide });
        try t.log.expected.turn(.{8});

        try expectEqual(Result.Default, try t.update(forced, move(1)));
        try t.expectProbability(255, 512); // (255/256) * (1/2)

        try t.log.expected.move(.{ P2.ident(3), Move.ConfuseRay, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Confusion });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.end(.{ P1.ident(1), .Bide });
        t.expected.p2.get(3).hp = 0;
        try t.log.expected.damage(.{ P2.ident(3), t.expected.p2.get(3), .None });
        try t.log.expected.faint(.{ P2.ident(3), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(forced, move(2)));
        try t.expectProbability(255, 512); // (255/256) * (1/2)
        try expectEqual(14, t.actual.p1.get(1).move(1).pp);

        try t.verify();
    }
    // failure
    {
        const BIDE_2 = MIN;
        var t = Test((if (showdown) .{ HIT, BIDE_2 } else .{ HIT, ~CRIT, BIDE_2 })).init(
            &.{.{ .species = .Wartortle, .moves = &.{ .SeismicToss, .Splash } }},
            &.{.{ .species = .Pinsir, .level = 50, .moves = &.{.Bide} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.SeismicToss, P2.ident(1) });
        t.expected.p2.get(1).hp -= 100;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Bide, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Bide });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.activate(.{ P2.ident(1), .Bide });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), forced));
        try t.expectProbability(1, 1);

        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.end(.{ P2.ident(1), .Bide });
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(2), forced));
        try t.expectProbability(1, 2);
        try t.verify();
    }
}

// Move.Metronome
test "Metronome effect" {
    // A random move is selected for use, other than Metronome or Struggle.
    const MIN_WRAP = MIN;
    const THRASH_3 = if (showdown) comptime ranged(1, 4 - 2) - 1 else MIN;
    const CFZ_2 = MIN;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;
    const MIMIC_2 = if (showdown) MAX else 1;
    const DISABLE_MOVE_2 = if (showdown) comptime ranged(2, 3) - 1 else 1;
    const DISABLE_DURATION_3 = comptime ranged(3, 9 - 1) - 1;

    const wrap = comptime metronome(.Wrap);
    const petal_dance = comptime metronome(.PetalDance);
    const mimic = comptime metronome(.Mimic);
    const disable = comptime metronome(.Disable);
    const rage = comptime metronome(.Rage);
    const quick_attack = comptime metronome(.QuickAttack);

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            wrap, HIT, ~CRIT, MIN_DMG, MIN_WRAP,
            // BUG: tackle, HIT,
            petal_dance, THRASH_3, HIT, ~CRIT, MIN_DMG,
            ~HIT, CFZ_2, ~HIT,
            CFZ_CAN, mimic, HIT, MIMIC_2, disable, HIT,
            DISABLE_MOVE_2, DISABLE_DURATION_3,
            rage, HIT, ~CRIT, MIN_DMG, quick_attack, HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, wrap, MIN_WRAP, ~CRIT, MIN_DMG, HIT,
            ~CRIT, petal_dance, THRASH_3, ~CRIT, MIN_DMG, HIT,
            ~CRIT, MIN_DMG, ~HIT, CFZ_2, ~CRIT, MIN_DMG, ~HIT,
            CFZ_CAN, ~CRIT, mimic, HIT, MIMIC_2, ~CRIT, disable, ~CRIT,
            HIT, DISABLE_MOVE_2, DISABLE_DURATION_3,
            ~CRIT, rage, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Clefable, .moves = &.{ .Metronome, .Splash } }},
        &.{.{ .species = .Primeape, .moves = &.{ .Metronome, .Mimic, .FurySwipes } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1), Move.Metronome });
    t.expected.p1.get(1).hp -= 14;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.cant(.{ P1.ident(1), .Bound });
    try t.log.expected.turn(.{2});

    // Pokémon Showdown partial trapping lock doesn't work with Metronome...
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1881, 17358848); // (1/163) * (216/256) * (209/256) * (1/39)

    var n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(
        Choice,
        if (showdown) &[_]Choice{ move(1), move(2), move(3) } else &[_]Choice{forced},
        choices[0..n],
    );

    if (showdown) {
        // try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        // try t.log.expected.move(.{ P2.ident(1), Move.Tackle, P1.ident(1), Move.Metronome });
        // BUG: can't implement Pokémon Showdown's broken partialtrappinglock mechanics
        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P1.ident(1) });
    } else {
        try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1) });
    }
    t.expected.p1.get(1).hp -= 14;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.cant(.{ P1.ident(1), .Bound });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, forced));
    try t.expectProbability(3, 8);

    try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.PetalDance, P1.ident(1), Move.Metronome });
    t.expected.p1.get(1).hp -= 41;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(17765, 138870784); // (1/163) * (255/256) * (209/256) * (1/39)

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.move(.{ P2.ident(1), Move.PetalDance, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(1, 256);

    if (!showdown) try t.log.expected.start(.{ P2.ident(1), .ConfusionSilent });
    try t.log.expected.move(.{ P2.ident(1), Move.PetalDance, P1.ident(1) });
    if (showdown) try t.log.expected.start(.{ P2.ident(1), .ConfusionSilent });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(1, 512); // (1/2) * (1/256)

    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Mimic, P1.ident(1), Move.Metronome });
    try t.log.expected.start(.{ P2.ident(1), .Mimic, Move.Splash });
    try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1), Move.Metronome });
    const disabled = if (showdown) Move.Splash else Move.Mimic;
    try t.log.expected.start(.{ P2.ident(1), .Disable, disabled });
    try t.log.expected.turn(.{7});

    // Metronome -> Mimic only works on Pokémon Showdown if Mimic
    // is in the moveset and replaces *that* slot instead of Metronome
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (1/2) ** 2 * (1/163) ** 2 * (255/256) * (140/256) * (1/3)
    try t.expectProbability(2975, 1741225984);

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(3) }, choices[0..n]);

    try t.log.expected.end(.{ P2.ident(1), .Confusion });
    if (showdown) {
        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Rage, P1.ident(1), Move.Metronome });
        t.expected.p1.get(1).hp -= 19;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.QuickAttack, P2.ident(1), Move.Metronome });
        t.expected.p2.get(1).hp -= 48;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.boost(.{ P2.ident(1), .Rage, 1 });
    } else {
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Rage, P2.ident(1), Move.Metronome });
        t.expected.p2.get(1).hp -= 25;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    }
    try t.log.expected.turn(.{8});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    if (showdown) {
        // (7/8) * (1/4) * (1/163) ** 2 * (255/256) ** 2 * (209/256) * (226/256) * (1/39) ** 2
        try t.expectProbability(1194429775, 308561514380394496);
    } else {
        // (7/8) * (1/4) * (1/163) * (255/256) * (226/256) * (1/39)
        try t.expectProbability(67235, 2221932544);
    }

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(
        Choice,
        if (showdown) &[_]Choice{ move(1), move(2) } else &[_]Choice{forced},
        choices[0..n],
    );
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(
        Choice,
        if (showdown) &[_]Choice{forced} else &[_]Choice{ move(1), move(3) },
        choices[0..n],
    );

    try t.verify();
}

// Move.MirrorMove
test "MirrorMove effect" {
    // The user uses the last move used by the target. Fails if the target has not made a move, or
    // if the last move used was Mirror Move.
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, ~CRIT, MIN_DMG,
            ~CRIT, MIN_DMG, ~CRIT, MIN_DMG,
            ~CRIT, MIN_DMG, ~HIT, ~HIT,
        } else .{
            ~CRIT, ~CRIT, ~CRIT, MIN_DMG, HIT, ~CRIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG,
            ~CRIT, ~CRIT, MIN_DMG, ~CRIT, ~CRIT, MIN_DMG,
            ~CRIT, ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, ~HIT, ~CRIT,
            ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, ~HIT, ~CRIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Fearow, .moves = &.{ .MirrorMove, .Peck, .Fly } }},
        &.{
            .{ .species = .Pidgeot, .moves = &.{ .MirrorMove, .Swift } },
            .{ .species = .Pidgeotto, .moves = &.{.Gust} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{2});

    // Can't Mirror Move if no move has been used or if Mirror Move is last used
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(Move.MirrorMove, t.actual.p1.last_used_move);
    try expectEqual(Move.MirrorMove, t.actual.p2.last_used_move);
    try expectEqual(31, t.actual.p1.get(1).move(1).pp);
    try expectEqual(31, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    t.expected.p2.get(1).hp -= 43;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Peck, P1.ident(1), Move.MirrorMove });
    t.expected.p1.get(1).hp -= 44;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    // Can Mirror Move regular attacks
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    // (255/256) ** 2 * (206/256) * (211/256) * (1/39) ** 2
    try t.expectProbability(157020925, 362924736512);
    try expectEqual(Move.Peck, t.actual.p1.last_used_move);
    try expectEqual(Move.Peck, t.actual.p2.last_used_move);
    try expectEqual(31, t.actual.p1.get(1).move(1).pp);
    try expectEqual(30, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1), Move.MirrorMove });
    t.expected.p2.get(1).hp -= 43;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Swift, P1.ident(1) });
    t.expected.p1.get(1).hp -= 74;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    // (255/256) * (206/256) * (211/256) * (1/39) ** 2
    try t.expectProbability(1847305, 4253024256);
    try expectEqual(Move.Peck, t.actual.p1.last_used_move);
    try expectEqual(Move.Swift, t.actual.p2.last_used_move);
    try expectEqual(30, t.actual.p1.get(1).move(1).pp);
    try expectEqual(30, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Swift, P2.ident(1), Move.MirrorMove });
    t.expected.p2.get(1).hp -= 74;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Swift, P1.ident(1), Move.MirrorMove });
    t.expected.p1.get(1).hp -= 74;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(21733, 49840128); // (206/256) * (211/256) * (1/39) ** 2

    try expectEqual(Move.Swift, t.actual.p1.last_used_move);
    try expectEqual(Move.Swift, t.actual.p2.last_used_move);
    try expectEqual(29, t.actual.p1.get(1).move(1).pp);
    try expectEqual(29, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.Fly, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.Fly });
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Swift, P1.ident(1), Move.MirrorMove });
    t.expected.p1.get(1).hp -= 74;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{6});

    // Should actually copy Swift and not Fly
    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    try t.expectProbability(211, 9984); // (211/256) * (1/39)
    try expectEqual(Move.Swift, t.actual.p1.last_used_move);
    try expectEqual(Move.Swift, t.actual.p2.last_used_move);
    try expectEqual(29, t.actual.p1.get(1).move(1).pp);
    try expectEqual(28, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.Fly, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Fly, ID{}, Move.MirrorMove });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P2.ident(1), Move.Fly });
    try t.log.expected.turn(.{7});

    try expectEqual(Result.Default, try t.update(forced, move(1)));
    try t.expectProbability(7, 128); // (14/256)
    try expectEqual(Move.Fly, t.actual.p1.last_used_move);
    try expectEqual(Move.MirrorMove, t.actual.p2.last_used_move);
    try expectEqual(29, t.actual.p1.get(1).move(1).pp);
    try expectEqual(28, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.Fly, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{8});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(7, 128); // (14/256)
    try expectEqual(29, t.actual.p1.get(1).move(1).pp);
    try expectEqual(27, t.actual.p2.get(1).move(1).pp);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.turn(.{9});

    // Switching resets last used moves
    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(1, 1);
    try expectEqual(Move.MirrorMove, t.actual.p1.last_used_move);
    try expectEqual(Move.None, t.actual.p2.last_used_move);
    try expectEqual(28, t.actual.p1.get(1).move(1).pp);

    try t.verify();
}

// Move.{SelfDestruct,Explosion}
test "Explode effect" {
    // The user faints after using this move, unless the target's substitute was broken by the
    // damage. The target's Defense is halved during damage calculation.
    var t = Test((if (showdown)
        .{ HIT, HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG }
    else
        .{ HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, HIT })).init(
        &.{
            .{ .species = .Electrode, .level = 80, .moves = &.{ .Explosion, .Toxic } },
            .{ .species = .Onix, .moves = &.{.SelfDestruct} },
        },
        &.{
            .{ .species = .Chansey, .moves = &.{ .Substitute, .Splash } },
            .{ .species = .Gengar, .moves = &.{.NightShade} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
    t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 175;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).hp -= 43;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(27, 32); // (216/256)

    try t.log.expected.move(.{ P1.ident(1), Move.Explosion, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    t.expected.p2.get(1).hp -= 86;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(7905, 425984); // (255/256) * (186/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Explosion, P2.ident(1) });
    t.expected.p2.get(1).hp -= 342;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.faint(.{ P1.ident(1), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(2)));
    try t.expectProbability(7905, 425984); // (255/256) * (186/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(2), Move.SelfDestruct, P2.ident(2) });
    try t.log.expected.immune(.{ P2.ident(2), .None });
    t.expected.p1.get(2).hp = 0;
    try t.log.expected.faint(.{ P1.ident(2), false });
    try t.log.expected.win(.{.P2});

    try expectEqual(Result.Lose, try t.update(move(1), swtch(2)));
    try t.expectProbability(1, 1);
    try t.verify();
}

// Move.Swift
test "Swift effect" {
    // This move does not check accuracy and hits even if the target is using Dig or Fly.
    var t = Test(.{ ~CRIT, MIN_DMG }).init(
        &.{.{ .species = .Eevee, .moves = &.{.Swift} }},
        &.{.{ .species = .Diglett, .moves = &.{.Dig} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Dig, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P2.ident(1), Move.Dig });
    try t.log.expected.move(.{ P1.ident(1), Move.Swift, P2.ident(1) });
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(229, 9984); // (229/256) * (1/39)

    try t.verify();
}

// Move.Transform
test "Transform effect" {
    // The user transforms into the target. The target's current stats, stat stages, types, moves,
    // DVs, species, and sprite are copied. The user's level and HP remain the same and each copied
    // move receives only 5 PP. This move can hit a target using Dig or Fly.
    const TIE_1 = MIN;
    const TIE_2 = MAX;
    const no_crit = if (showdown) comptime ranged(Species.chance(.Articuno), 256) else 6;
    const DVS = .{ .atk = 0, .def = 0, .spe = 0, .spc = 0 };

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            TIE_1, ~HIT, TIE_2, HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG, TIE_2,
        } else .{
            ~CRIT, ~CRIT, TIE_1, ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, ~HIT,
            TIE_2, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG, HIT,
            TIE_2, ~CRIT, ~CRIT, ~CRIT, ~CRIT, ~CRIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Mew, .level = 50, .moves = &.{ .SwordsDance, .Transform } },
            .{ .species = .Ditto, .dvs = DVS, .moves = &.{.Transform} },
        },
        &.{.{ .species = .Articuno, .moves = &.{ .Agility, .Fly, .Peck } }},
    );
    defer t.deinit();

    const pp = t.expected.p1.get(1).move(2).pp;

    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.SwordsDance, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Attack, 2 });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(2, t.actual.p1.active.boosts.atk);
    try expectEqual(2, t.actual.p2.active.boosts.spe);

    try t.log.expected.move(.{ P2.ident(1), Move.Fly, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P2.ident(1), Move.Fly });
    try t.log.expected.move(.{ P1.ident(1), Move.Transform, P2.ident(1) });
    try t.log.expected.transform(.{ P1.ident(1), P2.ident(1) });
    try t.log.expected.turn(.{3});

    // Transform can hit an invulnerable target
    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(1, 1);

    // Transform should copy species, types, stats, and boosts but not level or HP
    try expectEqual(pp - 1, t.actual.p1.get(1).move(2).pp);

    try expectEqual(Species.Articuno, t.actual.p1.active.species);
    try expectEqual(t.actual.p2.active.types, t.actual.p1.active.types);
    try expectEqual(50, t.actual.p1.get(1).level);

    inline for (@typeInfo(@TypeOf(t.actual.p1.get(1).stats)).Struct.fields) |field| {
        if (!std.mem.eql(u8, field.name, "hp")) {
            try expectEqual(
                @field(t.actual.p2.active.stats, field.name),
                @field(t.actual.p1.active.stats, field.name),
            );
        }
    }
    try expectEqual(t.actual.p2.active.boosts, t.actual.p1.active.boosts);

    const moves = [_]Move{ .Agility, .Fly, .Peck, .None };
    const pps = [_]u8{ 5, 5, 5, 0 };
    for (t.actual.p1.active.moves, 0..) |m, i| {
        try expectEqual(moves[i], m.id);
        try expectEqual(pps[i], m.pp);
    }

    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.Fly, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(3), forced));
    try t.expectProbability(7, 256); // (1/2) * (14/256)

    try t.log.expected.move(.{ P2.ident(1), Move.Peck, P1.ident(1) });
    t.expected.p1.get(1).hp -= 35;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Peck, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 20; // crit = uses untransformed stats
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{5});

    // Transformed Pokémon should retain their original crit rate (and this should speed tie)
    try expectEqual(Result.Default, try t.update(move(3), move(3)));
    // (1/2) * (255/256) ** 2 * (214/256) * (50/256) * (1/39) ** 2
    try t.expectProbability(19326875, 362924736512);

    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 2);

    inline for (@typeInfo(@TypeOf(t.actual.p1.get(1).stats)).Struct.fields) |field| {
        if (!std.mem.eql(u8, field.name, "hp")) {
            try expectEqual(
                @field(t.actual.p2.active.stats, field.name),
                @field(t.actual.p1.active.stats, field.name),
            );
        }
    }
    try expectEqual(t.actual.p2.active.boosts, t.actual.p1.active.boosts);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, 2 });
    try t.log.expected.turn(.{7});

    try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(Species.Mew, t.actual.p1.get(2).species);
    try expectEqual(pp - 1, t.actual.p1.get(2).move(2).pp);

    const stats = t.actual.p1.get(1).stats;
    try expectEqual(stats, t.actual.p1.active.stats);

    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.move(.{ P1.ident(2), Move.Transform, P2.ident(1) });
    try t.log.expected.transform(.{ P1.ident(2), P2.ident(1) });
    try t.log.expected.turn(.{8});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    inline for (@typeInfo(@TypeOf(t.actual.p1.get(1).stats)).Struct.fields) |field| {
        if (!std.mem.eql(u8, field.name, "hp")) {
            try expectEqual(
                @field(t.actual.p2.active.stats, field.name),
                @field(t.actual.p1.active.stats, field.name),
            );
        }
    }

    try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Agility, P2.ident(1) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{9});

    try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(stats, t.actual.p1.get(2).stats);
    try t.verify();
}

// Move.Conversion
test "Conversion effect" {
    // Causes the user's types to become the same as the current types of the target.
    var t = Test(.{}).init(
        &.{.{ .species = .Porygon, .moves = &.{.Conversion} }},
        &.{.{ .species = .Slowbro, .moves = &.{.Splash} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Conversion, P2.ident(1) });
    try t.log.expected.start(.{
        P1.ident(1),
        .TypeChange,
        Types{ .type1 = .Water, .type2 = .Psychic },
        P2.ident(1),
    });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
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
    var t = Test((if (showdown)
        .{ HIT, HIT, ~CRIT, MIN_DMG, HIT, HIT }
    else
        .{ ~CRIT, ~CRIT, MIN_DMG, HIT, ~CRIT, HIT, ~CRIT, HIT })).init(
        &.{
            .{ .species = .Mewtwo, .moves = &.{ .Substitute, .Splash } },
            .{ .species = .Abra, .hp = 3, .level = 2, .stats = .{}, .moves = &.{.Substitute} },
        },
        &.{.{ .species = .Electabuzz, .stats = .{}, .moves = &.{ .Flash, .Strength } }},
    );
    defer t.deinit();

    t.expected.p1.get(2).stats.hp = 3;
    t.actual.p1.get(2).stats.hp = 3;

    try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Substitute });
    t.expected.p1.get(1).hp -= 103;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Flash, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .None });
    try t.log.expected.turn(.{2});

    // Takes 1/4 of maximum HP to make a Substitute with that HP + 1, protects against stat down
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(104, t.actual.p1.active.volatiles.substitute);

    try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
    try t.log.expected.fail(.{ P1.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.Strength, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Substitute });
    try t.log.expected.turn(.{3});

    // Can't make a Substitute if you already have one, absorbs damage
    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(4335, 212992); // (255/256) * (204/256) * (1/39)
    try expectEqual(62, t.actual.p1.active.volatiles.substitute);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Flash, P1.ident(2) });
    try t.log.expected.boost(.{ P1.ident(2), .Accuracy, -1 });
    try t.log.expected.turn(.{4});

    // Disappears when switching out
    try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
    try t.expectProbability(89, 128); // (178/256)
    try expect(!t.actual.p1.active.volatiles.Substitute);

    try t.log.expected.move(.{ P2.ident(1), Move.Flash, P1.ident(2) });
    try t.log.expected.boost(.{ P1.ident(2), .Accuracy, -1 });
    try t.log.expected.move(.{ P1.ident(2), Move.Substitute, P1.ident(2) });
    try t.log.expected.start(.{ P1.ident(2), .Substitute });
    try t.log.expected.turn(.{5});

    // Can get "free" Substitutes if 3 or less max HP
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(89, 128); // (178/256)
    try expectEqual(1, t.actual.p1.active.volatiles.substitute);

    try t.verify();
}

// Pokémon Showdown Bugs

test "Bide residual bug" {
    const BIDE_2 = MIN;

    var t = Test((if (showdown)
        .{ HIT, HIT, BIDE_2, HIT, HIT }
    else
        .{ HIT, HIT, ~CRIT, BIDE_2, HIT, HIT })).init(
        &.{.{ .species = .Jolteon, .moves = &.{ .LeechSeed, .Bide } }},
        &.{
            .{ .species = .Sandslash, .hp = 100, .moves = &.{ .Toxic, .SeismicToss } },
            .{ .species = .Victreebel, .moves = &.{.SolarBeam} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
    try t.log.expected.move(.{ P2.ident(1), Move.Toxic, P1.ident(1) });
    t.expected.p1.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(6183, 8192); // (229/256) * (216/256)

    try t.log.expected.move(.{ P1.ident(1), Move.Bide, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Bide });
    t.expected.p1.get(1).hp -= 20;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
    try t.log.expected.move(.{ P2.ident(1), Move.SeismicToss, P1.ident(1) });
    t.expected.p1.get(1).hp -= 100;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    t.expected.p1.get(1).hp += 22;
    try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(255, 256);

    try t.log.expected.activate(.{ P1.ident(1), .Bide });
    t.expected.p1.get(1).hp -= 40;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
    try t.log.expected.move(.{ P2.ident(1), Move.SeismicToss, P1.ident(1) });
    t.expected.p1.get(1).hp -= 100;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    t.expected.p1.get(1).hp += 22;
    try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
    try t.log.expected.turn(.{4});

    const choice = move(if (showdown) 2 else 0);
    try expectEqual(Result.Default, try t.update(choice, move(2)));
    try t.expectProbability(255, 256);

    try t.log.expected.end(.{ P1.ident(1), .Bide });
    t.expected.p2.get(1).hp = 0;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    if (showdown) {
        t.expected.p1.get(1).hp -= 60;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
    }
    try t.log.expected.faint(.{ P2.ident(1), true });

    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(choice, move(2)));
    try t.expectProbability(1, 2);
    try t.verify();
}

test "Confusion self-hit bug" {
    const CFZ_5 = MAX;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;
    const CFZ_CANT = if (showdown) CFZ_CAN + 1 else MAX;

    var t = Test(.{ HIT, CFZ_5, CFZ_CANT, CFZ_CANT }).init(
        &.{.{ .species = .Jolteon, .moves = &.{ .ConfuseRay, .Reflect } }},
        &.{.{
            .species = .Arcanine,
            .level = 97,
            .dvs = .{ .atk = 1, .def = 3 },
            .stats = .{ .hp = 18 * 18, .atk = 159 * 159, .def = 30 * 30, .spe = EXP, .spc = EXP },
            .moves = &.{.Flamethrower},
        }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.ConfuseRay, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Confusion });
    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    t.expected.p2.get(1).hp -= if (showdown) 50 else 49;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Confusion });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(255, 512); // (255/256) * (1/2)

    try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Reflect });
    try t.log.expected.activate(.{ P2.ident(1), .Confusion });
    t.expected.p2.get(1).hp -= if (showdown) 50 else 25;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Confusion });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(3, 8); // (3/4) * (1/2)

    try t.verify();
}

test "Flinch persistence bug" {
    const PROC = comptime ranged(77, 256) - 1;

    var t = Test(if (showdown)
        .{ HIT, HIT, ~CRIT, MIN_DMG, PROC }
    else
        .{ HIT, ~CRIT, MIN_DMG, HIT, PROC }).init(
        &.{.{ .species = .Persian, .moves = &.{ .PoisonPowder, .Splash } }},
        &.{
            .{ .species = .Arcanine, .hp = 1, .moves = &.{.RollingKick} },
            .{ .species = .Squirtle, .moves = &.{.WaterGun} },
            .{ .species = .Rhydon, .moves = &.{.Earthquake} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.PoisonPowder, P2.ident(1) });
    t.expected.p2.get(1).status = Status.init(.PSN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.RollingKick, P1.ident(1) });
    try t.log.expected.supereffective(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 127;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p2.get(1).hp = 0;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.faint(.{ P2.ident(1), true });

    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(1), move(1)));
    // (191/256) * (216/256) * (209/256) * (1/39) * (77/256)
    try t.expectProbability(27663867, 6979321856);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(.{}, swtch(2)));
    try t.expectProbability(1, 1);

    try t.log.expected.switched(.{ P2.ident(3), t.expected.p2.get(3) });
    if (showdown) {
        try t.log.expected.cant(.{ P1.ident(1), .Flinch });
    } else {
        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
    }
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), swtch(3)));
    try t.expectProbability(1, 1);
    try t.verify();
}

test "Disable + Transform bug" {
    const DISABLE_MOVE_2 = if (showdown) comptime ranged(2, 4) - 1 else 1;
    const DISABLE_DURATION_5 = comptime ranged(5, 9 - 1) - 1;
    {
        var t = Test((if (showdown)
            .{ HIT, DISABLE_MOVE_2, DISABLE_DURATION_5 }
        else
            .{ ~CRIT, HIT, DISABLE_MOVE_2, DISABLE_DURATION_5 })).init(
            &.{.{ .species = .Voltorb, .moves = &.{ .Disable, .Splash } }},
            &.{.{ .species = .Goldeen, .moves = &.{ .Transform, .WaterGun, .Splash, .Haze } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Disable, Move.WaterGun });
        try t.log.expected.move(.{ P2.ident(1), Move.Transform, P1.ident(1) });
        try t.log.expected.transform(.{ P2.ident(1), P1.ident(1) });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(245, 2048); // (140/256) * (1/4) * (7/8)

        const n = t.battle.actual.choices(.P2, .Move, &choices);
        // BUG: Pokémon Showdown saves move identity instead of slot
        // if (showdown) {
        // try expectEqualSlices(Choice, &[_]Choice{move(1), move(2)}, choices[0..n]);
        // } else {
        try expectEqualSlices(Choice, &[_]Choice{move(1)}, choices[0..n]);
        // }

        try t.verify();
    }
    {
        var t = Test((if (showdown)
            .{ HIT, DISABLE_MOVE_2, DISABLE_DURATION_5 }
        else
            .{ ~CRIT, HIT, DISABLE_MOVE_2, DISABLE_DURATION_5 })).init(
            &.{.{ .species = .Voltorb, .moves = &.{ .Disable, .WaterGun, .Splash } }},
            &.{.{ .species = .Goldeen, .moves = &.{ .Transform, .Splash, .WaterGun, .Haze } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Disable, Move.Splash });
        try t.log.expected.move(.{ P2.ident(1), Move.Transform, P1.ident(1) });
        try t.log.expected.transform(.{ P2.ident(1), P1.ident(1) });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(245, 2048); // (140/256) * (1/4) * (7/8)

        const n = t.battle.actual.choices(.P2, .Move, &choices);
        // BUG: Pokémon Showdown saves move identity instead of slot
        // if (showdown) {
        // try expectEqualSlices(Choice, &[_]Choice{move(1), move(2)}, choices[0..n]);
        // } else {
        try expectEqualSlices(Choice, &[_]Choice{ move(1), move(3) }, choices[0..n]);
        // }

        try t.verify();
    }
}

// Fixed by smogon/pokemon-showdown#{9201,9301} & smogon/pokemon-showdown@203fda57
test "Disable + Bide bug" {
    const PAR_CAN = MAX;
    const BIDE_3 = MAX;
    const DISABLE_MOVE_1 = if (showdown) comptime ranged(1, 2) - 1 else 0;
    const DISABLE_DURATION_5 = comptime ranged(5, 9 - 1) - 1;

    var t = Test((if (showdown)
        .{ HIT, PAR_CAN, BIDE_3, HIT, DISABLE_MOVE_1, DISABLE_DURATION_5 }
    else
        .{ HIT, PAR_CAN, ~CRIT, BIDE_3, ~CRIT, HIT, DISABLE_MOVE_1, DISABLE_DURATION_5 })).init(
        &.{.{ .species = .Voltorb, .moves = &.{ .Glare, .Disable, .Splash } }},
        &.{.{ .species = .Golem, .moves = &.{ .Bide, .RockThrow } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Glare, P2.ident(1) });
    t.expected.p2.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Bide, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Bide });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(573, 1024); // (191/256) * (3/4)
    try expect(t.actual.p2.active.volatiles.Bide);
    try expectEqual(3, t.actual.p2.active.volatiles.attacks);

    try t.log.expected.move(.{ P1.ident(1), Move.Disable, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Disable, Move.Bide });
    try t.log.expected.cant(.{ P2.ident(1), .Disable, Move.Bide });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(245, 1024); // (140/256) * (1/2) * (7/8)
    try expectEqual(4, t.actual.p2.active.volatiles.disable_duration);
    try expect(t.actual.p2.active.volatiles.Bide);
    try expectEqual(3, t.actual.p2.active.volatiles.attacks);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.cant(.{ P2.ident(1), .Disable, Move.Bide });
    try t.log.expected.turn(.{4});

    // Bide should not execute when Disabled
    try expectEqual(Result.Default, try t.update(move(3), forced));
    try t.expectProbability(6, 7);
    try expectEqual(3, t.actual.p2.active.volatiles.disable_duration);
    try expect(t.actual.p2.active.volatiles.Bide);
    try expectEqual(3, t.actual.p2.active.volatiles.attacks);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.cant(.{ P2.ident(1), .Disable, Move.Bide });
    try t.log.expected.turn(.{5});

    // Disabled should trump paralysis
    try expectEqual(Result.Default, try t.update(move(3), forced));
    try t.expectProbability(5, 6);
    try expectEqual(2, t.actual.p2.active.volatiles.disable_duration);
    try expect(t.actual.p2.active.volatiles.Bide);
    try expectEqual(3, t.actual.p2.active.volatiles.attacks);

    try t.verify();
}

// Fixed by smogon/pokemon-showdown#9243
test "Charge + Sleep bug" {
    const SLP_1 = if (showdown) comptime ranged(1, 8 - 1) else 1;

    var t = Test((if (showdown)
        .{ HIT, SLP_1, HIT, ~CRIT, MIN_DMG }
    else
        .{ ~CRIT, HIT, SLP_1, ~CRIT, MIN_DMG, HIT })).init(
        &.{.{ .species = .Venusaur, .moves = &.{ .SolarBeam, .Tackle } }},
        &.{.{ .species = .Snorlax, .moves = &.{ .LovelyKiss, .Splash } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.SolarBeam, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.SolarBeam });
    try t.log.expected.move(.{ P2.ident(1), Move.LovelyKiss, P1.ident(1) });
    t.expected.p1.get(1).status = Status.slp(1);
    const from: protocol.Status = .From;
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, from, Move.LovelyKiss });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(191, 256);

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.curestatus(.{ P1.ident(1), t.expected.p1.get(1).status, .Message });
    t.expected.p1.get(1).status = 0;
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(1, 7);

    // The charging move should be forced and should execute instead of preparing again
    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.SolarBeam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 168;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(2295, 106496); // (255/256) * (216/256) * (1/39)

    try t.verify();
}

// Fixed by smogon/pokemon-showdown#9034
test "Explosion invulnerability bug" {
    var t = Test((if (showdown) .{} else .{ ~CRIT, MIN_DMG })).init(
        &.{.{ .species = .Dugtrio, .moves = &.{.Dig} }},
        &.{.{ .species = .Golem, .moves = &.{.Explosion} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Dig, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.Dig });
    try t.log.expected.move(.{ P2.ident(1), Move.Explosion, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    t.expected.p2.get(1).hp = 0;
    try t.log.expected.faint(.{ P2.ident(1), false });
    try t.log.expected.win(.{.P1});

    try expectEqual(Result.Win, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try t.verify();
}

// Fixed by smogon/pokemon-showdown#9201
test "Bide + Substitute bug" {
    const BIDE_2 = MIN;

    var t = Test((if (showdown) .{ BIDE_2, HIT, HIT } else .{ ~CRIT, BIDE_2, HIT, HIT })).init(
        &.{.{ .species = .Voltorb, .moves = &.{ .SonicBoom, .Substitute } }},
        &.{.{ .species = .Chansey, .moves = &.{ .Bide, .Splash } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Substitute });
    t.expected.p1.get(1).hp -= 70;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Bide, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Bide });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(1, 1);
    try expectEqual(71, t.actual.p1.active.volatiles.substitute);

    try t.log.expected.move(.{ P1.ident(1), Move.SonicBoom, P2.ident(1) });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.activate(.{ P2.ident(1), .Bide });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), forced));

    try t.expectProbability(229, 256);
    try expectEqual(71, t.actual.p1.active.volatiles.substitute);

    try t.log.expected.move(.{ P1.ident(1), Move.SonicBoom, P2.ident(1) });
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.end(.{ P2.ident(1), .Bide });
    try t.log.expected.end(.{ P1.ident(1), .Substitute });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), forced));
    try t.expectProbability(229, 512); // (229/256) * (1/2)

    try t.verify();
}

// Fixed by smogon/pokemon-showdown#8969
test "Counter + Substitute bug" {
    // https://www.youtube.com/watch?v=_cEVqYFoBhE
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, HIT })).init(
        &.{.{ .species = .Snorlax, .moves = &.{ .Reflect, .BodySlam } }},
        &.{.{ .species = .Chansey, .moves = &.{ .Substitute, .Counter } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 175;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Reflect });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.BodySlam, P2.ident(1) });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.faint(.{ P1.ident(1), false });
    try t.log.expected.win(.{.P2});

    try expectEqual(Result.Lose, try t.update(move(2), move(2)));
    try t.expectProbability(5223675, 218103808); // (255/256) ** 2 * (241/256) * (1/39)
    try t.verify();
}

// Fixed by smogon/pokemon-showdown#8974
test "Simultaneous Counter bug" {
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, HIT }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT })).init(
        &.{
            .{ .species = .Golem, .moves = &.{.Strength} },
            .{ .species = .Chansey, .moves = &.{.Counter} },
        },
        &.{
            .{ .species = .Tauros, .moves = &.{.Strength} },
            .{ .species = .Snorlax, .moves = &.{.Counter} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Strength, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 35;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Strength, P2.ident(1) });
    t.expected.p2.get(1).hp -= 63;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (255/256) ** 2 * (201/256) * (234/256) * (1/39) ** 2
    try t.expectProbability(13070025, 27917287424);

    if (showdown) {
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    } else {
        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    }
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(2), Move.Counter, P2.ident(2) });
    if (showdown) {
        try t.log.expected.fail(.{ P1.ident(2), .None });
        try t.log.expected.move(.{ P2.ident(2), Move.Counter, P1.ident(2) });
        try t.log.expected.fail(.{ P2.ident(2), .None });
        try t.log.expected.turn(.{4});
    }

    const result = if (showdown) Result.Default else Result.Error;
    try expectEqual(result, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try t.verify();
}

test "Counter + sleep = Desync Clause Mod bug" {
    const SLP_8 = MAX;
    var t = Test(if (showdown)
        .{ HIT, HIT, SLP_8, HIT, HIT, ~CRIT, MIN_DMG, HIT }
    else
        .{ HIT, ~CRIT, HIT, SLP_8, ~CRIT, ~CRIT, MIN_DMG, HIT, ~CRIT, HIT }).init(
        &.{
            .{ .species = .Alakazam, .moves = &.{ .SeismicToss, .Psychic } },
            .{ .species = .Snorlax, .moves = &.{.BodySlam} },
        },
        &.{.{ .species = .Chansey, .moves = &.{ .Sing, .SoftBoiled, .Counter } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.SeismicToss, P2.ident(1) });
    t.expected.p2.get(1).hp -= 100;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Sing, P1.ident(1) });
    t.expected.p1.get(1).status = Status.slp(7);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .From, Move.Sing });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(8925, 16384); // (255/256) * (140/256)

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(2) });
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(swtch(2), move(3)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P2.ident(1), Move.SoftBoiled, P2.ident(1) });
    t.expected.p2.get(1).hp += 100;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(2), Move.BodySlam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 268;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(20485, 851968); // (255/256) * (241/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.SoftBoiled, P2.ident(1) });
    t.expected.p2.get(1).hp += 268;
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(swtch(2), move(2)));
    try t.expectProbability(1, 1);

    try t.log.expected.cant(.{ P1.ident(1), .Sleep });
    t.expected.p1.get(1).status -= 1;
    try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
    if (showdown) {
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.turn(.{6});
    } else {
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.faint(.{ P1.ident(1), true });
    }

    // Choice made while sleeping should not have been saved (and lead to a desync) as
    // on the cartridge no opportunity is given for choosing a move while sleeping
    const result = if (showdown) Result.Default else Result{ .p1 = .Switch, .p2 = .Pass };
    try expectEqual(result, try t.update(move(if (showdown) 2 else 0), move(3)));
    // (6/7) * (255/256)
    try if (showdown) t.expectProbability(6, 7) else t.expectProbability(765, 896);

    try t.verify();
}

// Fixed by smogon/pokemon-showdown#9156
test "Counter via Metronome bug" {
    const counter = comptime metronome(.Counter);

    // Counter first
    {
        var t = Test((if (showdown)
            .{ HIT, counter, HIT, HIT }
        else
            .{ HIT, ~CRIT, counter, ~CRIT, HIT })).init(
            &.{.{ .species = .Snorlax, .moves = &.{.SeismicToss} }},
            &.{.{ .species = .Chansey, .moves = &.{ .Splash, .Metronome } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.SeismicToss, P2.ident(1) });
        t.expected.p2.get(1).hp -= 100;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1), Move.Metronome });
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.SeismicToss, P2.ident(1) });
        t.expected.p2.get(1).hp -= 100;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(255, 41728); // (1/163) * (255/256)
        try t.verify();
    }
    // Counter second
    {
        var t = Test((if (showdown)
            .{ HIT, counter, HIT }
        else
            .{ HIT, ~CRIT, counter, ~CRIT })).init(
            &.{.{ .species = .Alakazam, .moves = &.{.SeismicToss} }},
            &.{.{ .species = .Chansey, .moves = &.{.Metronome} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.SeismicToss, P2.ident(1) });
        t.expected.p2.get(1).hp -= 100;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1), Move.Metronome });
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 41728); // (255/256) * (1/163)
        try t.verify();
    }
}

// Fixed by smogon/pokemon-showdown#9243
test "Infinite Metronome" {
    const skull_bash = comptime metronome(.SkullBash);
    const mirror_move = comptime metronome(.MirrorMove);
    const fly = comptime metronome(.Fly);
    const pound = comptime metronome(.Pound);

    // Charge
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                skull_bash, mirror_move, mirror_move, fly, ~HIT,
            } else .{
                ~CRIT, skull_bash, ~CRIT, mirror_move, ~CRIT, ~CRIT, mirror_move, ~CRIT, ~CRIT, fly,
                ~CRIT, MIN_DMG, ~CRIT, MIN_DMG, ~HIT
            }
        // zig fmt: on
        ).init(
            &.{.{ .species = .Clefairy, .moves = &.{.Metronome} }},
            &.{.{ .species = .Clefable, .moves = &.{.Metronome} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.SkullBash, ID{}, Move.Metronome });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P2.ident(1), Move.SkullBash });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1), Move.Metronome });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1), Move.MirrorMove });
        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1), Move.Metronome });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1), Move.MirrorMove });
        try t.log.expected.move(.{ P1.ident(1), Move.Fly, ID{}, Move.Metronome });
        try t.log.expected.laststill(.{});
        try t.log.expected.prepare(.{ P1.ident(1), Move.Fly });

        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 705911761); // (1/163) ** 4

        try expectEqual(16, t.actual.p1.active.move(1).pp);
        try expectEqual(16, t.actual.p1.active.move(1).pp);

        try t.log.expected.move(.{ P2.ident(1), Move.SkullBash, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.move(.{ P1.ident(1), Move.Fly, P2.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(1)});
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, forced));
        try t.expectProbability(7, 128);

        try expectEqual(15, t.actual.p1.active.move(1).pp);
        try expectEqual(15, t.actual.p1.active.move(1).pp);

        try t.verify();
    }
    // non-Charge
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                pound, HIT, ~CRIT, MIN_DMG, mirror_move, HIT, ~CRIT, MIN_DMG,
            } else .{
                ~CRIT, pound, ~CRIT, MIN_DMG, HIT, ~CRIT, mirror_move, ~CRIT, ~CRIT, MIN_DMG, HIT,
            }
        // zig fmt: on
        ).init(
            &.{.{ .species = .Clefairy, .moves = &.{.Metronome} }},
            &.{.{ .species = .Clefable, .moves = &.{.Metronome} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Pound, P1.ident(1), Move.Metronome });
        t.expected.p1.get(1).hp -= 54;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1), Move.Metronome });
        try t.log.expected.move(.{ P1.ident(1), Move.Pound, P2.ident(1), Move.MirrorMove });
        t.expected.p2.get(1).hp -= 34;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        // (1/163) ** 2 * (255/256) ** 2 * (226/256) * (239/256) * (1/39) ** 2
        try t.expectProbability(195125575, 9642547324387328);
        try t.verify();
    }
}

test "Mirror Move/Metronome + Substitute bug" {
    const seismic_toss = comptime metronome(.SeismicToss);
    const bonemerang = comptime metronome(.Bonemerang);
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            seismic_toss, HIT, ~HIT, bonemerang, HIT, ~CRIT, MIN_DMG
        } else .{
            ~CRIT, seismic_toss, HIT,
            ~CRIT, MIN_DMG, ~HIT, ~CRIT, bonemerang, ~CRIT, MIN_DMG, HIT
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Hitmonchan, .moves = &.{.Metronome} }},
        &.{.{ .species = .Kadabra, .moves = &.{ .Substitute, .Sludge } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 70;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.SeismicToss, P2.ident(1), Move.Metronome });
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(255, 41728); // (1/163) * (255/256)

    try t.log.expected.move(.{ P2.ident(1), Move.Sludge, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.Bonemerang, P2.ident(1), Move.Metronome });
    t.expected.p2.get(1).hp -= 71;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    // BUG: Pokémon Showdown's broken useMove mechanics mean subFainted never gets cleared
    // if (showdown) {
    //     try t.log.expected.hitcount(.{ P2.ident(1), 1 });
    // } else {
    t.expected.p2.get(1).hp -= 71;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.hitcount(.{ P2.ident(1), 2 });
    // }
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    //  (1/163) * (1/256) * (229/256) * (218/256) * (1/39)
    try t.expectProbability(24961, 53326381056);
    try t.verify();
}

// Fixed by smogon/pokemon-showdown#8963
test "Hyper Beam + Substitute bug" {
    var t = Test(if (showdown) .{ HIT, ~CRIT, MAX_DMG } else .{ ~CRIT, MAX_DMG, HIT }).init(
        &.{.{ .species = .Abra, .moves = &.{.HyperBeam} }},
        &.{.{ .species = .Jolteon, .moves = &.{ .Substitute, .Splash } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 83;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    try t.log.expected.mustrecharge(.{P1.ident(1)});
    try t.log.expected.turn(.{2});

    // Should require recharge if it doesn't knock out the Substitute
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(48319, 2555904); // (229/256) * (211/256) * (1/39)

    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.cant(.{ P1.ident(1), .Recharge });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(1, 1);
    try t.verify();
}

test "Mimic infinite PP bug" {
    // Mimic first
    {
        var battle = Battle.fixed(
            if (showdown)
                .{ HIT, MAX }
            else
                .{ HIT, 1 } ++ .{ ~CRIT, HIT } ** 15,
            &.{.{ .species = .Gengar, .moves = &.{ .Splash, .MegaKick } }},
            &.{
                .{ .species = .Gengar, .level = 99, .moves = &.{ .Mimic, .MegaKick, .Splash } },
                .{ .species = .Clefable, .moves = &.{.Splash} },
            },
        );
        try expectEqual(Result.Default, try battle.update(.{}, .{}, &NULL));

        try expectEqual(Result.Default, try battle.update(move(1), move(1), &NULL));
        try expectEqual(15, battle.side(.P2).active.move(1).pp);
        try expectEqual(15, battle.side(.P2).get(1).move(1).pp);
        try expectEqual(8, battle.side(.P2).active.move(2).pp);
        try expectEqual(8, battle.side(.P2).get(1).move(2).pp);

        // BUG: can't implement Pokémon Showdown's negative PP so need to stop iterating early
        for (1..16) |_| try expectEqual(Result.Default, try battle.update(move(1), move(1), &NULL));
        try expectEqual(0, battle.side(.P2).active.move(1).pp);
        try expectEqual(0, battle.side(.P2).get(1).move(1).pp);
        try expectEqual(8, battle.side(.P2).active.move(2).pp);
        try expectEqual(8, battle.side(.P2).get(1).move(2).pp);

        try expectEqual(Result.Default, try battle.update(move(1), swtch(2), &NULL));

        try expectEqual(0, battle.side(.P2).get(2).move(1).pp);
        try expectEqual(8, battle.side(.P2).get(2).move(2).pp);

        try expect(battle.rng.exhausted());
    }
    // Mimicked move first
    {
        var battle = Battle.fixed(
            if (showdown)
                .{ HIT, MAX }
            else
                .{ HIT, 1 } ++ .{ ~CRIT, HIT } ** 15,
            &.{.{ .species = .Gengar, .moves = &.{ .Splash, .MegaKick } }},
            &.{
                .{ .species = .Gengar, .level = 99, .moves = &.{ .MegaKick, .Mimic, .Splash } },
                .{ .species = .Clefable, .moves = &.{.Splash} },
            },
        );
        try expectEqual(Result.Default, try battle.update(.{}, .{}, &NULL));

        try expectEqual(Result.Default, try battle.update(move(1), move(2), &NULL));
        try expectEqual(8, battle.side(.P2).active.move(1).pp);
        try expectEqual(8, battle.side(.P2).get(1).move(1).pp);
        try expectEqual(15, battle.side(.P2).active.move(2).pp);
        try expectEqual(15, battle.side(.P2).get(1).move(2).pp);

        // BUG: can't implement Pokémon Showdown's negative PP so need to stop iterating early
        for (1..16) |_| try expectEqual(Result.Default, try battle.update(move(1), move(2), &NULL));
        // BUG: Pokémon Showdown decrements the wrong slot here
        try expectEqual(8, battle.side(.P2).active.move(1).pp);
        try expectEqual(8, battle.side(.P2).get(1).move(1).pp);
        try expectEqual(0, battle.side(.P2).active.move(2).pp);
        try expectEqual(0, battle.side(.P2).get(1).move(2).pp);

        try expectEqual(Result.Default, try battle.update(move(1), swtch(2), &NULL));

        try expectEqual(8, battle.side(.P2).get(2).move(1).pp);
        try expectEqual(0, battle.side(.P2).get(2).move(2).pp);

        try expect(battle.rng.exhausted());
    }
}

test "Mirror Move + Wrap bug" {
    const MIN_WRAP = MIN;

    var t = Test((if (showdown)
        .{ ~HIT, HIT, ~CRIT, MIN_DMG, MIN_WRAP }
        // BUG: .{ ~HIT, HIT, ~CRIT, MIN_DMG, MIN_WRAP, HIT }
    else
        .{ MIN_WRAP, ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_WRAP, ~CRIT, MIN_DMG, HIT })).init(
        &.{.{ .species = .Tentacruel, .moves = &.{ .Wrap, .Surf } }},
        &.{.{ .species = .Pidgeot, .moves = &.{ .MirrorMove, .Gust } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1), Move.MirrorMove });
    t.expected.p1.get(1).hp -= 20;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(9495, 3407872); // (40/256) * (216/256) * (211/256) * (1/39)

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    const expected = if (showdown) &[_]Choice{ move(1), move(2) } else &[_]Choice{move(0)};
    try expectEqualSlices(Choice, expected, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, expected, choices[0..n]);

    try t.log.expected.cant(.{ P1.ident(1), .Bound });
    if (showdown) {
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
    } else {
        try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1) });
    }
    t.expected.p1.get(1).hp -= 20;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{3});

    const choice = if (showdown) move(2) else move(0);
    try expectEqual(Result.Default, try t.update(choice, choice));
    try t.expectProbability(3, 8);

    try t.verify();
}

// Fixed by smogon/pokemon-showdown#8966
test "Mirror Move recharge bug" {
    var t = Test((if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MAX_DMG }
    else
        .{ ~CRIT, MIN_DMG, HIT, ~CRIT, ~CRIT, MAX_DMG, HIT, ~CRIT })).init(
        &.{
            .{ .species = .Kadabra, .moves = &.{.HyperBeam} },
            .{ .species = .Haunter, .moves = &.{.Splash} },
        },
        &.{.{ .species = .Pidgeot, .moves = &.{ .MirrorMove, .Gust } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 74;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.mustrecharge(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.HyperBeam, P1.ident(1), Move.MirrorMove });
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.faint(.{ P1.ident(1), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    // (229/256) ** 2 * (204/256) * (211/256) * (1/39) ** 2
    try t.expectProbability(188105867, 544387104768);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    var n = t.battle.actual.choices(.P2, .Move, &choices);
    // Mirror Move should not apply Hyper Beam recharge upon KOing a Pokemon
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(2), Move.Splash, P1.ident(2) });
    try t.log.expected.activate(.{ P1.ident(2), .Splash });
    try t.log.expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1) });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1), Move.MirrorMove });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2) }, choices[0..n]);

    try t.verify();
}

test "Wrap locking + KOs bug" {
    const PROC = MIN;
    const MIN_WRAP = MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, PROC, HIT, ~CRIT, MIN_DMG, MIN_WRAP,
            HIT, ~HIT, HIT, ~CRIT, MIN_DMG, PROC, ~HIT,
            HIT, ~CRIT, MIN_DMG, MIN_WRAP,
            HIT, ~CRIT, MIN_DMG, MIN_WRAP,
        } else .{
            ~CRIT, MIN_DMG, HIT, PROC, MIN_WRAP, ~CRIT, MIN_DMG, HIT,
            HIT, ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, HIT, PROC, ~CRIT, MIN_DMG, ~HIT,
            MIN_WRAP, ~CRIT, MIN_DMG, HIT,
            MIN_WRAP, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Dragonair, .hp = 21, .moves = &.{.Wrap} },
            .{ .species = .Dragonite, .moves = &.{ .DragonRage, .Ember, .Wrap } },
        },
        &.{
            .{ .species = .Beedrill, .hp = 210, .moves = &.{.PoisonSting} },
            .{ .species = .Kakuna, .moves = &.{.Harden} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.PoisonSting, P1.ident(1) });
    t.expected.p1.get(1).hp -= 20;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p1.get(1).status = Status.init(.PSN);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 17;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
    try t.log.expected.faint(.{ P1.ident(1), true });

    // Target should not still be bound after the user faints from residual damage
    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    // (255/256) * (216/256) * (219/256) *  (221/256) * (1/39) ** 2 * (52/256)
    try t.expectProbability(2848095, 34359738368);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(2), Move.DragonRage, P2.ident(1) });
    t.expected.p2.get(1).hp -= 40;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.PoisonSting, P1.ident(2) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(255, 65536); // (255/256) * (1/256)

    try t.log.expected.move(.{ P1.ident(2), Move.Ember, P2.ident(1) });
    try t.log.expected.supereffective(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 91;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.BRN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.PoisonSting, P1.ident(2) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 20;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(2295, 268435456); // (255/256) * (1/256) * (216/256) * (1/39) * (26/256)

    try t.log.expected.move(.{ P1.ident(2), Move.Wrap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 23;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Bound });
    t.expected.p2.get(1).hp = 0;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    try t.log.expected.faint(.{ P2.ident(1), true });

    try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(3), move(1)));
    try t.expectProbability(243, 13312); // (216/256) * (216/256) * (1/39)

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(.{}, swtch(2)));
    try t.expectProbability(1, 1);

    // User should not still be locked into Wrap after residual KO
    const n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{ move(1), move(2), move(3) }, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(2), Move.Wrap, P2.ident(2) });
    t.expected.p2.get(2).hp -= 21;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.cant(.{ P2.ident(2), .Bound });
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(3), move(1)));
    try t.expectProbability(243, 13312); // (216/256) * (216/256) * (1/39)
    try t.verify();
}

test "Thrashing + Substitute bugs" {
    const THRASH_3 = if (showdown) comptime ranged(1, 4 - 2) - 1 else MIN;

    // Thrash should lock the user into the move even if it hits a Substitute
    // Fixed by smogon/pokemon-showdown#8963
    {
        var t = Test((if (showdown)
            .{ THRASH_3, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG }
        else
            .{ THRASH_3, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
            &.{.{ .species = .Nidoking, .level = 50, .moves = &.{ .Thrash, .ThunderWave } }},
            &.{.{ .species = .Vileplume, .moves = &.{ .Substitute, .Splash } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Substitute });
        t.expected.p2.get(1).hp -= 88;
        var subhp: u8 = 89;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Substitute });
        subhp -= 18;
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)
        try expectEqual(subhp, t.actual.p2.active.volatiles.substitute);

        const n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Substitute });
        subhp -= 18;
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, move(2)));
        try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)
        try expectEqual(subhp, t.actual.p2.active.volatiles.substitute);

        try t.verify();
    }
    // Thrash should lock the user into the move even if it breaks a Substitute
    // Fixed by smogon/pokemon-showdown#9315
    {
        var t = Test((if (showdown)
            .{ THRASH_3, HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG }
        else
            .{ THRASH_3, ~CRIT, MAX_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
            &.{.{ .species = .Nidoking, .moves = &.{ .Thrash, .ThunderWave } }},
            &.{.{ .species = .Abra, .moves = &.{ .Substitute, .Splash } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Substitute });
        t.expected.p2.get(1).hp -= 63;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        try t.log.expected.end(.{ P2.ident(1), .Substitute });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)

        const n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
        t.expected.p2.get(1).hp -= 142;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, move(2)));
        try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)

        try t.verify();
    }
}

test "Thrashing speed tie bug" {
    const TIE_1 = MIN;
    const THRASH_4 = MAX;

    var t = Test((if (showdown)
        .{ TIE_1, THRASH_4, HIT, ~CRIT, MIN_DMG, TIE_1, HIT, ~CRIT, MIN_DMG }
    else
        .{ TIE_1, THRASH_4, ~CRIT, MIN_DMG, HIT, TIE_1, ~CRIT, MIN_DMG, HIT })).init(
        &.{.{ .species = .Dratini, .moves = &.{.Thrash} }},
        &.{.{ .species = .Vileplume, .moves = &.{.Splash} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
    t.expected.p2.get(1).hp -= 55;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(19635, 1703936); // (1/2) * (255/256) * (231/256) * (1/39)

    if (showdown) {
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
    }
    try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
    t.expected.p2.get(1).hp -= 55;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    if (!showdown) {
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
    }
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, move(1)));
    try t.expectProbability(19635, 1703936); // (1/2) * (255/256) * (231/256) * (1/39)
    try t.verify();
}

// Fixed by smogon/pokemon-showdown#9475
test "Min/max stat recalculation bug" {
    const PAR_CAN = MAX;
    const HI_PROC = comptime ranged(77, 256) - 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, HIT, PAR_CAN, NOP, HIT, HIT, HIT, HIT, ~CRIT,
            MIN_DMG, HI_PROC, PAR_CAN, NOP, HIT, PAR_CAN, HIT, PAR_CAN,
        } else .{
            ~CRIT, HIT, HIT, PAR_CAN, ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT, ~CRIT,
            MIN_DMG, HIT, HI_PROC, PAR_CAN, HIT, PAR_CAN, ~CRIT, HIT, PAR_CAN,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Jolteon, .moves = &.{ .StringShot, .ThunderWave, .Lick, .Splash } }},
        &.{.{ .species = .Omanyte, .hp = 1, .level = 51, .moves = &.{ .Splash, .Rest } }},
    );
    defer t.deinit();
    try t.start();

    try expectEqual(88, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.StringShot, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, -1 });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(121, 128); // (242/256)
    try expectEqual(-1, t.actual.p2.active.boosts.spe);
    try expectEqual(58, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.ThunderWave, P2.ident(1) });
    t.expected.p2.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Rest, P2.ident(1) });
    t.expected.p2.get(1).hp += 143;
    t.expected.p2.get(1).status = Status.slf(2);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .From, Move.Rest });
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Silent });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(765, 1024); // (255/256) * (3/4)
    try expectEqual(-1, t.actual.p2.active.boosts.spe);
    try expectEqual(14, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.StringShot, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, -1 });
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    t.expected.p2.get(1).status -= 1;
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), forced));
    try t.expectProbability(121, 128); // (242/256)
    try expectEqual(-2, t.actual.p2.active.boosts.spe);
    try expectEqual(44, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.StringShot, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, -1 });
    try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Message });
    t.expected.p2.get(1).status = 0;
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(1), forced));
    try t.expectProbability(121, 128); // (242/256)
    try expectEqual(-3, t.actual.p2.active.boosts.spe);
    try expectEqual(35, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.StringShot, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Speed, -1 });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(121, 128); // (242/256)
    try expectEqual(-4, t.actual.p2.active.boosts.spe);
    try expectEqual(29, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.Lick, P2.ident(1) });
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Rest, P2.ident(1) });
    t.expected.p2.get(1).hp += 22;
    t.expected.p2.get(1).status = Status.slf(2);
    try t.log.expected.status(.{ P2.ident(1), Status.slf(2), .From, Move.Rest });
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Silent });
    try t.log.expected.turn(.{7});

    try expectEqual(Result.Default, try t.update(move(3), move(2)));
    // (255/256) * (191/256) * (1/39) * (77/256) * (3/4)
    try t.expectProbability(3750285, 872415232);
    try expectEqual(-4, t.actual.p2.active.boosts.spe);
    try expectEqual(7, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    t.expected.p2.get(1).status -= 1;
    try t.log.expected.turn(.{8});

    try expectEqual(Result.Default, try t.update(move(4), forced));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Message });
    t.expected.p2.get(1).status = 0;
    try t.log.expected.turn(.{9});

    try expectEqual(Result.Default, try t.update(move(4), forced));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(1), Move.ThunderWave, P2.ident(1) });
    t.expected.p2.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{10});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(765, 1024); // (255/256) * (3/4)
    try expectEqual(-4, t.actual.p2.active.boosts.spe);
    try expectEqual(1, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.StringShot, P2.ident(1) });
    if (showdown) {
        try t.log.expected.boost(.{ P2.ident(1), .Speed, -1 });
        try t.log.expected.boost(.{ P2.ident(1), .Speed, 1 });
    }
    try t.log.expected.fail(.{ P2.ident(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    try t.log.expected.turn(.{11});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(363, 512); // (242/256) * (3/4)
    try expectEqual(-4, t.actual.p2.active.boosts.spe);
    try expectEqual(1, t.actual.p2.active.stats.spe);

    try t.verify();
}

// Glitches

test "0 damage glitch" {
    // https://pkmn.cc/bulba-glitch-1#0_damage_glitch
    // https://www.youtube.com/watch?v=fxNzPeLlPTU
    var t = Test(if (showdown)
        .{ HIT, HIT, ~CRIT, HIT, HIT, HIT, ~CRIT }
    else
        .{ ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT }).init(
        &.{.{ .species = .Bulbasaur, .moves = &.{.Growl} }},
        &.{
            .{ .species = .Bellsprout, .level = 2, .stats = .{}, .moves = &.{.VineWhip} },
            .{ .species = .Chansey, .level = 2, .stats = .{}, .moves = &.{.VineWhip} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Growl, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Attack, -1 });
    try t.log.expected.move(.{ P2.ident(1), Move.VineWhip, P1.ident(1) });
    if (showdown) {
        try t.log.expected.resisted(.{P1.ident(1)});
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    } else {
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
    }
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    if (showdown) {
        try t.expectProbability(3836475, 4194304); // (255/256) ** 2 * (236/256)
    } else {
        try t.expectProbability(255, 256);
    }

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.Growl, P2.ident(2) });
    try t.log.expected.boost(.{ P2.ident(2), .Attack, -1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try t.expectProbability(255, 256);

    try t.log.expected.move(.{ P1.ident(1), Move.Growl, P2.ident(2) });
    try t.log.expected.boost(.{ P2.ident(2), .Attack, -1 });
    try t.log.expected.move(.{ P2.ident(2), Move.VineWhip, P1.ident(1) });
    if (showdown) {
        try t.log.expected.resisted(.{P1.ident(1)});
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    } else {
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(2)});
    }
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    if (showdown) {
        try t.expectProbability(15020775, 16777216); // (255/256) ** 2 * (231/256)
    } else {
        try t.expectProbability(255, 256);
    }

    try t.verify();
}

test "1/256 miss glitch" {
    // https://pkmn.cc/bulba-glitch-1#1.2F256_miss_glitch
    var t = Test(if (showdown)
        .{ ~HIT, ~HIT }
    else
        .{ CRIT, MAX_DMG, ~HIT, CRIT, MAX_DMG, ~HIT }).init(
        &.{.{ .species = .Jigglypuff, .moves = &.{.Pound} }},
        &.{.{ .species = .NidoranF, .moves = &.{.Scratch} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Scratch, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.move(.{ P1.ident(1), Move.Pound, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 65536); // (255/256) ** 2
    try t.verify();
}

// Fixed by smogon/pokemon-showdown#9201
test "Bide damage accumulation glitches" {
    // https://glitchcity.wiki/Bide_fainted_Pokémon_damage_accumulation_glitch
    // https://glitchcity.wiki/Bide_non-damaging_move/action_damage_accumulation_glitch
    // https://www.youtube.com/watch?v=IVxHGyNDW4g
    const BIDE_2 = MIN;

    // Non-damaging move/action damage accumulation
    {
        var t = Test((if (showdown)
            .{ BIDE_2, HIT, ~CRIT, MIN_DMG }
        else
            .{ ~CRIT, BIDE_2, ~CRIT, MIN_DMG, HIT })).init(
            &.{
                .{ .species = .Poliwrath, .level = 40, .moves = &.{ .Surf, .Splash } },
                .{ .species = .Snorlax, .level = 80, .moves = &.{.Rest} },
            },
            &.{.{ .species = .Chansey, .level = 80, .moves = &.{.Bide} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Bide, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Bide });
        try t.log.expected.move(.{ P1.ident(1), Move.Surf, P2.ident(1) });
        t.expected.p2.get(1).hp -= 18;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1445, 65536); // (255/256) * (221/256) * (1/39)

        try t.log.expected.activate(.{ P2.ident(1), .Bide });
        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), forced));
        try t.expectProbability(1, 1);

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.end(.{ P2.ident(1), .Bide });
        t.expected.p1.get(2).hp -= 72;
        try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(swtch(2), forced));
        try t.expectProbability(1, 2);

        try t.verify();
    }
    // Fainted Pokémon damage accumulation desync
    {
        var t = Test((if (showdown)
            .{ HIT, BIDE_2, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG }
        else
            .{ HIT, ~CRIT, BIDE_2, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT })).init(
            &.{
                .{ .species = .Wigglytuff, .hp = 179, .moves = &.{ .Splash, .TriAttack } },
                .{ .species = .Snorlax, .moves = &.{.DefenseCurl} },
            },
            &.{.{ .species = .Chansey, .moves = &.{ .Toxic, .Bide } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Toxic, P1.ident(1) });
        t.expected.p1.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
        try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        t.expected.p1.get(1).hp -= 30;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(27, 32); // (216/256)

        try t.log.expected.move(.{ P2.ident(1), Move.Bide, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Bide });
        try t.log.expected.move(.{ P1.ident(1), Move.TriAttack, P2.ident(1) });
        t.expected.p2.get(1).hp -= 191;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        t.expected.p1.get(1).hp -= 60;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(765, 32768); // (255/256) * (234/256) * (1/39)

        try t.log.expected.activate(.{ P2.ident(1), .Bide });
        try t.log.expected.move(.{ P1.ident(1), Move.TriAttack, P2.ident(1) });
        t.expected.p2.get(1).hp -= 191;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        t.expected.p1.get(1).hp = 0;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Poison });
        if (showdown) try t.log.expected.faint(.{ P1.ident(1), true });

        _ = t.battle.actual.choices(.P2, .Move, &choices);

        const result = if (showdown) Result{ .p1 = .Switch, .p2 = .Pass } else Result.Error;
        try expectEqual(result, try t.update(move(2), move(if (showdown) 2 else 0)));
        try t.expectProbability(765, 32768); // (255/256) * (234/256) * (1/39)

        if (showdown) {
            try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
            try t.log.expected.turn(.{4});

            try expectEqual(Result.Default, try t.update(swtch(2), .{}));
            try t.expectProbability(1, 1);
        }

        try t.verify();
    }
}

test "Counter glitches" {
    // https://pkmn.cc/bulba-glitch-1#Counter_glitches
    // https://glitchcity.wiki/Counter_glitches_(Generation_I)
    // https://www.youtube.com/watch?v=ftTalHMjPRY
    const PAR_CAN = MAX;
    const PAR_CANT = MIN;

    // self-Counter
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                HIT, PAR_CAN, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, PAR_CANT, HIT,
            } else .{
                ~CRIT, HIT,
                PAR_CAN, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
                PAR_CANT, ~CRIT, HIT,
            }
        // zig fmt: on
        ).init(
            &.{.{ .species = .Jolteon, .moves = &.{ .Agility, .Tackle } }},
            &.{.{
                .species = .Chansey,
                .level = 80,
                .moves = &.{ .ThunderWave, .MegaDrain, .Counter },
            }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
        try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(1) });
        t.expected.p1.get(1).status = Status.init(.PAR);
        try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
        t.expected.p2.get(1).hp -= 67;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.MegaDrain, P1.ident(1) });
        t.expected.p1.get(1).hp -= 19;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        t.expected.p2.get(1).hp += 9;
        try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Drain, P1.ident(1) });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        // (3/4) * (242/256) * (255/256) * (191/256) * (231/256) * (1/39) ** 2
        try t.expectProbability(453784485, 1451698946048);

        try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
        try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
        t.expected.p1.get(1).hp -= 2 * 9;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(2), move(3)));
        try t.expectProbability(255, 1024); // (1/4) * (255/256)
        try t.verify();
    }
    // Desync
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                HIT, PAR_CAN, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, PAR_CANT, HIT,
            } else .{
                ~CRIT, HIT,
                PAR_CAN, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
                PAR_CANT, ~CRIT,
            }
        // zig fmt: on
        ).init(
            &.{.{ .species = .Jolteon, .moves = &.{ .Agility, .Tackle } }},
            &.{.{
                .species = .Chansey,
                .level = 80,
                .moves = &.{ .ThunderWave, .MegaDrain, .Counter },
            }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
        try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(1) });
        t.expected.p1.get(1).status = Status.init(.PAR);
        try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
        t.expected.p2.get(1).hp -= 67;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.MegaDrain, P1.ident(1) });
        t.expected.p1.get(1).hp -= 19;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        t.expected.p2.get(1).hp += 9;
        try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Drain, P1.ident(1) });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        // (3/4) * (242/256) * (255/256) * (191/256) * (231/256) * (1/39) ** 2
        try t.expectProbability(453784485, 1451698946048);

        try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
        try t.log.expected.move(.{ P2.ident(1), Move.Counter, P1.ident(1) });
        if (showdown) {
            try t.log.expected.fail(.{ P2.ident(1), .None });
            try t.log.expected.turn(.{4});
        }

        const result = if (showdown) Result.Default else Result.Error;
        try expectEqual(result, try t.update(move(1), move(3)));
        try t.expectProbability(1, 4);
        try t.verify();
    }
}

test "Freeze top move selection glitch" {
    // https://glitchcity.wiki/Freeze_top_move_selection_glitch
    const FRZ = comptime ranged(26, 256) - 1;
    const NO_BRN = FRZ + 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, FRZ, HIT, ~CRIT, MIN_DMG,
            HIT, ~CRIT, MIN_DMG, NO_BRN,
        } else .{
            ~CRIT, MIN_DMG, HIT, FRZ, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Slowbro, .moves = &.{ .Psychic, .Amnesia, .Splash } },
            .{ .species = .Spearow, .level = 8, .moves = &.{.Peck} },
        },
        &.{.{ .species = .Mew, .moves = &.{ .Blizzard, .FireBlast } }},
    );
    defer t.deinit();

    t.actual.p1.get(1).move(1).pp = 0;

    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 50;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p1.get(1).status = Status.init(.FRZ);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.cant(.{ P1.ident(1), .Freeze });
    try t.log.expected.turn(.{2});

    // last_selected_move is Amnesia before getting Frozen
    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(23587, 12582912); // (229/256) * (206/256) * (1/39) * (26/256)
    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.move(.{ P2.ident(1), Move.FireBlast, P1.ident(2) });
    t.expected.p1.get(2).hp = 0;
    try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
    try t.log.expected.faint(.{ P1.ident(2), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(swtch(2), move(2)));
    try t.expectProbability(927, 53248); // (216/256) * (206/256) * (1/39)

    try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    const n = t.battle.actual.choices(.P1, .Move, &choices);
    if (showdown) {
        try expectEqualSlices(Choice, &[_]Choice{ move(2), move(3) }, choices[0..n]);
    } else {
        try expectEqualSlices(Choice, &[_]Choice{move(0)}, choices[0..n]);
    }
    try t.log.expected.move(.{ P2.ident(1), Move.FireBlast, P1.ident(1) });
    try t.log.expected.resisted(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 50;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.curestatus(.{ P1.ident(1), t.expected.p1.get(1).status, .Message });
    t.expected.p1.get(1).status = 0;
    if (showdown) {
        try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
        try t.log.expected.activate(.{ P1.ident(1), .Splash });
        try t.log.expected.turn(.{4});
    }

    // last_selected_move is still Amnesia but desync occurs as Psychic gets chosen
    const choice = if (showdown) move(3) else move(0);
    const result = if (showdown) Result.Default else Result.Error;
    try expectEqual(result, try t.update(choice, move(2)));
    try t.expectProbability(927, 53248); // (216/256) * (206/256) * (1/39)
    try t.verify();
}

test "Toxic counter glitches" {
    // https://pkmn.cc/bulba-glitch-1#Toxic_counter_glitches
    // https://glitchcity.wiki/Leech_Seed_and_Toxic_stacking
    const BRN = comptime ranged(77, 256) - 1;
    var t = Test(if (showdown)
        .{ HIT, NOP, HIT, HIT, ~CRIT, MIN_DMG, BRN }
    else
        .{ HIT, HIT, ~CRIT, MIN_DMG, HIT, BRN }).init(
        &.{.{ .species = .Venusaur, .moves = &.{ .Toxic, .LeechSeed, .Splash, .FireBlast } }},
        &.{.{ .species = .Clefable, .hp = 392, .moves = &.{ .Splash, .Rest } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
    try t.log.expected.status(.{
        P2.ident(1),
        if (showdown) Status.TOX else Status.init(.PSN),
        .None,
    });
    try t.log.expected.move(.{ P2.ident(1), Move.Rest, P2.ident(1) });
    try t.log.expected.status(.{ P2.ident(1), Status.slf(2), .From, Move.Rest });
    t.expected.p2.get(1).hp += 1;
    t.expected.p2.get(1).status = Status.slf(2);
    try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .Silent });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(27, 32); // (216/256)
    try expectEqual(0, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(3), forced));
    try t.expectProbability(1, 1);
    try expectEqual(0, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
    t.expected.p2.get(1).status = 0;
    try t.log.expected.curestatus(.{ P2.ident(1), Status.slf(1), .Message });
    t.expected.p2.get(1).hp -= 24;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(229, 256);
    try expectEqual(1, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.FireBlast, P2.ident(1) });
    t.expected.p2.get(1).hp -= 96;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.BRN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Splash });
    t.expected.p2.get(1).hp -= 48;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    t.expected.p2.get(1).hp -= 72;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .LeechSeed });
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(4), move(1)));
    try t.expectProbability(18711, 3407872); // (216/256) * (216/256) * (1/39) * (77/256)
    try expectEqual(3, t.actual.p2.active.volatiles.toxic);

    try t.verify();
}

test "Poison/Burn animation with 0 HP" {
    // https://pkmn.cc/bulba/List_of_graphical_quirks_(Generation_I)

    // Faint from Recoil (no healing on Pokémon Showdown)
    {
        var t = Test(if (showdown)
            .{ HIT, HIT, HIT, ~CRIT, MAX_DMG }
        else
            .{ HIT, HIT, ~CRIT, MAX_DMG, HIT }).init(
            &.{
                .{ .species = .Ivysaur, .hp = 137, .moves = &.{ .Toxic, .LeechSeed } },
                .{ .species = .NidoranM, .moves = &.{.HornAttack} },
            },
            &.{
                .{ .species = .Wigglytuff, .hp = 60, .moves = &.{ .Splash, .DoubleEdge } },
                .{ .species = .NidoranM, .moves = &.{.DoubleKick} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
        t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        t.expected.p2.get(1).hp -= 30;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(27, 32); // (216/256)
        try expectEqual(1, t.actual.p2.active.volatiles.toxic);

        try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
        try t.log.expected.move(.{ P2.ident(1), Move.DoubleEdge, P1.ident(1) });
        t.expected.p1.get(1).hp -= 136;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        t.expected.p2.get(1).hp -= 30;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .RecoilOf, P1.ident(1) });
        if (!showdown) {
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
            t.expected.p1.get(1).hp += 90;
            try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
        }
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(2), move(2)));
        try t.expectProbability(175185, 8388608); // (229/256) * (255/256) * (234/256) * (1/39)
        try t.verify();
    }
    // Faint from Crash (no healing on Pokémon Showdown)
    {
        var t = Test(if (showdown)
            .{ HIT, HIT, ~HIT }
        else
            .{ HIT, HIT, ~CRIT, MAX_DMG, ~HIT }).init(
            &.{
                .{ .species = .Ivysaur, .hp = 1, .moves = &.{ .Toxic, .LeechSeed } },
                .{ .species = .NidoranM, .moves = &.{.HornAttack} },
            },
            &.{
                .{ .species = .Wigglytuff, .hp = 31, .moves = &.{ .Splash, .JumpKick } },
                .{ .species = .NidoranM, .moves = &.{.DoubleKick} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
        t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        t.expected.p2.get(1).hp -= 30;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(27, 32); // (216/256)
        try expectEqual(1, t.actual.p2.active.volatiles.toxic);

        try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
        try t.log.expected.move(.{ P2.ident(1), Move.JumpKick, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        t.expected.p2.get(1).hp -= 1;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        if (!showdown) {
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
            t.expected.p1.get(1).hp += 90;
            try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
        }
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(2), move(2)));
        try t.expectProbability(1603, 32768); // (229/256) * (14/256)
        try t.verify();
    }
    // Faint from Toxic (heals on Pokémon Showdown)
    {
        var t = Test(if (showdown) .{ HIT, HIT } else .{ HIT, HIT }).init(
            &.{
                .{ .species = .Ivysaur, .hp = 1, .moves = &.{ .Toxic, .LeechSeed } },
                .{ .species = .NidoranM, .moves = &.{.HornAttack} },
            },
            &.{
                .{ .species = .Wigglytuff, .hp = 60, .moves = &.{ .Splash, .DoubleEdge } },
                .{ .species = .NidoranM, .moves = &.{.DoubleKick} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
        t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
        try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        t.expected.p2.get(1).hp -= 30;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(27, 32); // (216/256)
        try expectEqual(1, t.actual.p2.active.volatiles.toxic);

        try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        t.expected.p2.get(1).hp -= 30;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
        t.expected.p1.get(1).hp += 90;
        try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(2), move(1)));
        try t.expectProbability(229, 256);
        try t.verify();
    }
    // Faint from confusion self-hit (heals on Pokémon Showdown)
    {
        const CFZ_5 = MAX;
        const CFZ_CANT = if (showdown) comptime ranged(128, 256) else MAX;
        var t = Test(.{ HIT, CFZ_5, CFZ_CANT, HIT, CFZ_CANT }).init(
            &.{
                .{ .species = .Ivysaur, .hp = 1, .moves = &.{ .ConfuseRay, .LeechSeed } },
                .{ .species = .NidoranM, .moves = &.{.HornAttack} },
            },
            &.{
                .{ .species = .Wigglytuff, .hp = 50, .moves = &.{ .Splash, .DoubleEdge } },
                .{ .species = .NidoranM, .moves = &.{.DoubleKick} },
            },
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.ConfuseRay, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Confusion });
        try t.log.expected.activate(.{ P2.ident(1), .Confusion });
        t.expected.p2.get(1).hp -= 44;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Confusion });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 512); // (255/256) * (1/2)

        try t.log.expected.move(.{ P1.ident(1), Move.LeechSeed, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .LeechSeed });
        try t.log.expected.activate(.{ P2.ident(1), .Confusion });
        t.expected.p2.get(1).hp -= 6;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Confusion });
        t.expected.p1.get(1).hp += 30;
        try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Silent });
        try t.log.expected.faint(.{ P2.ident(1), true });

        try expectEqual(Result{ .p1 = .Pass, .p2 = .Switch }, try t.update(move(2), move(1)));
        try t.expectProbability(687, 2048); // (229/256) * (3/4) * (1/2)
        try t.verify();
    }
}

test "Defrost move forcing" {
    // https://pkmn.cc/bulba-glitch-1#Defrost_move_forcing
    const FRZ = comptime ranged(26, 256) - 1;
    const NO_BRN = FRZ + 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, FRZ,
            HIT, ~CRIT, MIN_DMG, NO_BRN, HIT, ~CRIT, MIN_DMG,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, FRZ, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Hypno, .level = 50, .moves = &.{ .Splash, .IcePunch, .FirePunch } }},
        &.{
            .{ .species = .Bulbasaur, .level = 6, .moves = &.{.VineWhip} },
            .{ .species = .Poliwrath, .level = 40, .moves = &.{ .Surf, .WaterGun } },
        },
    );
    defer t.deinit();

    // Set up P2's last_selected_move to be Vine Whip
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.move(.{ P2.ident(1), Move.VineWhip, P1.ident(1) });
    t.expected.p1.get(1).hp -= 2;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(765, 32768); // (255/256) * (234/256) * (1/39)

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.IcePunch, P2.ident(2) });
    try t.log.expected.resisted(.{P2.ident(2)});
    t.expected.p2.get(2).hp -= 23;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    t.expected.p2.get(2).status = Status.init(.FRZ);
    try t.log.expected.status(.{ P2.ident(2), t.expected.p2.get(2).status, .None });
    try t.log.expected.turn(.{3});

    // Switching clears last_used_move but not last_selected_move
    try expectEqual(Result.Default, try t.update(move(2), swtch(2)));
    try t.expectProbability(18955, 8388608); // (255/256) * (223/256) * (1/39) * (26/256)
    try expectEqual(t.expected.p2.get(2).status, t.actual.p2.get(1).status);

    const choice = move(if (showdown) 2 else 0);
    var n = t.battle.actual.choices(.P2, .Move, &choices);
    if (showdown) {
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), choice }, choices[0..n]);
    } else {
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), choice }, choices[0..n]);
    }
    try t.log.expected.move(.{ P1.ident(1), Move.FirePunch, P2.ident(2) });
    try t.log.expected.resisted(.{P2.ident(2)});
    t.expected.p2.get(2).hp -= 23;
    try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
    try t.log.expected.curestatus(.{ P2.ident(2), t.expected.p2.get(2).status, .Message });
    t.expected.p2.get(2).status = 0;
    if (showdown) {
        try t.log.expected.move(.{ P2.ident(2), Move.WaterGun, P1.ident(1) });
        t.expected.p1.get(1).hp -= 12;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{4});
    }

    // After defrosting, Poliwrath will appear to use Surf to P1 and Vine Whip to P2
    const result = if (showdown) Result.Default else Result.Error;
    try expectEqual(result, try t.update(move(3), choice));

    if (showdown) {
        // (255/256) ** 2 * (223/256) * (221/256) * (1/39) ** 2
        try t.expectProbability(27389975, 55834574848);
        n = t.battle.actual.choices(.P2, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1), choice }, choices[0..n]);
    } else {
        try t.expectProbability(18955, 851968); // (255/256) * (223/256) * (1/39)
    }

    try t.verify();
}

test "Division by 0" {
    // https://pkmn.cc/bulba-glitch-1#Division_by_0
    // https://www.youtube.com/watch?v=V6iUlyS8GMU
    // https://www.youtube.com/watch?v=fVtO_DKxIsI

    // Attack/Special > 255 vs. Defense/Special stat < 4.
    {
        var t = Test(if (showdown)
            .{ HIT, HIT, ~HIT, ~HIT, HIT, ~CRIT, MIN_DMG }
        else
            .{ ~CRIT, HIT, ~CRIT, HIT, ~CRIT, ~HIT, ~CRIT, ~CRIT, ~HIT, ~CRIT }).init(
            &.{
                .{ .species = .Cloyster, .level = 65, .moves = &.{.Screech} },
                .{ .species = .Parasect, .moves = &.{ .SwordsDance, .LeechLife } },
            },
            &.{.{ .species = .Rattata, .level = 2, .stats = .{}, .moves = &.{.TailWhip} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Screech, P2.ident(1) });
        try t.log.expected.boost(.{ P2.ident(1), .Defense, -2 });
        try t.log.expected.move(.{ P2.ident(1), Move.TailWhip, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Defense, -1 });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(6885, 8192); // (216/256) * (255/256)

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.move(.{ P2.ident(1), Move.TailWhip, P1.ident(2) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
        try t.expectProbability(1, 256);

        try t.log.expected.move(.{ P1.ident(2), Move.SwordsDance, P1.ident(2) });
        try t.log.expected.boost(.{ P1.ident(2), .Attack, 2 });
        try t.log.expected.move(.{ P2.ident(1), Move.TailWhip, P1.ident(2) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 256);

        try expectEqual(576, t.actual.p1.active.stats.atk);
        try expectEqual(3, t.actual.p2.active.stats.def);

        try t.log.expected.move(.{ P1.ident(2), Move.LeechLife, P2.ident(1) });
        if (showdown) {
            t.expected.p2.get(1).hp = 0;
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
            try t.log.expected.faint(.{ P2.ident(1), false });
            try t.log.expected.win(.{.P1});
        }

        const result = if (showdown) Result.Win else Result.Error;
        try expectEqual(result, try t.update(move(2), move(1)));
        // (255/256) * (241/256) * (1/39)
        try if (showdown) t.expectProbability(20485, 851968) else t.expectProbability(1, 1);
        try t.verify();
    }
    // Defense/Special stat is 512 or 513 + Reflect/Light Screen.
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT, HIT, ~CRIT, MAX_DMG,
            } else .{
                ~CRIT, ~CRIT, MAX_DMG, HIT, ~CRIT, ~CRIT, MAX_DMG, HIT,
                ~CRIT, HIT, ~CRIT,
            }
        // zig fmt: on
        ).init(
            &.{.{
                .species = .Cloyster,
                .level = 64,
                .stats = .{ .def = 12 * 12 },
                .moves = &.{ .Withdraw, .Reflect },
            }},
            &.{.{
                .species = .Pidgey,
                .level = 5,
                .stats = .{},
                .moves = &.{ .Gust, .SandAttack },
            }},
        );
        defer t.deinit();

        try expectEqual(256, t.actual.p1.get(1).stats.def);

        try t.log.expected.move(.{ P1.ident(1), Move.Withdraw, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Defense, 1 });
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
        t.expected.p1.get(1).hp -= 3;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(4845, 212992); // (255/256) * (228/256) * (1/39)

        try t.log.expected.move(.{ P1.ident(1), Move.Withdraw, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Defense, 1 });
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
        t.expected.p1.get(1).hp -= 3;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(4845, 212992); // (255/256) * (228/256) * (1/39)
        try expectEqual(512, t.actual.p1.active.stats.def);

        try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Reflect });
        try t.log.expected.move(.{ P2.ident(1), Move.SandAttack, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Accuracy, -1 });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
        if (showdown) {
            t.expected.p1.get(1).hp -= 12;
            try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
            try t.log.expected.turn(.{5});
        }

        const result = if (showdown) Result.Default else Result.Error;
        try expectEqual(result, try t.update(move(2), move(1)));
        //  (255/256) * (228/256) * (1/39)
        try if (showdown) t.expectProbability(4845, 212992) else t.expectProbability(1, 1);
        try t.verify();
    }
    // Defense/Special stat >= 514 + Reflect/Light Screen.
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                HIT, ~CRIT, MAX_DMG, HIT, ~CRIT, MAX_DMG, HIT,  HIT, ~CRIT, MAX_DMG,
            } else .{
                ~CRIT, ~CRIT, MAX_DMG, HIT, ~CRIT, ~CRIT, MAX_DMG, HIT,
                ~CRIT, HIT, ~CRIT, MAX_DMG, HIT,
            }
        // zig fmt: on
        ).init(
            &.{.{
                .species = .Cloyster,
                .level = 64,
                .stats = .{ .def = 20 * 20 },
                .moves = &.{ .Withdraw, .Reflect },
            }},
            &.{.{
                .species = .Pidgey,
                .level = 5,
                .stats = .{},
                .moves = &.{ .Gust, .SandAttack },
            }},
        );
        defer t.deinit();

        try expectEqual(257, t.actual.p1.get(1).stats.def);

        try t.log.expected.move(.{ P1.ident(1), Move.Withdraw, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Defense, 1 });
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
        t.expected.p1.get(1).hp -= 3;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(4845, 212992); // (255/256) * (228/256) * (1/39)

        try t.log.expected.move(.{ P1.ident(1), Move.Withdraw, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Defense, 1 });
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
        t.expected.p1.get(1).hp -= 3;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(4845, 212992); // (255/256) * (228/256) * (1/39)
        try expectEqual(514, t.actual.p1.active.stats.def);

        try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Reflect });
        try t.log.expected.move(.{ P2.ident(1), Move.SandAttack, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Accuracy, -1 });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.Reflect, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.move(.{ P2.ident(1), Move.Gust, P1.ident(1) });
        t.expected.p1.get(1).hp -= 12;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        try t.expectProbability(4845, 212992); // (255/256) * (228/256) * (1/39)
        try t.verify();
    }
}

test "Hyper Beam + Freeze permanent helplessness" {
    // https://pkmn.cc/bulba-glitch-1#Hyper_Beam_.2B_Freeze_permanent_helplessness
    // https://glitchcity.wiki/Haze_glitch
    // https://www.youtube.com/watch?v=gXQlct-DvVg
    const FRZ = comptime ranged(26, 256) - 1;
    const NO_BRN = FRZ + 1;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, FRZ,
            HIT, ~CRIT, MIN_DMG, NO_BRN, ~HIT,
            HIT, ~CRIT, MIN_DMG, NO_BRN, ~HIT,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, FRZ,
            ~CRIT, MIN_DMG, HIT, NO_BRN, ~CRIT, MIN_DMG, HIT, NO_BRN,
        }
    // zig fmt: on
    ).init(
        &.{
            .{ .species = .Chansey, .moves = &.{ .HyperBeam, .SoftBoiled } },
            .{ .species = .Blastoise, .moves = &.{.HydroPump} },
        },
        &.{
            .{ .species = .Lapras, .level = 56, .moves = &.{ .Blizzard, .Haze } },
            .{ .species = .Charizard, .moves = &.{.Flamethrower} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
    t.expected.p2.get(1).hp -= 120;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.mustrecharge(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.Blizzard, P1.ident(1) });
    t.expected.p1.get(1).hp -= 39;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    t.expected.p1.get(1).status = Status.init(.FRZ);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    // (229/256) ** 2 (231/256) * (226/256) * (1/39) ** 2 * (26/256)
    try t.expectProbability(456289141, 10720238370816);
    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.cant(.{ P1.ident(1), .Freeze });
    try t.log.expected.move(.{ P2.ident(1), Move.Haze, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Haze });
    try t.log.expected.clearallboost(.{});
    try t.log.expected.curestatus(.{ P1.ident(1), t.expected.p1.get(1).status, .Silent });
    t.expected.p1.get(1).status = 0;
    try t.log.expected.turn(.{3});

    // After thawing Chansey should still be stuck recharging
    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(1, 1);
    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, &[_]Choice{forced}, choices[0..n]);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    if (showdown) try t.log.expected.cant(.{ P1.ident(1), .Recharge });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(forced, swtch(2)));
    try t.expectProbability(1, 1);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(
        Choice,
        if (showdown) &[_]Choice{ swtch(2), move(1), move(2) } else &[_]Choice{move(0)},
        choices[0..n],
    );

    try t.log.expected.move(.{ P2.ident(2), Move.Flamethrower, P1.ident(1) });
    t.expected.p1.get(1).hp -= 90;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    if (showdown) {
        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(2) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(1)});
    }
    try t.log.expected.turn(.{5});

    // Using a Fire-type move after should do nothing to fix the problem
    try expectEqual(Result.Default, try t.update(forced, move(1)));
    if (showdown) {
        // (255/256) * (206/256) * (230/256) * (1/39) * (27/256)
        try t.expectProbability(27184275, 13958643712);
    } else {
        // (255/256) * (206/256) * (230/256) * (1/39)
        try t.expectProbability(1006825, 54525952);
    }

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(
        Choice,
        if (showdown) &[_]Choice{ swtch(2), move(1), move(2) } else &[_]Choice{move(0)},
        choices[0..n],
    );

    try t.log.expected.move(.{ P2.ident(2), Move.Flamethrower, P1.ident(1) });
    t.expected.p1.get(1).hp -= 90;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    if (showdown) {
        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(2) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(1)});
    }
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(forced, move(1)));
    if (showdown) {
        // (255/256) * (206/256) * (230/256) * (1/39) * (27/256)
        try t.expectProbability(27184275, 13958643712);
    } else {
        // (255/256) * (206/256) * (230/256) * (1/39)
        try t.expectProbability(1006825, 54525952);
    }

    try t.verify();
}

test "Hyper Beam + Sleep move glitch" {
    // https://pkmn.cc/bulba-glitch-1#Hyper_Beam_.2B_Sleep_move_glitch
    // https://glitchcity.wiki/Hyper_Beam_sleep_move_glitch
    const SLP_2 = if (showdown) comptime ranged(2, 8 - 1) else 2;
    const PROC = MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, HIT, ~CRIT, MIN_DMG, SLP_2, HIT, ~CRIT, MIN_DMG, PROC, ~HIT,
        } else .{
            HIT, ~CRIT, MIN_DMG, HIT,
            ~CRIT, SLP_2,
            ~CRIT, MIN_DMG, HIT, PROC, ~CRIT, MIN_DMG, ~HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Hypno, .moves = &.{ .Toxic, .Hypnosis, .Splash, .FirePunch } }},
        &.{.{ .species = .Snorlax, .moves = &.{.HyperBeam} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Toxic, P2.ident(1) });
    t.expected.p2.get(1).status = if (showdown) Status.TOX else Status.init(.PSN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.HyperBeam, P1.ident(1) });
    t.expected.p1.get(1).hp -= 217;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.mustrecharge(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 32;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Poison });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(496701, 27262976); // (216/256) * (229/256) * (241/256) * (1/39)
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);
    try expect(t.actual.p2.active.volatiles.Toxic);
    try expectEqual(1, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.Hypnosis, P2.ident(1) });
    t.expected.p2.get(1).status = Status.slp(2);
    const from: protocol.Status = .From;
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, from, Move.Hypnosis });
    t.expected.p2.get(1).status -= 1;
    try t.log.expected.cant(.{ P2.ident(1), .Sleep });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try t.expectProbability(6, 7);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);
    try expectEqual(1, t.actual.p2.active.volatiles.toxic);

    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.curestatus(.{ P2.ident(1), t.expected.p2.get(1).status, .Message });
    t.expected.p2.get(1).status = 0;
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(3), forced));
    try t.expectProbability(1, 6);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);

    try t.log.expected.move(.{ P1.ident(1), Move.FirePunch, P2.ident(1) });
    t.expected.p2.get(1).hp -= 78;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    t.expected.p2.get(1).status = Status.init(.BRN);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.HyperBeam, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 64;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .Burn });
    try t.log.expected.turn(.{5});

    // The Toxic counter should be preserved
    try expectEqual(Result.Default, try t.update(move(4), move(1)));
    // (255/256) * (26/256) * (223/256) * (1/39) * (27/256)
    try t.expectProbability(511785, 2147483648);
    try expectEqual(t.expected.p2.get(1).status, t.actual.p2.get(1).status);
    try expect(t.actual.p2.active.volatiles.Toxic);
    try expectEqual(2, t.actual.p2.active.volatiles.toxic);

    try t.verify();
}

test "Hyper Beam automatic selection glitch" {
    // https://glitchcity.wiki/Hyper_Beam_automatic_selection_glitch
    const MIN_WRAP = MIN;

    // Regular
    {
        // zig fmt: off
        var t = Test((if (showdown)
            .{ ~HIT, HIT, ~CRIT, MIN_DMG, ~HIT }
        else
            .{ MIN_WRAP, ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, HIT,
                MIN_WRAP, ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, HIT })).init(
        // zig fmt: on
            &.{.{ .species = .Chansey, .moves = &.{ .HyperBeam, .SoftBoiled } }},
            &.{.{ .species = .Tentacool, .moves = &.{.Wrap} }},
        );
        defer t.deinit();

        t.actual.p1.get(1).move(1).pp = 1;

        try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
        t.expected.p2.get(1).hp -= 105;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.mustrecharge(.{P1.ident(1)});
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(88165, 27262976); // (40/256) * (229/256) * (231/256) * (1/39)
        try expectEqual(0, t.actual.p1.get(1).move(1).pp);

        try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        if (showdown) {
            try t.log.expected.cant(.{ P1.ident(1), .Recharge });
        } else {
            try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
            t.expected.p2.get(1).hp -= 105;
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
            try t.log.expected.mustrecharge(.{P1.ident(1)});
        }
        try t.log.expected.turn(.{3});

        // Missing should cause Hyper Beam to be automatically selected and underflow
        try expectEqual(Result.Default, try t.update(forced, move(1)));
        if (showdown) {
            try t.expectProbability(5, 32); // (40/256)
        } else {
            try t.expectProbability(88165, 27262976); // (40/256) * (229/256) * (231/256) * (1/39)
        }
        try expectEqual(if (showdown) 0 else 63, t.actual.p1.get(1).move(1).pp);

        try t.verify();
    }
    // via Metronome
    {
        const hyper_beam = comptime metronome(.HyperBeam);
        // zig fmt: off
        var t = Test((if (showdown)
            .{ ~HIT, hyper_beam, HIT, ~CRIT, MIN_DMG, ~HIT }
        else
            .{ MIN_WRAP, ~CRIT, MIN_DMG, ~HIT, ~CRIT, hyper_beam, ~CRIT, MIN_DMG, HIT,
                MIN_WRAP, ~CRIT, MIN_DMG, ~HIT, ~CRIT, MIN_DMG, HIT })).init(
        // zig fmt: on
            &.{.{ .species = .Chansey, .moves = &.{ .Metronome, .SoftBoiled } }},
            &.{.{ .species = .Tentacool, .moves = &.{.Wrap} }},
        );
        defer t.deinit();

        t.actual.p1.get(1).move(1).pp = 1;

        try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1), Move.Metronome });
        t.expected.p2.get(1).hp -= 105;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.mustrecharge(.{P1.ident(1)});
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        // (1/163) * (40/256) * (231/256) * (229/256) * (1/39)
        try t.expectProbability(88165, 4443865088);
        try expectEqual(0, t.actual.p1.get(1).move(1).pp);

        try t.log.expected.move(.{ P2.ident(1), Move.Wrap, P1.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P2.ident(1)});
        if (showdown) {
            try t.log.expected.cant(.{ P1.ident(1), .Recharge });
        } else {
            try t.log.expected.move(.{ P1.ident(1), Move.HyperBeam, P2.ident(1) });
            t.expected.p2.get(1).hp -= 105;
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
            try t.log.expected.mustrecharge(.{P1.ident(1)});
        }
        try t.log.expected.turn(.{3});

        // Missing should cause Hyper Beam to be automatically selected and underflow
        try expectEqual(Result.Default, try t.update(forced, move(1)));
        if (showdown) {
            try t.expectProbability(5, 32); // (40/256)
        } else {
            try t.expectProbability(88165, 27262976); // (40/256) * (229/256) * (231/256) * (1/39)
        }
        try expectEqual(if (showdown) 0 else 63, t.actual.p1.get(1).move(1).pp);

        try t.verify();
    }
}

test "Invulnerability glitch" {
    // https://pkmn.cc/bulba-glitch-1#Invulnerability_glitch
    // https://glitchcity.wiki/Invulnerability_glitch
    const PAR_CAN = MAX;
    const PAR_CANT = MIN;

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT,
            PAR_CAN,
            PAR_CANT,
            PAR_CAN, ~CRIT, MIN_DMG,
            PAR_CAN,
            PAR_CAN, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, NOP,
        } else .{
            ~CRIT, HIT,
            PAR_CAN, ~CRIT, MIN_DMG,
            PAR_CANT, ~CRIT, MIN_DMG,
            PAR_CAN, ~CRIT, ~CRIT, MIN_DMG,
            PAR_CAN, ~CRIT, MIN_DMG,
            PAR_CAN, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Fearow, .moves = &.{ .Agility, .Fly } }},
        &.{.{
            .species = .Pikachu,
            .level = 50,
            .moves = &.{ .ThunderWave, .ThunderShock, .Swift },
        }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(1) });
    t.expected.p1.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(255, 256);
    try expectEqual(t.expected.p1.get(1).status, t.actual.p1.get(1).status);

    try t.log.expected.move(.{ P1.ident(1), Move.Fly, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.Fly });
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderShock, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(3, 4);

    try t.log.expected.cant(.{ P1.ident(1), .Paralysis });
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderShock, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{4});

    // After Fly is interrupted by Paralysis, Invulnerability should be preserved
    try expectEqual(Result.Default, try t.update(forced, move(2)));
    try t.expectProbability(1, 4);

    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.Swift, P1.ident(1) });
    t.expected.p1.get(1).hp -= 11;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{5});

    // Swift should still be able to hit
    try expectEqual(Result.Default, try t.update(move(1), move(3)));
    try t.expectProbability(211, 13312); // (3/4) * (211/256) * (1/39

    try t.log.expected.move(.{ P1.ident(1), Move.Fly, ID{} });
    try t.log.expected.laststill(.{});
    try t.log.expected.prepare(.{ P1.ident(1), Move.Fly });
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderShock, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{6});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    try t.expectProbability(3, 4);

    try t.log.expected.move(.{ P1.ident(1), Move.Fly, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 130;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.ThunderShock, P1.ident(1) });
    try t.log.expected.supereffective(.{P1.ident(1)});
    t.expected.p1.get(1).hp -= 25;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.turn(.{7});

    // Successfully completing Fly removes Invulnerability
    try expectEqual(Result.Default, try t.update(forced, move(2)));
    // (3/4) * (242/256) * (255/256) * (206/256) * (211/256) * (1/39) ** 2
    try t.expectProbability(223523905, 725849473024);
    try t.verify();
}

test "Stat modification errors" {
    // https://pkmn.cc/bulba-glitch-1#Stat_modification_errors
    // https://glitchcity.wiki/Stat_modification_glitches
    const PROC = comptime ranged(63, 256) - 1;
    const NO_PROC = PROC + 1;
    {
        var t = Test((if (showdown)
            .{ HIT, HIT, NO_PROC, HIT, NO_PROC, HIT }
        else
            .{ ~CRIT, HIT, HIT, NO_PROC, ~CRIT, HIT, ~CRIT, ~CRIT, NO_PROC, ~CRIT, HIT })).init(
            &.{.{
                .species = .Bulbasaur,
                .level = 6,
                .stats = .{},
                .moves = &.{ .StunSpore, .Growth },
            }},
            &.{.{ .species = .Pidgey, .level = 56, .stats = .{}, .moves = &.{.SandAttack} }},
        );
        defer t.deinit();
        try t.start();

        try expectEqual(12, t.actual.p1.active.stats.spe);
        try expectEqual(84, t.actual.p2.active.stats.spe);

        try t.log.expected.move(.{ P2.ident(1), Move.SandAttack, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Accuracy, -1 });
        try t.log.expected.move(.{ P1.ident(1), Move.StunSpore, P2.ident(1) });
        try t.log.expected.status(.{ P2.ident(1), Status.init(.PAR), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(16065, 32768); // (255/256) * (126/256)
        try expectEqual(12, t.actual.p1.active.stats.spe);
        try expectEqual(21, t.actual.p2.active.stats.spe);

        try t.log.expected.move(.{ P2.ident(1), Move.SandAttack, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Accuracy, -1 });
        try t.log.expected.move(.{ P1.ident(1), Move.Growth, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .SpecialAttack, 1 });
        try t.log.expected.boost(.{ P1.ident(1), .SpecialDefense, 1 });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        try t.expectProbability(765, 1024); // (3/4) * (255/256)
        try expectEqual(12, t.actual.p1.active.stats.spe);
        try expectEqual(5, t.actual.p2.active.stats.spe);

        try t.log.expected.move(.{ P1.ident(1), Move.Growth, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .SpecialAttack, 1 });
        try t.log.expected.boost(.{ P1.ident(1), .SpecialDefense, 1 });
        try t.log.expected.move(.{ P2.ident(1), Move.SandAttack, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Accuracy, -1 });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        try t.expectProbability(765, 1024); // (3/4) * (255/256)
        try expectEqual(12, t.actual.p1.active.stats.spe);
        try expectEqual(1, t.actual.p2.active.stats.spe);

        try t.verify();
    }
    {
        var t = Test((if (showdown)
            .{ HIT, NO_PROC, HIT, PROC, HIT, HIT, PROC }
        else
            .{ HIT, NO_PROC, ~CRIT, ~CRIT, HIT, PROC, ~CRIT, HIT, ~CRIT, HIT, PROC })).init(
            &.{
                .{
                    .species = .Bulbasaur,
                    .level = 6,
                    .stats = .{},
                    .moves = &.{ .StunSpore, .Growth },
                },
                .{ .species = .Cloyster, .level = 82, .stats = .{}, .moves = &.{.Withdraw} },
            },
            &.{.{
                .species = .Rattata,
                .level = 2,
                .stats = .{},
                .moves = &.{ .ThunderWave, .TailWhip, .StringShot },
            }},
        );
        defer t.deinit();
        try t.start();

        try expectEqual(144, t.actual.p1.pokemon[1].stats.spe);
        try expectEqual(8, t.actual.p2.active.stats.spe);

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.move(.{ P2.ident(1), Move.ThunderWave, P1.ident(2) });
        try t.log.expected.status(.{ P1.ident(2), Status.init(.PAR), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
        try t.expectProbability(255, 256);
        try expectEqual(36, t.actual.p1.active.stats.spe);
        try expectEqual(8, t.actual.p2.active.stats.spe);

        try t.log.expected.move(.{ P1.ident(2), Move.Withdraw, P1.ident(2) });
        try t.log.expected.boost(.{ P1.ident(2), .Defense, 1 });
        try t.log.expected.move(.{ P2.ident(1), Move.TailWhip, P1.ident(2) });
        try t.log.expected.boost(.{ P1.ident(2), .Defense, -1 });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(765, 1024); // (3/4) * (255/256)
        try expectEqual(9, t.actual.p1.active.stats.spe);
        try expectEqual(8, t.actual.p2.active.stats.spe);

        try t.log.expected.cant(.{ P1.ident(2), .Paralysis });
        try t.log.expected.move(.{ P2.ident(1), Move.TailWhip, P1.ident(2) });
        try t.log.expected.boost(.{ P1.ident(2), .Defense, -1 });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(255, 1024); // (1/4) * (255/256)
        try expectEqual(2, t.actual.p1.active.stats.spe);
        try expectEqual(8, t.actual.p2.active.stats.spe);

        try t.log.expected.move(.{ P2.ident(1), Move.StringShot, P1.ident(2) });
        try t.log.expected.boost(.{ P1.ident(2), .Speed, -1 });
        try t.log.expected.cant(.{ P1.ident(2), .Paralysis });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(move(1), move(3)));
        try t.expectProbability(121, 512); // (242/256) * (1/4)
        try expectEqual(23, t.actual.p1.active.stats.spe);
        try expectEqual(8, t.actual.p2.active.stats.spe);

        try t.verify();
    }
}

test "Stat down modifier overflow glitch" {
    // https://www.youtube.com/watch?v=y2AOm7r39Jg
    const PROC = comptime ranged(85, 256) - 1;
    // 342 -> 1026
    {
        var t = Test((if (showdown)
            .{ HIT, ~CRIT, MIN_DMG, PROC, HIT, ~CRIT, MIN_DMG }
        else
            .{ ~CRIT, ~CRIT, ~CRIT, ~CRIT, MIN_DMG, HIT, PROC, ~CRIT })).init(
            &.{.{
                .species = .Porygon,
                .level = 58,
                .stats = .{},
                .moves = &.{ .Recover, .Psychic },
            }},
            &.{.{
                .species = .Mewtwo,
                .level = 99,
                .stats = .{ .hp = EXP, .atk = EXP, .def = EXP, .spe = EXP, .spc = 12 * 12 },
                .moves = &.{ .Amnesia, .Recover },
            }},
        );
        defer t.deinit();
        try t.start();

        try expectEqual(342, t.actual.p2.active.stats.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Amnesia, P2.ident(1) });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, 2 });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, 2 });
        try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(684, t.actual.p2.active.stats.spc);
        try expectEqual(2, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Amnesia, P2.ident(1) });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, 2 });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, 2 });
        try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));

        try expectEqual(999, t.actual.p2.active.stats.spc);
        try expectEqual(4, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Amnesia, P2.ident(1) });
        if (showdown) {
            try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, 2 });
            try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, -1 });
            try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, 2 });
            try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, -1 });
        }
        try t.log.expected.fail(.{ P2.ident(1), .None });

        try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
        try t.expectProbability(1, 1);
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(999, t.actual.p2.active.stats.spc);
        try expectEqual(5, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Recover, P2.ident(1) });
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
        try t.log.expected.resisted(.{P2.ident(1)});
        t.expected.p2.get(1).hp -= 2;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, -1 });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, -1 });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(426275, 54525952); // (255/256) * (85/256) * (236/256) * (1/39)
        try expectEqual(1026, t.actual.p2.active.stats.spc);
        try expectEqual(4, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Recover, P2.ident(1) });
        t.expected.p2.get(1).hp += 2;
        try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
        if (showdown) {
            try t.log.expected.resisted(.{P2.ident(1)});
            t.expected.p2.get(1).hp = 0;
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
            try t.log.expected.faint(.{ P2.ident(1), false });
            try t.log.expected.win(.{.P1});
        }

        // Division by 0
        const result = if (showdown) Result.Win else Result.Error;
        try expectEqual(result, try t.update(move(2), move(2)));
        // (255/256) * (236/256) * (1/39)
        try if (showdown) t.expectProbability(5015, 212992) else t.expectProbability(1, 1);
        try t.verify();
    }
    // 343 -> 1029
    {
        var t = Test((if (showdown)
            .{ HIT, ~CRIT, MIN_DMG, PROC, HIT, ~CRIT, MIN_DMG }
        else
            .{ ~CRIT, ~CRIT, ~CRIT, ~CRIT, MIN_DMG, HIT, PROC, ~CRIT, MIN_DMG, HIT })).init(
            &.{.{
                .species = .Porygon,
                .stats = .{},
                .level = 58,
                .moves = &.{ .Recover, .Psychic },
            }},
            &.{.{ .species = .Mewtwo, .stats = .{}, .moves = &.{ .Amnesia, .Recover } }},
        );
        defer t.deinit();
        try t.start();

        try expectEqual(343, t.actual.p2.active.stats.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Amnesia, P2.ident(1) });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, 2 });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, 2 });
        try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(686, t.actual.p2.active.stats.spc);
        try expectEqual(2, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Amnesia, P2.ident(1) });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, 2 });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, 2 });
        try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1, 1);
        try expectEqual(999, t.actual.p2.active.stats.spc);
        try expectEqual(4, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Amnesia, P2.ident(1) });
        if (showdown) {
            try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, 2 });
            try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, -1 });
            try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, 2 });
            try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, -1 });
        }
        try t.log.expected.fail(.{ P2.ident(1), .None });

        try t.log.expected.move(.{ P1.ident(1), Move.Recover, P1.ident(1) });
        try t.expectProbability(1, 1);
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try expectEqual(999, t.actual.p2.active.stats.spc);
        try expectEqual(5, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Recover, P2.ident(1) });
        try t.log.expected.fail(.{ P2.ident(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
        try t.log.expected.resisted(.{P2.ident(1)});
        t.expected.p2.get(1).hp -= 2;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialAttack, -1 });
        try t.log.expected.boost(.{ P2.ident(1), .SpecialDefense, -1 });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(426275, 54525952); // (255/256) *  (85/256) * (236/256) * (1/39)
        try expectEqual(1029, t.actual.p2.active.stats.spc);
        try expectEqual(4, t.actual.p2.active.boosts.spc);

        try t.log.expected.move(.{ P2.ident(1), Move.Recover, P2.ident(1) });
        t.expected.p2.get(1).hp += 2;
        try t.log.expected.heal(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Psychic, P2.ident(1) });
        try t.log.expected.resisted(.{P2.ident(1)});
        t.expected.p2.get(1).hp = 0;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.faint(.{ P2.ident(1), false });
        try t.log.expected.win(.{.P1});

        // Overflow means Mewtwo gets KOed
        try expectEqual(Result.Win, try t.update(move(2), move(2)));
        try t.expectProbability(5015, 212992); // (255/256) * (236/256) * (1/39)
        try t.verify();
    }
}

test "Struggle bypassing / Switch PP underflow" {
    // https://pkmn.cc/bulba-glitch-1#Struggle_bypassing
    // https://glitchcity.wiki/Switch_PP_underflow_glitch
    const MIN_WRAP = MIN;

    // Regular
    {
        var t = Test((if (showdown)
            .{ HIT, ~CRIT, MIN_DMG, MIN_WRAP, HIT, ~CRIT, MIN_DMG, MIN_WRAP }
        else
            .{ MIN_WRAP, ~CRIT, MIN_DMG, HIT, MIN_WRAP, ~CRIT, MIN_DMG, HIT })).init(
            &.{
                .{ .species = .Victreebel, .moves = &.{ .Wrap, .VineWhip } },
                .{ .species = .Seel, .moves = &.{.Bubble} },
            },
            &.{
                .{ .species = .Kadabra, .moves = &.{.Splash} },
                .{ .species = .MrMime, .moves = &.{.Splash} },
            },
        );
        defer t.deinit();

        t.actual.p1.get(1).move(1).pp = 1;

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1) });
        t.expected.p2.get(1).hp -= 22;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(153, 8192); // (216/256) * (221/256) * (1/39)
        try expectEqual(0, t.actual.p1.get(1).move(1).pp);

        const n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), forced }, choices[0..n]);

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(2) });
        t.expected.p2.get(2).hp -= 16;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, swtch(2)));
        try t.expectProbability(153, 8192); // (216/256) * (221/256) * (1/39)
        try expectEqual(63, t.actual.p1.get(1).move(1).pp);

        try t.verify();
    }
    // via Metronome
    if (!showdown) {
        const wrap = comptime metronome(.Wrap);
        const swift = comptime metronome(.Swift);
        var t = Test(
            .{ ~CRIT, wrap, MIN_WRAP, ~CRIT, MIN_DMG, HIT, ~CRIT, swift, ~CRIT, MIN_DMG },
        ).init(
            &.{
                .{ .species = .Victreebel, .moves = &.{ .Metronome, .VineWhip } },
                .{ .species = .Seel, .moves = &.{.Bubble} },
            },
            &.{
                .{ .species = .Kadabra, .moves = &.{.Splash} },
                .{ .species = .MrMime, .moves = &.{.Splash} },
            },
        );
        defer t.deinit();

        t.actual.p1.get(1).move(1).pp = 1;

        try t.log.expected.move(.{ P2.ident(1), Move.Splash, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Splash });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1), Move.Metronome });
        t.expected.p2.get(1).hp -= 22;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(153, 1335296); //  (1/163) * (216/256) * (221/256) * (1/39)
        try expectEqual(0, t.actual.p1.get(1).move(1).pp);

        const n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), forced }, choices[0..n]);

        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Swift, P2.ident(2), Move.Metronome });
        t.expected.p2.get(2).hp -= 59;
        try t.log.expected.damage(.{ P2.ident(2), t.expected.p2.get(2), .None });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(forced, swtch(2)));
        try t.expectProbability(17, 125184); // (1/163) * (221/256) * (1/39)
        try expectEqual(63, t.actual.p1.get(1).move(1).pp);

        try t.verify();
    }
}

test "Trapping sleep glitch" {
    // https://glitchcity.wiki/Trapping_move_and_sleep_glitch
    const MIN_WRAP = MIN;
    const SLP_5 = if (showdown) comptime ranged(5, 8 - 1) else 5;

    var t = Test(if (showdown)
        .{ HIT, ~CRIT, MIN_DMG, MIN_WRAP, HIT, SLP_5, HIT }
    else
        .{ MIN_WRAP, ~CRIT, MIN_DMG, HIT, ~CRIT, HIT, SLP_5, ~CRIT }).init(
        &.{
            .{ .species = .Weepinbell, .moves = &.{ .Wrap, .SleepPowder } },
            .{ .species = .Gloom, .moves = &.{.Absorb} },
        },
        &.{
            .{ .species = .Sandshrew, .moves = &.{ .Scratch, .SandAttack } },
            .{ .species = .Magnemite, .moves = &.{ .ThunderShock, .SonicBoom } },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 11;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Bound });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(2061, 106496); // (216/256) * (229/256) * (1/39)

    const p1_choices = &[_]Choice{ swtch(2), forced };
    const all_choices = &[_]Choice{ swtch(2), move(1), move(2) };
    const p2_choices = if (showdown) all_choices else &[_]Choice{ swtch(2), move(0) };

    var n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, p1_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, p2_choices, choices[0..n]);

    try t.log.expected.move(.{ P1.ident(1), Move.Wrap, P2.ident(1) });
    t.expected.p2.get(1).hp -= 11;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Bound });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(forced, forced));
    try t.expectProbability(3, 8);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, all_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, all_choices, choices[0..n]);

    try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    try t.log.expected.move(.{ P1.ident(1), Move.SleepPowder, P2.ident(2) });
    t.expected.p2.get(2).status = Status.slp(5);
    try t.log.expected.status(.{
        P2.ident(2),
        t.expected.p2.get(2).status,
        .From,
        Move.SleepPowder,
    });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), swtch(2)));
    try t.expectProbability(191, 256);
    try expectEqual(t.expected.p2.get(2).status, t.actual.p2.get(1).status);

    n = t.battle.actual.choices(.P1, .Move, &choices);
    try expectEqualSlices(Choice, all_choices, choices[0..n]);
    n = t.battle.actual.choices(.P2, .Move, &choices);
    try expectEqualSlices(Choice, p2_choices, choices[0..n]);

    // Should not have a turn, can only pass!
    try t.log.expected.move(.{ P1.ident(1), Move.SleepPowder, P2.ident(2) });
    try t.log.expected.fail(.{ P2.ident(2), .Sleep });
    if (showdown) {
        try t.log.expected.cant(.{ P2.ident(2), .Sleep });
        t.expected.p2.get(2).status -= 1;
    }
    try t.log.expected.turn(.{5});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    try if (showdown) t.expectProbability(6, 7) else t.expectProbability(1, 1);
    try expectEqual(t.expected.p2.get(2).status, t.actual.p2.get(1).status);

    try t.verify();
}

test "Partial trapping move Mirror Move glitch" {
    // https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch
    // https://pkmn.cc/bulba-glitch-1#Mirror_Move_glitch
    const MIN_WRAP = MIN;

    var t = Test((if (showdown)
        .{ ~HIT, HIT, ~CRIT, MAX_DMG, MIN_WRAP }
    else
        .{ ~CRIT, MIN_WRAP, ~CRIT, MAX_DMG, ~HIT, ~CRIT, MIN_WRAP, ~CRIT, MAX_DMG, HIT })).init(
        &.{.{ .species = .Pidgeot, .moves = &.{ .Agility, .MirrorMove } }},
        &.{
            .{ .species = .Moltres, .moves = &.{ .Leer, .FireSpin } },
            .{ .species = .Drowzee, .moves = &.{.Pound} },
        },
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Agility, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Speed, 2 });
    try t.log.expected.move(.{ P2.ident(1), Move.FireSpin, P1.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P2.ident(1)});
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(2)));
    try t.expectProbability(39, 128); // (78/256)

    try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
    try t.log.expected.move(.{ P1.ident(1), Move.FireSpin, P2.ident(1), Move.MirrorMove });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 5;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.cant(.{ P2.ident(1), .Bound });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(1)));
    try t.expectProbability(18779, 1277952); // (178/256) * (211/256) * (1/39)

    if (showdown) {
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.turn(.{4});
    }

    const result = if (showdown) Result.Default else Result.Error;
    try expectEqual(result, try t.update(move(if (showdown) 2 else 0), swtch(2)));
    try t.expectProbability(1, 1);

    try t.verify();
}

test "Rage + Substitute bug" {
    var t = Test(
    // zig fmt: off
        if (showdown) .{
            HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MAX_DMG,
        } else .{
            ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, ~CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, HIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Jigglypuff, .moves = &.{ .Splash, .Tackle } }},
        &.{.{ .species = .Electabuzz, .moves = &.{ .Substitute, .Rage } }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .Substitute });
    t.expected.p2.get(1).hp -= 83;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Splash, P1.ident(1) });
    try t.log.expected.activate(.{ P1.ident(1), .Splash });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P2.ident(1), Move.Rage, P1.ident(1) });
    t.expected.p1.get(1).hp -= 28;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
    try t.log.expected.activate(.{ P2.ident(1), .Substitute });
    if (!showdown) try t.log.expected.boost(.{ P2.ident(1), .Rage, 1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (255/256) * (242/256) * (204/256) * (246/256) * (1/39) ** 2
    try t.expectProbability(21505935, 45365592064);
    try expectEqual(if (showdown) 0 else 1, t.actual.p2.active.boosts.atk);

    try t.log.expected.move(.{ P2.ident(1), Move.Rage, P1.ident(1) });
    t.expected.p1.get(1).hp -= if (showdown) 28 else 42;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
    try t.log.expected.crit(.{P2.ident(1)});
    try t.log.expected.end(.{ P2.ident(1), .Substitute });
    if (!showdown) try t.log.expected.boost(.{ P2.ident(1), .Rage, 1 });
    try t.log.expected.turn(.{4});

    try expectEqual(Result.Default, try t.update(move(2), forced));
    // (255/256) * (242/256) * (204/256) * (10/256) * (1/39) ** 2
    try t.expectProbability(874225, 45365592064);
    try expectEqual(if (showdown) 0 else 2, t.actual.p2.active.boosts.atk);
    try t.verify();
}

test "Rage stat modification error bug" {
    const PAR_CAN = MAX;
    var t = Test((if (showdown)
        .{ HIT, PAR_CAN, HIT, PAR_CAN, HIT, ~CRIT, MIN_DMG, PAR_CAN, HIT }
    else
        .{ HIT, PAR_CAN, HIT, PAR_CAN, ~CRIT, MIN_DMG, HIT, PAR_CAN, HIT })).init(
        &.{.{ .species = .Charizard, .moves = &.{ .Glare, .Rage } }},
        &.{.{ .species = .Sandshrew, .moves = &.{ .StunSpore, .SeismicToss } }},
    );
    defer t.deinit();
    try t.start();

    try expectEqual(298, t.actual.p1.active.stats.spe);
    try expectEqual(178, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.Glare, P2.ident(1) });
    t.expected.p2.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P2.ident(1), t.expected.p2.get(1).status, .None });
    try t.log.expected.move(.{ P2.ident(1), Move.StunSpore, P1.ident(1) });
    t.expected.p1.get(1).status = Status.init(.PAR);
    try t.log.expected.status(.{ P1.ident(1), t.expected.p1.get(1).status, .None });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(109443, 262144); // (191/256) ** 2 (3/4)
    try expectEqual(74, t.actual.p1.active.stats.spe);
    try expectEqual(44, t.actual.p2.active.stats.spe);

    try t.log.expected.move(.{ P1.ident(1), Move.Rage, P2.ident(1) });
    t.expected.p2.get(1).hp -= 15;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.SeismicToss, P1.ident(1) });
    t.expected.p1.get(1).hp -= 100;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.boost(.{ P1.ident(1), .Rage, 1 });
    try t.log.expected.turn(.{3});

    try expectEqual(Result.Default, try t.update(move(2), move(2)));
    // (3/4) ** 2 * (255/256) ** 2 * (206/256) * (1/39)
    try t.expectProbability(20092725, 1744830464);
    try expectEqual(74, t.actual.p1.active.stats.spe);
    try expectEqual(if (showdown) 44 else 11, t.actual.p2.active.stats.spe);

    try t.verify();
}

test "Rage and Thrash / Petal Dance accuracy bug" {
    // https://www.youtube.com/watch?v=NC5gbJeExbs
    const THRASH_4 = MAX;
    const HIT_255 = comptime ranged(255, 256) - 1;
    const HIT_168 = comptime ranged(168, 256) - 1;
    const MISS_84 = comptime ranged(84, 256);

    var t = Test(
    // zig fmt: off
        if (showdown) .{
            THRASH_4, HIT_255, ~CRIT, MIN_DMG,
            HIT_168, ~CRIT, MIN_DMG,
            MISS_84,
        } else .{
            THRASH_4, ~CRIT, MIN_DMG, HIT_255, ~CRIT,
            ~CRIT, MIN_DMG, HIT_168, ~CRIT,
            ~CRIT, MIN_DMG, MISS_84, ~CRIT,
        }
    // zig fmt: on
    ).init(
        &.{.{ .species = .Nidoking, .moves = &.{.Thrash} }},
        &.{.{ .species = .Onix, .moves = &.{.DoubleTeam} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.DoubleTeam, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Evasion, 1 });
    try t.log.expected.turn(.{2});

    // 255 -> 168
    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try t.expectProbability(9095, 425984); // (255/256) * (214/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
    try t.log.expected.resisted(.{P2.ident(1)});
    t.expected.p2.get(1).hp -= 22;
    try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
    try t.log.expected.move(.{ P2.ident(1), Move.DoubleTeam, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Evasion, 1 });
    try t.log.expected.turn(.{3});

    // 168 -> 84
    try expectEqual(Result.Default, try t.update(forced, move(1)));
    try t.expectProbability(749, 53248); // (168/256) * (214/256) * (1/39)

    try t.log.expected.move(.{ P1.ident(1), Move.Thrash, P2.ident(1) });
    try t.log.expected.lastmiss(.{});
    try t.log.expected.miss(.{P1.ident(1)});
    try t.log.expected.move(.{ P2.ident(1), Move.DoubleTeam, P2.ident(1) });
    try t.log.expected.boost(.{ P2.ident(1), .Evasion, 1 });
    try t.log.expected.turn(.{4});

    // should miss!
    try expectEqual(Result.Default, try t.update(forced, move(1)));
    try t.expectProbability(43, 128); // (1/2) * (172/256)

    try t.verify();
}

test "Substitute HP drain bug" {
    // https://pkmn.cc/bulba-glitch-1#Substitute_HP_drain_bug
    // https://glitchcity.wiki/Substitute_drain_move_not_missing_glitch
    {
        var t = Test((if (showdown)
            .{ HIT, ~CRIT, MIN_DMG, HIT, HIT, ~CRIT, MIN_DMG }
        else
            .{ ~CRIT, MIN_DMG, HIT, HIT, ~CRIT, MIN_DMG, HIT })).init(
            &.{.{ .species = .Butterfree, .moves = &.{.MegaDrain} }},
            &.{.{ .species = .Jolteon, .moves = &.{ .Substitute, .SonicBoom } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Substitute });
        t.expected.p2.get(1).hp -= 83;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.MegaDrain, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Substitute });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(1445, 65536); // (255/256) * (221/256) * (1/39)

        try t.log.expected.move(.{ P2.ident(1), Move.SonicBoom, P1.ident(1) });
        t.expected.p1.get(1).hp -= 20;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.MegaDrain, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Substitute });
        t.expected.p1.get(1).hp += 12;
        try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Drain, P2.ident(1) });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(330905, 16777216); // (229/256) * (255/256) * (221/256) * (1/39)
        try t.verify();
    }
    // Pokémon Showdown incorrectly still heals if the attack did 0 damage
    {
        var t = Test((if (showdown) .{ HIT, ~CRIT } else .{ ~CRIT, MIN_DMG })).init(
            &.{.{ .species = .Sandshrew, .level = 1, .hp = 1, .moves = &.{.Absorb} }},
            &.{.{ .species = .Venusaur, .moves = &.{.Substitute} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Substitute });
        t.expected.p2.get(1).hp -= 90;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Absorb, P2.ident(1) });
        if (showdown) {
            try t.log.expected.resisted(.{P2.ident(1)});
            try t.log.expected.activate(.{ P2.ident(1), .Substitute });
            t.expected.p1.get(1).hp += 1;
            try t.log.expected.heal(.{ P1.ident(1), t.expected.p1.get(1), .Drain, P2.ident(1) });
        } else {
            try t.log.expected.lastmiss(.{});
            try t.log.expected.miss(.{P1.ident(1)});
        }
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        // (255/256) * (236/256)
        try if (showdown) t.expectProbability(15045, 16384) else t.expectProbability(1, 1);
        try expectEqual(91, t.actual.p2.active.volatiles.substitute);

        try t.verify();
    }
}

test "Substitute 1/4 HP glitch" {
    // https://glitchcity.wiki/Substitute_%C2%BC_HP_glitch
    var t = Test(.{}).init(
        &.{
            .{ .species = .Pidgey, .hp = 4, .level = 3, .stats = .{}, .moves = &.{.Substitute} },
            .{ .species = .Pikachu, .hp = 5, .level = 6, .stats = .{}, .moves = &.{.Substitute} },
        },
        &.{.{ .species = .Rattata, .level = 4, .stats = .{}, .moves = &.{.FocusEnergy} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.FocusEnergy, P2.ident(1) });
    try t.log.expected.start(.{ P2.ident(1), .FocusEnergy });
    try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
    try t.log.expected.start(.{ P1.ident(1), .Substitute });
    t.expected.p1.get(1).hp = 0;
    try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
    try t.log.expected.faint(.{ P1.ident(1), true });

    try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);

    try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
    try t.log.expected.turn(.{2});

    try expectEqual(Result.Default, try t.update(swtch(2), .{}));
    try t.expectProbability(1, 1);

    try t.log.expected.move(.{ P1.ident(2), Move.Substitute, P1.ident(2) });
    if (showdown) {
        try t.log.expected.fail(.{ P1.ident(2), .Weak });
        try t.log.expected.move(.{ P2.ident(1), Move.FocusEnergy, P2.ident(1) });
        try t.log.expected.turn(.{3});
    } else {
        try t.log.expected.start(.{ P1.ident(2), .Substitute });
        t.expected.p1.get(2).hp = 0;
        try t.log.expected.damage(.{ P1.ident(2), t.expected.p1.get(2), .None });
        try t.log.expected.faint(.{ P1.ident(2), false });
        try t.log.expected.win(.{.P2});
    }

    // Due to rounding, this should also cause the 1/4 HP glitch
    try expectEqual(if (showdown) Result.Default else Result.Lose, try t.update(move(1), move(1)));
    try t.expectProbability(1, 1);
    try t.verify();
}

test "Substitute + Confusion glitch" {
    // https://pkmn.cc/bulba-glitch-1#Substitute_.2B_Confusion_glitch
    // https://glitchcity.wiki/Confusion_and_Substitute_glitch
    const CFZ_5 = MAX;
    const CFZ_CAN = if (showdown) comptime ranged(128, 256) - 1 else MIN;
    const CFZ_CANT = if (showdown) CFZ_CAN + 1 else MAX;

    // Confused Pokémon has Substitute
    {
        var t = Test((if (showdown)
            .{ HIT, CFZ_5, CFZ_CAN, HIT, CFZ_CANT, HIT, CFZ_CANT }
        else
            .{ HIT, CFZ_5, CFZ_CAN, CFZ_CANT, CFZ_CANT })).init(
            &.{.{ .species = .Bulbasaur, .level = 6, .moves = &.{ .Substitute, .Growl, .Harden } }},
            &.{.{ .species = .Zubat, .level = 10, .moves = &.{.Supersonic} }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Supersonic, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Confusion });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Substitute });
        t.expected.p1.get(1).hp -= 6;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(35, 128); // (140/256) * (1/2)
        try expectEqual(7, t.actual.p1.active.volatiles.substitute);

        try t.log.expected.move(.{ P2.ident(1), Move.Supersonic, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.turn(.{3});

        // If Substitute is up, opponent's sub takes damage for Confusion self-hit or 0 damage
        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        try t.expectProbability(3, 8); // (3/4) * (1/2)
        try expectEqual(7, t.actual.p1.active.volatiles.substitute);

        try t.log.expected.move(.{ P2.ident(1), Move.Supersonic, P1.ident(1) });
        try t.log.expected.fail(.{ P1.ident(1), .None });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        if (showdown) try t.log.expected.activate(.{ P1.ident(1), .Substitute });
        try t.log.expected.turn(.{4});

        // Pokémon Showdown incorrectly applies damage to the confused Pokémon's sub when
        // selecting a self-targeting move
        try expectEqual(Result.Default, try t.update(move(3), move(1)));
        try t.expectProbability(1, 3); // (2/3) * (1/2)
        try expectEqual(if (showdown) 2 else 7, t.actual.p1.active.volatiles.substitute);

        try t.verify();
    }
    // Both Pokémon have Substitutes
    {
        var t = Test((if (showdown)
            .{ HIT, ~CRIT, MIN_DMG, HIT, CFZ_5, CFZ_CANT, CFZ_CAN, CFZ_CANT }
        else
            .{ ~CRIT, MIN_DMG, HIT, HIT, CFZ_5, CFZ_CANT, CFZ_CAN, CFZ_CANT })).init(
            &.{.{ .species = .Bulbasaur, .level = 6, .moves = &.{ .Substitute, .Tackle } }},
            &.{.{ .species = .Zubat, .level = 10, .moves = &.{ .Supersonic, .Substitute } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.start(.{ P2.ident(1), .Substitute });
        t.expected.p2.get(1).hp -= 9;
        try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
        try t.log.expected.move(.{ P1.ident(1), Move.Tackle, P2.ident(1) });
        try t.log.expected.activate(.{ P2.ident(1), .Substitute });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(363, 16384); // (242/256) * (234/256) * (1/39)
        try expectEqual(7, t.actual.p2.active.volatiles.substitute);

        try t.log.expected.move(.{ P2.ident(1), Move.Supersonic, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Confusion });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        t.expected.p1.get(1).hp -= 5;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .Confusion });
        try t.log.expected.turn(.{3});

        // Opponent's sub doesn't take damage because confused user doesn't have one
        try expectEqual(Result.Default, try t.update(move(2), move(1)));
        try t.expectProbability(35, 128); // (140/256) * (1/2)
        try expectEqual(7, t.actual.p2.active.volatiles.substitute);

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.fail(.{ P2.ident(1), .Substitute });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.move(.{ P1.ident(1), Move.Substitute, P1.ident(1) });
        try t.log.expected.start(.{ P1.ident(1), .Substitute });
        t.expected.p1.get(1).hp -= 6;
        try t.log.expected.damage(.{ P1.ident(1), t.expected.p1.get(1), .None });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(move(1), move(2)));
        try t.expectProbability(3, 8); // (3/4) * (1/2)
        try expectEqual(7, t.actual.p1.active.volatiles.substitute);
        try expectEqual(7, t.actual.p2.active.volatiles.substitute);

        try t.log.expected.move(.{ P2.ident(1), Move.Substitute, P2.ident(1) });
        try t.log.expected.fail(.{ P2.ident(1), .Substitute });
        try t.log.expected.activate(.{ P1.ident(1), .Confusion });
        try t.log.expected.activate(.{ P2.ident(1), .Substitute });
        try t.log.expected.turn(.{5});

        // Opponent's sub takes damage for Confusion self-hit if both have one
        try expectEqual(Result.Default, try t.update(move(2), move(2)));
        try t.expectProbability(1, 3); // (2/3) * (1/2)
        try expectEqual(7, t.actual.p1.active.volatiles.substitute);
        try expectEqual(2, t.actual.p2.active.volatiles.substitute);

        try t.verify();
    }
}

test "Psywave infinite loop" {
    // https://pkmn.cc/bulba-glitch-1#Psywave_infinite_loop
    var t = Test((if (showdown) .{ HIT, HIT, MAX_DMG } else .{ ~CRIT, HIT, HIT })).init(
        &.{.{ .species = .Charmander, .level = 1, .moves = &.{.Psywave} }},
        &.{.{ .species = .Rattata, .level = 3, .moves = &.{.TailWhip} }},
    );
    defer t.deinit();

    try t.log.expected.move(.{ P2.ident(1), Move.TailWhip, P1.ident(1) });
    try t.log.expected.boost(.{ P1.ident(1), .Defense, -1 });
    try t.log.expected.move(.{ P1.ident(1), Move.Psywave, P2.ident(1) });

    const result = if (showdown) Result.Default else Result.Error;
    if (showdown) try t.log.expected.turn(.{2});

    try expectEqual(result, try t.update(move(1), move(1)));
    try t.expectProbability(13005, 16384); // (255/256) * (204/256)
    try t.verify();
}

test "Transform + Mirror Move/Metronome PP error" {
    // https://pkmn.cc/bulba/Transform_glitches#Transform_.2B_Mirror_Move.2FMetronome_PP_error
    // https://www.youtube.com/watch?v=_c7tQkSyz7E
    const TIE_1 = MIN;
    const TIE_2 = MAX;

    // PP
    {
        var t = Test((if (showdown)
            .{ HIT, TIE_2, HIT, HIT }
        else
            .{ ~CRIT, HIT, TIE_2, ~CRIT, HIT, ~CRIT, ~CRIT, HIT })).init(
            &.{.{ .species = .Mew, .moves = &.{ .Transform, .IceBeam, .Psychic } }},
            &.{.{ .species = .Spearow, .moves = &.{ .Growl, .Leer, .MirrorMove } }},
        );
        defer t.deinit();

        try t.log.expected.move(.{ P1.ident(1), Move.Transform, P2.ident(1) });
        try t.log.expected.transform(.{ P1.ident(1), P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);
        try expectEqual(16, t.actual.p1.get(1).move(3).pp);

        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Growl, P2.ident(1), Move.MirrorMove });
        try t.log.expected.boost(.{ P2.ident(1), .Attack, -1 });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(3), move(1)));
        try t.expectProbability(65025, 131072); // (1/2) * (255/256) ** 2
        try expectEqual(if (showdown) 16 else 17, t.actual.p1.get(1).move(3).pp);
        try t.verify();
    }
    // Struggle softlock
    {
        var t = Test(
        // zig fmt: off
            if (showdown) .{
                HIT, TIE_1, HIT, HIT, HIT, ~HIT, HIT, ~CRIT, MIN_DMG, HIT,
            } else .{
                ~CRIT, HIT, TIE_1, ~CRIT, ~CRIT, HIT, ~CRIT, HIT,
                ~CRIT, HIT, ~CRIT, MIN_DMG, ~HIT,
            }
        // zig fmt: on
        ).init(
            &.{
                .{ .species = .Ditto, .level = 34, .moves = &.{.Transform} },
                .{ .species = .Koffing, .moves = &.{.Explosion} },
            },
            &.{.{ .species = .Spearow, .level = 23, .moves = &.{ .Growl, .Leer, .MirrorMove } }},
        );
        defer t.deinit();

        t.actual.p1.get(1).move(1).pp = 1;
        try t.start();

        var n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqualSlices(Choice, &[_]Choice{ swtch(2), move(1) }, choices[0..n]);

        try t.log.expected.move(.{ P1.ident(1), Move.Transform, P2.ident(1) });
        try t.log.expected.transform(.{ P1.ident(1), P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Growl, P2.ident(1), Move.MirrorMove });
        try t.log.expected.boost(.{ P2.ident(1), .Attack, -1 });
        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(3), move(1)));
        try t.expectProbability(65025, 131072); // (1/2) * (255/256) ** 2

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(2) });
        try t.log.expected.boost(.{ P1.ident(2), .Attack, -1 });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(swtch(2), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(2), Move.Explosion, P2.ident(1) });
        try t.log.expected.lastmiss(.{});
        try t.log.expected.miss(.{P1.ident(2)});
        t.expected.p1.get(2).hp = 0;
        try t.log.expected.faint(.{ P1.ident(2), true });

        try expectEqual(Result{ .p1 = .Switch, .p2 = .Pass }, try t.update(move(1), move(1)));
        try t.expectProbability(1, 256);

        try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
        try t.log.expected.turn(.{5});

        try expectEqual(Result.Default, try t.update(swtch(2), .{}));
        try t.expectProbability(1, 1);

        n = t.battle.actual.choices(.P1, .Move, &choices);
        try expectEqual(@intFromBool(showdown), n);
        if (showdown) {
            try t.log.expected.move(.{ P1.ident(1), Move.Struggle, P2.ident(1) });
            t.expected.p2.get(1).hp -= 34;
            try t.log.expected.damage(.{ P2.ident(1), t.expected.p2.get(1), .None });
            t.expected.p1.get(1).hp -= 17;
            try t.log.expected.damage(.{
                P1.ident(1),
                t.expected.p1.get(1),
                .RecoilOf,
                P2.ident(1),
            });
            try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
            try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
            try t.log.expected.turn(.{6});

            try expectEqualSlices(Choice, &[_]Choice{move(0)}, choices[0..n]);
            try expectEqual(Result.Default, try t.update(move(0), move(1)));
            try t.expectProbability(628575, 27262976); // (255/256) ** 2 * (232/256) * (1/39)
        }

        try t.verify();
    }
    // Disable softlock
    {
        var t = Test((if (showdown)
            .{ HIT, TIE_1, HIT, HIT, TIE_1, HIT }
        else
            .{ ~CRIT, HIT, TIE_1, ~CRIT, ~CRIT, HIT, ~CRIT, HIT, ~CRIT, HIT })).init(
            &.{
                .{ .species = .Ditto, .level = 34, .moves = &.{.Transform} },
                .{ .species = .Koffing, .moves = &.{.Explosion} },
            },
            &.{
                .{ .species = .Spearow, .level = 23, .moves = &.{ .Growl, .Leer, .MirrorMove } },
                .{ .species = .Drowzee, .level = 23, .moves = &.{.Disable} },
            },
        );
        defer t.deinit();

        t.actual.p1.get(1).move(1).pp = 1;
        try t.start();

        try t.log.expected.move(.{ P1.ident(1), Move.Transform, P2.ident(1) });
        try t.log.expected.transform(.{ P1.ident(1), P2.ident(1) });
        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
        try t.log.expected.turn(.{2});

        try expectEqual(Result.Default, try t.update(move(1), move(1)));
        try t.expectProbability(255, 256);

        try t.log.expected.move(.{ P1.ident(1), Move.MirrorMove, P1.ident(1) });
        try t.log.expected.move(.{ P1.ident(1), Move.Growl, P2.ident(1), Move.MirrorMove });
        try t.log.expected.boost(.{ P2.ident(1), .Attack, -1 });
        try t.log.expected.move(.{ P2.ident(1), Move.Growl, P1.ident(1) });
        try t.log.expected.boost(.{ P1.ident(1), .Attack, -1 });
        try t.log.expected.turn(.{3});

        try expectEqual(Result.Default, try t.update(move(3), move(1)));
        try t.expectProbability(65025, 131072); // (1/2) * (255/256) ** 2

        try t.log.expected.switched(.{ P1.ident(2), t.expected.p1.get(2) });
        try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
        try t.log.expected.turn(.{4});

        try expectEqual(Result.Default, try t.update(swtch(2), swtch(2)));
        try t.expectProbability(1, if (showdown) 2 else 1);

        try t.log.expected.switched(.{ P1.ident(1), t.expected.p1.get(1) });
        try t.log.expected.move(.{ P2.ident(2), Move.Disable, P1.ident(1) });
        if (showdown) {
            try t.log.expected.fail(.{ P1.ident(1), .None });
            try t.log.expected.turn(.{5});
        }

        const result = if (showdown) Result.Default else Result.Error;
        try expectEqual(result, try t.update(swtch(2), move(1)));
        try t.expectProbability(35, 64); // (140/256)

        try t.verify();
    }
}

// Miscellaneous

test "MAX_LOGS" {
    if (showdown or !log) return error.SkipZigTest;
    const BRN = Status.init(.BRN);
    const moves = &.{ .LeechSeed, .ConfuseRay, .Metronome };
    // make P2 slower to avoid speed ties
    const stats = .{ .hp = EXP, .atk = EXP, .def = EXP, .spe = 0, .spc = EXP };
    var battle = Battle.init(
        0,
        &.{.{ .species = .Aerodactyl, .status = BRN, .moves = moves }},
        &.{.{ .species = .Aerodactyl, .status = BRN, .stats = stats, .moves = moves }},
    );
    battle.rng = data.PRNG{ .src = .{ .seed = .{ 180, 137, 181, 165, 16, 97, 148, 20, 25 } } };
    try expectEqual(Result.Default, try battle.update(.{}, .{}, &NULL));

    // P1 and P2 both use Leech Seed
    try expectEqual(Result.Default, try battle.update(move(1), move(1), &NULL));

    // P1 and P2 both use Confuse Ray
    try expectEqual(Result.Default, try battle.update(move(2), move(2), &NULL));

    var copy = battle;
    var p1 = copy.side(.P1);
    var p2 = copy.side(.P2);

    var expected_buf: [data.MAX_LOGS]u8 = undefined;
    var actual_buf: [data.MAX_LOGS]u8 = undefined;

    var expected_stream: ByteStream = .{ .buffer = &expected_buf };
    var actual_stream: ByteStream = .{ .buffer = &actual_buf };

    const expected: FixedLog = .{ .writer = expected_stream.writer() };
    const actual: FixedLog = .{ .writer = actual_stream.writer() };

    try expected.activate(.{ P1.ident(1), .Confusion });
    try expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try expected.move(.{ P1.ident(1), Move.FurySwipes, P2.ident(1), Move.Metronome });
    try expected.crit(.{P2.ident(1)});
    try expected.resisted(.{P2.ident(1)});
    p2.get(1).hp -= 17;
    try expected.damage(.{ P2.ident(1), p2.get(1), .None });
    p2.get(1).hp -= 17;
    try expected.damage(.{ P2.ident(1), p2.get(1), .None });
    p2.get(1).hp -= 17;
    try expected.damage(.{ P2.ident(1), p2.get(1), .None });
    p2.get(1).hp -= 17;
    try expected.damage(.{ P2.ident(1), p2.get(1), .None });
    p2.get(1).hp -= 17;
    try expected.damage(.{ P2.ident(1), p2.get(1), .None });
    try expected.hitcount(.{ P2.ident(1), 5 });
    p1.get(1).hp -= 22;
    try expected.damage(.{ P1.ident(1), p1.get(1), .Burn });
    p1.get(1).hp -= 22;
    try expected.damage(.{ P1.ident(1), p1.get(1), .LeechSeed });
    p2.get(1).hp += 22;
    try expected.heal(.{ P2.ident(1), p2.get(1), .Silent });
    try expected.activate(.{ P2.ident(1), .Confusion });
    try expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
    try expected.move(.{ P2.ident(1), Move.MirrorMove, P2.ident(1), Move.Metronome });
    try expected.move(.{ P2.ident(1), Move.FurySwipes, P1.ident(1), Move.MirrorMove });
    try expected.crit(.{P1.ident(1)});
    try expected.resisted(.{P1.ident(1)});
    p1.get(1).hp -= 19;
    try expected.damage(.{ P1.ident(1), p1.get(1), .None });
    p1.get(1).hp -= 19;
    try expected.damage(.{ P1.ident(1), p1.get(1), .None });
    p1.get(1).hp -= 19;
    try expected.damage(.{ P1.ident(1), p1.get(1), .None });
    p1.get(1).hp -= 19;
    try expected.damage(.{ P1.ident(1), p1.get(1), .None });
    p1.get(1).hp -= 19;
    try expected.damage(.{ P1.ident(1), p1.get(1), .None });
    try expected.hitcount(.{ P1.ident(1), 5 });
    p2.get(1).hp -= 22;
    try expected.damage(.{ P2.ident(1), p2.get(1), .Burn });
    p2.get(1).hp -= 22;
    try expected.damage(.{ P2.ident(1), p2.get(1), .LeechSeed });
    p1.get(1).hp += 22;
    try expected.heal(.{ P1.ident(1), p1.get(1), .Silent });
    try expected.turn(.{4});

    // P1 uses Metronome -> Fury Swipes and P2 uses Metronome -> Mirror Move
    var options = pkmn.battle.options(actual, chance.NULL, calc.NULL);
    try expectEqual(Result.Default, try battle.update(move(3), move(3), &options));

    try expectLog(&expected_buf, &actual_buf);
}

test "RNG overrides" {
    const Random = extern struct {
        state: u8 = 0,

        pub fn speedTie(_: @This()) bool {
            return true;
        }

        pub fn criticalHit(_: @This(), _: Player, _: u8) bool {
            return false;
        }

        pub fn damage(_: @This(), _: Player) u8 {
            return 239;
        }

        pub fn hit(_: @This(), _: Player, _: u8) bool {
            return true;
        }

        pub fn confused(_: @This(), _: Player) bool {
            return false;
        }

        pub fn paralyzed(_: @This(), _: Player) bool {
            return false;
        }

        pub fn secondaryChance(_: @This(), _: Player, _: u8) bool {
            return true;
        }

        pub fn metronome(random: @This(), player: Player) Move {
            if (random.state == 0) {
                return if (player == .P1) Move.Psybeam else Move.Sludge;
            } else {
                return if (player == .P1) Move.Psychic else Move.Thrash;
            }
        }

        pub fn psywave(_: @This(), _: Player) u8 {
            return 1;
        }

        pub fn sleepDuration(_: @This(), _: Player) u3 {
            return 1;
        }

        pub fn disableDuration(_: @This(), _: Player) u4 {
            return 1;
        }

        pub fn confusionDuration(_: @This(), _: Player, _: bool) u3 {
            return 2;
        }

        // pub fn attackingDuration(_: @This(), _: Player, _: bool) u3 {
        //     return 3;
        // }

        pub fn distribution(_: @This(), _: Player) u3 {
            return 2;
        }

        pub fn moveSlot(_: @This(), _: Player, _: []data.MoveSlot, _: u4) u4 {
            return 2;
        }

        pub fn next(_: @This()) u8 {
            unreachable;
        }
    };
    var battle: data.Battle(Random) = .{
        .rng = .{},
        .sides = .{
            helpers.Side.init(&.{.{
                .species = .Chansey,
                .moves = &.{ .Spore, .Metronome, .ThunderShock, .Disable },
            }}),
            helpers.Side.init(&.{.{
                .species = .Chansey,
                .moves = &.{ .Metronome, .Psywave, .Clamp },
            }}),
        },
    };

    try expectEqual(Result.Default, try battle.update(.{}, .{}, &NULL));

    var copy = battle;
    // var p1 = copy.side(.P1);
    var p2 = copy.side(.P2);

    var expected_buf: [data.MAX_LOGS]u8 = undefined;
    var actual_buf: [data.MAX_LOGS]u8 = undefined;

    var expected_stream: ByteStream = .{ .buffer = &expected_buf };
    var actual_stream: ByteStream = .{ .buffer = &actual_buf };

    const expected: FixedLog = .{ .writer = expected_stream.writer() };
    const actual: FixedLog = .{ .writer = actual_stream.writer() };

    var options = pkmn.battle.options(actual, chance.NULL, calc.NULL);

    try expectEqual(Result.Default, try battle.update(move(1), move(1), &options));
    try expected.move(.{ P1.ident(1), Move.Spore, P2.ident(1) });
    p2.get(1).status = Status.slp(1);
    try expected.status(.{ P2.ident(1), p2.get(1).status, .From, Move.Spore });
    try expected.curestatus(.{ P2.ident(1), p2.get(1).status, .Message });
    try expected.turn(.{2});

    try expectLog(&expected_buf, &actual_buf);
    expected_stream.reset();
    actual_stream.reset();

    // FIXME damage

    try expectEqual(Result.Default, try battle.update(move(2), move(1), &options));
    try expected.move(.{ P1.ident(1), Move.Metronome, P1.ident(1) });
    try expected.move(.{ P1.ident(1), Move.Psybeam, P2.ident(1), Move.Metronome });
    try expected.start(.{ P2.ident(1), .Confusion });
    try expected.activate(.{ P2.ident(1), .Confusion });
    try expected.move(.{ P2.ident(1), Move.Metronome, P2.ident(1) });
    try expected.move(.{ P2.ident(1), Move.Sludge, P1.ident(1), Move.Metronome });

    try expectLog(&expected_buf, &actual_buf);
    expected_stream.reset();
    actual_stream.reset();

    battle.rng.state += 1;

    try expectEqual(Result.Default, try battle.update(move(3), move(2), &options));

    try expectEqual(Result.Default, try battle.update(move(4), move(3), &options));

    // try expectEqual(Result.Default, try battle.update(move(2), move(1), &NULL));
}

test "transitions" {
    if (!pkmn.options.calc or !pkmn.options.chance) return error.SkipZigTest;

    // const seed = 0x12345678; // DEBUG
    const seed = seed: {
        var secret: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
        std.crypto.random.bytes(&secret);
        var csprng = std.rand.DefaultCsprng.init(secret);
        const random = csprng.random();
        break :seed random.int(u64);
    };

    var battle = Battle.init(
        seed,
        &.{.{ .species = .Charmander, .hp = 5, .level = 5, .stats = .{}, .moves = &.{.Scratch} }},
        &.{.{ .species = .Squirtle, .hp = 4, .level = 5, .stats = .{}, .moves = &.{.Tackle} }},
    );
    try expectEqual(Result.Default, try battle.update(.{}, .{}, &data.NULL));

    const allocator = std.testing.allocator;
    const writer = std.io.null_writer;
    _ = try calc.transitions(battle, move(1), move(1), allocator, writer, .{
        .seed = seed,
        .cap = true,
    });
}

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

        options: pkmn.battle.Options(Log(ArrayList(u8).Writer), Chance(Rational(u64)), Calc),
        offset: usize,

        pub fn init(pokemon1: []const Pokemon, pokemon2: []const Pokemon) *Self {
            var t = std.testing.allocator.create(Self) catch unreachable;

            t.battle.expected = Battle.fixed(rolls, pokemon1, pokemon2);
            t.battle.actual = t.battle.expected;
            t.buf.expected = std.ArrayList(u8).init(std.testing.allocator);
            t.buf.actual = std.ArrayList(u8).init(std.testing.allocator);
            t.log.expected = .{ .writer = t.buf.expected.writer() };
            t.log.actual = .{ .writer = t.buf.actual.writer() };

            t.expected.p1 = t.battle.expected.side(.P1);
            t.expected.p2 = t.battle.expected.side(.P2);
            t.actual.p1 = t.battle.actual.side(.P1);
            t.actual.p2 = t.battle.actual.side(.P2);

            t.options = .{ .log = t.log.actual, .chance = .{ .probability = .{} }, .calc = .{} };
            t.offset = 0;

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

            var expected_stream: ByteStream = .{ .buffer = &expected_buf };
            var actual_stream: ByteStream = .{ .buffer = &actual_buf };

            const expected: FixedLog = .{ .writer = expected_stream.writer() };
            const actual: FixedLog = .{ .writer = actual_stream.writer() };

            try expected.switched(.{ P1.ident(1), self.actual.p1.get(1) });
            try expected.switched(.{ P2.ident(1), self.actual.p2.get(1) });
            try expected.turn(.{1});

            var options =
                pkmn.battle.options(actual, Chance(Rational(u64)){ .probability = .{} }, Calc{});
            try expectEqual(Result.Default, try self.battle.actual.update(.{}, .{}, &options));
            try expectLog(&expected_buf, &actual_buf);
            if (!pkmn.options.chance) {
                try expectEqual(Rational(u64){ .p = 1, .q = 1 }, options.chance.probability);
            }
        }

        pub fn update(self: *Self, c1: Choice, c2: Choice) !Result {
            if (self.battle.actual.turn == 0) try self.start();

            self.options.chance.reset();
            const result = if (pkmn.options.chance and pkmn.options.calc) result: {
                var copy = self.battle.actual;
                const actions = self.options.chance.actions;

                // Perfom the actual update
                const actual = self.battle.actual.update(c1, c2, &self.options);

                // Ensure we can generate all transitions from the same original state
                // (we must change the battle's RNG from a FixedRNG to a PRNG because
                // the transitions function relies on RNG for discovery of states)
                // FIXME
                // const allocator = std.testing.allocator;
                // const writer = std.io.null_writer;
                // _ = try calc.transitions(unfix(copy), c1, c2, allocator, writer, .{
                //     .actions = actions,
                //     .cap = true,
                // });

                // Demonstrate that we can produce the same state by forcing the RNG to behave the
                // same as we observed - note that because we do not pass in a durations override
                // mask none of the durations will be extended.
                var options = pkmn.battle.options(
                    protocol.NULL,
                    chance.NULL,
                    Calc{ .overrides = .{ .actions = actions } },
                );
                const overridden = copy.update(c1, c2, &options);
                try expectEqual(actual, overridden);

                // The actual battle excluding its RNG field should match a copy updated with
                // overridden RNG (the copy RNG may have advanced because of no-ops)
                copy.rng = self.battle.actual.rng;
                try expectEqual(copy, self.battle.actual);
                break :result actual;
            } else self.battle.actual.update(c1, c2, &self.options);

            try self.validate();
            return result;
        }

        pub fn expectProbability(self: *Self, p: u64, q: u64) !void {
            if (!pkmn.options.chance) return;

            self.options.chance.probability.reduce();
            const r = self.options.chance.probability;
            if (r.p != p or r.q != q) {
                print("expected {d}/{d}, found {}\n", .{ p, q, r });
                return error.TestExpectedEqual;
            }
        }

        pub fn verify(self: *Self) !void {
            try self.validate();
            try expect(self.battle.actual.rng.exhausted());
        }

        fn validate(self: *Self) !void {
            if (log) {
                try protocol.expectLog(
                    data,
                    self.buf.expected.items,
                    self.buf.actual.items,
                    self.offset,
                );
                self.offset = self.buf.expected.items.len;
            }
            for (self.expected.p1.pokemon, 0..) |p, i| {
                try expectEqual(p.hp, self.actual.p1.pokemon[i].hp);
            }
            for (self.expected.p2.pokemon, 0..) |p, i| {
                try expectEqual(p.hp, self.actual.p2.pokemon[i].hp);
            }
        }
    };
}

fn expectLog(expected: []const u8, actual: []const u8) !void {
    return protocol.expectLog(data, expected, actual, 0);
}

fn metronome(comptime m: Move) U {
    const param = @intFromEnum(m);
    if (!showdown) return param;
    const range: u64 = @intFromEnum(Move.Struggle) - 2;
    const mod: u2 = if (param < @intFromEnum(Move.Metronome) - 1) 1 else 2;
    return comptime ranged((param - mod) + 1, range) - 1;
}

fn unfix(actual: anytype) data.Battle(data.PRNG) {
    return .{
        .sides = actual.sides,
        .turn = actual.turn,
        .last_damage = actual.last_damage,
        .last_moves = actual.last_moves,
        .rng = .{ .src = .{
            .seed = if (showdown)
                0x12345678
            else
                .{ 123, 234, 56, 78, 9, 101, 112, 131, 4 },
        } },
    };
}

comptime {
    _ = @import("calc.zig");
    _ = @import("chance.zig");
    _ = @import("data.zig");
    _ = @import("helpers.zig");
    _ = @import("mechanics.zig");
}
