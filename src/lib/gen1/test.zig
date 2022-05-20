const std = @import("std");
const build_options = @import("build_options");

const common = @import("../common/data.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");
const helpers = @import("helpers.zig");

const ArrayList = std.ArrayList;

const assert = std.debug.assert;
const debug = std.debug.print;

const stream = std.io.fixedBufferStream;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const showdown = build_options.showdown;
const trace = build_options.trace;

const Player = common.Player;
const Result = common.Result;
const Choice = common.Choice;

const ArgType = protocol.ArgType;
const FixedLog = protocol.FixedLog;
const Log = protocol.Log;
const expectLog = protocol.expectLog;

const PRNG = rng.PRNG(6);

const Move = data.Move;

const Battle = helpers.Battle;
const Pokemon = helpers.Pokemon;
const move = helpers.move;
const swtch = helpers.swtch;

const OPTIONS_SIZE = data.OPTIONS_SIZE;

const P1_FIRST = 0;
const P2_FIRST = 255;
const NOP = 0;
const HIT = 0;
const MISS = 255;
const CRIT = 0;
const NO_CRIT = 255;
const MIN_DMG = if (showdown) 0 else 217;
const MAX_DMG = 255;
const PROC = 0;
const NO_PROC = 255;

const P1 = Player.P1;
const P2 = Player.P2;

fn expectOrder(p1: anytype, o1: []const u8, p2: anytype, o2: []const u8) !void {
    try expectEqualSlices(u8, o1, &p1.order);
    try expectEqualSlices(u8, o2, &p2.order);
}

test "switching (order)" {
    var battle = Battle.random(&PRNG.init(0x12345678), false);
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
    try expectEqual(Result.Default, try battle.update(swtch(5), swtch(5), null));
    try expectOrder(p1, &.{ 3, 1, 6, 4, 2, 5 }, p2, &.{ 2, 1, 3, 5, 4, 6 });
}

test "choices" {
    var random = PRNG.init(0x27182818);
    var battle = Battle.random(&random, false);
    var options: [OPTIONS_SIZE]Choice = undefined;
    const n = battle.choices(.P1, .Move, &options);
    try expectEqualSlices(Choice, &[_]Choice{
        swtch(2), swtch(3), swtch(4), swtch(5), swtch(6),
        move(1),  move(2),  move(3),  move(4),
    }, options[0..n]);
}

// Moves

// Move.{KarateChop,RazorLeaf,Crabhammer,Slash}
test "HighCritical" {
    // Has a higher chance for a critical hit.
    return error.SkipZigTest;
}

// Move.{DoubleSlap,CometPunch,FuryAttack,PinMissile,SpikeCannon,Barrage,FurySwipes}
test "MultiHit" {
    // Hits two to five times. Has a 3/8 chance to hit two or three times, and a 1/8 chance to hit
    // four or five times. Damage is calculated once for the first hit and used for every hit. If
    // one of the hits breaks the target's substitute, the move ends.
    return error.SkipZigTest;
}

// Move.{DoubleKick,Bonemerang}
test "DoubleHit" {
    // Hits twice. Damage is calculated once for the first hit and used for both hits. If the first
    // hit breaks the target's substitute, the move ends.
    return error.SkipZigTest;
}

// Move.PoisonSting
// Move.{Smog,Sludge}
test "PoisonChance" {
    // Has a X% chance to poison the target.
    return error.SkipZigTest;
}

// Move.{FirePunch,Ember,Flamethrower}: BurnChance1
// Move.FireBlast: BurnChance2
test "BurnChance" {
    // Has a X% chance to burn the target.
    return error.SkipZigTest;
}

// Move.{IcePunch,IceBeam,Blizzard}: FreezeChance
test "FreezeChance" {
    // Has a 10% chance to freeze the target.
    return error.SkipZigTest;
}

// Move.{ThunderPunch,ThunderShock,Thunderbolt,Thunder}: ParalyzeChance1
// Move.{BodySlam,Lick}: ParalyzeChance2
test "ParalyzeChance" {
    // Has a X% chance to paralyze the target.
    return error.SkipZigTest;
}

// Move.{Bite,BoneClub,HyperFang}: FlinchChance1
// Move.{Stomp,RollingKick,Headbutt,LowKick}: FlinchChance2
test "FlinchChance" {
    // Has a X% chance to flinch the target.
    return error.SkipZigTest;
}

// Move.{Psybeam,Confusion}: ConfusionChance
test "ConfusionChance" {
    // Has a 10% chance to confuse the target.
    return error.SkipZigTest;
}

// Move.Growl: AttackDown1
// Move.{TailWhip,Leer}: DefenseDown1
// Move.StringShot: SpeedDown1
// Move.{SandAttack,Smokescreen,Kinesis,Flash}: AccuracyDown1
// Move.Screech: DefenseDown2
test "StatDown" {
    // Lowers the target's X by Y stage(s).
    return error.SkipZigTest;
}

// Move.AuroraBeam: AttackDownChance
// Move.Acid: DefenseDownChance
// Move.{BubbleBeam,Constrict,Bubble}: SpeedDownChance
// Move.Psychic: SpecialDownChance
test "StatDownChance" {
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
test "StatUp" {
    // Raises the target's X by Y stage(s).
    return error.SkipZigTest;
}

// Move.{Guillotine,HornDrill,Fissure}
test "OHKO" {
    // Deals 65535 damage to the target. Fails if the target's Speed is greater than the user's.
    return error.SkipZigTest;
}

// Move.{RazorWind,SolarBeam,SkullBash,SkyAttack}
test "Charge" {
    // This attack charges on the first turn and executes on the second.
    return error.SkipZigTest;
}

// Move.{Whirlwind,Roar,Teleport}
test "SwitchAndTeleport" {
    // No competitive use.
    var t = Test(if (showdown) .{ NOP, HIT, NOP, MISS } else .{}).init(
        &.{.{ .species = .Abra, .moves = &.{.Teleport} }},
        &.{.{ .species = .Pidgey, .moves = &.{.Whirlwind} }},
    );
    defer t.deinit();

    // |move|p1a: Abra|Teleport|p1a: Abra
    // |move|p2a: Pidgey|Whirlwind|p2a: Abra
    // |turn|2
    // |move|p1a: Abra|Teleport|p1a: Abra
    // |move|p2a: Pidgey|Whirlwind|p2a: Abra|[miss]
    // |-miss|p2a: Pidgey
    // |turn|3
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
    try expectEqual(t.p1().get(1).hp, t.battle.p1().get(1).hp);
    try expectEqual(t.p2().get(1).hp, t.battle.p2().get(1).hp);
    try t.verify();
}

// Move.Splash
test "Splash" {
    // No competitive use.
    var t = Test(.{}).init(
        &.{.{ .species = .Gyarados, .moves = &.{.Splash} }},
        &.{.{ .species = .Magikarp, .moves = &.{.Splash} }},
    );
    defer t.deinit();

    // |move|p1a: Gyarados|Splash|p1a: Gyarados
    // |-activate||move: Splash
    // |move|p2a: Magikarp|Splash|p2a: Magikarp
    // |-activate||move: Splash
    // |turn|2
    try t.log.expected.move(P1.ident(1), Move.Splash, P1.ident(1), null);
    try t.log.expected.activate(P1.ident(1), .Splash);
    try t.log.expected.move(P2.ident(1), Move.Splash, P2.ident(1), null);
    try t.log.expected.activate(P2.ident(1), .Splash);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try expectEqual(t.p1().get(1).hp, t.battle.p1().get(1).hp);
    try expectEqual(t.p2().get(1).hp, t.battle.p2().get(1).hp);
    try t.verify();
}

// Move.{Fly,Dig}
test "Fly / Dig" {
    // This attack charges on the first turn and executes on the second. On the first turn, the user
    // avoids all attacks other than Bide, Swift, and Transform. If the user is fully paralyzed on
    // the second turn, it continues avoiding attacks until it switches out or successfully executes
    // the second turn of this move or {Fly,Dig}.
    return error.SkipZigTest;
}

// Move.{Bind,Wrap,FireSpin,Clamp}
test "Trapping" {
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
test "JumpKick" {
    // If this attack misses the target, the user takes 1 HP of crash damage. If the user has a
    // substitute, the crash damage is dealt to the target's substitute if it has one, otherwise no
    // crash damage is dealt.
    return error.SkipZigTest;
}

// Move.{TakeDown,DoubleEdge,Submission}
test "Recoil" {
    // If the target lost HP, the user takes recoil damage equal to 1/4 the HP lost by the target,
    // rounded down, but not less than 1 HP. If this move breaks the target's substitute, the user
    // does not take any recoil damage.
    return error.SkipZigTest;
}

// Move.Struggle
test "Recoil (Struggle)" {
    // Deals Normal-type damage. If this move was successful, the user takes damage equal to 1/2 the
    // HP lost by the target, rounded down, but not less than 1 HP. This move is automatically used
    // if none of the user's known moves can be selected.
    return error.SkipZigTest;
}

// Move.{Thrash,PetalDance}
test "Thrashing" {
    // Whether or not this move is successful, the user spends three or four turns locked into this
    // move and becomes confused immediately after its move on the last turn of the effect, even if
    // it is already confused. If the user is prevented from moving, the effect ends without causing
    // confusion. During the effect, this move's accuracy is overwritten every turn with the current
    // calculated accuracy including stat stage changes, but not to less than 1/256 or more than
    // 255/256.
    return error.SkipZigTest;
}

// Move.Twineedle
test "Twineedle" {
    // Hits twice, with the second hit having a 20% chance to poison the target. If the first hit
    // breaks the target's substitute, the move ends.
    return error.SkipZigTest;
}

// Move.{SonicBoom,DragonRage}
test "SpecialDamage (fixed)" {
    // Deals X HP of damage to the target. This move ignores type immunity.
    var t = Test(if (showdown) .{ NOP, NOP, HIT, HIT, NOP } else .{ HIT, HIT, HIT }).init(
        &.{.{ .species = .Voltorb, .moves = &.{.SonicBoom} }},
        &.{
            .{ .species = .Dratini, .moves = &.{.DragonRage} },
            .{ .species = .Gastly, .moves = &.{.NightShade} },
        },
    );
    defer t.deinit();

    t.p1().get(1).hp -= 40;
    t.p2().get(1).hp -= 20;

    // |move|p1a: Voltorb|Sonic Boom|p2a: Dratini
    // |-damage|p2a: Dratini|265/285
    // |move|p2a: Dratini|Dragon Rage|p1a: Voltorb
    // |-damage|p1a: Voltorb|243/283
    // |turn|2
    try t.log.expected.move(P1.ident(1), Move.SonicBoom, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.p2().get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.DragonRage, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.p1().get(1), .None);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try expectEqual(t.p1().get(1).hp, t.battle.p1().get(1).hp);
    try expectEqual(t.p2().get(1).hp, t.battle.p2().get(1).hp);
    try expectEqual(t.p2().get(2).hp, t.battle.p2().get(2).hp);

    // |switch|p2a: Gastly|Gastly|263/263
    // |move|p1a: Voltorb|Sonic Boom|p2a: Gastly
    try t.log.expected.switched(P2.ident(2), t.p2().get(2));
    try t.log.expected.move(P1.ident(1), Move.SonicBoom, P2.ident(2), null);
    if (showdown) {
        // |-immune|p2a: Gastly
        try t.log.expected.immune(P2.ident(2), .None);
    } else {
        // |-damage|p2a: Gastly|243/263
        t.p2().get(2).hp -= 20;
        try t.log.expected.damage(P2.ident(2), t.p2().get(2), .None);
    }
    // |turn|3
    try t.log.expected.turn(3);

    try expectEqual(Result.Default, try t.update(move(1), swtch(2)));
    try expectEqual(t.p1().get(1).hp, t.battle.p1().get(1).hp);
    try expectEqual(t.p2().get(2).hp, t.battle.p2().get(1).hp);
    try expectEqual(t.p2().get(1).hp, t.battle.p2().get(2).hp);
    try t.verify();
}

// Move.{SeismicToss,NightShade}
test "SpecialDamage (level)" {
    // Deals damage to the target equal to the user's level. This move ignores type immunity.
    var t = Test((if (showdown) .{ NOP, NOP, HIT, HIT } else .{ HIT, HIT })).init(
        &.{.{ .species = .Gastly, .level = 22, .moves = &.{.NightShade} }},
        &.{.{ .species = .Clefairy, .level = 16, .moves = &.{.SeismicToss} }},
    );
    defer t.deinit();

    t.p1().get(1).hp -= 16;
    t.p2().get(1).hp -= 22;

    // |move|p1a: Gastly|Night Shade|p2a: Clefairy
    // |-damage|p2a: Clefairy|41/63
    // |move|p2a: Clefairy|Seismic Toss|p1a: Gastly
    // |-damage|p1a: Gastly|49/65
    // |turn|2
    try t.log.expected.move(P1.ident(1), Move.NightShade, P2.ident(1), null);
    try t.log.expected.damage(P2.ident(1), t.p2().get(1), .None);
    try t.log.expected.move(P2.ident(1), Move.SeismicToss, P1.ident(1), null);
    try t.log.expected.damage(P1.ident(1), t.p1().get(1), .None);
    try t.log.expected.turn(2);

    try expectEqual(Result.Default, try t.update(move(1), move(1)));
    try expectEqual(t.p1().get(1).hp, t.battle.p1().get(1).hp);
    try expectEqual(t.p2().get(1).hp, t.battle.p2().get(1).hp);
    try t.verify();
}

// Move.Psywave
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Psywave_glitches
test "SpecialDamage (Psywave)" {
    // Deals damage to the target equal to a random number from 1 to (user's level * 1.5 - 1),
    // rounded down, but not less than 1 HP.
    return error.SkipZigTest;
}

// Move.SuperFang
test "SuperFang" {
    // Deals damage to the target equal to half of its current HP, rounded down, but not less than 1
    // HP. This move ignores type immunity.
    return error.SkipZigTest;
}

// Move.Disable
test "Disable" {
    // For 0 to 7 turns, one of the target's known moves that has at least 1 PP remaining becomes
    // disabled, at random. Fails if one of the target's moves is already disabled, or if none of
    // the target's moves have PP remaining. If any Pokemon uses Haze, this effect ends. Whether or
    // not this move was successful, it counts as a hit for the purposes of the opponent's use of
    // Rage.
    return error.SkipZigTest;
}

// Move.Mist
test "Mist" {
    // While the user remains active, it is protected from having its stat stages lowered by other
    // Pokemon, unless caused by the secondary effect of a move. Fails if the user already has the
    // effect. If any Pokemon uses Haze, this effect ends.
    return error.SkipZigTest;
}

// Move.HyperBeam
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Hyper_Beam_.2B_Freeze_permanent_helplessness FIXME haze
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Hyper_Beam_.2B_Sleep_move_glitch
test "HyperBeam" {
    // If this move is successful, the user must recharge on the following turn and cannot select a
    // move, unless the target or its substitute was knocked out by this move.
    return error.SkipZigTest;
}

// Move.Counter
// TODO: https://glitchcity.wiki/Counter_glitches_(Generation_I)
// TODO: https://www.youtube.com/watch?v=ftTalHMjPRY
test "Counter" {
    // Deals damage to the opposing Pokemon equal to twice the damage dealt by the last move used in
    // the battle. This move ignores type immunity. Fails if the user moves first, or if the
    // opposing side's last move was Counter, had 0 power, or was not Normal or Fighting type. Fails
    // if the last move used by either side did 0 damage and was not Confuse Ray, Conversion, Focus
    // Energy, Glare, Haze, Leech Seed, Light Screen, Mimic, Mist, Poison Gas, Poison Powder,
    // Recover, Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Teleport,
    // Thunder Wave, Toxic, or Transform.
    return error.SkipZigTest;
}

// Move.{Absorb,MegaDrain,LeechLife}
test "Drain" {
    // The user recovers 1/2 the HP lost by the target, rounded down.
    return error.SkipZigTest;
}

// Move.DreamEater
test "DreamEater" {
    // The target is unaffected by this move unless it is asleep. The user recovers 1/2 the HP lost
    // by the target, rounded down, but not less than 1 HP. If this move breaks the target's
    // substitute, the user does not recover any HP.
    return error.SkipZigTest;
}

// Move.LeechSeed
test "LeechSeed" {
    // At the end of each of the target's turns, The Pokemon at the user's position steals 1/16 of
    // the target's maximum HP, rounded down and multiplied by the target's current Toxic counter if
    // it has one, even if the target currently has less than that amount of HP remaining. If the
    // target switches out or any Pokemon uses Haze, this effect ends. Grass-type Pokemon are immune
    // to this move.
    return error.SkipZigTest;
}

// Move.{Sing,SleepPowder,Hypnosis,LovelyKiss,Spore}
test "Sleep" {
    // Causes the target to fall asleep.
    return error.SkipZigTest;
}

// Move.{Supersonic,ConfuseRay}
test "Confusion" {
    // Causes the target to become confused.
    return error.SkipZigTest;
}

// Move.{PoisonPowder,PoisonGas}
test "Poison" {
    // Poisons the target.
    return error.SkipZigTest;
}

// Move.{ThunderWave,StunSpore,Glare}
test "Paralyze" {
    // Paralyzes the target.
    return error.SkipZigTest;
}

// Move.Toxic
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Toxic_counter_glitches
test "Poison (Toxic)" {
    // Badly poisons the target.
    return error.SkipZigTest;
}

// Move.Rage
test "Rage" {
    // Once this move is successfully used, the user automatically uses this move every turn and can
    // no longer switch out. During the effect, the user's Attack is raised by 1 stage every time it
    // is hit by the opposing Pokemon, and this move's accuracy is overwritten every turn with the
    // current calculated accuracy including stat stage changes, but not to less than 1/256 or more
    // than 255/256.
    return error.SkipZigTest;
}

// Move.Mimic
test "Mimic" {
    // While the user remains active, this move is replaced by a random move known by the target,
    // even if the user already knows that move. The copied move keeps the remaining PP for this
    // move, regardless of the copied move's maximum PP. Whenever one PP is used for a copied move,
    // one PP is used for this move.
    return error.SkipZigTest;
}

// Move.{Recover,SoftBoiled}
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#HP_recovery_move_failure
test "Heal" {
    // The user restores 1/2 of its maximum HP, rounded down. Fails if (user's maximum HP - user's
    // current HP + 1) is divisible by 256.
    return error.SkipZigTest;
}

// Move.Rest
test "Heal (Rest)" {
    // The user falls asleep for the next two turns and restores all of its HP, curing itself of any
    // non-volatile status condition in the process. This does not remove the user's stat penalty
    // for burn or paralysis. Fails if the user has full HP.
    return error.SkipZigTest;
}

// Move.LightScreen
test "LightScreen" {
    // While the user remains active, its Special is doubled when taking damage. Critical hits
    // ignore this effect. If any Pokemon uses Haze, this effect ends.
    return error.SkipZigTest;
}

// Move.Reflect
test "Reflect" {
    // While the user remains active, its Defense is doubled when taking damage. Critical hits
    // ignore this protection. This effect can be removed by Haze.
    return error.SkipZigTest;
}

// Move.Haze
// TODO: https://www.youtube.com/watch?v=gXQlct-DvVg
test "Haze" {
    // Resets the stat stages of both Pokemon to 0 and removes stat reductions due to burn and
    // paralysis. Resets Toxic counters to 0 and removes the effect of confusion, Disable, Focus
    // Energy, Leech Seed, Light Screen, Mist, and Reflect from both Pokemon. Removes the opponent's
    // non-volatile status condition.
    return error.SkipZigTest;
}

// Move.FocusEnergy
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Critical_hit_ratio_error
test "FocusEnergy" {
    // While the user remains active, its chance for a critical hit is quartered. Fails if the user
    // already has the effect. If any Pokemon uses Haze, this effect ends.
    return error.SkipZigTest;
}

// Move.Bide
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Bide_errors
// TODO: https://glitchcity.wiki/Bide_fainted_Pokémon_damage_accumulation_glitch
// TODO: https://www.youtube.com/watch?v=IVxHGyNDW4g
test "Bide" {
    // The user spends two or three turns locked into this move and then, on the second or third
    // turn after using this move, the user attacks the opponent, inflicting double the damage in HP
    // it lost during those turns. This move ignores type immunity and cannot be avoided even if the
    // target is using Dig or Fly. The user can choose to switch out during the effect. If the user
    // switches out or is prevented from moving during this move's use, the effect ends. During the
    // effect, if the opposing Pokemon switches out or uses Confuse Ray, Conversion, Focus Energy,
    // Glare, Haze, Leech Seed, Light Screen, Mimic, Mist, Poison Gas, Poison Powder, Recover,
    // Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Teleport, Thunder
    // Wave, Toxic, or Transform, the previous damage dealt to the user will be added to the total.
    return error.SkipZigTest;
}

// Move.Metronome
test "Metronome" {
    // A random move is selected for use, other than Metronome or Struggle.
    return error.SkipZigTest;
}

// Move.MirrorMove
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Mirror_Move_glitch
test "MirrorMove" {
    // The user uses the last move used by the target. Fails if the target has not made a move, or
    // if the last move used was Mirror Move.
    return error.SkipZigTest;
}

// Move.{SelfDestruct,Explosion}
test "Explode" {
    // The user faints after using this move, unless the target's substitute was broken by the
    // damage. The target's Defense is halved during damage calculation.
    return error.SkipZigTest;
}

// Move.Swift
test "Swift" {
    // This move does not check accuracy and hits even if the target is using Dig or Fly.
    return error.SkipZigTest;
}

// Move.Transform
// TODO: https://pkmn.cc/bulba/Transform_glitches
test "Transform" {
    // The user transforms into the target. The target's current stats, stat stages, types, moves,
    // DVs, species, and sprite are copied. The user's level and HP remain the same and each copied
    // move receives only 5 PP. This move can hit a target using Dig or Fly.
    return error.SkipZigTest;
}

// Move.Conversion
test "Conversion" {
    // Causes the user's types to become the same as the current types of the target.
    return error.SkipZigTest;
}

// Move.Substitute
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Substitute_HP_drain_bug
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Substitute_.2B_Confusion_glitch
test "Substitute" {
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

// Glitches

test "0 damage glitch" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#0_damage_glitch
    return error.SkipZigTest;
}

test "1/256 miss glitch" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#1.2F256_miss_glitch
    return error.SkipZigTest;
}

test "Defrost move forcing" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Defrost_move_forcing
    return error.SkipZigTest;
}

test "Division by 0" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Division_by_0
    return error.SkipZigTest;
}

test "Invulnerability glitch" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Invulnerability_glitch
    return error.SkipZigTest;
}

test "Stat modification errors" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Stat_modification_errors
    return error.SkipZigTest;
}

test "Struggle bypassing" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Struggle_bypassing
    return error.SkipZigTest;
}

test "Trapping sleep glitch" {
    // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Trapping_sleep_glitch
    return error.SkipZigTest;
}

test "Partial trapping move Mirror Move glitch" {
    // https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch
    return error.SkipZigTest;
}

test "Rage and Thrash / Petal Dance accuracy bug" {
    // https://www.youtube.com/watch?v=NC5gbJeExbs
}

test "Stat down modifier overflow glitch" {
    // https://www.youtube.com/watch?v=y2AOm7r39Jg
}

test "Endless Battle Clause (initial)" {
    if (!showdown) return;

    var t = Test(.{}).init(
        &.{.{ .species = .Gengar, .moves = &.{.Tackle} }},
        &.{.{ .species = .Gengar, .moves = &.{.Tackle} }},
    );
    defer t.deinit();

    t.battle.expected.sides[0].pokemon[0].moves[0].pp = 0;
    t.battle.expected.sides[1].pokemon[0].moves[0].pp = 0;

    t.battle.actual.sides[0].pokemon[0].moves[0].pp = 0;
    t.battle.actual.sides[1].pokemon[0].moves[0].pp = 0;

    try t.log.expected.switched(P1.ident(1), t.p1().get(1));
    try t.log.expected.switched(P2.ident(1), t.p2().get(1));
    try t.log.expected.tie();

    try expectEqual(Result.Tie, try t.battle.expected.update(.{}, .{}, t.log.actual));
    try t.verify();
}

fn Test(comptime rolls: anytype) type {
    return struct {
        const Self = @This();

        battle: struct {
            const This = @This();

            expected: data.Battle(rng.FixedRNG(1, rolls.len)),
            actual: data.Battle(rng.FixedRNG(1, rolls.len)),

            pub fn p1(this: *This) *data.Side {
                return this.actual.side(.P1);
            }

            pub fn p2(this: *This) *data.Side {
                return this.actual.side(.P2);
            }
        },
        buf: struct {
            expected: ArrayList(u8),
            actual: ArrayList(u8),
        },
        log: struct {
            expected: Log(ArrayList(u8).Writer),
            actual: Log(ArrayList(u8).Writer),
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
            return t;
        }

        pub fn deinit(self: *Self) void {
            self.buf.expected.deinit();
            self.buf.actual.deinit();
            std.testing.allocator.destroy(self);
        }

        pub fn p1(self: *Self) *data.Side {
            return self.battle.expected.side(.P1);
        }

        pub fn p2(self: *Self) *data.Side {
            return self.battle.expected.side(.P2);
        }

        pub fn update(self: *Self, c1: Choice, c2: Choice) !Result {
            if (self.battle.actual.turn == 0) {
                var expected_buf: [22]u8 = undefined;
                var actual_buf: [22]u8 = undefined;

                var expected = FixedLog{ .writer = stream(&expected_buf).writer() };
                var actual = FixedLog{ .writer = stream(&actual_buf).writer() };

                try expected.switched(P1.ident(1), self.battle.p1().get(1));
                try expected.switched(P2.ident(1), self.battle.p2().get(1));
                try expected.turn(1);

                try expectEqual(Result.Default, try self.battle.actual.update(.{}, .{}, actual));
                try expectLog(&expected_buf, &actual_buf);
            }

            return self.battle.actual.update(c1, c2, self.log.actual);
        }

        pub fn verify(t: *Self) !void {
            try expect(t.battle.actual.rng.exhausted());
            if (trace) try expectLog(t.buf.expected.items, t.buf.actual.items);
        }
    };
}

// BUG: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Dual-type_damage_misinformation
// BUG: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Poison.2FBurn_animation_with_0_HP

comptime {
    _ = @import("data.zig");
    _ = @import("mechanics.zig");
}
