const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const showdown = pkmn.options.showdown;

const Damage = protocol.Damage;
const Heal = protocol.Heal;

const Gen12 = rng.Gen12;

const ActivePokemon = data.ActivePokemon;
const Effectiveness = data.Effectiveness;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Pokemon = data.Pokemon;
const Side = data.Side;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;
const Type = data.Type;
const Types = data.Types;

// zig fmt: off
const STAT_BOOSTS = &[_][2]u8{
    .{ 25, 100 }, // -6
    .{ 28, 100 }, // -5
    .{ 33, 100 }, // -4
    .{ 40, 100 }, // -3
    .{ 50, 100 }, // -2
    .{ 66, 100 }, // -1
    .{   1,  1 }, //  0
    .{ 15,  10 }, // +1
    .{  2,   1 }, // +2
    .{ 25,  10 }, // +3
    .{  3,   1 }, // +4
    .{ 35,  10 }, // +5
    .{  4,   1 }, // +6
};

const ACCURACY_BOOSTS = &[_][2]u8{
    .{  33, 100 }, // -6
    .{  36, 100 }, // -5
    .{  43, 100 }, // -4
    .{  50, 100 }, // -3
    .{  60, 100 }, // -2
    .{  75, 100 }, // -1
    .{   1,   1 }, //  0
    .{ 133, 100 }, // +1
    .{ 166, 100 }, // +2
    .{   2,   1 }, // +3
    .{ 233, 100 }, // +4
    .{ 133,  50 }, // +5
    .{   3,   1 }, // +6
};

const CRITICAL_HITS = &[_]u8{
    256 / 15, //  0
    256 /  8, // +1
    256 /  4, // +2
    256 /  3, // +3
    256 /  2, // +4
    256 /  2, // +5
    256 /  2, // +6
};
// zig fmt: on

const MAX_STAT_VALUE = 999;

const DISTRIBUTION = [_]u3{ 2, 2, 2, 3, 3, 3, 4, 5 };

pub fn update(battle: anytype, c1: Choice, c2: Choice, options: anytype) !Result {
    assert(c1.type != .Pass or c2.type != .Pass or battle.turn == 0);
    if (battle.turn == 0) return start(battle, options);

    if (try turnOrder(battle, c1, c2, options) == .P1) {
        if (try doTurn(battle, .P1, c1, .P2, c2, options)) |r| return r;
    } else {
        if (try doTurn(battle, .P2, c2, .P1, c1, options)) |r| return r;
    }

    return endTurn(battle, options);
}

fn start(battle: anytype, options: anytype) !Result {
    const p1 = battle.side(.P1);
    const p2 = battle.side(.P2);

    var p1_slot = findFirstAlive(p1);
    assert(!showdown or p1_slot == 1);
    if (p1_slot == 0) return if (findFirstAlive(p2) == 0) Result.Tie else Result.Lose;

    var p2_slot = findFirstAlive(p2);
    assert(!showdown or p2_slot == 1);
    if (p2_slot == 0) return Result.Win;

    try switchIn(battle, .P1, p1_slot, true, options);
    try switchIn(battle, .P2, p2_slot, true, options);

    return endTurn(battle, options);
}

fn findFirstAlive(side: *const Side) u8 {
    for (side.pokemon, 0..) |pokemon, i| if (pokemon.hp > 0) return side.pokemon[i].position;
    return 0;
}

fn selectMove(battle: anytype, player: Player, choice: Choice) void {
    if (choice.type == .Pass) return; // FIXME BATON PASS

    var side = battle.side(player);
    var volatiles = &side.active.volatiles;

    // pre-battle menu
    const forced = forced: {
        if (volatiles.Recharging) break :forced true;
        // Pokémon Showdown removes Flinch at the end-of-turn in its residual handler
        if (!showdown) {
            volatiles.Flinch = false;
            battle.foe(player).active.volatiles.Flinch = false;
        }
        break :forced (volatiles.Thrashing or volatiles.Charging or volatiles.Rollout);
    };

    // battle menu
    if (choice.type == .Switch) return;
    assert(choice.type == .Move and (!forced or choice.data == @intFromBool(showdown)));

    done: {
        if (forced) break :done;
        // pre-move select
        if (volatiles.Encore) {
            // TODO wCurPlayerMove = side.lastMove(true);
            // assert(wCurPlayerMove != .None);
            volatiles.Bide = false; // FIXME wPlayerCharging vs. SUBSTATUS_BIDE?
            const effect = Move.get(.Pound).effect; // TODO
            if (effect != .FuryCutter) volatiles.fury_cutter = false;
            if (effect != .Rage) {
                volatiles.Rage = false;
                volatiles.rage = 0;
            }
            if (effect != .Protect and effect != .Endure) volatiles.protect = 0;
            return;
        }
        if (volatiles.Bide) break :done;
        // move select
        if (choice.data == 0) {
            const struggle = ok: {
                for (side.active.moves, 0..) |move, i| {
                    if (move.pp > 0 and volatiles.disabled_move != i + 1) break :ok false;
                }
                break :ok true;
            };
            assert(struggle);
            // TODO wCurPlayerMove = .Struggle;
        } else {
            assert(showdown or side.active.volatiles.disabled_move != choice.data);
            const move = side.active.move(choice.data);
            // You cannot *select* a move with 0 PP
            assert(move.pp != 0);
            // TODO wCurPlayerMove = move.id;
            // battle.lastMove(player).index = @intCast(c.data);
        }
    }

    volatiles.Rage = false;
    volatiles.rage = 0;
    volatiles.fury_cutter = 0;
    volatiles.protect = 0;
}

fn switchIn(battle: anytype, player: Player, slot: u8, initial: bool, options: anytype) !void {
    var side = battle.side(player);
    var foe = battle.foe(player);

    var active = &side.active;
    const incoming = side.get(slot);

    assert(incoming.hp != 0);
    assert(slot != 1 or initial);

    const out = side.pokemon[0].position;
    side.pokemon[0].position = side.pokemon[slot - 1].position;
    side.pokemon[slot - 1].position = out;

    side.last_used_move = .None;
    foe.active.volatiles.dirty = true;

    active.volatiles = .{};
    active.stats = incoming.stats;
    active.moves = incoming.moves;
    active.boosts = .{};
    active.types = incoming.types;
    active.species = incoming.species;

    statusModify(incoming.status, &active.stats);

    try options.log.switched(battle.active(player), incoming);
    options.chance.switched(player, side.pokemon[0].position, out);

    if (side.conditions.Spikes and !active.types.includes(.Flying)) {
        incoming.hp -|= @max(incoming.stats.hp / 8, 1);
        try options.log.damage(battle.active(player), incoming, .Spikes);
    }
}

fn turnOrder(battle: anytype, c1: Choice, c2: Choice, options: anytype) !Player {
    assert(c1.type != .Pass or c2.type != .Pass);

    if (c1.type == .Pass) return .P2;
    if (c2.type == .Pass) return .P1;

    // Pokémon Showdown always rolls for Quick Claw every turn, even if no Pokémon hold Quick Claw
    // TODO: add to pending and only commit roll on Pokémon Showdown if roll is used
    const qkc = showdown and try Rolls.quickClaw(battle, .P1, options);

    if ((c1.type == .Switch) != (c2.type == .Switch)) return if (c1.type == .Switch) .P1 else .P2;

    // https://www.smogon.com/forums/threads/adv-switch-priority.3622189/
    // > In Gen 1 it's irrelevant [which player switches first] because switches happen instantly on
    // > your own screen without waiting for the other player's choice (and their choice will appear
    // > to happen first for them too, unless they attacked in which case your switch happens first)
    // A cartridge-compatible implemention must not advance the RNG so we simply default to P1
    const double_switch = c1.type == .Switch and c2.type == .Switch;
    if (!showdown and double_switch) return .P1;

    const m1 = .Pound; // TODO battle.side(.P1).last_selected_move;
    const m2 = .Pound; // TODO battle.side(.P2).last_selected_move;
    if (!showdown or !double_switch) {
        const pri1 = Move.get(m1).priority;
        const pri2 = Move.get(m2).priority;
        if (pri1 != pri2) return if (pri1 > pri2) .P1 else .P2;

        const qkc1 = battle.side(.P1).stored().item == .QuickClaw;
        const qkc2 = battle.side(.P2).stored().item == .QuickClaw;
        if (!showdown and qkc1 and qkc2) {
            // If both Pokémon have Quick Claw the cartridge checks them in order and exits early if
            // the first one procs, meaning the host has a slightly higher chance of going first
            if (try Rolls.quickClaw(battle, .P1, options)) return .P1;
            if (try Rolls.quickClaw(battle, .P2, options)) return .P2;
        } else if (qkc1) {
            const proc = if (showdown) qkc else try Rolls.quickClaw(battle, .P1, options);
            if (proc) return .P1;
        } else if (qkc2) {
            const proc = if (showdown) qkc else try Rolls.quickClaw(battle, .P2, options);
            if (proc) return .P2;
        }
    }

    const spe1 = battle.side(.P1).active.stats.spe;
    const spe2 = battle.side(.P2).active.stats.spe;
    if (spe1 == spe2) {
        // Pokémon Showdown's beforeTurnCallback shenanigans
        if (showdown and !double_switch and hasCallback(m1) and hasCallback(m2)) {
            battle.rng.advance(1);
        }

        const p1 = try Rolls.speedTie(battle, options);
        if (!showdown) return if (p1) .P1 else .P2;

        // Pokémon Showdown's "lockedmove" volatile's onBeforeTurn uses BattleQueue#changeAction,
        // meaning that if a side is locked into a thrashing move and wins the speed tie, it
        // actually uses its priority to simply insert its actual changed action into the queue,
        // causing it to then execute *after* the side which should go second...
        const t1 = battle.side(.P1).active.volatiles.Thrashing;
        const t2 = battle.side(.P2).active.volatiles.Thrashing;
        // If *both* sides are thrashing it really should be another speed tie, but we've patched
        // that out and enforce host ordering of events, so P1 just goes first regardless of who
        // won the original coin flip
        if (t1 and t2) return .P1;
        return if (p1) if (t1 and !t2) .P2 else .P1 else if (t2 and !t1) .P1 else .P2;
    }

    return if (spe1 > spe2) .P1 else .P2;
}

fn hasCallback(m: Move) bool {
    return switch (m) {
        .Counter, .MirrorCoat, .Pursuit => true,
        else => false,
    };
}

fn doTurn(
    battle: anytype,
    player: Player,
    player_choice: Choice,
    foe_player: Player,
    foe_choice: Choice,
    options: anytype,
) !?Result {
    assert(player_choice.type != .Pass);

    const volatiles = &battle.side(player).active.volatiles;
    const foe_volatiles = &battle.foe(player).active.volatiles;

    volatiles.DestinyBond = false;
    if (try executeMove(battle, player, player_choice, options)) |r| return r;
    foe_volatiles.Protect = false;
    foe_volatiles.Endure = false;
    foe_volatiles.DestinyBond = false;

    // foe_volatiles.DestinyBond = false;
    if (try executeMove(battle, foe_player, foe_choice, options)) |r| return r;
    volatiles.Protect = false;
    volatiles.Endure = false;
    volatiles.DestinyBond = false;

    return null;
}

fn executeMove(battle: anytype, player: Player, choice: Choice, options: anytype) !?Result {
    if (choice.type == .Switch) {
        try switchIn(battle, player, choice.data, false, options);
        return null;
    }

    assert(choice.type == .Move);
    var mslot: u4 = @intCast(choice.data);

    // const move = Move.get(side.last_selected_move);

    // CheckTurn

    return doMove(battle, player, options, mslot);
}

fn beforeMove(battle: anytype, player: Player, options: anytype) !void {
    _ = battle;
    _ = player;
    _ = options;
}

fn canMove(battle: anytype, player: Player, options: anytype) !bool {
    _ = battle;
    _ = player;
    _ = options;
    return false;
}

fn decrementPP(side: *Side, mslot: u4) void {
    var active = &side.active;
    const volatiles = &active.volatiles;

    // TODO assert(side.last_selected_move != .Struggle);
    assert(!volatiles.Charging and !volatiles.BeatUp and !volatiles.Thrashing and !volatiles.Bide);

    assert(active.move(mslot).pp > 0);
    active.move(mslot).pp = @as(u6, @intCast(active.move(mslot).pp)) -% 1;
    if (volatiles.Transform) return;

    // FIXME mimic

    assert(side.stored().move(mslot).pp > 0);
    side.stored().move(mslot).pp = @as(u6, @intCast(side.stored().move(mslot).pp)) -% 1;
    assert(active.move(mslot).pp == side.stored().move(mslot).pp);
}

fn doMove(battle: anytype, player: Player, options: anytype, mslot: u4) !?Result {
    _ = options;
    var side = battle.side(player);
    const move = Move.get(.Teleport); // side.last_selected_move
    switch (move.effect) {
        .Teleport => {
            // side.useMove();
            decrementPP(side, mslot);
        },
        else => @panic("TODO"),
    }
    return null;
}

fn checkCriticalHit(battle: anytype, player: Player, move: Move.Data, options: anytype) !bool {
    if (move.bp == 0) return false;

    const side = battle.side(player);
    const pokemon = side.stored();

    var stage: u8 =
        if ((pokemon.species == .Chansey and pokemon.item == .LuckyPunch) or
        (pokemon.species == .Farfetchd and pokemon.item == .Stick)) 2 else 0;
    if (side.active.volatiles.FocusEnergy) stage += 1;
    if (move.effect.isHighCritical()) stage += 2;
    if (pokemon.item == .ScopeLens) stage += 1;
    assert(stage <= 5);

    return Rolls.criticalHit(battle, player, CRITICAL_HITS[stage], options);
}

fn calcDamage(
    battle: anytype,
    player: Player,
    target_player: Player,
    m: ?Move.Data,
    crit: bool,
) u16 {
    _ = battle;
    _ = player;
    _ = target_player;
    _ = m;
    _ = crit;
    return 0;
}
const FORESIGHT: Types = .{ .type1 = .Normal, .type2 = .Fighting };

fn adjustDamage(battle: anytype, player: Player, m: Move, damage: u16, effectiveness: *u16) u16 {
    if (m == .Struggle) return;

    const side = battle.side(player);
    const foe = battle.foe(player);
    const types = foe.active.types;
    const move = Move.get(side.m);

    var d = damage;
    if ((move.type == .Water and battle.field.weather == .Rain) or
        (move.type == .Fire and battle.field.weather == .Sun))
    {
        d = d *% @intFromEnum(Effectiveness.Super) / 10;
    } else if ((move.type == .Water and battle.field.weather == .Sun) or
        ((move.type == .Fire or m == .SolarBeam) and battle.field.weather == .Rain))
    {
        d = d *% @intFromEnum(Effectiveness.Resisted) / 10;
    }

    if (side.active.types.includes(move.type)) d +%= d / 2;

    const neutral = @intFromEnum(Effectiveness.Neutral);
    const foresight = foe.active.volatiles.Foresight and FORESIGHT.includes(move.type);
    const eff1: u16 = if (foresight and types.type1 == .Ghost)
        10
    else
        @intFromEnum(move.type.effectiveness(types.type1));
    const eff2: u16 = if (foresight and types.type2 == .Ghost)
        10
    else
        @intFromEnum(move.type.effectiveness(types.type2));

    // Type effectiveness matchup precedence only matters with (NVE, SE)
    if (!showdown and (eff1 + eff2) == Effectiveness.mismatch and
        Type.precedence(move.type, types.type1) > Type.precedence(move.type, types.type2))
    {
        assert(eff2 != neutral);
        d = d *% eff2 / 10;
        assert(types.type1 != types.type2);
        assert(eff1 != neutral);
        d = d *% eff1 / 10;
    } else {
        if (eff1 != neutral) d = d *% eff1 / 10;
        if (types.type1 != types.type2 and eff2 != neutral) d = d *% eff2 / 10;
    }

    effectiveness.* = if (types.type1 == types.type2) eff1 * neutral else eff1 * eff2;
    return d;
}

fn randomizeDamage(battle: anytype, player: Player, options: anytype) !u16 {
    _ = battle;
    _ = player;
    _ = options;
    return 0;
}

fn applyDamage(
    battle: anytype,
    player: Player,
    options: anytype,
) !bool {
    _ = battle;
    _ = player;
    _ = options;
    return false;
}

fn checkHit(battle: anytype, player: Player, move: Move.Data, options: anytype) !bool {
    if (moveHit(battle, player, move, options)) return true;

    try options.chance.commit(player, .miss);
    try options.log.lastmiss();
    try options.log.miss(battle.active(player));

    return false;
}

fn moveHit(
    battle: anytype,
    player: Player,
    move: Move.Data,
    options: anytype,
) bool {
    var side = battle.side(player);
    const foe = battle.foe(player);
    _ = move;
    _ = side;
    _ = foe;
    _ = options;
    return false;
}

fn checkFaint(
    battle: anytype,
    player: Player,
    options: anytype,
) @TypeOf(options.log).Error!?Result {
    _ = battle;
    _ = player;
    return null;
}

fn faint(battle: anytype, player: Player, done: bool, options: anytype) !?Result {
    _ = battle;
    _ = player;
    _ = done;
    _ = options;
    return null;
}

fn handleResidual(battle: anytype, player: Player, options: anytype) !void {
    var side = battle.side(player);
    var stored = side.stored();
    const ident = battle.active(player);
    var volatiles = &side.active.volatiles;

    // TODO if (stored.hp == 0) return;
    assert(stored.hp > 0);

    const brn = Status.is(stored.status, .BRN);
    if (brn or Status.is(stored.status, .PSN)) {
        var damage: u16 = undefined;
        if (volatiles.Toxic) {
            volatiles.toxic += 1;
            damage = @max(stored.stats.hp / 16, 1) * volatiles.toxic;
        } else {
            damage = @max(stored.stats.hp / 8, 1);
        }
        damage = @min(damage, stored.hp);

        if (!showdown or damage > 0) {
            stored.hp -= damage;
            // Pokémon Showdown uses damageOf here but its not relevant in Generation II
            try options.log.damage(ident, stored, if (brn) Damage.Burn else Damage.Poison);
            if (stored.hp == 0) return;
        }
    }

    if (volatiles.LeechSeed) {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        // if (foe_stored.hp == 0) {
        //     assert(showdown);
        //     return;
        // }

        const damage = @min(@max(stored.stats.hp / 8, 1), stored.hp);
        stored.hp -= damage;
        // As above, Pokémon Showdown uses damageOf but its not relevant
        if (damage > 0) try options.log.damage(ident, stored, .LeechSeed);

        const before = foe_stored.hp;
        foe_stored.hp = @min(foe_stored.hp + damage, foe_stored.stats.hp);
        // Pokémon Showdown uses the less specific heal here instead of drain... because reasons?
        if (foe_stored.hp > before) try options.log.heal(foe_ident, foe_stored, .Silent);
        if (stored.hp == 0) return;
    }

    if (volatiles.Nightmare) {
        const damage = @min(@max(stored.stats.hp / 4, 1), stored.hp);
        if (!showdown or damage > 0) {
            stored.hp -= damage;
            // ibid
            try options.log.damage(ident, stored, Damage.Nightmare);
            if (stored.hp == 0) return;
        }
    }

    if (volatiles.Curse) {
        const damage = @min(@max(stored.stats.hp / 4, 1), stored.hp);
        if (!showdown or damage > 0) {
            stored.hp -= damage;
            // ibid
            try options.log.damage(ident, stored, Damage.Curse);
            if (stored.hp == 0) return;
        }
    }
}

fn betweenTurn(battle: anytype, options: anytype) !void {
    var p1 = battle.side(.P1);
    var p2 = battle.side(.P2);

    _ = p1;
    _ = p2;
    _ = options;

    // TODO checkFaintThen(p1, p2);

}

fn endTurn(battle: anytype, options: anytype) @TypeOf(options.log).Error!Result {
    battle.turn += 1;

    if (showdown and battle.turn >= 1000) {
        try options.log.tie();
        return Result.Tie;
    } else if (battle.turn >= 65535) {
        return Result.Error;
    }

    try options.log.turn(battle.turn);

    return Result.Default;
}

pub const Effects = struct {
    fn protect(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        // TODO or if we didn't go first
        if (volatiles.Substitute) return try options.log.fail(battle.active(player), .None);

        // TODO

        if (move.effect == .Endure) {
            volatiles.Endure = true;
        } else {
            volatiles.Protect = true;
        }
        try options.log.singleturn(battle.active(player), move.id);
    }
};

fn statusModify(status: u8, stats: *Stats(u16)) void {
    if (Status.is(status, .PAR)) {
        stats.spe = @max(stats.spe / 4, 1);
    } else if (Status.is(status, .BRN)) {
        stats.atk = @max(stats.atk / 2, 1);
    }
}

inline fn isForced(active: anytype) bool {
    return active.volatiles.Recharging or active.volatiles.Rage or
        active.volatiles.Thrashing or active.volatiles.Charging or
        // FIXME TODO Underground or Flying?
        active.volatiles.Underground or active.volatiles.Flying or
        active.volatiles.Rollout;
}

pub const Rolls = struct {
    inline fn speedTie(battle: anytype, options: anytype) !bool {
        const p1 = if (options.calc.overridden(.P1, .speed_tie)) |player|
            player == .P1
        else if (showdown)
            battle.rng.range(u8, 0, 2) == 0
        else
            battle.rng.next() < Gen12.percent(50) + 1;

        try options.chance.speedTie(p1);
        return p1;
    }

    inline fn quickClaw(battle: anytype, player: Player, options: anytype) !bool {
        const qkc = if (options.calc.overridden(player, .quick_claw)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 60, 256)
        else
            battle.rng.next() < 60;

        try options.chance.quickClaw(player, qkc);
        return qkc;
    }

    inline fn criticalHit(battle: anytype, player: Player, rate: u8, options: anytype) !bool {
        const crit = if (options.calc.overridden(player, .critical_hit)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, rate, 256)
        else
            battle.rng.next() < rate;

        try options.chance.criticalHit(player, crit, rate);
        return crit;
    }

    const METRONOME = init: {
        var num = 0;
        var moves: [238]Move = undefined;
        for (1..Move.size) |i| {
            if (Move.get(@enumFromInt(i)).flags.metronome) {
                moves[num] = @enumFromInt(i);
                num += 1;
            }
        }
        assert(num == moves.len);
        break :init moves;
    };
};

test "RNG agreement" {
    if (!showdown) return;
    var expected: [256]u32 = undefined;
    for (0..expected.len) |i| {
        expected[i] = @intCast(i * 0x1000000);
    }

    var spe = rng.FixedRNG(2, expected.len){ .rolls = expected };
    var qkc = rng.FixedRNG(2, expected.len){ .rolls = expected };

    for (0..expected.len) |i| {
        try expectEqual(spe.range(u8, 0, 2) == 0, i < Gen12.percent(50) + 1);
        try expectEqual(qkc.chance(u8, 60, 256), i < 60);
    }
}

pub fn choices(battle: anytype, player: Player, request: Choice.Type, out: []Choice) u8 {
    var n: u8 = 0;
    switch (request) {
        .Pass => {
            out[n] = .{};
            n += 1;
        },
        .Switch => {
            const side = battle.side(player);
            var slot: u4 = 2;
            while (slot <= 6) : (slot += 1) {
                const id = side.order[slot - 1];
                if (id == 0 or side.pokemon[id - 1].hp == 0) continue;
                out[n] = .{ .type = .Switch, .data = slot };
                n += 1;
            }
            if (n == 0) {
                out[n] = .{};
                n += 1;
            }
        },
        .Move => {
            const side = battle.side(player);

            var active = &side.active;
            const stored = side.stored();

            // While players are not given any input options on the cartridge in these cases,
            // Pokémon Showdown instead produces a list with a single move that must be chosen.
            //
            // Given that no input is allowed on the cartridge 'Pass' seems like it would be logical
            // here when not in compatibility mode, but the engine needs to be able to differentiate
            // between passing while waiting for an opponent's forced switch after fainting and
            // passing due to being forced into using a move. Instead of introducing another option
            // we simply repurpose Move with no move slot, even though pedantically this is not
            // strictly correct as the player would not have been presented the option to move or
            // switch at all.
            if (isForced(active)) {
                out[n] = .{ .type = .Move, .data = @intFromBool(showdown) };
                n += 1;
                return n;
            }

            var slot: u4 = 2;
            while (!active.volatiles.trapped and slot <= 6) : (slot += 1) {
                const id = side.order[slot - 1];
                if (id == 0 or side.pokemon[id - 1].hp == 0) continue;
                out[n] = .{ .type = .Switch, .data = slot };
                n += 1;
            }

            const limited = active.volatiles.Bide or active.volatiles.bind > 0;
            // On the cartridge, all of these happen after "FIGHT" (indicating you are not
            // switching) but before you are allowed to select a move. Pokémon Showdown instead
            // either disables all other moves in the case of limited or requires you to select a
            // move normally if sleeping/frozen/bound.
            if (!showdown and (limited or
                Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP)))
            {
                out[n] = .{ .type = .Move, .data = 0 };
                n += 1;
                return n;
            }

            slot = 1;
            // Pokémon Showdown handles Bide and Binding moves by checking if the move in question
            // is present in the Pokémon's moveset (which means moves called via Metronome / Mirror
            // Move will not result in forcing the subsequent use unless the user also had the
            // proc-ed move in their moveset) and disabling all other moves.
            if (limited) {
                assert(showdown);
                assert(side.last_selected_move != .None);
                while (slot <= 4) : (slot += 1) {
                    const m = active.moves[slot - 1];
                    if (m.id == .None) break;
                    if (m.id == if (active.volatiles.Bide) .Bide else side.last_selected_move) {
                        // Pokémon Showdown displays Struggle if limited to Bide but unable to pick
                        const struggle =
                            m.id == .Bide and (m.pp == 0 or active.volatiles.disabled_move == slot);
                        const s = if (struggle) 0 else slot;
                        out[n] = .{ .type = .Move, .data = s };
                        n += 1;
                        return n;
                    }
                }
            }

            const before = n;
            slot = 1;
            while (slot <= 4) : (slot += 1) {
                const m = active.moves[slot - 1];
                if (m.id == .None) break;
                if (m.pp == 0) continue;
                if (active.volatiles.disabled_move == slot) continue;
                out[n] = .{ .type = .Move, .data = slot };
                n += 1;
            }
            // Struggle (Pokémon Showdown would use 'move 1' here)
            if (n == before) {
                out[n] = .{ .type = .Move, .data = 0 };
                n += 1;
            }
        },
    }
    return n;
}
