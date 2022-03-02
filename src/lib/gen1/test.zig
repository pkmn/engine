const std = @import("std");
const build_options = @import("build_options");

const rng = @import("../common/rng.zig");
const util = @import("../common/util.zig"); // DEBUG

const data = @import("data.zig");
const protocol = @import("protocol.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const trace = build_options.trace;

const Random = rng.Random;

const DVs = data.DVs;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;

const Log = protocol.Log(std.io.FixedBufferStream([]u8).Writer);
const expectTrace = protocol.expectTrace;

pub const Battle = struct {
    pub fn init(
        comptime rolls: anytype,
        p1: []const Pokemon,
        p2: []const Pokemon,
    ) data.Battle(rng.FixedRNG(1, rolls.len)) {
        return .{
            .rng = .{ .rolls = rolls },
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

    pub fn random(rand: *Random) data.Battle(rng.PRNG(1)) {
        return .{
            .rng = prng(rand),
            .turn = rand.range(u16, 1, 1000),
            .last_damage = rand.range(u16, 1, 704),
            .sides = .{ Side.random(rand), Side.random(rand) },
        };
    }
};

pub fn prng(rand: *Random) rng.PRNG(1) {
    return .{ .src = .{ .seed = if (build_options.showdown) rand.int(u64) else .{
        rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8),
        rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8),
    } } };
}

pub const Side = struct {
    pub fn init(ps: []const Pokemon) data.Side {
        assert(ps.len > 0 and ps.len <= 6);
        var side = data.Side{ .active = 1 };

        var i: u4 = 0;
        while (i < ps.len) : (i += 1) {
            const p = ps[i];
            var pokemon = &side.team[i];
            pokemon.species = p.species;
            const specie = Species.get(p.species);
            inline for (std.meta.fields(@TypeOf(pokemon.stats))) |field| {
                @field(pokemon.stats, field.name) = Stats(u12).calc(
                    field.name,
                    @field(specie.stats, field.name),
                    0xF,
                    0xFFFF,
                    p.level,
                );
            }
            pokemon.position = i + 1;
            assert(p.moves.len > 0 and p.moves.len <= 4);
            for (p.moves) |move, j| {
                pokemon.moves[j].id = move;
                pokemon.moves[j].pp = @truncate(u6, Move.pp(move) / 5 * 8);
            }
            if (p.hp) |hp| {
                pokemon.hp = hp;
            } else {
                pokemon.hp = pokemon.stats.hp;
            }
            pokemon.status = p.status;
            pokemon.types = specie.types;
            pokemon.level = p.level;
            if (i == 0) {
                var active = &side.pokemon;
                inline for (std.meta.fields(@TypeOf(active.stats))) |field| {
                    @field(active.stats, field.name) = @field(pokemon.stats, field.name);
                }
                active.species = pokemon.species;
                for (pokemon.moves) |move, j| {
                    active.moves[j] = move;
                }
            }
        }
        return side;
    }

    pub fn random(rand: *Random) data.Side {
        const n = if (rand.chance(1, 100)) rand.range(u4, 1, 5) else 6;
        var side = data.Side{ .active = 1 };

        var i: u4 = 0;
        while (i < n) : (i += 1) {
            side.team[i] = Pokemon.random(rand);
            const pokemon = &side.team[i];
            pokemon.position = i + 1;
            var j: u4 = 0;
            while (j < 4) : (j += 1) {
                if (rand.chance(1, 5 + (@as(u8, i) * 2))) {
                    side.last_selected_move = side.team[i].moves[j].id;
                }
                if (rand.chance(1, 5 + (@as(u8, i) * 2))) {
                    side.last_used_move = side.team[i].moves[j].id;
                }
            }
            if (i == 0) {
                side.active = 1;
                var active = &side.pokemon;
                inline for (std.meta.fields(@TypeOf(active.stats))) |field| {
                    @field(active.stats, field.name) = @field(pokemon.stats, field.name);
                }
                inline for (std.meta.fields(@TypeOf(active.boosts))) |field| {
                    if (rand.chance(1, 10)) {
                        @field(active.boosts, field.name) = rand.range(i4, -6, 6);
                    }
                }
                active.species = pokemon.species;
                for (pokemon.moves) |move, k| {
                    active.moves[k] = move;
                }
                inline for (std.meta.fields(@TypeOf(active.volatiles))) |field| {
                    if (field.field_type != bool) continue;
                    if (rand.chance(1, 18)) {
                        @field(active.volatiles, field.name) = true;
                        if (std.mem.eql(u8, field.name, "Bide")) {
                            active.volatiles.data.bide = rand.range(u16, 1, active.stats.hp - 1);
                        } else if (std.mem.eql(u8, field.name, "Confusion")) {
                            active.volatiles.data.confusion = rand.range(u4, 1, 5);
                        } else if (std.mem.eql(u8, field.name, "Toxic")) {
                            pokemon.status = Status.init(Status.PSN);
                            active.volatiles.data.toxic = rand.range(u4, 1, 15);
                        } else if (std.mem.eql(u8, field.name, "Substitute")) {
                            active.volatiles.data.substitute =
                                rand.range(u8, 1, @truncate(u8, active.stats.hp / 4));
                        }
                    }
                }
                if (rand.chance(1, 20)) {
                    const m = rand.range(u4, 1, 4);
                    if (active.moves[m].id != .None) {
                        active.volatiles.data.disabled = .{
                            .move = m,
                            .duration = rand.range(u4, 1, 5),
                        };
                    }
                }
            }
        }

        return side;
    }
};

pub const Pokemon = struct {
    species: Species,
    moves: []const Move,
    hp: ?u16 = null,
    status: u8 = 0,
    level: u8 = 100,

    pub fn random(rand: *Random) data.Pokemon {
        const s = @intToEnum(Species, rand.range(u8, 1, 151));
        const specie = Species.get(s);
        const lvl = if (rand.chance(1, 20)) rand.range(u8, 1, 99) else 100;
        var stats: Stats(u12) = .{};
        const dvs = DVs.random(rand);
        inline for (std.meta.fields(@TypeOf(stats))) |field| {
            @field(stats, field.name) = Stats(u12).calc(
                field.name,
                @field(specie.stats, field.name),
                if (field.field_type != u4) dvs.hp() else @field(dvs, field.name),
                if (rand.chance(1, 20)) rand.range(u8, 0, 255) else 255,
                lvl,
            );
        }

        var ms = [_]MoveSlot{.{}} ** 4;
        var i: u4 = 0;
        const n = if (rand.chance(1, 100)) rand.range(u4, 1, 3) else 4;
        while (i < n) : (i += 1) {
            var move: Move = .None;
            sample: while (true) {
                move = @intToEnum(Move, rand.range(u8, 1, 165));
                var j: u4 = 0;
                while (j < i) : (j += 1) {
                    if (ms[j].id == move) continue :sample;
                }
                break;
            }
            const pp_ups = if (rand.chance(1, 10)) rand.range(u2, 0, 2) else 3;
            const max_pp = @truncate(u6, Move.pp(move) / 5 * (5 + @as(u8, pp_ups)));
            ms[i] = .{
                .id = move,
                .pp = rand.range(u6, 0, max_pp),
                .pp_ups = pp_ups,
            };
        }

        return .{
            .species = s,
            .types = specie.types,
            .level = lvl,
            .stats = stats,
            .hp = rand.range(u16, 0, stats.hp),
            .status = if (rand.chance(1, 6)) 0 | (@as(u8, 1) << rand.range(u3, 1, 6)) else 0,
            .moves = ms,
        };
    }
};

test "Battle" {
    const p1 = .{ .species = .Gengar, .moves = &.{ .Absorb, .Pound, .DreamEater, .Psychic } };
    const p2 = .{ .species = .Mew, .moves = &.{ .HydroPump, .Surf, .Bubble, .WaterGun } };
    var battle = Battle.init(.{42}, &.{p1}, &.{p2});

    var buf = [_]u8{0} ** 0;
    var log: Log = .{ .writer = std.io.fixedBufferStream(&buf).writer() };

    _ = try battle.update(.{ .type = .Move, .data = 4 }, .{ .type = .Switch, .data = 1 }, &log);
    try expectTrace(&[_]u8{}, &buf);

    util.debug.print(battle);
    // util.debug.print(Battle.random(&Random.init(5)));
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

// Move.{FirePunch,Ember,Flamethrower}: BurnChance1
// Move.{IcePunch,IceBeam,Blizzard}: FreezeChance
// Move.{ThunderPunch,ThunderShock,Thunderbolt,Thunder}: ParalyzeChance1
// Move.{Bite,BoneClub,HyperFang}: FlinchChance1
// Move.{Psybeam,Confusion}: ConfusionChance
test "<10 percent secondary>" {
    // Has a 10% chance to X the target.
    return error.SkipZigTest;
}

// Move.{Stomp,RollingKick,Headbutt,LowKick}: FlinchChance2
// Move.{BodySlam,Lick}: ParalyzeChance2
// Move.FireBlast: BurnChance2
test "<30 percent secondary>" {
    // Has a 30% chance to X the target
    return error.SkipZigTest;
}

// Move.AuroraBeam: AttackDownChance
// Move.Acid: DefenseDownChance
// Move.{BubbleBeam,Constrict,Bubble}: SpeedDownChance
// Move.Psychic: SpecialDownChance
test "<33 percent secondary>" {
    // Has a 33% chance to lower the target's X by 1 stage.
    return error.SkipZigTest;
}

// Move.Growl: AttackDown1
// Move.{TailWhip,Leer}: DefenseDown1
// Move.StringShot: SpeedDown1
// Move.{SandAttack,Smokescreen,Kinesis,Flash}: AccuracyDown1
// Move.Screech: DefenseDown2
test "<status lower>" {
    // Lowers the target's X by Y stage(s).
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
test "<status upper>" {
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
    return error.SkipZigTest;
}

// Move.Splash
test "Splash" {
    // No competitive use.
    return error.SkipZigTest;
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
test "Locking" {
    // Whether or not this move is successful, the user spends three or four turns locked into this
    // move and becomes confused immediately after its move on the last turn of the effect, even if
    // it is already confused. If the user is prevented from moving, the effect ends without causing
    // confusion. During the effect, this move's accuracy is overwritten every turn with the current
    // calculated accuracy including stat stage changes, but not to less than 1/256 or more than
    // 255/256.
    return error.SkipZigTest;
}

// Move.PoisonSting
test "PoisonChance1" {
    // Has a 20% chance to poison the target.
    return error.SkipZigTest;
}

// Move.{Smog,Sludge}
test "PoisonChance2" {
    // Has a 40% chance to poison the target.
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
    return error.SkipZigTest;
}

// Move.{SeismicToss,NightShade}
test "SpecialDamage (level)" {
    // Deals damage to the target equal to the user's level. This move ignores type immunity.
    return error.SkipZigTest;
}

// Move.Psywave
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Psywave_glitches
test "SpecialDamage (Psywave)" {
    // Deals damage to the target equal to a random number from 1 to (user's level * 1.5 - 1),
    // rounded down, but not less than 1 HP.
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
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Hyper_Beam_.2B_Freeze_permanent_helplessness
// TODO: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Hyper_Beam_.2B_Sleep_move_glitch
test "HyperBeam" {
    // If this move is successful, the user must recharge on the following turn and cannot select a
    // move, unless the target or its substitute was knocked out by this move.
    return error.SkipZigTest;
}

// Move.Counter
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

// Move.SuperFang
test "SuperFang" {
    // Deals damage to the target equal to half of its current HP, rounded down, but not less than 1
    // HP. This move ignores type immunity.
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

// BUG: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Dual-type_damage_misinformation
// BUG: https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Poison.2FBurn_animation_with_0_HP

comptime {
    _ = @import("data.zig");
}
