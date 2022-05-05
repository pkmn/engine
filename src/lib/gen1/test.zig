const std = @import("std");
const build_options = @import("build_options");

const common = @import("../common/data.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");
const helpers = @import("helpers.zig");

const assert = std.debug.assert;

const stream = std.io.fixedBufferStream;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const showdown = build_options.showdown;

const Player = common.Player;
const Result = common.Result;
const Choice = common.Choice;

const ArgType = protocol.ArgType;
const TestLogs = protocol.TestLogs;
const FixedLog = protocol.FixedLog;

const PRNG = rng.PRNG(6);

const Move = data.Move;

const Battle = helpers.Battle;
const move = helpers.move;
const swtch = helpers.swtch;

const MAX_OPTIONS_SIZE = data.MAX_OPTIONS_SIZE;

const P1_FIRST = 0;
const P2_FIRST = 255;
const NOP = 0;
const HIT = 0;
const MISS = 255;
const CRIT = 0;
const NO_CRIT = 255;
const MIN_DMG = 217;
const MAX_DMG = 255;

const P1 = Player.P1;
const P2 = Player.P2;

test "TODO Battle1" {
    const p1 = .{ .species = .Gengar, .moves = &.{ .Absorb, .Pound, .DreamEater, .Psychic } };
    const p2 = .{ .species = .Mew, .moves = &.{ .HydroPump, .Surf, .Bubble, .WaterGun } };
    const rolls = if (showdown)
        (.{ NOP, NOP, HIT, NO_CRIT, HIT, NO_CRIT, MAX_DMG })
    else
        (.{ NO_CRIT, HIT, NO_CRIT, MAX_DMG, HIT });
    var battle = Battle.fixed(rolls, &.{p1}, &.{p2});
    try expectEqual(Result.Default, try update(&battle, move(4), move(2), null));
    try expect(battle.rng.exhausted());
}

test "TODO Battle2" {
    const p1 = .{ .species = .Gengar, .moves = &.{ .Absorb, .Pound, .DreamEater, .Psychic } };
    const p2 = .{ .species = .Mew, .moves = &.{ .HydroPump, .Surf, .Bubble, .WaterGun } };
    const rolls = if (showdown)
        (.{ NOP, NOP, HIT, NO_CRIT, HIT, NO_CRIT, MAX_DMG })
    else
        (.{ NO_CRIT, HIT, NO_CRIT, MAX_DMG, HIT });
    var battle = Battle.fixed(rolls, &.{p1}, &.{p2});

    // var logs = TestLogs(100){};
    // var expected = FixedLog{ .writer = stream(&logs.expected).writer() };
    // try expected.move(P1.ident(1), Move.Psychic, P2.ident(1), .None);

    const actual = null; // FixedLog{ .writer = stream(&logs.actual).writer() };
    try expectEqual(Result.Default, try update(&battle, move(4), move(2), actual));
    // try logs.expectMatches();
    try expect(battle.rng.exhausted());
}

fn expectOrder(p1: anytype, o1: []const u8, p2: anytype, o2: []const u8) !void {
    try expectEqualSlices(u8, o1, &p1.order);
    try expectEqualSlices(u8, o2, &p2.order);
}

test "switching" {
    var battle = Battle.random(&PRNG.init(0x31415926), false);
    const p1 = battle.side(.P1);
    const p2 = battle.side(.P2);

    try expectEqual(Result.Default, try update(&battle, swtch(3), swtch(2), null));
    try expectOrder(p1, &.{ 3, 2, 1, 4, 5, 6 }, p2, &.{ 2, 1, 3, 4, 5, 6 });
    try expectEqual(Result.Default, try update(&battle, swtch(5), swtch(5), null));
    try expectOrder(p1, &.{ 5, 2, 1, 4, 3, 6 }, p2, &.{ 5, 1, 3, 4, 2, 6 });
    try expectEqual(Result.Default, try update(&battle, swtch(6), swtch(3), null));
    try expectOrder(p1, &.{ 6, 2, 1, 4, 3, 5 }, p2, &.{ 3, 1, 5, 4, 2, 6 });
    try expectEqual(Result.Default, try update(&battle, swtch(3), swtch(3), null));
    try expectOrder(p1, &.{ 1, 2, 6, 4, 3, 5 }, p2, &.{ 5, 1, 3, 4, 2, 6 });
    try expectEqual(Result.Default, try update(&battle, swtch(2), swtch(4), null));
    try expectOrder(p1, &.{ 2, 1, 6, 4, 3, 5 }, p2, &.{ 4, 1, 3, 5, 2, 6 });
    try expectEqual(Result.Default, try update(&battle, swtch(5), swtch(5), null));
    try expectOrder(p1, &.{ 3, 1, 6, 4, 2, 5 }, p2, &.{ 2, 1, 3, 5, 4, 6 });
}

test "choices" {
    var random = PRNG.init(0x27182818);
    var battle = Battle.random(&random, false);
    var options: [MAX_OPTIONS_SIZE]Choice = undefined;
    const n = battle.choices(.P1, .Move, &options);
    try expectEqualSlices(Choice, &[_]Choice{
        swtch(2), swtch(3), swtch(4), swtch(5), swtch(6),
        move(1),  move(2),  move(3),  move(4),
    }, options[0..n]);
}

// // Moves

// // Move.{KarateChop,RazorLeaf,Crabhammer,Slash}
// test "HighCritical" {
//     // Has a higher chance for a critical hit.
//     return error.SkipZigTest;
// }

// // Move.{DoubleSlap,CometPunch,FuryAttack,PinMissile,SpikeCannon,Barrage,FurySwipes}
// test "MultiHit" {
//     // Hits two to five times. Has a 3/8 chance to hit two or three times, and a 1/8 chance to hit
//     // four or five times. Damage is calculated once for the first hit and used for every hit. If
//     // one of the hits breaks the target's substitute, the move ends.
//     return error.SkipZigTest;
// }

// // Move.{DoubleKick,Bonemerang}
// test "DoubleHit" {
//     // Hits twice. Damage is calculated once for the first hit and used for both hits. If the first
//     // hit breaks the target's substitute, the move ends.
//     return error.SkipZigTest;
// }

// // Move.{FirePunch,Ember,Flamethrower}: BurnChance1
// // Move.{IcePunch,IceBeam,Blizzard}: FreezeChance
// // Move.{ThunderPunch,ThunderShock,Thunderbolt,Thunder}: ParalyzeChance1
// // Move.{Bite,BoneClub,HyperFang}: FlinchChance1
// // Move.{Psybeam,Confusion}: ConfusionChance
// test "<10 percent secondary>" {
//     // Has a 10% chance to X the target.
//     return error.SkipZigTest;
// }

// // Move.{Stomp,RollingKick,Headbutt,LowKick}: FlinchChance2
// // Move.{BodySlam,Lick}: ParalyzeChance2
// // Move.FireBlast: BurnChance2
// test "<30 percent secondary>" {
//     // Has a 30% chance to X the target
//     return error.SkipZigTest;
// }

// // Move.AuroraBeam: AttackDownChance
// // Move.Acid: DefenseDownChance
// // Move.{BubbleBeam,Constrict,Bubble}: SpeedDownChance
// // Move.Psychic: SpecialDownChance
// test "<33 percent secondary>" {
//     // Has a 33% chance to lower the target's X by 1 stage.
//     return error.SkipZigTest;
// }

// // Move.Growl: AttackDown1
// // Move.{TailWhip,Leer}: DefenseDown1
// // Move.StringShot: SpeedDown1
// // Move.{SandAttack,Smokescreen,Kinesis,Flash}: AccuracyDown1
// // Move.Screech: DefenseDown2
// test "<status lower>" {
//     // Lowers the target's X by Y stage(s).
//     return error.SkipZigTest;
// }

// // Move.{Meditate,Sharpen}: AttackUp1
// // Move.{Harden,Withdraw,DefenseCurl}: DefenseUp1
// // Move.Growth: SpecialUp1
// // Move.{DoubleTeam,Minimize}: EvasionUp1
// // Move.SwordsDance: AttackUp2
// // Move.{Barrier,AcidArmor}: DefenseUp2
// // Move.Agility: SpeedUp2
// // Move.Amnesia: SpecialUp2
// test "<status upper>" {
//     // Raises the target's X by Y stage(s).
//     return error.SkipZigTest;
// }

// // Move.{Guillotine,HornDrill,Fissure}
// test "OHKO" {
//     // Deals 65535 damage to the target. Fails if the target's Speed is greater than the user's.
//     return error.SkipZigTest;
// }

// // Move.{RazorWind,SolarBeam,SkullBash,SkyAttack}
// test "Charge" {
//     // This attack charges on the first turn and executes on the second.
//     return error.SkipZigTest;
// }

// // Move.{Whirlwind,Roar,Teleport}
// test "SwitchAndTeleport" {
//     // No competitive use.
//     return error.SkipZigTest;
// }

// // Move.Splash
// test "Splash" {
//     // No competitive use.
//     return error.SkipZigTest;
// }

// // Move.{Fly,Dig}
// test "Fly / Dig" {
//     // This attack charges on the first turn and executes on the second. On the first turn, the user
//     // avoids all attacks other than Bide, Swift, and Transform. If the user is fully paralyzed on
//     // the second turn, it continues avoiding attacks until it switches out or successfully executes
//     // the second turn of this move or {Fly,Dig}.
//     return error.SkipZigTest;
// }

// // Move.{Bind,Wrap,FireSpin,Clamp}
// test "Trapping" {
//     // The user spends two to five turns using this move. Has a 3/8 chance to last two or three
//     // turns, and a 1/8 chance to last four or five turns. The damage calculated for the first turn
//     // is used for every other turn. The user cannot select a move and the target cannot execute a
//     // move during the effect, but both may switch out. If the user switches out, the target remains
//     // unable to execute a move during that turn. If the target switches out, the user uses this
//     // move again automatically, and if it had 0 PP at the time, it becomes 63. If the user or the
//     // target switch out, or the user is prevented from moving, the effect ends. This move can
//     // prevent the target from moving even if it has type immunity, but will not deal damage.
//     return error.SkipZigTest;
// }

// // Move.{JumpKick,HighJumpKick}
// test "JumpKick" {
//     // If this attack misses the target, the user takes 1 HP of crash damage. If the user has a
//     // substitute, the crash damage is dealt to the target's substitute if it has one, otherwise no
//     // crash damage is dealt.
//     return error.SkipZigTest;
// }

// // Move.{TakeDown,DoubleEdge,Submission}
// test "Recoil" {
//     // If the target lost HP, the user takes recoil damage equal to 1/4 the HP lost by the target,
//     // rounded down, but not less than 1 HP. If this move breaks the target's substitute, the user
//     // does not take any recoil damage.
//     return error.SkipZigTest;
// }

// // Move.Struggle
// test "Recoil (Struggle)" {
//     // Deals Normal-type damage. If this move was successful, the user takes damage equal to 1/2 the
//     // HP lost by the target, rounded down, but not less than 1 HP. This move is automatically used
//     // if none of the user's known moves can be selected.
//     return error.SkipZigTest;
// }

// // Move.{Thrash,PetalDance}
// test "Locking" {
//     // Whether or not this move is successful, the user spends three or four turns locked into this
//     // move and becomes confused immediately after its move on the last turn of the effect, even if
//     // it is already confused. If the user is prevented from moving, the effect ends without causing
//     // confusion. During the effect, this move's accuracy is overwritten every turn with the current
//     // calculated accuracy including stat stage changes, but not to less than 1/256 or more than
//     // 255/256.
//     return error.SkipZigTest;
// }

// // Move.PoisonSting
// test "PoisonChance1" {
//     // Has a 20% chance to poison the target.
//     return error.SkipZigTest;
// }

// // Move.{Smog,Sludge}
// test "PoisonChance2" {
//     // Has a 40% chance to poison the target.
//     return error.SkipZigTest;
// }

// // Move.Twineedle
// test "Twineedle" {
//     // Hits twice, with the second hit having a 20% chance to poison the target. If the first hit
//     // breaks the target's substitute, the move ends.
//     return error.SkipZigTest;
// }

// // Move.{SonicBoom,DragonRage}
// test "SpecialDamage (fixed)" {
//     // Deals X HP of damage to the target. This move ignores type immunity.
//     return error.SkipZigTest;
// }

// // Move.{SeismicToss,NightShade}
// test "SpecialDamage (level)" {
//     // Deals damage to the target equal to the user's level. This move ignores type immunity.
//     return error.SkipZigTest;
// }

// // Move.Psywave
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Psywave_glitches
// test "SpecialDamage (Psywave)" {
//     // Deals damage to the target equal to a random number from 1 to (user's level * 1.5 - 1),
//     // rounded down, but not less than 1 HP.
//     return error.SkipZigTest;
// }

// // Move.Disable
// test "Disable" {
//     // For 0 to 7 turns, one of the target's known moves that has at least 1 PP remaining becomes
//     // disabled, at random. Fails if one of the target's moves is already disabled, or if none of
//     // the target's moves have PP remaining. If any Pokemon uses Haze, this effect ends. Whether or
//     // not this move was successful, it counts as a hit for the purposes of the opponent's use of
//     // Rage.
//     return error.SkipZigTest;
// }

// // Move.Mist
// test "Mist" {
//     // While the user remains active, it is protected from having its stat stages lowered by other
//     // Pokemon, unless caused by the secondary effect of a move. Fails if the user already has the
//     // effect. If any Pokemon uses Haze, this effect ends.
//     return error.SkipZigTest;
// }

// // Move.HyperBeam
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Hyper_Beam_.2B_Freeze_permanent_helplessness FIXME haze
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Hyper_Beam_.2B_Sleep_move_glitch
// test "HyperBeam" {
//     // If this move is successful, the user must recharge on the following turn and cannot select a
//     // move, unless the target or its substitute was knocked out by this move.
//     return error.SkipZigTest;
// }

// // Move.Counter
// // TODO: https://glitchcity.wiki/Counter_glitches_(Generation_I)
// // TODO: https://www.youtube.com/watch?v=ftTalHMjPRY
// test "Counter" {
//     // Deals damage to the opposing Pokemon equal to twice the damage dealt by the last move used in
//     // the battle. This move ignores type immunity. Fails if the user moves first, or if the
//     // opposing side's last move was Counter, had 0 power, or was not Normal or Fighting type. Fails
//     // if the last move used by either side did 0 damage and was not Confuse Ray, Conversion, Focus
//     // Energy, Glare, Haze, Leech Seed, Light Screen, Mimic, Mist, Poison Gas, Poison Powder,
//     // Recover, Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Teleport,
//     // Thunder Wave, Toxic, or Transform.
//     return error.SkipZigTest;
// }

// // Move.{Absorb,MegaDrain,LeechLife}
// test "Drain" {
//     // The user recovers 1/2 the HP lost by the target, rounded down.
//     return error.SkipZigTest;
// }

// // Move.DreamEater
// test "DreamEater" {
//     // The target is unaffected by this move unless it is asleep. The user recovers 1/2 the HP lost
//     // by the target, rounded down, but not less than 1 HP. If this move breaks the target's
//     // substitute, the user does not recover any HP.
//     return error.SkipZigTest;
// }

// // Move.LeechSeed
// test "LeechSeed" {
//     // At the end of each of the target's turns, The Pokemon at the user's position steals 1/16 of
//     // the target's maximum HP, rounded down and multiplied by the target's current Toxic counter if
//     // it has one, even if the target currently has less than that amount of HP remaining. If the
//     // target switches out or any Pokemon uses Haze, this effect ends. Grass-type Pokemon are immune
//     // to this move.
//     return error.SkipZigTest;
// }

// // Move.{Sing,SleepPowder,Hypnosis,LovelyKiss,Spore}
// test "Sleep" {
//     // Causes the target to fall asleep.
//     return error.SkipZigTest;
// }

// // Move.{Supersonic,ConfuseRay}
// test "Confusion" {
//     // Causes the target to become confused.
//     return error.SkipZigTest;
// }

// // Move.{PoisonPowder,PoisonGas}
// test "Poison" {
//     // Poisons the target.
//     return error.SkipZigTest;
// }

// // Move.{ThunderWave,StunSpore,Glare}
// test "Paralyze" {
//     // Paralyzes the target.
//     return error.SkipZigTest;
// }

// // Move.Toxic
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Toxic_counter_glitches
// test "Poison (Toxic)" {
//     // Badly poisons the target.
//     return error.SkipZigTest;
// }

// // Move.Rage
// test "Rage" {
//     // Once this move is successfully used, the user automatically uses this move every turn and can
//     // no longer switch out. During the effect, the user's Attack is raised by 1 stage every time it
//     // is hit by the opposing Pokemon, and this move's accuracy is overwritten every turn with the
//     // current calculated accuracy including stat stage changes, but not to less than 1/256 or more
//     // than 255/256.
//     return error.SkipZigTest;
// }

// // Move.Mimic
// test "Mimic" {
//     // While the user remains active, this move is replaced by a random move known by the target,
//     // even if the user already knows that move. The copied move keeps the remaining PP for this
//     // move, regardless of the copied move's maximum PP. Whenever one PP is used for a copied move,
//     // one PP is used for this move.
//     return error.SkipZigTest;
// }

// // Move.{Recover,SoftBoiled}
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#HP_recovery_move_failure
// test "Heal" {
//     // The user restores 1/2 of its maximum HP, rounded down. Fails if (user's maximum HP - user's
//     // current HP + 1) is divisible by 256.
//     return error.SkipZigTest;
// }

// // Move.Rest
// test "Heal (Rest)" {
//     // The user falls asleep for the next two turns and restores all of its HP, curing itself of any
//     // non-volatile status condition in the process. This does not remove the user's stat penalty
//     // for burn or paralysis. Fails if the user has full HP.
//     return error.SkipZigTest;
// }

// // Move.LightScreen
// test "LightScreen" {
//     // While the user remains active, its Special is doubled when taking damage. Critical hits
//     // ignore this effect. If any Pokemon uses Haze, this effect ends.
//     return error.SkipZigTest;
// }

// // Move.Reflect
// test "Reflect" {
//     // While the user remains active, its Defense is doubled when taking damage. Critical hits
//     // ignore this protection. This effect can be removed by Haze.
//     return error.SkipZigTest;
// }

// // Move.Haze
// // TODO: https://www.youtube.com/watch?v=gXQlct-DvVg
// test "Haze" {
//     // Resets the stat stages of both Pokemon to 0 and removes stat reductions due to burn and
//     // paralysis. Resets Toxic counters to 0 and removes the effect of confusion, Disable, Focus
//     // Energy, Leech Seed, Light Screen, Mist, and Reflect from both Pokemon. Removes the opponent's
//     // non-volatile status condition.
//     return error.SkipZigTest;
// }

// // Move.FocusEnergy
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Critical_hit_ratio_error
// test "FocusEnergy" {
//     // While the user remains active, its chance for a critical hit is quartered. Fails if the user
//     // already has the effect. If any Pokemon uses Haze, this effect ends.
//     return error.SkipZigTest;
// }

// // Move.Bide
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Bide_errors
// // TODO: https://glitchcity.wiki/Bide_fainted_Pokémon_damage_accumulation_glitch
// // TODO: https://www.youtube.com/watch?v=IVxHGyNDW4g
// test "Bide" {
//     // The user spends two or three turns locked into this move and then, on the second or third
//     // turn after using this move, the user attacks the opponent, inflicting double the damage in HP
//     // it lost during those turns. This move ignores type immunity and cannot be avoided even if the
//     // target is using Dig or Fly. The user can choose to switch out during the effect. If the user
//     // switches out or is prevented from moving during this move's use, the effect ends. During the
//     // effect, if the opposing Pokemon switches out or uses Confuse Ray, Conversion, Focus Energy,
//     // Glare, Haze, Leech Seed, Light Screen, Mimic, Mist, Poison Gas, Poison Powder, Recover,
//     // Reflect, Rest, Soft-Boiled, Splash, Stun Spore, Substitute, Supersonic, Teleport, Thunder
//     // Wave, Toxic, or Transform, the previous damage dealt to the user will be added to the total.
//     return error.SkipZigTest;
// }

// // Move.Metronome
// test "Metronome" {
//     // A random move is selected for use, other than Metronome or Struggle.
//     return error.SkipZigTest;
// }

// // Move.MirrorMove
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Mirror_Move_glitch
// test "MirrorMove" {
//     // The user uses the last move used by the target. Fails if the target has not made a move, or
//     // if the last move used was Mirror Move.
//     return error.SkipZigTest;
// }

// // Move.{SelfDestruct,Explosion}
// test "Explode" {
//     // The user faints after using this move, unless the target's substitute was broken by the
//     // damage. The target's Defense is halved during damage calculation.
//     return error.SkipZigTest;
// }

// // Move.Swift
// test "Swift" {
//     // This move does not check accuracy and hits even if the target is using Dig or Fly.
//     return error.SkipZigTest;
// }

// // Move.Transform
// // TODO: https://pkmn.cc/bulba/Transform_glitches
// test "Transform" {
//     // The user transforms into the target. The target's current stats, stat stages, types, moves,
//     // DVs, species, and sprite are copied. The user's level and HP remain the same and each copied
//     // move receives only 5 PP. This move can hit a target using Dig or Fly.
//     return error.SkipZigTest;
// }

// // Move.Conversion
// test "Conversion" {
//     // Causes the user's types to become the same as the current types of the target.
//     return error.SkipZigTest;
// }

// // Move.SuperFang
// test "SuperFang" {
//     // Deals damage to the target equal to half of its current HP, rounded down, but not less than 1
//     // HP. This move ignores type immunity.
//     return error.SkipZigTest;
// }

// // Move.Substitute
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Substitute_HP_drain_bug
// // TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Substitute_.2B_Confusion_glitch
// test "Substitute" {
//     // The user takes 1/4 of its maximum HP, rounded down, and puts it into a substitute to take its
//     // place in battle. The substitute has 1 HP plus the HP used to create it, and is removed once
//     // enough damage is inflicted on it or 255 damage is inflicted at once, or if the user switches
//     // out or faints. Until the substitute is broken, it receives damage from all attacks made by
//     // the opposing Pokemon and shields the user from status effects and stat stage changes caused
//     // by the opponent, unless the effect is Disable, Leech Seed, sleep, primary paralysis, or
//     // secondary confusion and the user's substitute did not break. The user still takes normal
//     // damage from status effects while behind its substitute, unless the effect is confusion
//     // damage, which is applied to the opposing Pokemon's substitute instead. If the substitute
//     // breaks during a multi-hit attack, the attack ends. Fails if the user does not have enough HP
//     // remaining to create a substitute, or if it already has a substitute. The user will create a
//     // substitute and then faint if its current HP is exactly 1/4 of its maximum HP.
//     return error.SkipZigTest;
// }

// // Glitches

// test "0 damage glitch" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#0_damage_glitch
//     return error.SkipZigTest;
// }

// test "1/256 miss glitch" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#1.2F256_miss_glitch
//     return error.SkipZigTest;
// }

// test "Defrost move forcing" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Defrost_move_forcing
//     return error.SkipZigTest;
// }

// test "Division by 0" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Division_by_0
//     return error.SkipZigTest;
// }

// test "Invulnerability glitch" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Invulnerability_glitch
//     return error.SkipZigTest;
// }

// test "Stat modification errors" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Stat_modification_errors
//     return error.SkipZigTest;
// }

// test "Struggle bypassing" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Struggle_bypassing
//     return error.SkipZigTest;
// }

// test "Trapping sleep glitch" {
//     // https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Trapping_sleep_glitch
//     return error.SkipZigTest;
// }

// test "Partial trapping move Mirror Move glitch" {
//     //  https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch
//     return error.SkipZigTest;
// }

// test "Rage and Thrash / Petal Dance accuracy bug" {
//     // https://www.youtube.com/watch?v=NC5gbJeExbs
// }

// test "Stat down modifier overflow glitch" {
//     // https://www.youtube.com/watch?v=y2AOm7r39Jg
// }

test "Endless Battle Clause (initial)" {
    if (!showdown) return;

    const p1 = .{ .species = .Gengar, .moves = &.{.Tackle} };
    const p2 = .{ .species = .Gengar, .moves = &.{.Tackle} };
    var battle = Battle.fixed(.{}, &.{p1}, &.{p2});

    battle.sides[0].pokemon[0].moves[0].pp = 0;
    battle.sides[1].pokemon[0].moves[0].pp = 0;

    var logs = TestLogs(20){};
    var expected = FixedLog{ .writer = stream(&logs.expected).writer() };
    try expected.switched(P1.ident(1), battle.side(.P1).pokemon[0]);
    try expected.switched(P2.ident(1), battle.side(.P2).pokemon[0]);
    try expected.tie();

    const actual = FixedLog{ .writer = stream(&logs.actual).writer() };
    try expectEqual(Result.Tie, try battle.update(.{}, .{}, actual));
    try logs.expectMatches();
    try expect(battle.rng.exhausted());
}

// BUG: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Dual-type_damage_misinformation
// BUG: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Poison.2FBurn_animation_with_0_HP

fn update(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    if (battle.turn == 0) {
        if (@typeInfo(@TypeOf(log)) == .Null) {
            var logs = TestLogs(22){};
            var expected = FixedLog{ .writer = stream(&logs.expected).writer() };
            try expected.switched(P1.ident(1), battle.side(.P1).pokemon[0]);
            try expected.switched(P2.ident(1), battle.side(.P2).pokemon[0]);
            try expected.turn(1);

            var actual = FixedLog{ .writer = stream(&logs.actual).writer() };
            try expectEqual(Result.Default, try battle.update(.{}, .{}, actual));
            try logs.expectMatches();
        } else {
            try expectEqual(Result.Default, try battle.update(.{}, .{}, null));
        }
    }
    return battle.update(c1, c2, log);
}

comptime {
    _ = @import("data.zig");
    _ = @import("mechanics.zig");
}
