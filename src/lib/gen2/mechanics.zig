const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const showdown = pkmn.options.showdown;

const Activate = protocol.Activate;
const Cant = protocol.Cant;
const Damage = protocol.Damage;
const End = protocol.End;
const Heal = protocol.Heal;
const Start = protocol.Start;

const Gen12 = rng.Gen12;

const ActivePokemon = data.ActivePokemon;
const Effectiveness = data.Effectiveness;
const Item = data.Item;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Pokemon = data.Pokemon;
const Side = data.Side;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;
const TriAttack = data.TriAttack;
const Type = data.Type;
const Types = data.Types;
const Volatiles = data.Volatiles;

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

fn beforeMove(battle: anytype, player: Player, options: anytype) !bool {
    var log = options.log;
    var side = battle.side(player);
    // const foe = battle.foe(player);
    var active = &side.active;
    var stored = side.stored();
    const ident = battle.active(player);
    var volatiles = &active.volatiles;

    const move = Move.Pound; // TODO

    if (volatiles.Recharging) {
        volatiles.Recharging = false;
        cantMove(volatiles);
        try log.cant(ident, .Recharge);
        return false;
    }

    if (Status.is(stored.status, .SLP)) slp: {
        const before = stored.status;
        // Even if the EXT bit is set this will still correctly modify the sleep duration
        // if (options.calc.modify(player, .sleep)) |extend| {
        //     if (!extend) stored.status = 0;
        // } else {
        stored.status -= 1;
        // }

        const duration = Status.duration(stored.status);
        if (!Status.is(stored.status, .EXT)) {
            try options.chance.sleep(player, duration);
        }

        if (duration == 0) {
            try log.curestatus(ident, before, .Message);
            stored.status = 0; // clears EXT if present
            cantMove(volatiles);
            volatiles.Nightmare = false;
        } else {
            try log.cant(ident, .Sleep);
            if (move == .Snore or move == .SleepTalk) break :slp;
            cantMove(volatiles);
            return false;
        }
    }

    if (Status.is(stored.status, .FRZ) and !(move == .FlameWheel or move == .SacredFire)) {
        cantMove(volatiles);
        try log.cant(ident, .Freeze);
        return false;
    }

    if (volatiles.Flinch) {
        // Pokémon Showdown doesn't clear Flinch until its imaginary "residual" phase, meaning
        // Pokémon can sometimes flinch multiple times from the same original hit
        // if (!showdown) volatiles.Flinch = false;
        volatiles.Flinch = false;
        cantMove(volatiles);
        try log.cant(ident, .Flinch);
        return false;
    }

    if (volatiles.disabled_duration > 0) {
        // if (options.calc.modify(player, .disable)) |extend| {
        //     if (!extend) volatiles.disabled_duration = 0;
        // } else {
        volatiles.disabled_duration -= 1;
        // }
        try options.chance.disable(player, volatiles.disabled_duration);

        if (volatiles.disabled_duration == 0) {
            volatiles.disabled_move = 0;
            try log.end(ident, .Disable);
        }
    }

    if (volatiles.Confusion) {
        assert(volatiles.confusion > 0);

        // if (options.calc.modify(player, .confusion)) |extend| {
        //     if (!extend) volatiles.confusion = 0;
        // } else {
        volatiles.confusion -= 1;
        // }
        try options.chance.confusion(player, volatiles.confusion);

        if (volatiles.confusion == 0) {
            volatiles.Confusion = false;
            try log.end(ident, .Confusion);
        } else {
            try log.activate(ident, .Confusion);

            if (try Rolls.confused(battle, player, options)) {
                volatiles.BeatUp = false;
                volatiles.Flinch = false;
                cantMove(volatiles);

                // TODO HitConfusion

                return false;
            }
        }
    }

    if (volatiles.Attract) {
        try log.atrract(ident, .Attract);

        if (try Rolls.attract(battle, player, options)) {
            cantMove(volatiles);
            try log.cant(ident, .Attract);
            return false;
        }
    }

    if (side.active.volatiles.disabled_move != 0) {
        // A Pokémon that transforms after being disabled may end up with less move slots
        const m = side.active.moves[side.active.volatiles.disabled_move - 1].id;
        if (m != .None and m == move) {
            side.active.volatiles.Charging = false;
            cantMove(volatiles);
            try options.log.disabled(ident, move);
            return false;
        }
    }

    if (Status.is(stored.status, .PAR) and try Rolls.paralyzed(battle, player, options)) {
        cantMove(volatiles);
        try log.cant(ident, .Paralysis);
        return false;
    }

    return true;
}

fn cantMove(volatiles: *Volatiles) void {
    volatiles.Bide = false;
    volatiles.Thrashing = false;
    volatiles.Charging = false;
    volatiles.Underground = false;
    volatiles.Flying = false;
    volatiles.Rollout = false;

    volatiles.fury_cutter = 0;
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
    if (stage == 0) {
        if (side.active.volatiles.FocusEnergy) stage += 1;
        if (move.effect.isHighCritical()) stage += 2;
        if (pokemon.item == .ScopeLens) stage += 1;
    }
    assert(stage <= 4);

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

fn randomizeDamage(battle: anytype, player: Player, damage: u16, options: anytype) !u16 {
    if (damage <= 1) return;
    const random = try Rolls.damage(battle, player, options);
    options.calc.base(player.foe(), damage);
    damage = @intCast(@as(u32, damage) *% random / 255);
    options.calc.final(player.foe(), damage);
    return damage;
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

    // try options.chance.commit(player, .miss);
    try options.log.lastmiss();
    try options.log.miss(battle.active(player));

    return false;
}

// TODO: set damage = 0 if missed and not (High) Jump Kick
fn moveHit(
    battle: anytype,
    player: Player,
    move: Move.Data,
    options: anytype,
) !bool {
    const side = battle.side(player);
    const foe = battle.foe(player);

    if (move.effect == .DreamEater and !Status.is(foe.stored().status, .SLP)) return false;
    if (foe.active.volatiles.Protect) return false;
    const drain = move.effect == .DrainHP or move.effect == .DreamEater;
    if (drain and foe.active.volatiles.Substitute) return false;
    if (side.active.volatiles.LockOn) {
        return !(foe.active.volatiles.Flying and move.extra.undeground);
    }
    assert(!(foe.active.volatiles.Flying and foe.active.volatiles.Underground));
    if (foe.active.volatiles.Flying) {
        if (!move.extra.flying) return false;
    } else if (foe.active.volatiles.Underground) {
        if (!move.extra.underground) return false;
    }
    if (move.effect == .Thunder and battle.field.weather == .Rain) return true;
    if (move.effect == .AlwaysHit) return true;

    var accuracy: u16 = move.accuracy;
    if (foe.active.boosts.evasion <= side.active.boosts.accuracy or
        !foe.active.volatiles.Foresight)
    {
        var boost = ACCURACY_BOOSTS[@as(u4, @intCast(@as(i8, side.active.boosts.accuracy) + 6))];
        accuracy = accuracy * boost[0] / boost[1];
        boost = ACCURACY_BOOSTS[@as(u4, @intCast(@as(i8, -foe.active.boosts.evasion) + 6))];
        accuracy = accuracy * boost[0] / boost[1];
        accuracy = @min(255, @max(1, accuracy));
    }

    if (foe.stored().item == .BrightPowder) {
        accuracy -|= 20;
    }

    // The accuracy roll is skipped entirely if maxed
    if (accuracy == 255) return true;
    return !try Rolls.hit(battle, player, @intCast(accuracy), options);
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

        stored.hp -|= damage;
        // Pokémon Showdown uses damageOf here but its not relevant in Generation II
        try options.log.damage(ident, stored, if (brn) Damage.Burn else Damage.Poison);
        if (stored.hp == 0) return;
    }

    if (volatiles.LeechSeed) {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        // if (foe_stored.hp == 0) {
        //     assert(showdown);
        //     return;
        // }

        const damage = @max(stored.stats.hp / 8, 1);
        stored.hp -|= damage;
        // As above, Pokémon Showdown uses damageOf but its not relevant
        try options.log.damage(ident, stored, .LeechSeed);

        const before = foe_stored.hp;
        foe_stored.hp = @min(foe_stored.hp + damage, foe_stored.stats.hp);
        // Pokémon Showdown uses the less specific heal here instead of drain... because reasons?
        if (foe_stored.hp > before) try options.log.heal(foe_ident, foe_stored, .Silent);
        if (stored.hp == 0) return;
    }

    if (volatiles.Nightmare) {
        stored.hp -= @max(stored.stats.hp / 4, 1);
        // ibid
        try options.log.damage(ident, stored, Damage.Nightmare);
        if (stored.hp == 0) return;
    }

    if (volatiles.Curse) {
        stored.hp -= @max(stored.stats.hp / 4, 1);
        // ibid
        try options.log.damage(ident, stored, Damage.Curse);
        if (stored.hp == 0) return;
    }
}

fn betweenTurns(battle: anytype, mslot: u4, options: anytype) !void {
    const players = std.enums.values(Player);

    // TODO checkFaintThen(p1, p2);

    // Future Sight
    inline for (players) |player| {
        var side = battle.side(player);
        var future_sight = &side.conditions.future_sight;

        if (future_sight.count > 0) {
            future_sight.count -= 1;
            assert(future_sight.count != 0);
            if (future_sight.count == 1) {
                try options.log.end(battle.active(player), .FutureSight);
                // TODO doMove
            }
        }
    }
    // TODO checkFaintThen(p1, p2);

    // Weather
    if (battle.field.weather != .None) {
        assert(battle.field.weather_duration > 0);
        battle.field.weather_duration -= 1;

        if (battle.field.weather_duration == 0) {
            battle.field.weather = .None;
            try options.log.weather(battle.field.weather, .None);
        } else {
            try options.log.weather(battle.field.weather, .Upkeep);
            if (battle.field.weather == .Sandstorm) {
                inline for (players) |player| {
                    var side = battle.side(player);
                    const active = side.active;
                    if (!(active.volatiles.underground or active.types.sandstormImmune())) {
                        side.stored().hp -|= @max(side.stored().stats.hp / 8, 1);
                        try options.log.damage(battle.active(player), side.stored(), .Sandstorm);
                    }
                }
                // TODO checkFaintThen(p1, p2);
            }
        }
    }

    // Binding
    inline for (players) |player| {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        if (volatiles.bind > 0 and !volatiles.Substitute) {
            volatiles.bind -= 1;
            if (volatiles.bind == 0) {
                const reason = @intFromEnum(End.Bind) + volatiles.bind_reason - 1;
                try options.log.end(battle.active(player), @enumFromInt(reason));
            } else {
                var reason = @intFromEnum(Activate.Bind) + volatiles.bind_reason - 1;
                try options.log.activate(battle.active(player), @enumFromInt(reason));

                reason = @intFromEnum(Activate.Damage) + volatiles.bind_reason - 1;
                side.stored().hp -|= @max(side.stored().stats.hp / 16, 1);
                try options.log.damage(battle.active(player), side.stored(), reason);
            }
        }
    }
    // TODO checkFaintThen(p1, p2);

    // Perish Song
    inline for (players) |player| {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        if (volatiles.PerishSong) {
            assert(volatiles.perish_song > 0);
            volatiles.perish_song -= 1;

            assert(volatiles.perish_song < 3);
            const reason = @intFromEnum(Start.PerishSong0) + volatiles.perish_song;
            try options.log.start(battle.active(player), reason);

            if (volatiles.perish_song == 0) {
                volatiles.PerishSong = false;
                side.stored().hp = 0;
            }
        }
    }
    // TODO checkFaintThen(p1, p2);

    // Leftovers
    inline for (players) |player| {
        var stored = battle.side(player).stored();

        if (stored.item == .Leftovers) {
            const before = stored.hp;
            stored.hp = @min(stored.hp + @max(stored.stats.hp / 16, 1), stored.stats.hp);
            if (stored.hp > before) try options.log.heal(battle.active(player), stored, .Leftovers);
        }
    }

    // Mystery Berry
    inline for (players) |player| {
        var stored = battle.side(player).stored();

        if (stored.item == .MysteryBerry) {
            // TODO stored and active moves, transform, etc
        }
    }

    // Defrost
    inline for (players) |player| {
        var side = battle.side(player);

        if (Status.is(side.stored().status, .FRZ) and
            !side.active.volatiles.frozen and
            try Rolls.defrost(battle, player, options))
        {
            try options.log.curestatus(battle.active(player), side.stored().status, .Message);
            side.stored().status = 0;
        }
    }

    // Side Conditions
    if (showdown) {
        inline for (players) |player| {
            updateSideCondition(battle, player, "Reflect", "reflect");
        }
        inline for (players) |player| {
            updateSideCondition(battle, player, "LightScreen", "light_screen");
        }
        inline for (players) |player| {
            updateSideCondition(battle, player, "Safeguard", "safeguard");
        }
    } else {
        inline for (players) |player| {
            updateSideCondition(battle, player, "Safeguard", "safeguard");
        }

        inline for (players) |player| {
            updateSideCondition(battle, player, "LightScreen", "light_screen");
            updateSideCondition(battle, player, "Reflect", "reflect");
        }
    }

    // Healing items
    inline for (players) |player| {
        var side = battle.side(player);
        var stored = side.stored();
        const ident = battle.active(player);

        const num = @intFromEnum(stored.item);
        if (num > @intFromEnum(Item.Berry)) {
            if (num <= @intFromEnum(Item.GoldBerry)) {
                const proc = if (showdown)
                    stored.hp <= stored.stats.hp
                else
                    stored.hp < stored.stats.hp;
                if (proc) {
                    assert(stored.hp != 0);
                    try options.log.enditem(ident, stored.item, .Eat);
                    stored.item = .None;

                    const offset = num - @intFromEnum(Item.Berry);
                    assert(offset < 3);
                    stored.hp = @min(stored.hp + ((offset + 1) * 10), stored.stats.hp);
                    const reason: Heal = @enumFromInt(@intFromEnum(Heal.Berry) + offset);
                    try options.log.heal(ident, stored, reason);
                }
            } else if (num < @intFromEnum(Item.BitterBerry)) {
                const proc = if (stored.item == .MiracleBerry)
                    Status.any(stored.status)
                else
                    Status.is(stored.status, @enumFromInt(num - @intFromEnum(Item.MintBerry) + 2));

                if (proc) {
                    assert(Status.any(stored.status));
                    try options.log.enditem(ident, stored.item, .Eat);
                    stored.item = .None;

                    // FIXME wtf?
                    // side.active.volatiles.Toxic = false;
                    // side.active.volatiles.NightMare = false;
                    if (stored.item == .MiracleBerry) {
                        side.active.volatiles.Confusion = false;
                        try options.log.end(ident, .Confusion);
                    }
                    stored.status = 0;

                    // FIXME recalc stats

                    try options.log.curestatus(ident, stored.status, .Message);
                }
            } else if (num == @intFromEnum(Item.BitterBerry)) {
                if (side.active.volatiles.Confusion) {
                    try options.log.enditem(ident, stored.item, .Eat);
                    stored.item = .None;

                    side.active.volatiles.Confusion = false;
                    try options.log.end(ident, .Confusion);
                }
            }
        }
    }

    // Encore
    inline for (players) |player| {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        if (volatiles.Encore) {
            assert(volatiles.encore > 0);
            volatiles.encore -= 1;

            if (volatiles.encore == 0 or side.active.moves(mslot).pp == 0) {
                volatiles.Encore = false;
                try options.log.end(battle.active(player), .Encore);
            }
        }
    }
}

inline fn updateSideCondition(
    battle: anytype,
    player: Player,
    comptime key: []const u8,
    comptime value: []const u8,
    options: anytype,
) !void {
    var side = battle.side(player);
    if (@field(side.conditions, key)) {
        assert(@field(side.conditions, value) > 0);
        @field(side.conditions, value) -= 1;

        if (@field(side.conditions, value) == 0) {
            @field(side.conditions, key) = false;
            try options.log.sideend(battle.active(player), @field(protocol.Side, key));
        }
    }
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

    const MAGNITUDE_POWER = [_]u8{ 10, 30, 50, 70, 90, 110, 150 };
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

    inline fn hit(battle: anytype, player: Player, accuracy: u8, options: anytype) !bool {
        const ok = if (options.calc.overridden(player, .hit)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, accuracy, 256)
        else
            battle.rng.next() < accuracy;

        try options.chance.hit(player, ok, accuracy);
        return ok;
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

    inline fn damage(battle: anytype, player: anytype, options: anytype) !u8 {
        const roll = if (options.calc.overridden(player, .damage)) |val|
            val
        else roll: {
            if (showdown) break :roll battle.rng.range(u8, 217, 256);
            while (true) {
                const r = std.math.rotr(u8, battle.rng.next(), 1);
                if (r >= 217) break :roll r;
            }
        };

        assert(roll >= 217 and roll <= 255);
        try options.chance.damage(player, roll);
        return roll;
    }

    inline fn confused(battle: anytype, player: Player, options: anytype) !bool {
        const cfz = if (options.calc.overridden(player, .confused)) |val|
            val == .true
        else if (showdown)
            !battle.rng.chance(u8, 128, 256)
        else
            battle.rng.next() >= Gen12.percent(50) + 1;

        try options.chance.confused(player, cfz);
        return cfz;
    }

    inline fn attract(battle: anytype, player: Player, options: anytype) !bool {
        const cant = if (options.calc.overridden(player, .attract)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 1, 2)
        else
            battle.rng.next() > Gen12.percent(50) + 1;

        try options.chance.attract(player, cant);
        return cant;
    }

    inline fn paralyzed(battle: anytype, player: Player, options: anytype) !bool {
        const par = if (options.calc.overridden(player, .paralyzed)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 63, 256)
        else
            battle.rng.next() < Gen12.percent(25);

        try options.chance.paralyzed(player, par);
        return par;
    }

    inline fn defrost(battle: anytype, player: Player, options: anytype) !bool {
        const thaw = if (options.calc.overridden(player, .defrost)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 25, 256)
        else
            battle.rng.next() < Gen12.percent(10);

        try options.chance.defrost(player, thaw);
        return thaw;
    }

    inline fn secondaryChance(battle: anytype, player: Player, rate: u8, options: anytype) !bool {
        // GLITCH: 100% secondary chance will still fail 1/256 of the time
        const proc = if (options.calc.overridden(player, .secondary_chance)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, rate, 256)
        else
            battle.rng.next() < rate;

        try options.chance.secondaryChance(player, proc, rate);
        return proc;
    }

    inline fn focusBand(battle: anytype, player: Player, options: anytype) !bool {
        const proc = if (options.calc.overridden(player, .focus_band)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 30, 256)
        else
            battle.rng.next() < 30;

        try options.chance.focusBand(player, proc);
        return proc;
    }

    inline fn kingsRock(battle: anytype, player: Player, options: anytype) !bool {
        const proc = if (options.calc.overridden(player, .kings_rock)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 30, 256)
        else
            battle.rng.next() < 30;

        try options.chance.kingsRock(player, proc);
        return proc;
    }

    inline fn sleepDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            @intCast(battle.rng.range(u8, 1, 7))
        else duration: {
            while (true) {
                const r = battle.rng.next() & 7;
                if (r != 0 and r != 7) break :duration @intCast(r);
            }
        };

        assert(duration >= 1 and duration <= 6);
        options.chance.duration(.sleep, player, player.foe(), duration);
        return duration + 1;
    }

    inline fn triAttack(battle: anytype, player: Player, options: anytype) !u8 {
        const status: TriAttack = if (options.calc.overridden(player, .tri_attack)) |val|
            val
        else if (showdown)
            @enumFromInt(battle.rng.range(u8, 0, 2))
        else loop: {
            while (true) {
                const r = std.math.rotr(u8, std.battle.rng.next(), 4) & 3;
                if (r != 0) break :loop @intCast(r - 1);
            }
        };

        try options.chance.triAttack(player, status);
        return status.status();
    }

    inline fn present(battle: anytype, player: Player, options: anytype) !u8 {
        const power = if (options.calc.overridden(player, .present)) |val|
            (val - 1) * 40
        else if (showdown) power: {
            const r = battle.rng.range(u8, 0, 10);
            if (r < 2) break :power 0;
            if (r < 6) break :power 40;
            if (r < 9) break :power 80;
            break :power 120;
        } else power: {
            const r = battle.rng.next();
            if (r <= Gen12.percent(40)) break :power 40;
            if (r <= Gen12.percent(70) + 1) break :power 80;
            if (r <= Gen12.percent(80)) break :power 120;
            break :power 0;
        };

        assert(power <= 120);
        try options.chance.present(player, power);
        return power;
    }

    inline fn magnitude(battle: anytype, player: Player, options: anytype) !u8 {
        const num = if (options.calc.overridden(player, .magnitude)) |val|
            val + 3
        else if (showdown) num: {
            const r = battle.rng.range(u8, 0, 100);
            if (r < 5) break :num 4;
            if (r < 15) break :num 5;
            if (r < 35) break :num 6;
            if (r < 65) break :num 7;
            if (r < 85) break :num 8;
            if (r < 95) break :num 9;
            break :num 10;
        } else num: {
            const r = battle.rng.next();
            if (r <= Gen12.percent(5) + 1) break :num 4;
            if (r <= Gen12.percent(15)) break :num 5;
            if (r <= Gen12.percent(35)) break :num 6;
            if (r <= Gen12.percent(65) + 1) break :num 7;
            if (r <= Gen12.percent(85) + 1) break :num 8;
            if (r <= Gen12.percent(95)) break :num 9;
            break :num 10;
        };

        assert(num >= 4 and num <= 10);
        try options.chance.magnitude(player, num);
        return num;
    }

    inline fn tripleKick(battle: anytype, player: Player, options: anytype) !u8 {
        const hits = if (options.calc.overridden(player, .triple_kick)) |val|
            val
        else if (showdown)
            battle.rng.range(u8, 1, 4)
        else power: {
            while (true) {
                const r = battle.rng.next() & 3;
                if (r != 0) break :power r - 1;
            }
        };

        assert(hits >= 1 and hits <= 3);
        try options.chance.tripleKick(player, hits);
        return hits;
    }

    inline fn spite(battle: anytype, player: Player, options: anytype) !u8 {
        const pp = if (options.calc.overridden(player, .spite)) |val|
            val + 1
        else if (showdown)
            battle.rng.range(u8, 2, 6)
        else
            (battle.rng.next() & 3) + 2;

        assert(pp >= 2 and pp <= 5);
        try options.chance.spite(player, pp);
        return pp;
    }

    // Conversion 2 can at most choose between 7 types (vs. a Grass-type attack)
    const CONVERSION_2: [7]Type = [_]Type{.{}} ** 7;

    inline fn conversion2(battle: anytype, player: Player, mtype: Type, options: anytype) !Type {
        var i: u8 = 0;
        const neutral = @intFromEnum(Effectiveness.Neutral);
        assert(mtype != .@"???");
        const ty: Type = if (options.calc.overridden(player, .conversion_2)) |val|
            @enumFromInt(@intFromEnum(val) - 1)
        else if (showdown) ty: {
            for (Type.SHOWDOWN) |t| {
                if (@intFromEnum(mtype.effectiveness(t)) < neutral) {
                    CONVERSION_2[i] = t;
                    i += 1;
                }
            }
            assert(i > 0 and i <= 7);
            break :ty CONVERSION_2[battle.rng.range(u8, 0, i)];
        } else ty: {
            while (true) {
                const r = battle.rng.next() & 0b11111;
                if (r == 6) continue; // BIRD
                if (r > 9 and r < 20) continue; // UNUSED_TYPES
                if (r > 27) continue; // TYPES_END

                const t = Types.conversion2(r);
                if (@intFromEnum(mtype.effectiveness(t)) < neutral) {
                    break :ty t;
                }
            }
        };

        assert(ty != .@"???");
        try options.chance.conversion2(player, ty, mtype, i);
        return ty;
    }

    // TODO thrashingDuration
    // TODO confusionDuraiton (from thrash vs. from move)
    // TODO forceSwitch
    // TODO bindingDuration
    // TODO bideDuration
    // TODO conversion moveSlot
    // TODO disable duration
    // TODO encore duration
    // TODO metronome
    // TODO protect
    // TODO sleeptalk move slot

    inline fn psywave(battle: anytype, player: Player, max: u8, options: anytype) !u8 {
        const power = if (options.calc.overridden(player, .psywave)) |val|
            val - 1
        else if (showdown)
            battle.rng.range(u8, 0, max)
        else power: {
            while (true) {
                const r = battle.rng.next();
                if (r < max) break :power r;
            }
        };

        assert(power < max);
        try options.chance.psywave(player, power, max);
        return power;
    }

    const METRONOME = init: {
        var num = 0;
        var moves: [238]Move = undefined;
        for (1..Move.size) |i| {
            if (Move.get(@enumFromInt(i)).extra.metronome) {
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

    var spe: rng.FixedRNG(2, expected.len) = .{ .rolls = expected };
    var qkc: rng.FixedRNG(2, expected.len) = .{ .rolls = expected };
    var cfz: rng.FixedRNG(2, expected.len) = .{ .rolls = expected };
    var atr: rng.FixedRNG(2, expected.len) = .{ .rolls = expected };
    var frz: rng.FixedRNG(2, expected.len) = .{ .rolls = expected };
    var fcb: rng.FixedRNG(2, expected.len) = .{ .rolls = expected };

    for (0..expected.len) |i| {
        try expectEqual(spe.range(u8, 0, 2) == 0, i < Gen12.percent(50) + 1);
        try expectEqual(qkc.chance(u8, 60, 256), i < 60);
        try expectEqual(!cfz.chance(u8, 128, 256), i >= Gen12.percent(50) + 1);
        try expectEqual(atr.chance(u8, 1, 2), i < Gen12.percent(50) + 1);
        try expectEqual(frz.chance(u8, 25, 256), i < Gen12.percent(10));
        try expectEqual(fcb.chance(u8, 30, 256), !(30 <= i));
    }
}

test "Roll probabilities" {
    if (showdown) return;

    var present = [4]u8{ 0, 0, 0, 0 };
    var magnitude = [7]u8{ 0, 0, 0, 0, 0, 0, 0 };
    for (0..256) |i| {
        present[
            if (i <= Gen12.percent(40))
                1
            else if (i <= Gen12.percent(70) + 1)
                2
            else if (i <= Gen12.percent(80))
                3
            else
                0
        ] += 1;
        magnitude[
            if (i <= Gen12.percent(5) + 1)
                0
            else if (i <= Gen12.percent(15) + 1)
                1
            else if (i <= Gen12.percent(35))
                2
            else if (i <= Gen12.percent(65) + 1)
                3
            else if (i <= Gen12.percent(85) + 1)
                4
            else if (i <= Gen12.percent(95))
                5
            else
                6
        ] += 1;
    }

    try expectEqualSlices(u8, &.{ 51, 103, 77, 25 }, &present);
    try expectEqualSlices(u8, &.{ 14, 26, 50, 77, 51, 25, 13 }, &magnitude);
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
