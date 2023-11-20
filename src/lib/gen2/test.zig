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

const Player = common.Player;
const Result = common.Result;
const Choice = common.Choice;

const showdown = pkmn.options.showdown;
const log = pkmn.options.log;

const ArgType = protocol.ArgType;
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

    var expected_buf: [24]u8 = undefined;
    var actual_buf: [24]u8 = undefined;

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
    for (o1, 0..) |o, i| try expectEqual(o, p1.pokemon[i].position);
    for (o2, 0..) |o, i| try expectEqual(o, p2.pokemon[i].position);
}

test "switching (reset)" {
    return error.SkipZigTest;
    // var t = Test(.{}).init(
    //     &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
    //     &.{
    //         .{ .species = .Charmander, .moves = &.{.Scratch} },
    //         .{ .species = .Squirtle, .moves = &.{.Tackle} },
    //     },
    // );
    // defer t.deinit();
    // try t.start();

    // var p1 = &t.actual.p1.active;
    // p1.volatiles.Protect = true;

    // t.actual.p2.last_counter_move = .Scratch;
    // var p2 = &t.actual.p2.active;
    // p2.boosts.atk = 1;
    // p2.volatiles.DefenseCurl = true;
    // t.actual.p2.get(1).status = Status.init(.PAR);

    // try t.log.expected.switched(.{ P2.ident(2), t.expected.p2.get(2) });
    // try t.log.expected.move(P1.ident(1), Move.Teleport, P1.ident(1), null);
    // try t.log.expected.turn(.{2});

    // try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    // try expect(p1.volatiles.Protect);

    // try expectEqual(data.Volatiles{}, p2.volatiles);
    // try expectEqual(data.Boosts{}, p2.boosts);
    // try expectEqual(@as(u8, 0), t.actual.p2.get(1).status);
    // try expectEqual(Status.init(.PAR), t.actual.p2.get(2).status);

    // try expectEqual(Move.Teleport, t.actual.p1.last_counter_move);
    // try expectEqual(Move.None, t.actual.p2.last_counter_move);

    // try t.verify();
}

test "switching (brn/par)" {
    return error.SkipZigTest;
}

test "turn order (priority)" {
    return error.SkipZigTest;
}

test "turn order (basic speed tie)" {
    // Start
    {
        // TODO
    }
    // Move vs. Move
    {
        // TODO
    }
    // Faint vs. Pass
    {
        // TODO
    }
    // Switch vs. Switch
    {
        // TODO
    }
    // Move vs. Switch
    {
        // TODO
    }
    return error.SkipZigTest;
}

test "turn order (complex speed tie)" {
    return error.SkipZigTest;
}

test "turn order (switch vs. move)" {
    return error.SkipZigTest;
}

test "PP deduction" {
    return error.SkipZigTest;
}

test "accuracy (normal)" {
    return error.SkipZigTest;
}

test "damage calc" {
    return error.SkipZigTest;
}

test "type precedence" {
    return error.SkipZigTest;
}

test "fainting (single)" {
    // Switch
    {
        // TODO
    }
    // Win
    {
        // TODO
    }
    // Lose
    {
        // TODO
    }
}

test "fainting (double)" {
    // Switch
    {
        // TODO
    }
    // Switch (boosted)
    {
        // TODO
    }
    // Switch (paralyzed)
    {
        // TODO
    }
    // Tie
    {
        // TODO
    }
}

test "end turn (turn limit)" {
    return error.SkipZigTest;
}

test "Endless Battle Clause (initial)" {
    if (!showdown) return error.SkipZigTest;
    return error.SkipZigTest;
}

test "Endless Battle Clause (basic)" {
    if (!showdown) return error.SkipZigTest;
    {
        // TODO
    }
    {
        // TODO
    }
    return error.SkipZigTest;
}

test "choices" {
    return error.SkipZigTest;
}

// Items

// Item.ThickClub
test "ThickClub effect" {
    // If held by a Cubone or a Marowak, its Attack is doubled.
    return error.SkipZigTest;
}

// Item.LightBall
test "LightBall effect" {
    // If held by a Pikachu, its Special Attack is doubled.
    return error.SkipZigTest;
}

// Item.BerserkGene
test "BerserkGene effect" {
    // On switch-in, raises holder's Attack by 2 and confuses it. Single use.
    return error.SkipZigTest;
}

// Item.Stick
test "Stick effect" {
    // If held by a Farfetch’d, its critical hit ratio is always at stage 2.
    return error.SkipZigTest;
}

// Item.{PinkBow,BlackBelt,SharpBeak,PoisonBarb,SoftSand,HardStone,SilverPowder,SpellTag,MetalCoat}
// Item.{PolkadotBow,Charcoal,MysticWater,MiracleSeed,Magnet,TwistedSpoon,NeverMeltIce,DragonScale}
// Item.BlackGlasses
test "Boost effect" {
    // Holder's X-type attacks have 1.1x power.
    return error.SkipZigTest;
}

// Item.BrightPowder
test "BrightPowder effect" {
    // An attack against the holder has its accuracy out of 255 lowered by 20.
    return error.SkipZigTest;
}

// Item.MetalPowder
test "MetalPowder effect" {
    // If held by a Ditto, its Defense and Sp. Def are 1.5x, even while Transformed.
    return error.SkipZigTest;
}

// Item.QuickClaw
test "QuickClaw effect" {
    // Each turn, holder has a ~23.4% chance to move first in its priority bracket.
    return error.SkipZigTest;
}

// Item.KingsRock
test "Flinch effect" {
    // Holder's attacks without a chance to make the target flinch gain a 10% chance to make the
    // target flinch.
    return error.SkipZigTest;
}

// Item.ScopeLens
test "CriticalUp effect" {
    // Holder's critical hit ratio is raised by 1 stage.
    return error.SkipZigTest;
}

// Item.Leftovers
test "Leftovers effect" {
    // At the end of every turn, holder restores 1/16 of its max HP.
    return error.SkipZigTest;
}

// Item.{PSNCureBerry,PRZCureBerry,BurntBerry,IceBerry,BitterBerry,MintBerry,MiracleBerry}
test "HealStatus effect" {
    // Holder is cured if it has status X. Single use.
    return error.SkipZigTest;
}

// Item.{BerryJuice,Berry,GoldBerry}
test "Berry effect" {
    // Restores X HP when at 1/2 max HP or less. Single use.
    return error.SkipZigTest;
}

// Item.MysteryBerry
test "RestorePP effect" {
    // Restores 5 PP to the first of the holder's moves to reach 0 PP. Single use.
    return error.SkipZigTest;
}

// Item.{FlowerMail,SurfMail,LightBlueMail,PortrailMail,LovelyMail,EonMail}
// Item.{MorphMail,BlueSkyMail,MusicMail,MirageMail}
test "Mail effect" {
    // Cannot be taken from a Pokemon.
    return error.SkipZigTest;
}

// Item.FocusBand
test "FocusBand effect" {
    // Holder has a ~11.7% chance to survive an attack that would KO it with 1 HP.
    return error.SkipZigTest;
}

// Moves

// Move.{KarateChop,RazorLeaf,Crabhammer,Slash,Aeroblast,CrossChop}
test "HighCritical effect" {
    // Has a higher chance for a critical hit.
    return error.SkipZigTest;
}

// Move.FocusEnergy
test "FocusEnergy effect" {
    // Raises the user's chance for a critical hit by 1 stage. Fails if the user already has the
    // effect. Baton Pass can be used to transfer this effect to an ally.
    return error.SkipZigTest;
}

// Move.{DoubleSlap,CometPunch,FuryAttack,PinMissile,SpikeCannon,Barrage,FurySwipes,BoneRush}
test "MultiHit effect" {
    // Hits two to five times. Has a 3/8 chance to hit two or three times, and a 1/8 chance to hit
    // four or five times. If one of the hits breaks the target's substitute, it will take damage
    // for the remaining hits.
    return error.SkipZigTest;
}

// Move.{DoubleKick,Bonemerang}
test "DoubleHit effect" {
    // Hits twice. If the first hit breaks the target's substitute, it will take damage for the
    // second hit.
    return error.SkipZigTest;
}

// Move.TripleKick
test "TripleKick effect" {
    // Hits one to three times, at random. Power increases to 20 for the second hit and 30 for the
    // third.
    return error.SkipZigTest;
}

// Move.Twineedle
test "Twineedle effect" {
    // Hits twice, with the second hit having a 20% chance to poison the target. If the first hit
    // breaks the target's substitute, it will take damage for the second hit but the target cannot
    // be poisoned by it.
    return error.SkipZigTest;
}

// Move.Toxic
// Move.{PoisonPowder,PoisonGas}
test "Poison effect" {
    // (Badly) Poisons the target.
    return error.SkipZigTest;
}

// Move.{PoisonSting,Smog,Sludge,SludgeBomb}
test "PoisonChance effect" {
    // Has a X% chance to poison the target.
    return error.SkipZigTest;
}

// Move.{FirePunch,Ember,Flamethrower,FireBlast}
test "BurnChance effect" {
    // Has a 10% chance to burn the target.
    return error.SkipZigTest;
}

// Move.FlameWheel
test "FlameWheel effect" {
    // Has a 10% chance to burn the target. Thaws the user.
    return error.SkipZigTest;
}

// Move.SacredFire
test "SacredFire effect" {
    // Has a 50% chance to burn the target. Thaws the user.
    return error.SkipZigTest;
}

// Move.{IcePunch,IceBeam,Blizzard,PowderSnow}
test "FreezeChance effect" {
    // Has a 10% chance to freeze the target.
    return error.SkipZigTest;
}

// Move.{StunSpore,ThunderWave,Glare}
test "Paralyze effect" {
    // Paralyzes the target. This move does not ignore type immunity.
    return error.SkipZigTest;
}

// Move.{ThunderPunch,BodySlam,ThunderShock,Thunderbolt,Lick,ZapCannon,Spark,DragonBreath}
test "ParalyzeChance effect" {
    // Has a X% chance to paralyze the target.
    return error.SkipZigTest;
}

// Move.TriAttack
test "TriAttack effect" {
    // This move selects burn, freeze, or paralysis at random, and has a 20% chance to inflict the
    // target with that status. If the target is frozen and burn was selected, it thaws out.
    return error.SkipZigTest;
}

// Move.{Sing,SleepPowder,Hypnosis,LovelyKiss,Spore}
test "Sleep effect" {
    // Causes the target to fall asleep.
    return error.SkipZigTest;
}

// Move.{Supersonic,ConfuseRay,SweetKiss}
test "Confusion effect" {
    // Causes the target to become confused.
    return error.SkipZigTest;
}

// Move.{Psybeam,Confusion,DizzyPunch,DynamicPunch}
test "ConfusionChance effect" {
    // Has a 100% chance to confuse the target.
    return error.SkipZigTest;
}

// Move.{RollingKick,Headbutt,Bite,LowKick,BoneClub,RockSlide,HyperFang}
test "FlinchChance effect" {
    // Has a X% chance to make the target flinch.
    return error.SkipZigTest;
}

// Move.Snore
test "Snore effect" {
    // Has a 30% chance to make the target flinch. Fails if the user is not asleep.
    return error.SkipZigTest;
}

// Move.Stomp
test "Stomp effect" {
    // Has a 30% chance to make the target flinch. Power doubles if the target is under the effect
    // of Minimize.
    return error.SkipZigTest;
}

// Move.Growl: AttackDown1
// Move.Charm: AttackDown2
// Move.{TailWhip,Leer}: DefenseDown1
// Move.Screech: DefenseDown2
// Move.StringShot: SpeedDown1
// Move.{CottonSpore,ScaryFace}: SpeedDown2
// Move.{SandAttack,Smokescreen,Kinesis,Flash}: AccuracyDown1
// Move.SweetScent: EvasionDown1
test "StatDown effect" {
    // Lowers the target's X stat by Y stage(s).
    return error.SkipZigTest;
}

// Move.AuroraBeam: AttackDownChance
// Move.{Acid,IronTail,RockSmash}: DefenseDownChance
// Move.{BubbleBeam,Constrict,Bubble,IcyWind}: SpeedDownChance
// Move.{Psychic,Crunch,ShadowBall}: SpDefDownChance
// Move.{MudSlap,Octazooka}: AccuracyDownChance
test "StatDownChance effect" {
    // Has a X% chance to lower the target's Y stat by Z stage(s).
    return error.SkipZigTest;
}

// Move.{Meditate,Sharpen}: AttackUp1
// Move.SwordsDance: AttackUp2
// Move.{Harden,Withdraw}: DefenseUp1
// Move.{Barrier,AcidArmor}: DefenseUp2
// Move.Agility: SpeedUp2
// Move.Growth: SpAtkUp1
// Move.Amnesia: SpDefUp2
// Move.{DoubleTeam,Minimize}: EvasionUp1
test "StatUp effect" {
    // Raises the target's X stat by Y stage(s).
    return error.SkipZigTest;
}

// Move.DefenseCurl
test "DefenseCurl effect" {
    // Raises the user's Defense by 1 stage. While the user remains active, the power of the user's
    // Rollout will be doubled (this effect is not stackable). Baton Pass can be used to transfer
    // this effect to an ally.
    return error.SkipZigTest;
}

// Move.MetalClaw: AttackUpChance
// Move.SteelWing: DefenseUpChance
test "StatUpChance effect" {
    // Has a X% chance to raise the target's Y stat by Z stage(s).
    return error.SkipZigTest;
}

// Move.AncientPower
test "AllStatUpChance effect" {
    // Has a 10% chance to raise the user's Attack, Defense, Special Attack, Special Defense, and
    // Speed by 1 stage.
    return error.SkipZigTest;
}

// Move.{Guillotine,HornDrill,Fissure}
test "OHKO effect" {
    // Deals 65535 damage to the target. This attack's accuracy out of 256 is equal to the lesser of
    // (2 * (user's level - target's level) + 76) and 255, before applying accuracy and evasiveness
    // modifiers. Fails if the target is at a higher level.
    return error.SkipZigTest;
}

// Move.SkyAttack
test "SkyAttack effect" {
    // This attack charges on the first turn and executes on the second.
    return error.SkipZigTest;
}

// Move.SkullBash
test "SkullBash effect" {
    // This attack charges on the first turn and executes on the second. Raises the user's Defense
    // by 1 stage on the first turn.
    return error.SkipZigTest;
}

// Move.RazorWind
test "RazorWind effect" {
    // Has a higher chance for a critical hit. This attack charges on the first turn and executes on
    // the second.
    return error.SkipZigTest;
}

// Move.SolarBeam
test "Solarbeam effect" {
    // This attack charges on the first turn and executes on the second. Damage is halved if the
    // weather is Rain Dance. If the weather is Sunny Day, the move completes in one turn.
    return error.SkipZigTest;
}

// Move.{Fly,Dig}
test "Fly effect" {
    // This attack charges on the first turn and executes on the second. Fly: On the first turn, the
    // user avoids all attacks other than Gust, Thunder, Twister, and Whirlwind, and Gust and
    // Twister have doubled power when used against it. Dig: On the first turn, the user avoids all
    // attacks other than Earthquake, Fissure, and Magnitude, the user is unaffected by weather, and
    // Earthquake and Magnitude have doubled power when used against the user.
    return error.SkipZigTest;
}

// Move.{Gust,Earthquake}
test "Gust/Earthquake effect" {
    // Power doubles if the target is using Fly/Dig.
    return error.SkipZigTest;
}

// Move.Twister
test "Twister effect" {
    // Has a 20% chance to make the target flinch. Power doubles if the target is using Fly.
    return error.SkipZigTest;
}

// Move.{Whirlwind,Roar}
test "ForceSwitch effect" {
    // The target is forced to switch out and be replaced with a random unfainted ally. Fails if the
    // target is the last unfainted Pokemon in its party, or if the user moves before the target.
    return error.SkipZigTest;
}

// Move.Teleport
test "Teleport effect" {
    // Fails when used.
    return error.SkipZigTest;
}

// Move.Splash
test "Splash effect" {
    // No competitive use.
    return error.SkipZigTest;
}

// Move.{Bind,Wrap,FireSpin,Clamp,Whirlpool}
test "Binding effect" {
    // Prevents the target from switching for two to five turns. Causes damage to the target equal
    // to 1/16 of its maximum HP, rounded down, at the end of each turn during effect. The target
    // can still switch out if it uses Baton Pass. The effect ends if either the user or the target
    // leaves the field, or if the target uses Rapid Spin or Substitute successfully. This effect is
    // not stackable or reset by using this or another binding move.
    return error.SkipZigTest;
}

// Move.{JumpKick,HighJumpKick}
test "JumpKick effect" {
    // If this attack is not successful and the target was not immune, the user loses HP equal to
    // 1/8 the damage the target would have taken, rounded down, but not less than 1 HP, as crash
    // damage.
    return error.SkipZigTest;
}

// Move.{TakeDown,DoubleEdge,Submission}
test "RecoilHit effect" {
    // If the target lost HP, the user takes recoil damage equal to 1/4 the HP lost by the target,
    // rounded half up, but not less than 1 HP. If this move hits a substitute, the recoil damage is
    // always 1 HP.
    return error.SkipZigTest;
}

test "Struggle effect" {
    // Deals typeless damage. If this move was successful, the user takes damage equal to 1/4 the HP
    // lost by the target, rounded down, but not less than 1 HP. This move is automatically used if
    // none of the user's known moves can be selected.
    return error.SkipZigTest;
}

// Move.{Thrash,PetalDance,Outrage}
test "Thrashing effect" {
    // Whether or not this move is successful, the user spends two or three turns locked into this
    // move and becomes confused immediately after its move on the last turn of the effect, even if
    // it is already confused. If the user is prevented from moving, the effect ends without causing
    // confusion. If this move is called by Sleep Talk, the move is used for one turn and does not
    // confuse the user.
    return error.SkipZigTest;
}

// Move.{SonicBoom,DragonRage}
test "FixedDamage effect" {
    // Deals 40 HP of damage to the target.
    return error.SkipZigTest;
}

// Move.{SeismicToss,NightShade}
test "LevelDamage effect" {
    // Deals damage to the target equal to the user's level.
    return error.SkipZigTest;
}

// Move.Psywave
test "Psywave effect" {
    // Deals damage to the target equal to a random number from 1 to (user's level * 1.5 - 1),
    // rounded down, but not less than 1 HP.
    return error.SkipZigTest;
}

// Move.SuperFang
test "SuperFang effect" {
    // Deals damage to the target equal to half of its current HP, rounded down, but not less than 1
    // HP.
    return error.SkipZigTest;
}

// Move.Disable
test "Disable effect" {
    // For 1 to 7 turns, the target's last move used becomes disabled. Fails if one of the target's
    // moves is already disabled, if the target has not made a move, if the target no longer knows
    // the move, or if the move has 0 PP.
    return error.SkipZigTest;
}

// Move.Mist
test "Mist effect" {
    // While the user remains active, it is protected from having its stat stages lowered by other
    // Pokemon. Fails if the user already has the effect. Baton Pass can be used to transfer this
    // effect to an ally.
    return error.SkipZigTest;
}

// Move.HyperBeam
test "HyperBeam effect" {
    // If this move is successful, the user must recharge on the following turn and cannot select a
    // move.
    return error.SkipZigTest;
}

// Move.Counter
test "Counter effect" {
    // Deals damage to the opposing Pokemon equal to twice the HP lost by the user from a physical
    // attack this turn. This move considers Hidden Power as Normal type, and only the last hit of a
    // multi-hit attack is counted. Fails if the user moves first, if the user was not hit by a
    // physical attack this turn, or if the user did not lose HP from the attack. If the opposing
    // Pokemon used Fissure or Horn Drill and missed, this move deals 65535 damage.
    return error.SkipZigTest;
}

// Move.MirrorCoat
test "MirrorCoat effect" {
    // Deals damage to the opposing Pokemon equal to twice the HP lost by the user from a special
    // attack this turn. This move considers Hidden Power as Normal type, and only the last hit of a
    // multi-hit attack is counted. Fails if the user moves first, if the user was not hit by a
    // special attack this turn, or if the user did not lose HP from the attack.
    return error.SkipZigTest;
}

// Move.{Recover,SoftBoiled,MilkDrink}
test "Heal effect" {
    // The user restores 1/2 of its maximum HP, rounded down.
    return error.SkipZigTest;
}

// Move.{Moonlight,MorningSun,Synthesis}
test "WeatherHeal effect" {
    // The user restores 1/2 of its maximum HP if no weather conditions are in effect, all of its HP
    // if the weather is Sunny Day, and 1/4 of its maximum HP if the weather is Rain Dance or
    // Sandstorm, all rounded down.
    return error.SkipZigTest;
}

// Move.Rest
test "Rest effect" {
    // The user falls asleep for the next two turns and restores all of its HP, curing itself of any
    // non-volatile status condition in the process, even if it was already asleep. Fails if the
    // user has full HP.
    return error.SkipZigTest;
}

// Move.{Absorb,MegaDrain,LeechLife,GigaDrain}
test "DrainHP effect" {
    // The user recovers 1/2 the HP lost by the target, rounded down.
    return error.SkipZigTest;
}

// Move.DreamEater
test "DreamEater effect" {
    // The target is unaffected by this move unless it is asleep and does not have a substitute. The
    // user recovers 1/2 the HP lost by the target, rounded down, but not less than 1 HP.
    return error.SkipZigTest;
}

// Move.LeechSeed
test "LeechSeed effect" {
    // The Pokemon at the user's position steals 1/8 of the target's maximum HP, rounded down, at
    // the end of each turn. If the target uses Baton Pass, the replacement will continue being
    // leeched. If the target switches out or uses Rapid Spin, the effect ends. Grass-type Pokemon
    // are immune to this move on use, but not its effect.
    return error.SkipZigTest;
}

// Move.Rage
test "Rage effect" {
    // Once this move is successfully used, X starts at 1. This move's damage is multiplied by X,
    // and whenever the user is hit by the opposing Pokemon, X increases by 1, with a maximum of
    // 255. X resets to 1 when the user is no longer active or did not choose this move for use.
    return error.SkipZigTest;
}

// Move.Mimic
test "Mimic effect" {
    // While the user remains active, this move is replaced by the last move used by the target. The
    // copied move has 5 PP. Fails if the target has not made a move, if the user already knows the
    // move, or if the move is Struggle.
    return error.SkipZigTest;
}

// Move.LightScreen
test "LightScreen effect" {
    // For 5 turns, the user and its party members have their Special Defense doubled. Critical hits
    // ignore this effect. Fails if the effect is already active on the user's side.
    return error.SkipZigTest;
}

// Move.Reflect
test "Reflect effect" {
    // For 5 turns, the user and its party members have their Defense doubled. Critical hits ignore
    // this effect. Fails if the effect is already active on the user's side.
    return error.SkipZigTest;
}

// Move.Haze
test "Haze effect" {
    // Resets the stat stages of all active Pokemon to 0.
    return error.SkipZigTest;
}

// Move.Bide
test "Bide effect" {
    // The user spends two or three turns locked into this move and then, on the second or third
    // turn after using this move, the user attacks the opponent, inflicting double the damage in HP
    // it lost during those turns. If the user is prevented from moving during this move's use, the
    // effect ends. This move does not ignore type immunity.
    return error.SkipZigTest;
}

// Move.Metronome
test "Metronome effect" {
    // A random move is selected for use, other than Counter, Destiny Bond, Detect, Endure,
    // Metronome, Mimic, Mirror Coat, Protect, Sketch, Sleep Talk, Struggle, Thief, or any move the
    // user already knows.
    return error.SkipZigTest;
}

// Move.MirrorMove
test "MirrorMove effect" {
    // The user uses the last move used by the target. Fails if the target has not made a move, or
    // if the last move used was Metronome, Mimic, Mirror Move, Sketch, Sleep Talk, Transform, or
    // any move the user knows.
    return error.SkipZigTest;
}

// Move.{SelfDestruct,Explosion}
test "Explode effect" {
    // The user faints after using this move. The target's Defense is halved during damage
    // calculation.
    return error.SkipZigTest;
}

// Move.{Swift,FeintAttack,VitalThrow}
test "AlwaysHit effect" {
    // This move does not check accuracy.
    return error.SkipZigTest;
}

// Move.Transform
test "Transform effect" {
    // The user transforms into the target. The target's current stats, stat stages, types, moves,
    // DVs, species, and sprite are copied. The user's level and HP remain the same and each copied
    // move receives only 5 PP. This move fails if the target has transformed.
    return error.SkipZigTest;
}

// Move.Conversion
test "Conversion effect" {
    // The user's type changes to match the original type of one of its known moves besides Curse,
    // at random, but not either of its current types. Fails if the user cannot change its type, or
    // if this move would only be able to select one of the user's current types.
    return error.SkipZigTest;
}

// Move.Conversion2
test "Conversion2 effect" {
    // The user's type changes to match a type that resists or is immune to the type of the last
    // move used by the opposing Pokemon, even if it is one of the user's current types. The
    // original type of the move is used rather than the determined type. Fails if the opposing
    // Pokemon has not used a move.
    return error.SkipZigTest;
}

// Move.Substitute
test "Substitute effect" {
    // The user takes 1/4 of its maximum HP, rounded down, and puts it into a substitute to take its
    // place in battle. The substitute is removed once enough damage is inflicted on it, or if the
    // user switches out or faints. Baton Pass can be used to transfer the substitute to an ally,
    // and the substitute will keep its remaining HP. Until the substitute is broken, it receives
    // damage from all attacks made by other Pokemon and shields the user from status effects and
    // stat stage changes caused by other Pokemon. The user still takes normal damage from weather
    // and status effects while behind its substitute. If the substitute breaks during a multi-hit
    // attack, the user will take damage from any remaining hits. If a substitute is created while
    // the user is trapped by a binding move, the binding effect ends immediately. Fails if the user
    // does not have enough HP remaining to create a substitute without fainting, or if it already
    // has a substitute.
    return error.SkipZigTest;
}

// Move.Sketch
test "Sketch effect" {
    // Fails when used in Link Battles.
    return error.SkipZigTest;
}

// Move.Thief
test "Thief effect" {
    // Has a 100% chance to steal the target's held item if the user is not holding one. The
    // target's item is not stolen if it is a Mail.
    return error.SkipZigTest;
}

// Move.{SpiderWeb,MeanLook}
test "MeanLook effect" {
    // Prevents the target from switching out. The target can still switch out if it uses Baton
    // Pass. If the target leaves the field using Baton Pass, the replacement will remain trapped.
    // The effect ends if the user leaves the field, unless it uses Baton Pass, in which case the
    // target will remain trapped.
    return error.SkipZigTest;
}

// Move.{MindReader,LockOn}
test "LockOn effect" {
    // The next accuracy check against the target succeeds. The target will still avoid Earthquake,
    // Fissure, and Magnitude if it is using Fly. If the target leaves the field using Baton Pass,
    // the replacement remains under this effect. This effect ends when the target leaves the field
    // or an accuracy check is done against it.
    return error.SkipZigTest;
}

// Move.Nightmare
test "Nightmare effect" {
    // Causes the target to lose 1/4 of its maximum HP, rounded down, at the end of each turn as
    // long as it is asleep. This move does not affect the target unless it is asleep. The effect
    // ends when the target wakes up, even if it falls asleep again in the same turn.
    return error.SkipZigTest;
}

// Move.Curse
test "Curse effect" {
    // If the user is not a Ghost type, lowers the user's Speed by 1 stage and raises the user's
    // Attack and Defense by 1 stage, unless the user's Attack and Defense stats are both at stage
    // 6. If the user is a Ghost type, the user loses 1/2 of its maximum HP, rounded down and even
    // if it would cause fainting, in exchange for the target losing 1/4 of its maximum HP, rounded
    // down, at the end of each turn while it is active. If the target uses Baton Pass, the
    // replacement will continue to be affected. Fails if the target is already affected or has a
    // substitute.
    return error.SkipZigTest;
}

// Move.{Flail,Reversal}
test "Reversal effect" {
    // The power of this move is 20 if X is 33 to 48, 40 if X is 17 to 32, 80 if X is 10 to 16, 100
    // if X is 5 to 9, 150 if X is 2 to 4, and 200 if X is 0 or 1, where X is equal to (user's
    // current HP * 48 / user's maximum HP), rounded down. This move does not apply damage variance
    // and cannot be a critical hit.
    return error.SkipZigTest;
}

// Move.Spite
test "Spite effect" {
    // Causes the target's last move used to lose 2 to 5 PP, at random. Fails if the target has not
    // made a move, or if the move has 0 PP.
    return error.SkipZigTest;
}

// Move.{Protect,Detect}
test "Protect effect" {
    // The user is protected from attacks made by the opponent during this turn. This move has an
    // X/255 chance of being successful, where X starts at 255 and halves, rounded down, each time
    // this move is successfully used. X resets to 255 if this move fails or if the user's last move
    // used is not Detect, Endure, or Protect. Fails if the user has a substitute or moves last this
    // turn.
    return error.SkipZigTest;
}

// Move.Endure
test "Endure effect" {
    // The user will survive attacks made by the opponent during this turn with at least 1 HP. This
    // move has an X/255 chance of being successful, where X starts at 255 and halves, rounded down,
    // each time this move is successfully used. X resets to 255 if this move fails or if the user's
    // last move used is not Detect, Endure, or Protect. Fails if the user has a substitute or moves
    // last this turn.
    return error.SkipZigTest;
}

// Move.BellyDrum
test "BellyDrum effect" {
    // Raises the user's Attack by 12 stages in exchange for the user losing 1/2 of its maximum HP,
    // rounded down. Fails if the user would faint or if its Attack stat stage is 6.
    return error.SkipZigTest;
}

// Move.Spikes
test "Spikes effect" {
    // Sets up a hazard on the opposing side of the field, causing each opposing Pokemon that
    // switches in to lose 1/8 of their maximum HP, rounded down, unless it is a Flying-type
    // Pokemon. Fails if the effect is already active on the opposing side. Can be removed from the
    // opposing side if any opposing Pokemon uses Rapid Spin successfully.
    return error.SkipZigTest;
}

// Move.RapidSpin
test "RapidSpin effect" {
    // If this move is successful, the effects of Leech Seed and binding moves end for the user, and
    // Spikes are removed from the user's side of the field.
    return error.SkipZigTest;
}

// Move.Foresight
test "Foresight effect" {
    // As long as the target remains active, if its evasiveness stat stage is greater than the
    // attacker's accuracy stat stage, both are ignored during accuracy checks, and Normal- and
    // Fighting-type attacks can hit the target if it is a Ghost type. If the target leaves the
    // field using Baton Pass, the replacement will remain under this effect. Fails if the target is
    // already affected.
    return error.SkipZigTest;
}

// Move.DestinyBond
test "DestinyBond effect" {
    // Until the user's next turn, if an opposing Pokemon's attack knocks the user out, that Pokemon
    // faints as well.
    return error.SkipZigTest;
}

// Move.PerishSong
test "PerishSong effect" {
    // Each active Pokemon receives a perish count of 4 if it doesn't already have a perish count.
    // At the end of each turn including the turn used, the perish count of all active Pokemon
    // lowers by 1 and Pokemon faint if the number reaches 0. The perish count is removed from
    // Pokemon that switch out. If a Pokemon uses Baton Pass while it has a perish count, the
    // replacement will gain the perish count and continue to count down.
    return error.SkipZigTest;
}

// Move.Rollout
test "Rollout effect" {
    // If this move is successful, the user is locked into this move and cannot make another move
    // until it misses, 5 turns have passed, or the attack cannot be used. Power doubles with each
    // successful hit of this move and doubles again if Defense Curl was used previously by the
    // user. If this move is called by Sleep Talk, the move is used for one turn.
    return error.SkipZigTest;
}

// Move.FalseSwipe
test "FalseSwipe effect" {
    // Leaves the target with at least 1 HP.
    return error.SkipZigTest;
}

// Move.Swagger
test "Swagger effect" {
    // Raises the target's Attack by 2 stages and confuses it. This move will miss if the target's
    // Attack cannot be raised.
    return error.SkipZigTest;
}

// Move.FuryCutter
test "FuryCutter effect" {
    // Power doubles with each successful hit, up to a maximum of 160 power. The power is reset if
    // this move misses or another move is used.
    return error.SkipZigTest;
}

// Move.Attract
test "Attract effect" {
    // Causes the target to become infatuated, making it unable to attack 50% of the time. Fails if
    // both the user and the target are the same gender, if either is genderless, or if the target
    // is already infatuated. The effect ends when either the user or the target is no longer
    // active.
    return error.SkipZigTest;
}

// Move.SleepTalk
test "SleepTalk effect" {
    // One of the user's known moves, besides this move, is selected for use at random. Fails if the
    // user is not asleep. The selected move does not have PP deducted from it, and can currently
    // have 0 PP. This move cannot select Bide, Sleep Talk, or any two-turn move.
    return error.SkipZigTest;
}

// Move.HealBell
test "HealBell effect" {
    // Every Pokemon in the user's party is cured of its non-volatile status condition.
    return error.SkipZigTest;
}

// Move.{Return,Frustration}
test "Return/Frustration effect" {
    // Power is equal to the greater of ([255 -] user's Happiness * 2/5), rounded down, or 1.
    return error.SkipZigTest;
}

// Move.Present
test "Present effect" {
    // If this move is successful, it deals damage or heals the target. 102/256 chance for 40 power,
    // 76/256 chance for 80 power, 26/256 chance for 120 power, or 52/256 chance to heal the target
    // by 1/4 of its maximum HP, rounded down. If this move deals damage, it uses an abnormal
    // version of the damage formula by substituting certain values. The user's Attack stat is
    // replaced with 10 times the effectiveness of this move against the target, the target's
    // Defense stat is replaced with the index number of the user's secondary type, and the user's
    // level is replaced with the index number of the target's secondary type. If a Pokemon does not
    // have a secondary type, its primary type is used. The index numbers for each type are Normal:
    // 0, Fighting: 1, Flying: 2, Poison: 3, Ground: 4, Rock: 5, Bug: 7, Ghost: 8, Steel: 9, Fire:
    // 20, Water: 21, Grass: 22, Electric: 23, Psychic: 24, Ice: 25, Dragon: 26, Dark: 27. If at any
    // point a division by 0 would happen in the damage formula, it divides by 1 instead.
    return error.SkipZigTest;
}

// Move.Safeguard
test "Safeguard effect" {
    // For 5 turns, the user and its party members cannot have non-volatile status conditions or
    // confusion inflicted on them by other Pokemon. During the effect, Outrage, Thrash, and Petal
    // Dance do not confuse the user. Fails if the effect is already active on the user's side.
    return error.SkipZigTest;
}

// Move.PainSplit
test "PainSplit effect" {
    // The user and the target's HP become the average of their current HP, rounded down, but not
    // more than the maximum HP of either one.
    return error.SkipZigTest;
}

// Move.Magnitude
test "Magnitude effect" {
    // The power of this move varies. 5% chances for 10 and 150 power, 10% chances for 30 and 110
    // power, 20% chances for 50 and 90 power, and 30% chance for 70 power. Power doubles if the
    // target is using Dig.
    return error.SkipZigTest;
}

// Move.BatonPass
test "BatonPass effect" {
    // The user is replaced with another Pokemon in its party. The selected Pokemon has the user's
    // stat stage changes, confusion, and certain move effects transferred to it.
    return error.SkipZigTest;
}

// Move.Encore
test "Encore effect" {
    // For 3 to 6 turns, the target is forced to repeat its last move used. If the affected move
    // runs out of PP, the effect ends. Fails if the target is already under this effect, if it has
    // not made a move, if the move has 0 PP, or if the move is Encore, Metronome, Mimic, Mirror
    // Move, Sketch, Sleep Talk, Struggle, or Transform.
    return error.SkipZigTest;
}

// Move.Pursuit
test "Pursuit effect" {
    // If the target switches out this turn, this move hits it before it leaves the field with
    // doubled power and the user's turn is over.
    return error.SkipZigTest;
}

// Move.HiddenPower
test "HiddenPower effect" {
    // This move's type and power depend on the user's individual values (IVs). Power varies between
    // 30 and 70, and type can be any but Normal.
    return error.SkipZigTest;
}

// Move.Sandstorm
test "Sandstorm effect" {
    // For 5 turns, the weather becomes Sandstorm. At the end of each turn except the last, all
    // active Pokemon lose 1/8 of their maximum HP, rounded down, unless they are a Ground, Rock, or
    // Steel type. Fails if the current weather is Sandstorm.
    return error.SkipZigTest;
}

// Move.SunnyDay
test "SunnyDay effect" {
    // For 5 turns, the weather becomes Sunny Day, even if the current weather is Sunny Day. The
    // damage of Fire-type attacks is multiplied by 1.5 and the damage of Water-type attacks is
    // multiplied by 0.5 during the effect.
    return error.SkipZigTest;
}

// Move.RainDance
test "RainDance effect" {
    // For 5 turns, the weather becomes Rain Dance, even if the current weather is Rain Dance. The
    // damage of Water-type attacks is multiplied by 1.5 and the damage of Fire-type attacks is
    // multiplied by 0.5 during the effect.
    return error.SkipZigTest;
}

// Move.Thunder
test "Thunder effect" {
    // Has a 30% chance to paralyze the target. This move can hit a target using Fly. If the weather
    // is Rain Dance, this move does not check accuracy. If the weather is Sunny Day, this move's
    // accuracy is 50%.
    return error.SkipZigTest;
}

// Move.PsychUp
test "PsychUp effect" {
    // The user copies all of the target's current stat stage changes. Fails if the target's stat
    // stages are 0.
    return error.SkipZigTest;
}

// Move.FutureSight
test "FutureSight effect" {
    // Deals typeless damage that cannot be a critical hit two turns after this move is used. Damage
    // is calculated against the target on use, and at the end of the final turn that damage is
    // dealt to the Pokemon at the position the original target had at the time. Fails if this move
    // is already in effect for the target's position.
    return error.SkipZigTest;
}

// Move.BeatUp
test "BeatUp effect" {
    // Deals typeless damage. Hits one time for each unfainted Pokemon without a non-volatile status
    // condition in the user's party. For each hit, the damage formula uses the participating
    // Pokemon's level, its base Attack as the Attack stat, the target's base Defense as the Defense
    // stat, and ignores stat stages and other effects that modify Attack or Defense. Fails if no
    // party members can participate.
    return error.SkipZigTest;
}

// Pokémon Showdown Bugs

// TODO: https://www.smogon.com/forums/threads/gen-2-ps-development-post-bugs-here.3524926/

// Glitches

test "Spikes 0 HP glitch" {
    // Perish Song and Spikes can leave a Pokémon with 0 HP and not faint
    // https://pkmn.cc/bulba-glitch-2#Sandstorm_Spikes_glitch
    // https://www.youtube.com/watch?v=1IiPWw5fMf8&t=85
    // https://www.youtube.com/watch?v=u7GHUpISEP8
    return error.SkipZigTest;
}

test "Thick Club wrap around glitch" {
    // Thick Club and Light Ball can make (Special) Attack wrap around above 1024
    // https://www.youtube.com/watch?v=rGqu3d3pdok&t=450
    return error.SkipZigTest;
}

test "Metal Powder increased damage glitch" {
    // Metal Powder can increase damage taken with boosted (Special) Defense
    // https://www.youtube.com/watch?v=rGqu3d3pdok&t=450
    return error.SkipZigTest;
}

test "Reflect / Light Screen wrap around glitch" {
    // Reflect and Light Screen can make (Special) Defense wrap around above 1024
    return error.SkipZigTest;
}

test "Secondary chance 1/256 glitch" {
    // Moves with a 100% secondary effect chance will not trigger it in 1/256 uses
    // https://www.youtube.com/watch?v=mHkyO5T5wZU&t=206
    return error.SkipZigTest;
}
test "Belly Drum failure glitch" {
    // Belly Drum sharply boosts Attack even with under 50% HP
    // https://pkmn.cc/bulba-glitch-2#Belly_Drum_effect
    // https://www.youtube.com/watch?v=zuCLMikWo4Y
    return error.SkipZigTest;
}

test "Berserk Gene confusion duration glitch" {
    // Berserk Gene's confusion lasts for 256 turns or the previous Pokémon's confusion count
    // https://youtube.com/watch?v=Pru3mohq20A
    return error.SkipZigTest;
}

test "Confusion self-hit damage glitch" {
    // "Confusion damage is affected by type-boosting items and Explosion/Self-Destruct doubling
    // https://twitter.com/crystal_rby/status/874626362287562752
    return error.SkipZigTest;
}

test "Defense lowering after breaking Substitute glitch" {
    // Moves that lower Defense can do so after breaking a Substitute
    // https://www.youtube.com/watch?v=OGwKPRJLaaI
    return error.SkipZigTest;
}
test "PP Up + Disable freeze" {
    // A Disabled but PP Up–enhanced move may not trigger Struggle
    // https://www.youtube.com/watch?v=1v9x4SgMggs
    return error.SkipZigTest;
}

test "Lock-On / Mind Reader oversight" {
    // Lock-On and Mind Reader don't always bypass Fly and Dig"
    // https://pkmn.cc/bulba-glitch-2#Lock-On.2FMind_Reader_oversight
    return error.SkipZigTest;
}

test "Beat Up desync" {
    // Beat Up can desynchronize link battles
    // https://www.youtube.com/watch?v=202-iAsrIa8
    return error.SkipZigTest;
}

test "Beat Up Kings Rock failure glitch" {
    // Beat Up may trigger Kings Rock even if it failed (due to having no party)
    return error.SkipZigTest;
}

test "Return/Frustration 0 damage glitch" {
    // Return and Frustration deal no damage when the user's happiness is low or high, respectively
    // https://www.youtube.com/watch?v=r_2EwJnNKwU
    // https://www.youtube.com/watch?v=JafUJzoIa_s
    return error.SkipZigTest;
}

test "Stat increase post KO glitch" {
    // Moves that do damage and increase your stats do not increase stats after a KO
    return error.SkipZigTest;
}

// Miscellaneous

test "MAX_LOGS" {
    if (showdown or !log) return error.SkipZigTest;
    return error.SkipZigTest;
}

fn Test(comptime rolls: anytype) type {
    return struct {
        const Self = @This();

        battle: struct {
            expected: data.Battle(rng.FixedRNG(2, rolls.len)),
            actual: data.Battle(rng.FixedRNG(2, rolls.len)),
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
            var expected_buf: [24]u8 = undefined;
            var actual_buf: [24]u8 = undefined;

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
            const result = self.battle.actual.update(c1, c2, &self.options);

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

comptime {
    _ = @import("calc.zig");
    _ = @import("chance.zig");
    _ = @import("data.zig");
    _ = @import("helpers.zig");
    _ = @import("mechanics.zig");
}
