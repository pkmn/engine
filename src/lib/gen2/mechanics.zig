const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");
const util = @import("../common/util.zig");

const data = @import("data.zig");
const generated = @import("generated.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;

const showdown = pkmn.options.showdown;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const Activate = protocol.Activate;
const Boost = protocol.Boost;
const Cant = protocol.Cant;
const Damage = protocol.Damage;
const End = protocol.End;
const Heal = protocol.Heal;
const Start = protocol.Start;

const Gen12 = rng.Gen12;

const PointerType = util.PointerType;

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
const Weather = data.Weather;

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

pub const State = struct {
    damage: u16 = 0, // wCurDamage
    effectiveness: u16 = Effectiveness.neutral, // wTypeModifier
    bp: u8, // wPlayerMoveStructPower
    accuracy: u8, // wEnemyMoveStruct + MOVE_ACC
    move: Move, // wCurPlayerMove
    from: Move = .None,
    mslot: u4, // wCurMoveNum
    first: bool, // wEnemyGoesFirst
    miss: bool = false, // wAttackMissed
    crit: bool = false, // wCriticalHit = 1
    ohko: bool = false, // wCriticalHit = 2
    proc: bool = true, // wEffectFailed

    comptime {
        assert(@sizeOf(State) == 14);
    }

    pub fn immune(self: *State) bool {
        return self.effectiveness == 0;
    }
};

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

    try switchIn(battle, .P1, p1_slot, .Initial, options);
    try switchIn(battle, .P2, p2_slot, .Initial, options);

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
                    if (move.pp > 0 and volatiles.disable.move != i + 1) break :ok false;
                }
                break :ok true;
            };
            assert(struggle);
            // TODO wCurPlayerMove = .Struggle;
        } else {
            assert(showdown or side.active.volatiles.disable.move != choice.data);
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

const SwitchIn = enum { Initial, Switch, Drag };

fn switchIn(battle: anytype, player: Player, slot: u8, kind: SwitchIn, options: anytype) !void {
    var side = battle.side(player);
    var foe = battle.foe(player);

    var active = &side.active;
    const incoming = side.get(slot);

    assert(incoming.hp != 0);
    assert(slot != 1 or kind == .Initial);

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

    if (kind == .Drag) {
        try options.log.drag(battle.active(player), incoming);
    } else {
        try options.log.switched(battle.active(player), incoming);
    }
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

    if ((c1.type == .Switch) != (c2.type == .Switch)) {
        const m1 = .Pound; // TODO battle.side(.P1).last_selected_move;
        const m2 = .Pound; // TODO battle.side(.P2).last_selected_move;
        return if (c1.type == .Switch)
            if (m1 == .Pursuit) .P2 else .P1
        else if (m2 == .Pursuit) .P1 else .P2;
    }

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

    // Technically this happens at the very beginning of update but its unused until now
    // TODO: move into state and pass into betweenTurns
    volatiles.frozen = false;
    foe_volatiles.frozen = false;

    volatiles.DestinyBond = false;
    if (try executeMove(battle, player, player_choice, true, options)) |r| return r;
    foe_volatiles.Protect = false;
    foe_volatiles.Endure = false;
    foe_volatiles.DestinyBond = false;
    if (try checkFaint(battle, foe_player, options)) |r| return r;
    if (try handleResidual(battle, player, options)) {
        if (try checkFaint(battle, player, options)) |r| return r;
    }

    // foe_volatiles.DestinyBond = false;
    if (try executeMove(battle, foe_player, foe_choice, false, options)) |r| return r;
    volatiles.Protect = false;
    volatiles.Endure = false;
    volatiles.DestinyBond = false;
    if (try checkFaint(battle, player, options)) |r| return r;
    if (try handleResidual(battle, foe_player, options)) {
        if (try checkFaint(battle, foe_player, options)) |r| return r;
    }

    // FIXME
    return betweenTurns(battle, 0, options);
}

fn executeMove(
    battle: anytype,
    player: Player,
    choice: Choice,
    first: bool,
    options: anytype,
) !?Result {
    if (choice.type == .Switch) {
        try switchIn(battle, player, choice.data, .Switch, options);
        return null;
    }

    assert(choice.type == .Move);
    var mslot: u4 = @intCast(choice.data);
    var move = Move.Pound; // TODO

    if (!try beforeMove(battle, player, move, options)) return null;

    // FIXME: need damage from doTurn
    const m = Move.get(move);
    var state: State =
        .{ .move = move, .mslot = mslot, .first = first, .accuracy = m.accuracy, .bp = m.bp };
    try generated.runMove(battle, player, &state, options);
    return null;
}

fn beforeMove(battle: anytype, player: Player, move: Move, options: anytype) !bool {
    var log = options.log;
    var side = battle.side(player);
    // const foe = battle.foe(player);
    var active = &side.active;
    var stored = side.stored();
    const ident = battle.active(player);
    var volatiles = &active.volatiles;

    if (volatiles.Recharging) {
        volatiles.Recharging = false;
        resetCant(volatiles);
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
            resetCant(volatiles);
            volatiles.Nightmare = false;
        } else {
            try log.cant(ident, .Sleep);
            if (move == .Snore or move == .SleepTalk) break :slp;
            resetCant(volatiles);
            return false;
        }
    }

    if (Status.is(stored.status, .FRZ) and !(move == .FlameWheel or move == .SacredFire)) {
        resetCant(volatiles);
        try log.cant(ident, .Freeze);
        return false;
    }

    if (volatiles.Flinch) {
        // Pokémon Showdown doesn't clear Flinch until its imaginary "residual" phase, meaning
        // Pokémon can sometimes flinch multiple times from the same original hit
        // if (!showdown) volatiles.Flinch = false;
        volatiles.Flinch = false;
        resetCant(volatiles);
        try log.cant(ident, .Flinch);
        return false;
    }

    if (volatiles.disable.duration > 0) {
        // if (options.calc.modify(player, .disable)) |extend| {
        //     if (!extend) volatiles.disable.duration = 0;
        // } else {
        volatiles.disable.duration -= 1;
        // }
        try options.chance.disable(player, volatiles.disable.duration);

        if (volatiles.disable.duration == 0) {
            volatiles.disable.move = 0;
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
                resetCant(volatiles);

                // TODO HitConfusion

                return false;
            }
        }
    }

    if (volatiles.Attract) {
        try log.activate(ident, .Attract);

        if (try Rolls.attract(battle, player, options)) {
            resetCant(volatiles);
            try log.cant(ident, .Attract);
            return false;
        }
    }

    if (side.active.volatiles.disable.move != 0) {
        // A Pokémon that transforms after being disable may end up with less move slots
        const m = side.active.moves[side.active.volatiles.disable.move - 1].id;
        if (m != .None and m == move) {
            side.active.volatiles.Charging = false;
            resetCant(volatiles);
            try options.log.disabled(ident, move);
            return false;
        }
    }

    if (Status.is(stored.status, .PAR) and try Rolls.paralyzed(battle, player, options)) {
        resetCant(volatiles);
        try log.cant(ident, .Paralysis);
        return false;
    }

    return true;
}

fn resetCant(volatiles: *align(8) Volatiles) void {
    volatiles.Bide = false;
    volatiles.Thrashing = false;
    volatiles.Charging = false;
    volatiles.Underground = false;
    volatiles.Flying = false;
    volatiles.Rollout = false;

    volatiles.fury_cutter = 0;
}

pub fn canMove(battle: anytype, player: Player, state: *State, options: anytype) !bool {
    var side = battle.side(player);
    var volatiles = &side.active.volatiles;

    // FIXME: pass in target to avoid lookup?
    const target = if (Move.get(state.move).target == .Self) player else player.foe();
    try options.log.moveFrom(battle.active(player), state.move, battle.active(target), state.from);

    const charging = false; // TODO charging uses doUse
    const skip_pp = charging or state.move == .Struggle or
        (volatiles.BeatUp or volatiles.Thrashing or volatiles.Bide);
    if (!skip_pp) _ = decrementPP(side, state.move, state.mslot); // TODO if no pp return

    return true;
}

pub fn canCharge(battle: anytype, player: Player, state: *State, options: anytype) !bool {
    _ = battle;
    _ = player;
    _ = state;
    _ = options;
    // TODO skipsuncharge account for SolarBeam
    return true;
}

pub fn decrementPP(side: *Side, move: Move, mslot: u4) bool {
    var active = &side.active;
    const volatiles = &active.volatiles;

    assert(move != .Struggle);
    assert(!volatiles.Charging and !volatiles.BeatUp and !volatiles.Thrashing and !volatiles.Bide);

    var move_slot = active.move(mslot);
    if (move_slot.pp == 0) return false;

    move_slot.pp = @as(u6, @intCast(move_slot.pp)) -% 1;
    if (volatiles.Transform) return true;

    move_slot = side.stored().move(mslot);
    assert(move_slot.pp > 0);

    if (move_slot.id == .Mimic and move != .Mimic) return true;

    move_slot.pp = @as(u6, @intCast(move_slot.pp)) -% 1;
    assert(active.move(mslot).pp == side.stored().move(mslot).pp);

    return true;
}

pub fn doMove(
    comptime secondary: bool,
    battle: anytype,
    player: Player,
    state: *State,
    options: anytype,
) !bool {
    try checkCriticalHit(battle, player, state, options);
    try calcDamage(battle, player, state, options);
    try adjustDamage(battle, player, state, options);
    try randomizeDamage(battle, player, state, options);
    try checkHit(battle, player, state, options);
    if (secondary) try effectChance(battle, player, state, options);
    try applyDamage(battle, player, state, options);
    try reportOutcome(battle, player, state, options);
    if (try destinyBond(battle, player, state, options)) return false;
    try buildRage(battle, player, state, options);
    try kingsRock(battle, player, state, options);
    return true;
}

pub fn afterMove(
    comptime kings: bool,
    battle: anytype,
    player: Player,
    state: *State,
    options: anytype,
) !bool {
    if (try destinyBond(battle, player, state, options)) return false;
    try buildRage(battle, player, state, options);
    if (kings) try kingsRock(battle, player, state, options);
    return true;
}

pub fn checkCriticalHit(battle: anytype, player: Player, state: *State, options: anytype) !void {
    const move = Move.get(state.move);
    if (move.bp == 0) return;

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

    state.crit = try Rolls.criticalHit(battle, player, CRITICAL_HITS[stage], options);
}

pub fn calcDamage(
    battle: anytype,
    player: Player,
    state: *State,
    options: anytype,
) !void {
    _ = battle;
    _ = player;
    _ = state;
    _ = options;
}

const FORESIGHT: Types = .{ .type1 = .Normal, .type2 = .Fighting };

pub fn adjustDamage(battle: anytype, player: Player, state: *State, _: anytype) !void {
    if (state.move == .Struggle) return;

    const side = battle.side(player);
    const foe = battle.foe(player);
    const types = foe.active.types;
    const move = Move.get(state.move);

    var d = state.damage;
    if ((move.type == .Water and battle.field.weather == .Rain) or
        (move.type == .Fire and battle.field.weather == .Sun))
    {
        d = d *% @intFromEnum(Effectiveness.Super) / 10;
    } else if ((move.type == .Water and battle.field.weather == .Sun) or
        ((move.type == .Fire or state.move == .SolarBeam) and battle.field.weather == .Rain))
    {
        d = d *% @intFromEnum(Effectiveness.Resisted) / 10;
    }

    if (side.active.types.includes(move.type)) d +%= d / 2;

    const neutral = @intFromEnum(Effectiveness.Neutral);
    const foresight = foe.active.volatiles.Foresight and FORESIGHT.includes(move.type);
    const eff1: u16 = if (foresight and types.type1 == .Ghost)
        neutral
    else
        @intFromEnum(move.type.effectiveness(types.type1));
    const eff2: u16 = if (foresight and types.type2 == .Ghost)
        neutral
    else
        @intFromEnum(move.type.effectiveness(types.type2));

    // Type effectiveness matchup precedence only matters with (NVE, SE)
    if (!showdown and (eff1 + eff2) == Effectiveness.mismatch and
        types.type1.precedence() > types.type2.precedence())
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

    state.effectiveness = if (types.type1 == types.type2) eff1 * neutral else eff1 * eff2;
    state.damage = d;
}

pub fn randomizeDamage(battle: anytype, player: Player, state: *State, options: anytype) !void {
    if (state.damage <= 1) return;
    const random = try Rolls.damage(battle, player, options);
    options.calc.base(player.foe(), state.damage);
    state.damage = @intCast(@as(u32, state.damage) *% random / 255);
    options.calc.final(player.foe(), state.damage);
}

pub fn applyDamage(
    battle: anytype,
    player: Player,
    state: *State,
    options: anytype,
) !void {
    // TODO failuretext (if not Bide) + applydamage
    _ = battle;
    _ = player;
    _ = state;
    _ = options;
}

// TODO: set damage = 0 if missed and not (High) Jump Kick
pub fn checkHit(
    battle: anytype,
    player: Player,
    state: *State,
    options: anytype,
) !void {
    const side = battle.side(player);
    const foe = battle.foe(player);

    const move = Move.get(state.move);

    if (move.effect == .DreamEater and !Status.is(foe.stored().status, .SLP)) {
        state.miss = true;
        return;
    }
    if (foe.active.volatiles.Protect) {
        state.miss = true;
        return;
    }
    const drain = move.effect == .DrainHP or move.effect == .DreamEater;
    if (drain and foe.active.volatiles.Substitute) {
        state.miss = true;
        return;
    }
    if (side.active.volatiles.LockOn) {
        state.miss = !(foe.active.volatiles.Flying and move.extra.underground);
        return;
    }
    assert(!(foe.active.volatiles.Flying and foe.active.volatiles.Underground));
    if (foe.active.volatiles.Flying) {
        if (!move.extra.flying) {
            state.miss = true;
            return;
        }
    } else if (foe.active.volatiles.Underground) {
        if (!move.extra.underground) {
            state.miss = true;
            return;
        }
    }
    if (move.effect == .Thunder) {
        if (battle.field.weather == .Rain) {
            state.miss = false;
            return;
        } else if (battle.field.weather == .Sun) {
            // This latter part gets applied in a separate Thunder accuracy handler
            // on the cartridge but it makes more sense to just do it here
            state.accuracy = Gen12.percent(50) + 1;
        }
    }
    if (move.effect == .AlwaysHit) {
        state.miss = false;
        return;
    }

    var accuracy: u16 = state.accuracy;
    assert(accuracy > 0);
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
    state.miss = if (accuracy == 255)
        false
    else
        !try Rolls.hit(battle, player, @intCast(accuracy), options);
}

fn checkFaint(
    battle: anytype,
    player: Player,
    options: anytype,
) @TypeOf(options.log).Error!?Result {
    const side = battle.side(player);
    const foe = battle.foe(player);

    const player_fainted = side.stored().hp == 0;
    const foe_fainted = foe.stored().hp == 0;
    if (!(player_fainted or foe_fainted)) return null;

    const player_out = player_fainted and findFirstAlive(side) == 0;
    const foe_out = foe_fainted and findFirstAlive(foe) == 0;
    const more = player_out or foe_out;

    if (player_fainted) try faint(battle, player, !(more or foe_fainted), options);
    if (foe_fainted) try faint(battle, player.foe(), !more, options);

    if (player_out and foe_out) {
        try options.log.tie();
        return Result.Tie;
    } else if (player_out) {
        try options.log.win(player.foe());
        return if (player == .P1) Result.Lose else Result.Win;
    } else if (foe_out) {
        try options.log.win(player);
        return if (player == .P1) Result.Win else Result.Lose;
    }

    const foe_choice: Choice.Type = if (foe_fainted) .Switch else .Pass;
    if (player == .P1) return .{ .p1 = .Switch, .p2 = foe_choice };
    return .{ .p1 = foe_choice, .p2 = .Switch };
}

fn faint(battle: anytype, player: Player, done: bool, options: anytype) !void {
    var side = battle.side(player);
    var foe = battle.foe(player);
    assert(side.stored().hp == 0);

    var foe_volatiles = &foe.active.volatiles;
    foe_volatiles.BeatUp = false;

    // We always need to clear status for Pokémon Showdown's Sleep/Freeze Clause Mod
    const status = side.stored().status;

    side.stored().status = 0;
    // This shouldn't matter, but Pokémon Showdown decides double switching priority based on speed,
    // and resets a Pokémon's stats when it faints... only it still factors in paralysis -_-
    if (showdown) {
        side.active.stats.spe = if (Status.is(status, .PAR))
            @max(side.stored().stats.spe / 4, 1)
        else
            side.stored().stats.spe;
    }

    try options.log.faint(battle.active(player), done);
    options.calc.capped(player);
}

// TODO: see if we can move *before* applyDamage and include failuretext logic
pub fn reportOutcome(battle: anytype, player: Player, state: *State, options: anytype) !void {
    const foe_ident = battle.active(player.foe());
    if (state.crit) try options.log.crit(foe_ident);
    if (!state.immune()) {
        if (state.effectiveness > Effectiveness.neutral) {
            try options.log.supereffective(foe_ident);
        } else if (state.effectiveness < Effectiveness.neutral) {
            try options.log.resisted(foe_ident);
        }
    }
}

pub fn effectChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
    const rate = Move.get(state.move).chance;
    assert(rate > 0);
    // FIXME: only commit secondary chance roll if effect actually is successful (doesn't fail)
    state.proc = !battle.foe(player).active.volatiles.Substitute and
        try Rolls.secondaryChance(battle, player, rate, options);
}

fn handleResidual(battle: anytype, player: Player, options: anytype) !bool {
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
        if (stored.hp == 0) return true;
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
        if (stored.hp == 0) return true;
    }

    if (volatiles.Nightmare) {
        stored.hp -= @max(stored.stats.hp / 4, 1);
        // ibid
        try options.log.damage(ident, stored, .Nightmare);
        if (stored.hp == 0) return true;
    }

    if (volatiles.Curse) {
        stored.hp -= @max(stored.stats.hp / 4, 1);
        // ibid
        try options.log.damage(ident, stored, .Curse);
        if (stored.hp == 0) return true;
    }

    return false;
}

fn betweenTurns(battle: anytype, mslot: u4, options: anytype) !?Result {
    const players = comptime std.enums.values(Player);

    if (try checkFaint(battle, .P1, options)) |r| return r;

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
    if (try checkFaint(battle, .P1, options)) |r| return r;

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
                    if (!(active.volatiles.Underground or active.types.sandstormImmune())) {
                        side.stored().hp -|= @max(side.stored().stats.hp / 8, 1);
                        try options.log.damage(battle.active(player), side.stored(), .Sandstorm);
                    }
                }
                if (try checkFaint(battle, .P1, options)) |r| return r;
            }
        }
    }

    // Binding
    inline for (players) |player| {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        if (volatiles.bind.duration > 0 and !volatiles.Substitute) {
            volatiles.bind.duration -= 1;
            if (volatiles.bind.duration == 0) {
                const reason = @intFromEnum(End.Bind) + volatiles.bind.reason - 1;
                try options.log.end(battle.active(player), @enumFromInt(reason));
            } else {
                var reason = @intFromEnum(Activate.Bind) + volatiles.bind.reason - 1;
                try options.log.activate(battle.active(player), @enumFromInt(reason));

                reason = @intFromEnum(Damage.Bind) + volatiles.bind.reason - 1;
                side.stored().hp -|= @max(side.stored().stats.hp / 16, 1);
                try options.log.damage(battle.active(player), side.stored(), @enumFromInt(reason));
            }
        }
    }
    if (try checkFaint(battle, .P1, options)) |r| return r;

    // Perish Song
    inline for (players) |player| {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        if (volatiles.PerishSong) {
            assert(volatiles.perish_song > 0);
            volatiles.perish_song -= 1;

            assert(volatiles.perish_song < 3);
            const reason = @intFromEnum(Start.PerishSong0) + volatiles.perish_song;
            try options.log.start(battle.active(player), @enumFromInt(reason));

            if (volatiles.perish_song == 0) {
                volatiles.PerishSong = false;
                side.stored().hp = 0;
            }
        }
    }
    if (try checkFaint(battle, .P1, options)) |r| return r;

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
            try updateSideCondition(battle, player, "Reflect", "reflect", options);
        }
        inline for (players) |player| {
            try updateSideCondition(battle, player, "LightScreen", "light_screen", options);
        }
        inline for (players) |player| {
            try updateSideCondition(battle, player, "Safeguard", "safeguard", options);
        }
    } else {
        inline for (players) |player| {
            try updateSideCondition(battle, player, "Safeguard", "safeguard", options);
        }
        inline for (players) |player| {
            try updateSideCondition(battle, player, "LightScreen", "light_screen", options);
            try updateSideCondition(battle, player, "Reflect", "reflect", options);
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
                    // side.active.volatiles.Nightmare = false;
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

            if (volatiles.encore == 0 or side.active.move(mslot).pp == 0) {
                volatiles.Encore = false;
                try options.log.end(battle.active(player), .Encore);
            }
        }
    }

    return null;
}

fn updateSideCondition(
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
            try options.log.sideend(player, @field(protocol.Side, key));
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

pub fn buildRage(battle: anytype, player: Player, state: *State, options: anytype) !void {
    assert(!state.miss); // TODO
    var foe = battle.foe(player);
    if (foe.active.volatiles.Rage) {
        if (showdown) {
            // TODO if showdown boost
            if (foe.active.boosts.atk < 6) {
                try Effects.boost(battle, player, state, options);
            }
        } else {
            foe.active.volatiles.rage +|= 1;
            try options.log.activate(battle.active(player), .Rage);
        }
    }
}

pub fn kingsRock(battle: anytype, player: Player, state: *State, options: anytype) !void {
    assert(!state.miss); // TODO
    var foe = battle.foe(player);
    const flinch = battle.side(player).stored().item == .KingsRock and
        !foe.active.volatiles.Substitute and
        try Rolls.item(battle, player, options);
    if (flinch) {
        foe.active.volatiles.Recharging = false;
        foe.active.volatiles.Flinch = true;
    }
}

pub fn destinyBond(battle: anytype, player: Player, _: *State, options: anytype) !bool {
    const foe = battle.foe(player);
    if (foe.stored().hp > 0) return false;

    if (foe.active.volatiles.DestinyBond) {
        battle.side(player).stored().hp = 0;
        try options.log.activate(battle.active(player.foe()), .DestinyBond);
    }
    return true;
}

pub const Effects = struct {
    pub fn attract(battle: anytype, player: Player, _: *State, options: anytype) !void {
        const side = battle.side(player);
        var foe = battle.foe(player);

        const gender: u8 = @intFromEnum(side.stored().dvs.gender);
        const foe_gender: u8 = @intFromEnum(foe.stored().dvs.gender);
        if (gender + foe_gender != 1) {
            return options.log.immune(battle.active(player.foe()), .None);
        } else if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
            try options.log.lastmiss();
            return options.log.miss(battle.active(player));
        }

        foe.active.volatiles.Attract = true;
        try options.log.start(battle.active(player.foe()), .Attract);
    }

    pub fn batonPass(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn beatUp(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn bellyDrum(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub const bide = struct {
        pub fn store(battle: anytype, player: Player, state: *State, options: anytype) !void {
            var side = battle.side(player);
            var volatiles = &side.active.volatiles;

            const ident = battle.active(player);

            if (!volatiles.Bide) return;

            assert(volatiles.attacks > 0);
            // if (options.calc.modify(player, .attacking)) |extend| {
            //     if (!extend) volatiles.attacks = 0;
            // } else {
            volatiles.attacks -= 1;
            // }
            try options.chance.attacking(player, volatiles.attacks);

            if (volatiles.attacks != 0) return options.log.activate(ident, .Bide);

            volatiles.Bide = false;
            try options.log.end(ident, .Bide);

            state.damage = volatiles.bide *% 2;
            volatiles.bide = 0;

            if (state.damage == 0) state.miss = true;
        }

        pub fn unleash(battle: anytype, player: Player, state: *State, options: anytype) !void {
            _ = .{ battle, player, state, options }; // TODO
        }
    };

    pub fn binding(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn burnChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute) return;
        if (Status.any(foe_stored.status)) {
            if (Status.is(foe_stored.status, .FRZ)) {
                assert(Move.get(state.move).type == .Fire);
                try options.log.curestatus(
                    battle.active(player.foe()),
                    foe_stored.status,
                    .Message,
                );
                foe_stored.status = 0;
            }
            return;
        }
        if (!state.proc) return;
        if (foe.conditions.Safeguard) return;
        // Nothing is immune to Fire-type, but Ghosts are immune to burnChance called by Tri Attack
        if (state.immune()) return;
        if (foe.active.types.includes(Move.get(state.move).type)) return;

        foe_stored.status = Status.init(.BRN);
        foe.active.stats.atk = @max(foe.active.stats.atk / 2, 1);
        try options.log.status(battle.active(player.foe()), foe_stored.status, .None);

        // TODO: check for status berry
    }

    pub fn confusion(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn confusionChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn conversion(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);

        var n: u3 = 0;
        for (side.active.moves) |m| {
            if (convertible(side.active, m.id)) n += 1;
        }
        if (n == 0) return options.log.fail(battle.active(player), .None);

        side.active.types.type1 = try Rolls.conversion(battle, player, n, options);
        side.active.types.type2 = side.active.types.type1;
    }

    pub fn conversion2(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);

        const last = battle.foe(player).lastMove(false);
        if (last == .None) return options.log.fail(battle.active(player), .None);
        const move = Move.get(last);
        if (move.type == .@"???") return options.log.fail(battle.active(player), .None);

        side.active.types.type1 = try Rolls.conversion2(battle, player, move.type, options);
        side.active.types.type2 = side.active.types.type1;
    }

    pub fn counter(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn curse(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn defenseCurl(battle: anytype, player: Player, _: *State, _: anytype) !void {
        battle.side(player).active.volatiles.DefenseCurl = true;
    }

    pub fn defrost(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);
        assert(Status.is(side.stored().status, .FRZ));

        try options.log.curestatus(battle.active(player), side.stored().status, .Message);
        side.stored().status = 0;
    }

    pub fn destinyBond(battle: anytype, player: Player, _: *State, options: anytype) !void {
        battle.side(player).active.volatiles.DestinyBond = true;
        try options.log.singlemove(battle.active(player), Move.DestinyBond);
    }

    pub fn disable(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var volatiles = &foe.active.volatiles;
        const foe_ident = battle.active(player.foe());

        if (volatiles.disable.move != 0) {
            return options.log.fail(foe_ident, .None);
        }

        const last = battle.foe(player).lastMove(false);
        if (last == .None or last == .Struggle) {
            return options.log.fail(foe_ident, .None);
        }

        var slot: u3 = 0;
        for (foe.active.moves) |m| {
            assert(m.id != .None);
            slot += 1;
            if (m.id == last) break;
        }
        const move = foe.active.move(slot);
        if (move.pp == 0) return options.log.fail(foe_ident, .None);

        volatiles.disable.move = slot;
        volatiles.disable.duration = Rolls.disableDuration(battle, player, options);

        try options.log.startEffect(foe_ident, .Disable, move.id);
    }

    pub const double = struct {
        pub fn flying(battle: anytype, player: Player, state: *State, _: anytype) !void {
            if (battle.foe(player).active.volatiles.Flying) state.damage *|= 2;
        }

        pub fn underground(battle: anytype, player: Player, state: *State, _: anytype) !void {
            if (battle.foe(player).active.volatiles.Underground) state.damage *|= 2;
        }

        pub fn minimize(battle: anytype, player: Player, state: *State, _: anytype) !void {
            if (battle.foe(player).active.volatiles.minimized) state.damage *|= 2;
        }
    };

    pub fn drainHP(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var stored = battle.side(player).stored();

        assert(state.damage != 0);

        if (stored.hp == stored.stats.hp) return;
        stored.hp = @min(stored.stats.hp, stored.hp + @max(state.damage / 2, 1));

        try options.log.drain(battle.active(player), stored, battle.active(player.foe()));
    }

    pub fn encore(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var volatiles = &foe.active.volatiles;
        const foe_ident = battle.active(player.foe());

        const last = battle.foe(player).lastMove(true);
        const failed = volatiles.Encore or
            (last == .None or last == .Struggle or
            last == .Encore or .last == .MirrorMove);
        if (failed) return options.log.fail(foe_ident, .None);

        var slot: u3 = 0;
        for (foe.active.moves) |m| {
            assert(m.id != .None);
            slot += 1;
            if (m.id == last) break;
        }
        const move = foe.active.move(slot);
        if (move.pp == 0) return options.log.fail(foe_ident, .None);

        volatiles.Encore = true;
        volatiles.encore = Rolls.encoreDuration(battle, player, options);

        // TODO ???
        _ = state;

        try options.log.startEffect(foe_ident, .Encore, move.id);
    }

    pub fn explode(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn falseSwipe(battle: anytype, player: Player, state: *State, _: anytype) !void {
        const foe = battle.foe(player);
        assert(foe.stored().hp > 0);
        // FIXME crit?
        if (state.damage > foe.stored().hp) state.damage = foe.stored().hp - 1;
    }

    pub fn fixedDamage(battle: anytype, player: Player, state: *State, options: anytype) !void {
        const side = battle.side(player);
        const foe = battle.foe(player);

        state.damage = switch (Move.get(state.move).effect) {
            .SuperFang => @max(foe.stored().hp / 2, 1),
            .LevelDamage => side.stored().level,
            .FixedDamage => if (state.move == .SonicBoom) 20 else 40,
            .Psywave => try Rolls.psywave(
                battle,
                player,
                @intCast(@as(u16, side.stored().level) * 3 / 2),
                options,
            ),
            else => unreachable,
        };
    }

    pub fn flinchChance(battle: anytype, player: Player, state: *State, _: anytype) !void {
        const foe = battle.foe(player);
        const status = foe.stored().status;
        var volatiles = &foe.active.volatiles;

        if (volatiles.Substitute) return;
        if (Status.is(status, .FRZ) or Status.is(status, .SLP)) return;
        if (!state.first) return;
        if (!state.proc) return;

        volatiles.Flinch = true;
        volatiles.Recharging = false;
    }

    pub fn flyDig(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn focusEnergy(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.FocusEnergy) {
            if (!showdown) try options.log.fail(battle.active(player), .None);
            return;
        }

        side.active.volatiles.FocusEnergy = true;
        try options.log.start(battle.active(player), .FocusEnergy);
    }

    var SLOTS: [5]u4 = .{ 0, 0, 0, 0, 0 };

    pub fn forceSwitch(battle: anytype, player: Player, state: *State, options: anytype) !void {
        assert(!state.miss); // FIXME ensure checkHit handles fail message

        const foe = battle.foe(player);

        if (state.first) return options.log.fail(battle.active(player), .None);

        var n: u4 = 0;
        var i: u4 = 0;
        for (foe.pokemon, 0..) |pokemon, j| {
            if (pokemon.species == .None) break;
            n += 1;
            if (pokemon.position == 1) continue;
            if (pokemon.hp > 0) {
                SLOTS[i] = @intCast(foe.pokemon[j].position);
                i += 1;
            }
        }

        if (n == 0) return options.log.fail(battle.active(player), .None);

        const slot = try Rolls.forceSwitch(battle, player, SLOTS[0..i], n, options);
        try switchIn(battle, player.foe(), slot, .Drag, options);
    }

    pub fn foresight(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var foe = battle.foe(player);

        if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
            try options.log.lastmiss();
            return options.log.miss(battle.active(player));
        } else if (foe.active.volatiles.Foresight) {
            return options.log.fail(battle.active(player), .None);
        }

        foe.active.volatiles.Foresight = true;
        try options.log.start(battle.active(player.foe()), .FocusEnergy);
    }

    pub fn freezeChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Substitute) return;
        if (Status.any(foe_stored.status)) return;

        // Nothing is immune to Ice-type, but Ghosts are immune to freezeChance called by Tri Attack
        if (battle.field.weather == .Sun) return;
        if (foe.active.types.includes(Move.get(state.move).type)) return;
        if (!state.proc) return;
        if (foe.conditions.Safeguard) return;
        // Freeze Clause Mod
        if (showdown) for (foe.pokemon) |p| if (Status.is(p.status, .FRZ)) return;

        foe_stored.status = Status.init(.FRZ);
        try options.log.status(foe_ident, foe_stored.status, .None);

        // TODO: check for status berry

        foe.active.volatiles.Recharging = false;
        foe.active.volatiles.frozen = true;
    }

    pub fn furyCutter(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn futureSight(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn happiness(battle: anytype, player: Player, state: *State, _: anytype) !void {
        const val = battle.side(player).stored().happiness;
        const frustration = Move.get(state.move).effect == .Frustration;
        state.bp = ((if (frustration) 255 - val else val) * 10) / 25;
    }

    pub fn haze(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn heal(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn healBell(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn hiddenPower(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn hyperBeam(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn leechSeed(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn lockOn(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    const MAGNITUDE_POWER = [_]u8{ 10, 30, 50, 70, 90, 110, 150 };

    pub fn magnitude(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn meanLook(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn metronome(
        battle: anytype,
        player: Player,
        state: *State,
        options: anytype,
    ) anyerror!void {
        var side = battle.side(player);

        side.last_used_move = .None;
        side.active.volatiles.dirty = false;

        // if (wPlayerCharging) ???
        // wPlayerCharging = 1

        // FIXME
        state.move = try Rolls.metronome(battle, player, options);
        state.from = .Metronome;
        return generated.runMove(battle, player, state, options);
    }

    pub fn mimic(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn mirrorCoat(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn mirrorMove(
        battle: anytype,
        player: Player,
        state: *State,
        options: anytype,
    ) anyerror!void {
        var side = battle.side(player);
        const foe = battle.foe(player);

        side.last_used_move = .None;
        side.active.volatiles.dirty = false;

        const last = foe.lastMove(false);

        if (last == .None) return options.log.fail(battle.active(player), .None);
        const knows = knows: for (side.active.moves) |m| {
            if (last == m.id) break :knows true;
        } else false;
        if (knows) return options.log.fail(battle.active(player), .None);

        // if (wPlayerCharging) ???
        // wPlayerCharging = 1

        // FIXME
        state.move = last;
        state.from = .MirrorMove;
        return generated.runMove(battle, player, state, options);
    }

    pub fn mist(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.Mist) return options.log.fail(battle.active(player), .None);
        side.active.volatiles.Mist = true;

        try options.log.start(battle.active(player), .Mist);
    }

    pub fn weatherHeal(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var stored = battle.side(player).stored();
        const ident = battle.active(player);

        if (stored.hp == stored.stats.hp) return options.log.fail(ident, .None);

        stored.hp = switch (battle.field.weather) {
            .Sun => stored.stats.hp,
            .None => @min(stored.stats.hp, stored.hp + (stored.stats.hp / 2)),
            else => @min(stored.stats.hp, stored.hp + (stored.stats.hp / 4)),
        };

        try options.log.heal(ident, stored, Heal.None);
    }

    pub fn multiHit(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn nightmare(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_volatiles = &foe.active.volatiles;
        const foe_ident = battle.active(player.foe());

        if (foe_volatiles.Flying or foe_volatiles.Underground) {
            if (!showdown) return options.log.fail(battle.active(player.foe()), .None);
            try options.log.lastmiss();
            return options.log.miss(battle.active(player));
        } else if (foe_volatiles.Substitute) {
            return options.log.activateMove(foe_ident, .SubstituteBlock, state.move);
        } else if (!Status.is(foe.stored().status, .SLP) or foe_volatiles.Nightmare) {
            return options.log.fail(foe_ident, .None);
        }

        foe_volatiles.Nightmare = true;
        try options.log.start(battle.active(player.foe()), .Nightmare);
    }

    pub const ohko = struct {
        // OHKO calls adjustDamage but only actually cares about immunity
        pub fn immune(battle: anytype, player: Player, state: *State, _: anytype) !void {
            const move = Move.get(state.move);

            assert(move.type == .Normal or move.type == .Ground);
            const foe = battle.foe(player);
            const zero = if (move.type == .Normal)
                foe.active.types.includes(.Ghost) and !foe.active.volatiles.Foresight
            else
                foe.active.types.includes(.Flying);
            state.effectiveness = if (zero) 0 else Effectiveness.neutral;
        }

        pub fn damage(battle: anytype, player: Player, state: *State, options: anytype) !void {
            const side = battle.side(player);
            const foe = battle.foe(player);

            const foe_ident = battle.active(player.foe());

            state.damage = 0;
            if (state.immune()) return options.log.immune(foe_ident, .None);
            const delta = side.stored().level -| foe.stored().level;
            if (delta == 0) return options.log.immune(foe_ident, .OHKO);

            state.accuracy = 2 * delta +| Gen12.percent(30);
            try checkHit(battle, player, state, options);
            if (!state.miss) state.damage = 65535;
            state.ohko = true;
        }
    };

    pub fn painSplit(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        const ident = battle.active(player);
        const foe_ident = battle.active(player.foe());

        if (state.miss) return options.log.fail(foe_ident, .None);
        if (foe.active.volatiles.Substitute) {
            return options.log.activateMove(foe_ident, .SubstituteBlock, state.move);
        }

        const avg = @max((foe.stored().hp + side.stored().hp) / 2, 1);
        foe.stored().hp -= avg;
        side.stored().hp = avg;

        try options.log.sethp(foe_ident, foe.stored(), .Silent);
        try options.log.sethp(ident, side.stored(), .None);
    }

    pub fn paralyze(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn paralyzeChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute) return;
        if (Status.any(foe_stored.status)) return;
        if (state.immune()) return;
        if (!state.proc) return;
        if (foe.conditions.Safeguard) return;

        foe_stored.status = Status.init(.PAR);
        foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);
        try options.log.status(battle.active(player.foe()), foe_stored.status, .None);

        // TODO: check for status berry
    }

    pub fn payDay(battle: anytype, player: Player, _: *State, options: anytype) !void {
        if (!showdown or !battle.foe(player).active.volatiles.Substitute) {
            try options.log.fieldactivate(); // FIXME .PayDay
        }
    }

    pub fn perishSong(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        if (foe.active.volatiles.PerishSong) {
            return options.log.fail(battle.active(player.foe()), .None);
        } else if (!side.active.volatiles.PerishSong) {
            side.active.volatiles.PerishSong = true;
            side.active.volatiles.perish_song = 4;
            try options.log.start(battle.active(player), .PerishSong3Silent);
        }
        foe.active.volatiles.PerishSong = true;
        foe.active.volatiles.perish_song = 4;
        try options.log.start(battle.active(player.foe()), .PerishSong3Silent);

        try options.log.fieldactivate(); // FIXME .PerishSong
    }

    pub fn poison(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        const toxic = state.move == .Toxic;
        if (state.immune() or foe.active.types.includes(.Poison)) {
            return options.log.immune(foe_ident, .None);
        } else if (Status.any(foe_stored.status)) {
            // Pokémon Showdown considers Toxic to be a status even in Generation II and so
            // will not include a fail reason for Toxic vs. Poison or vice-versa...
            return options.log.fail(foe_ident, if (Status.is(foe_stored.status, .PSN))
                if (!showdown)
                    .Poison
                else if (toxic == (foe_stored.status == Status.TOX))
                    if (toxic) .Toxic else .Poison
                else
                    .None
            else
                .None);
        } else if (foe.active.volatiles.Substitute) {
            return options.log.activateMove(foe_ident, .SubstituteBlock, state.move);
        } else if (state.miss) {
            try options.log.lastmiss();
            try options.log.miss(battle.active(player));
        }

        foe_stored.status = Status.init(.PSN);
        if (toxic) {
            if (showdown) foe_stored.status = Status.TOX;
            foe.active.volatiles.Toxic = true;
            foe.active.volatiles.toxic = 0;
        }

        try options.log.status(foe_ident, foe_stored.status, .None);

        // TODO: check for status berry
    }

    pub fn poisonChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute) return;
        if (Status.any(foe_stored.status)) return if (showdown) battle.rng.advance(1);
        if (state.immune() or foe.active.types.includes(.Poison)) return;
        if (!state.proc) return;
        if (foe.conditions.Safeguard) return;

        foe_stored.status = Status.init(.PSN);
        try options.log.status(battle.active(player.foe()), foe_stored.status, .None);

        // TODO: check for status berry
    }

    pub fn present(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    pub fn protect(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        const failed = !state.first or volatiles.Substitute or
            !try Rolls.protect(battle, player, volatiles.protect, options);
        if (failed) {
            return options.log.fail(battle.active(player), .None);
        }

        volatiles.protect = @max(8, volatiles.protect + 1);
        if (state.move == .Endure) {
            volatiles.Endure = true;
        } else {
            volatiles.Protect = true;
        }
        try options.log.singleturn(battle.active(player), state.move);
    }

    pub fn psychUp(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);
        const foe = battle.foe(player);

        // Pokémon Showdown should fail when the enemy has no boosts/unboosts but doesn't
        if (!showdown and @as(u32, @bitCast(foe.active.boosts)) == 0) {
            return options.log.fail(battle.active(player), .None);
        }

        side.active.boosts = foe.active.boosts;
        try options.log.copyboost(battle.active(player), battle.active(player.foe()));
    }

    pub fn pursuit(battle: anytype, player: Player, state: *State, _: anytype) !void {
        // TODO: remove switching variable and just look at Choice saved in Battle struct?
        if (battle.foe(player).active.volatiles.switching) state.damage *|= 2;
    }

    pub const rage = struct {
        pub fn start(battle: anytype, player: Player, _: *State, options: anytype) !void {
            battle.side(player).active.volatiles.Rage = true;
            try options.log.singlemove(battle.active(player), Move.Rage);
        }

        pub fn damage(battle: anytype, player: Player, state: *State, _: anytype) !void {
            var side = battle.side(player);
            var volatiles = &side.active.volatiles;

            assert(volatiles.Rage);
            state.damage *|= (volatiles.rage +| 1);
        }
    };

    pub fn rainDance(battle: anytype, _: Player, _: *State, options: anytype) !void {
        return weather(battle, .Rain, options);
    }

    pub fn rapidSpin(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.LeechSeed) {
            try options.log.end(battle.active(player), .LeechSeedFrom);
            side.active.volatiles.LeechSeed = false;
        }

        if (side.conditions.Spikes) {
            try options.log.spikesend(battle.active(player));
            side.conditions.Spikes = false;
        }

        if (side.active.volatiles.bind.duration > 0) {
            const reason = @intFromEnum(End.Bind) + side.active.volatiles.bind.reason - 1;
            try options.log.end(battle.active(player), @enumFromInt(reason));
            side.active.volatiles.bind = .{};
        }
    }

    pub fn recoil(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var side = battle.side(player);
        var stored = side.stored();

        assert(state.damage > 0);

        const damage: i16 = @intCast(@max(state.damage / 4, 1));
        stored.hp = @intCast(@max(@as(i16, @intCast(stored.hp)) - damage, 0));

        try options.log.damageOf(
            battle.active(player),
            stored,
            .RecoilOf,
            battle.active(player.foe()),
        );
    }

    pub fn reversal(battle: anytype, player: Player, state: *State, options: anytype) !void {
        const stored = battle.side(player).stored();

        // Pokémon Showdown Gen II implementation incorrectly inherits Gen IV's table instead
        state.bp = if (showdown) power: {
            const x = @max(1, stored.hp * 64 / stored.stats.hp);
            if (x < 2) break :power 200;
            if (x < 6) break :power 150;
            if (x < 13) break :power 100;
            if (x < 22) break :power 80;
            if (x < 43) break :power 40;
            break :power 20;
        } else power: {
            const x = @max(1, stored.hp * 48 / stored.stats.hp);
            if (x < 1) break :power 200;
            if (x < 4) break :power 150;
            if (x < 9) break :power 100;
            if (x < 16) break :power 80;
            if (x < 32) break :power 40;
            break :power 20;
        };

        try calcDamage(battle, player, state, options);
    }

    pub const rollout = struct {
        pub fn check(battle: anytype, player: Player, _: *State, _: anytype) !void {
            var side = battle.side(player);

            if (!side.active.volatiles.Rollout) {
                side.active.volatiles.attacks = 0;
            } else {
                // TODO SkipToBattleCommand(doturn_command)
            }
        }

        pub fn power(battle: anytype, player: Player, state: *State, _: anytype) !void {
            var side = battle.side(player);

            if (Status.is(side.stored().status, .SLP)) return;

            if (side.active.volatiles.attacks > 0) {
                // TODO set wSomeoneIsRampaging
            }

            if (state.miss) {
                side.active.volatiles.Rollout = false;
                return;
            }

            assert(side.active.volatiles.attacks < 5);
            side.active.volatiles.attacks += 1;
            side.active.volatiles.Rollout = side.active.volatiles.attacks != 5;

            if (side.active.volatiles.DefenseCurl) state.damage *|= 2;
        }
    };

    pub fn sandstorm(battle: anytype, player: Player, _: *State, options: anytype) !void {
        if (battle.field.weather != .Sandstorm) return weather(battle, .Sandstorm, options);
        return options.log.fail(battle.active(player), .None);
    }

    pub fn safeguard(battle: anytype, player: Player, _: *State, options: anytype) !void {
        return screens(battle, player, "Safeguard", "safeguard", options);
    }

    pub fn reflect(battle: anytype, player: Player, _: *State, options: anytype) !void {
        return screens(battle, player, "Reflect", "reflect", options);
    }

    pub fn lightScreen(battle: anytype, player: Player, _: *State, options: anytype) !void {
        return screens(battle, player, "LightScreen", "light_screen", options);
    }

    fn screens(
        battle: anytype,
        player: Player,
        comptime key: []const u8,
        comptime value: []const u8,
        options: anytype,
    ) !void {
        var side = battle.side(player);

        if (@field(side.conditions, key)) return options.log.fail(battle.active(player), .None);

        @field(side.conditions, key) = true;
        @field(side.conditions, value) = 5;
        try options.log.sidestart(player, @field(protocol.Side, key));
    }

    pub fn sketch(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);

        side.last_used_move = .None;
        side.active.volatiles.dirty = false;

        if (showdown) {
            // yes, actually "Splash". '|nothing' gets blindly mapped to  '|-activate||move:Splash'
            try options.log.activate(battle.active(player), .Splash);
        } else {
            try options.log.fail(battle.active(player), .None);
        }
    }

    pub fn sleep(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (Status.any(foe_stored.status)) {
            return options.log.fail(
                foe_ident,
                if (Status.is(foe_stored.status, .SLP)) .Sleep else .None,
            );
        }

        if (foe.active.volatiles.Substitute) {
            return options.log.activateMove(foe_ident, .SubstituteBlock, state.move);
        }

        // Sleep Clause Mod
        if (showdown) {
            for (foe.pokemon) |p| {
                if (Status.is(p.status, .SLP) and !Status.is(p.status, .EXT)) return;
            }
        }

        foe_stored.status = Status.slp(Rolls.sleepDuration(battle, player, options));
        try options.log.statusFrom(foe_ident, foe_stored.status, state.move);
    }

    pub fn sleepTalk(battle: anytype, player: Player, state: *State, options: anytype) !void {
        const side = battle.side(player);

        if (!Status.is(side.stored().status, .SLP)) {
            if (!showdown) try options.log.fail(battle.active(player), .None);
            return;
        }

        var n: u3 = 0;
        for (side.active.moves, 0..) |m, i| {
            if (state.mslot - 1 != i and Move.get(m.id).extra.sleep_talk) n += 1;
        }
        if (n == 0) return options.log.fail(battle.active(player), .None);

        _ = try Rolls.sleepTalk(battle, player, n, state.mslot, options); // TODO
    }

    pub fn snore(battle: anytype, player: Player, state: *State, options: anytype) !bool {
        if (Status.is(battle.side(player).stored().status, .SLP)) return true;
        state.damage = 0;
        state.miss = true; // TODO is this necessary?
        if (!showdown) try options.log.fail(battle.active(player), .None);
        return false;
    }

    pub fn spikes(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var foe = battle.foe(player);
        if (foe.conditions.Spikes) return options.log.fail(battle.active(player), .None);

        foe.conditions.Spikes = true;
        try options.log.sidestart(player.foe(), .Spikes);
    }

    pub fn spite(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
        // var foe = battle.foe(player);

        // if (state.miss) return options.log.fail(battle.active(player), .None);

        // const last = foe.lastMove(false);
        // if (showdown) {
        //     const roll = try Rolls.spite(battle, player, options);
        // } else {
        //     if (last != .None) {}
        // }
    }

    pub fn splash(battle: anytype, player: Player, _: *State, options: anytype) !void {
        try options.log.activate(battle.active(player), .Splash);
    }

    pub fn substitute(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);
        if (side.active.volatiles.Substitute) {
            return options.log.fail(battle.active(player), .Substitute);
        }

        assert(side.stored().stats.hp <= 1023);
        const hp: u8 = @intCast(side.stored().stats.hp / 4);

        if (hp == 0 or side.stored().hp <= hp) {
            return options.log.fail(battle.active(player), .Weak);
        }

        side.stored().hp -= hp;
        side.active.volatiles.substitute = hp;
        side.active.volatiles.Substitute = true;
        side.active.volatiles.bind = .{};
        try options.log.start(battle.active(player), .Substitute);
        try options.log.damage(battle.active(player), side.stored(), .None);
    }

    pub fn sunnyDay(battle: anytype, _: Player, _: *State, options: anytype) !void {
        return weather(battle, .Sun, options);
    }

    fn weather(battle: anytype, w: Weather, options: anytype) !void {
        battle.field.weather = w;
        battle.field.weather_duration = 5;
        try options.log.weather(w, .None);
    }

    pub fn teleport(battle: anytype, player: Player, _: *State, options: anytype) !void {
        if (showdown) return;

        try options.log.fail(battle.active(player), .None);
        try options.log.laststill();
    }

    pub fn thief(battle: anytype, player: Player, state: *State, options: anytype) !void {
        const side = battle.side(player);
        const foe = battle.foe(player);

        if (side.stored().item != .None or foe.stored().item == .None) return;
        // Pokémon Showdown incorrectly allows you steal Mail
        if (!showdown and foe.stored().item.isMail()) return;
        if (!state.proc) return;

        side.stored().item = foe.stored().item;
        foe.stored().item = .None;

        try options.log.item(
            battle.active(player),
            side.stored().item,
            battle.active(player.foe()),
        );
    }

    pub fn thrashing(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);
        if (Status.is(side.stored().status, .SLP)) return;

        assert(!side.active.volatiles.Thrashing);
        side.active.volatiles.Thrashing = true;
        side.active.volatiles.attacks = Rolls.attackingDuration(battle, player, options);
        // TODO wSomeoneIsRampaging = true;
    }

    pub fn transform(battle: anytype, player: Player, _: *State, options: anytype) !void {
        var side = battle.side(player);
        const foe = battle.foe(player);
        const foe_ident = battle.active(player.foe());

        side.last_used_move = .None;
        side.active.volatiles.dirty = false;

        if (foe.active.volatiles.Transform) {
            return options.log.fail(battle.active(player), .None);
        } else if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
            if (!showdown) return options.log.fail(battle.active(player), .None);
            try options.log.lastmiss();
            return options.log.miss(battle.active(player));
        }

        side.active.volatiles.Transform = true;
        side.active.volatiles.transform = foe_ident.int();
        side.active.volatiles.disable = .{};

        // HP is not copied by Transform
        side.active.stats.atk = foe.active.stats.atk;
        side.active.stats.def = foe.active.stats.def;
        side.active.stats.spe = foe.active.stats.spe;
        side.active.stats.spa = foe.active.stats.spa;
        side.active.stats.spd = foe.active.stats.spd;

        side.active.species = foe.active.species;
        side.active.types = foe.active.types;
        side.active.boosts = foe.active.boosts;
        for (foe.active.moves, 0..) |m, i| {
            side.active.moves[i].id = m.id;
            side.active.moves[i].pp = if (m.id != .None) if (m.id == .Sketch) 1 else 5 else 0;
        }

        try options.log.transform(battle.active(player), foe_ident);
    }

    pub fn triAttack(battle: anytype, player: Player, state: *State, options: anytype) !void {
        // FIXME only commit effectchance and triattack rolls if actually does something...
        try effectChance(battle, player, state, options);
        if (state.proc) {
            try switch (try Rolls.triAttack(battle, player, options)) {
                .PAR => paralyzeChance(battle, player, state, options),
                .FRZ => freezeChance(battle, player, state, options),
                .BRN => burnChance(battle, player, state, options),
            };
        } else if (!showdown) battle.rng.advance(1);
    }

    pub fn tripleKick(battle: anytype, player: Player, state: *State, options: anytype) !void {
        _ = .{ battle, player, state, options }; // TODO
    }

    const ALL_STAT_UP_STATS = [_][]const u8{ "atk", "def", "spe", "spa", "spd" };
    const ALL_STAT_UP_REASONS =
        [_]Boost{ .Attack, .Defense, .Speed, .SpecialAttack, .SpecialDefense };

    pub fn allStatUpChance(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var side = battle.side(player);

        var stats = &side.active.stats;
        var boosts = &side.active.boosts;

        if (!state.proc) return;
        inline for (ALL_STAT_UP_STATS, ALL_STAT_UP_REASONS) |s, r| {
            assert(@field(boosts, s) >= -6 and @field(boosts, s) <= 6);
            if (@field(boosts, s) == 6 or @field(stats, s) == MAX_STAT_VALUE) {
                try options.log.boost(battle.active(player), r, 0);
            } else {
                @field(boosts, s) = @intCast(@min(6, @as(i8, @field(boosts, s)) + 1));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, @field(boosts, s)) + 6))];
                const stat = @field(unmodifiedStats(battle, side), s);
                @field(stats, s) = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try options.log.boost(battle.active(player), r, 1);
            }
        }

        statusModify(side.stored().status, stats);
    }

    pub fn boost(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var log = options.log;
        var side = battle.side(player);
        const ident = battle.active(player);

        if (state.miss) return log.fail(ident, .None);

        var stats = &side.active.stats;
        var boosts = &side.active.boosts;

        const move = Move.get(state.move);
        switch (move.effect) {
            .AttackUp1, .AttackUp2, .Rage, .Swagger => {
                assert(boosts.atk >= -6 and boosts.atk <= 6);
                if (boosts.atk == 6 or stats.atk == MAX_STAT_VALUE) return log.fail(ident, .None);
                const n: u2 = if (move.effect == .AttackUp2 or move.effect == .Swagger) 2 else 1;
                boosts.atk = @as(i4, @intCast(@min(6, @as(i8, boosts.atk) + n)));
                const reason = if (showdown and move.effect == .Rage) Boost.Rage else Boost.Attack;
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.atk) + 6))];
                const stat = unmodifiedStats(battle, side).atk;
                stats.atk = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, reason, n);
            },
            .DefenseUp1, .DefenseUp2, .SkullBash => {
                assert(boosts.def >= -6 and boosts.def <= 6);
                if (boosts.def == 6 or stats.def == MAX_STAT_VALUE) return log.fail(ident, .None);
                const n: u2 = if (move.effect == .DefenseUp2) 2 else 1;
                boosts.def = @intCast(@min(6, @as(i8, boosts.def) + n));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.def) + 6))];
                const stat = unmodifiedStats(battle, side).def;
                stats.def = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .Defense, n);
            },
            .SpeedUp2 => {
                assert(boosts.spe >= -6 and boosts.spe <= 6);
                if (boosts.spe == 6 or stats.spe == MAX_STAT_VALUE) return log.fail(ident, .None);
                boosts.spe = @intCast(@min(6, @as(i8, boosts.spe) + 2));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.spe) + 6))];
                const stat = unmodifiedStats(battle, side).spe;
                stats.spe = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .Speed, 2);
            },
            .SpAtkUp1 => {
                assert(boosts.spa >= -6 and boosts.spa <= 6);
                if (boosts.spa == 6 or stats.spa == MAX_STAT_VALUE) return log.fail(ident, .None);
                boosts.spa = @intCast(@min(6, @as(i8, boosts.spa) + 1));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.spa) + 6))];
                const stat = unmodifiedStats(battle, side).spa;
                stats.spa = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .SpecialAttack, 1);
            },
            .SpDefUp2 => {
                assert(boosts.spd >= -6 and boosts.spd <= 6);
                if (boosts.spd == 6 or stats.spd == MAX_STAT_VALUE) return log.fail(ident, .None);
                boosts.spd = @intCast(@min(6, @as(i8, boosts.spd) + 2));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.spd) + 6))];
                const stat = unmodifiedStats(battle, side).spd;
                stats.spd = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .SpecialDefense, 2);
            },
            .EvasionUp1 => {
                assert(boosts.evasion >= -6 and boosts.evasion <= 6);
                if (boosts.evasion == 6) return log.fail(ident, .None);
                boosts.evasion = @intCast(@min(6, @as(i8, boosts.evasion) + 1));
                try log.boost(ident, .Evasion, 1);
                if (state.move == .Minimize) side.active.volatiles.minimized = true;
            },
            else => unreachable,
        }

        statusModify(side.stored().status, stats);
    }

    pub fn unboost(battle: anytype, player: Player, state: *State, options: anytype) !void {
        var log = options.log;
        var foe = battle.foe(player);
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Mist) {
            try log.activate(foe_ident, .Mist);
            return log.fail(foe_ident, .None);
        }

        const fail = foe.active.volatiles.Substitute or state.miss or !state.proc;

        var stats = &foe.active.stats;
        var boosts = &foe.active.boosts;

        const move = Move.get(state.move);
        switch (move.effect) {
            .AttackDown1, .AttackDown2, .AttackDownChance => {
                assert(boosts.atk >= -6 and boosts.atk <= 6);
                if (fail or boosts.atk == -6) {
                    return if (move.effect != .AttackDownChance) try log.fail(foe_ident, .None);
                } else if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
                    try options.log.lastmiss();
                    return options.log.miss(battle.active(player));
                } else if (stats.atk == 1) {
                    return if (move.effect != .AttackDownChance) try log.fail(foe_ident, .None);
                }
                const n: u2 = if (move.effect == .AttackDown2) 2 else 1;
                boosts.atk = @intCast(@max(-6, @as(i8, boosts.atk) - n));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.atk) + 6))];
                const stat = unmodifiedStats(battle, foe).atk;
                stats.atk = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Attack, -@as(i8, n));
            },
            .DefenseDown1, .DefenseDown2, .DefenseDownChance => {
                assert(boosts.def >= -6 and boosts.def <= 6);
                if (fail or boosts.def == -6) {
                    return if (move.effect != .DefenseDownChance) try log.fail(foe_ident, .None);
                } else if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
                    try options.log.lastmiss();
                    return options.log.miss(battle.active(player));
                } else if (stats.def == 1) {
                    return if (move.effect != .DefenseDownChance) try log.fail(foe_ident, .None);
                }
                const n: u2 = if (move.effect == .DefenseDown2) 2 else 1;
                boosts.def = @intCast(@max(-6, @as(i8, boosts.def) - n));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.def) + 6))];
                const stat = unmodifiedStats(battle, foe).def;
                stats.def = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Defense, -@as(i8, n));
            },
            .SpeedDown1, .SpeedDown2, .SpeedDownChance => {
                assert(boosts.spe >= -6 and boosts.spe <= 6);
                if (fail or boosts.spe == -6) {
                    return if (move.effect != .SpeedDownChance) try log.fail(foe_ident, .None);
                } else if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
                    try options.log.lastmiss();
                    return options.log.miss(battle.active(player));
                } else if (stats.spe == 1) {
                    return if (move.effect != .SpeedDownChance) try log.fail(foe_ident, .None);
                }
                const n: u2 = if (move.effect == .SpeedDown2) 2 else 1;
                boosts.spe = @intCast(@max(-6, @as(i8, boosts.spe) - 1));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.spe) + 6))];
                const stat = unmodifiedStats(battle, foe).spe;
                stats.spe = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Speed, -@as(i8, n));
                assert(boosts.spe >= -6);
            },
            .SpDefDownChance => {
                assert(boosts.spd >= -6 and boosts.spd <= 6);
                if (fail or boosts.spd == -6) return;
                if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
                    try options.log.lastmiss();
                    return options.log.miss(battle.active(player));
                } else if (stats.spd == 1) return;
                boosts.spd = @intCast(@max(-6, @as(i8, boosts.spd) - 1));
                var mod = STAT_BOOSTS[@as(u4, @intCast(@as(i8, boosts.spd) + 6))];
                const stat = unmodifiedStats(battle, foe).spd;
                stats.spd = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .SpecialDefense, -1);
            },
            .AccuracyDown1, .AccuracyDownChance => {
                assert(boosts.accuracy >= -6 and boosts.accuracy <= 6);
                if (fail or boosts.accuracy == -6) {
                    return if (move.effect != .AccuracyDownChance) try log.fail(foe_ident, .None);
                } else if (foe.active.volatiles.Flying or foe.active.volatiles.Underground) {
                    try options.log.lastmiss();
                    return options.log.miss(battle.active(player));
                }
                boosts.accuracy = @intCast(@max(-6, @as(i8, boosts.accuracy) - 1));
                try log.boost(foe_ident, .Accuracy, -1);
            },
            else => unreachable,
        }

        statusModify(foe.stored().status, stats);
    }
};

fn unmodifiedStats(battle: anytype, side: *Side) *Stats(u16) {
    if (!side.active.volatiles.Transform) return &side.stored().stats;
    const id = ID.from(side.active.volatiles.transform);
    return &battle.side(id.player).pokemon[id.id - 1].stats;
}

fn statusModify(status: u8, stats: *Stats(u16)) void {
    if (Status.is(status, .PAR)) {
        stats.spe = @max(stats.spe / 4, 1);
    } else if (Status.is(status, .BRN)) {
        stats.atk = @max(stats.atk / 2, 1);
    }
}

fn isForced(active: anytype) bool {
    return active.volatiles.Recharging or active.volatiles.Rage or
        active.volatiles.Thrashing or active.volatiles.Charging or
        active.volatiles.Rollout;
}

fn convertible(active: ActivePokemon, m: Move) bool {
    if (m == .None) return false;
    const t = Move.get(m).type;
    return t != .@"???" and !active.types.includes(t);
}

pub const Rolls = struct {
    fn speedTie(battle: anytype, options: anytype) !bool {
        const p1 = if (options.calc.overridden(.P1, .speed_tie)) |player|
            player == .P1
        else if (showdown)
            battle.rng.range(u8, 0, 2) == 0
        else
            battle.rng.next() < Gen12.percent(50) + 1;

        try options.chance.speedTie(p1);
        return p1;
    }

    fn quickClaw(battle: anytype, player: Player, options: anytype) !bool {
        const qkc = if (options.calc.overridden(player, .quick_claw)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 60, 256)
        else
            battle.rng.next() < 60;

        try options.chance.quickClaw(player, qkc);
        return qkc;
    }

    fn hit(battle: anytype, player: Player, accuracy: u8, options: anytype) !bool {
        const ok = if (options.calc.overridden(player, .hit)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, accuracy, 256)
        else
            battle.rng.next() < accuracy;

        try options.chance.hit(player, ok, accuracy);
        return ok;
    }

    fn criticalHit(battle: anytype, player: Player, rate: u8, options: anytype) !bool {
        const crit = if (options.calc.overridden(player, .critical_hit)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, rate, 256)
        else
            battle.rng.next() < rate;

        try options.chance.criticalHit(player, crit, rate);
        return crit;
    }

    fn damage(battle: anytype, player: Player, options: anytype) !u8 {
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

    fn confused(battle: anytype, player: Player, options: anytype) !bool {
        const cfz = if (options.calc.overridden(player, .confused)) |val|
            val == .true
        else if (showdown)
            !battle.rng.chance(u8, 128, 256)
        else
            battle.rng.next() >= Gen12.percent(50) + 1;

        try options.chance.confused(player, cfz);
        return cfz;
    }

    fn attract(battle: anytype, player: Player, options: anytype) !bool {
        const cant = if (options.calc.overridden(player, .attract)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 1, 2)
        else
            battle.rng.next() > Gen12.percent(50) + 1;

        try options.chance.attract(player, cant);
        return cant;
    }

    fn paralyzed(battle: anytype, player: Player, options: anytype) !bool {
        const par = if (options.calc.overridden(player, .paralyzed)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 63, 256)
        else
            battle.rng.next() < Gen12.percent(25);

        try options.chance.paralyzed(player, par);
        return par;
    }

    fn defrost(battle: anytype, player: Player, options: anytype) !bool {
        const thaw = if (options.calc.overridden(player, .defrost)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 25, 256)
        else
            battle.rng.next() < Gen12.percent(10);

        try options.chance.defrost(player, thaw);
        return thaw;
    }

    fn secondaryChance(battle: anytype, player: Player, rate: u8, options: anytype) !bool {
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

    fn item(battle: anytype, player: Player, options: anytype) !bool {
        const proc = if (options.calc.overridden(player, .item)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 30, 256)
        else
            battle.rng.next() < 30;

        try options.chance.item(player, proc);
        return proc;
    }

    fn triAttack(battle: anytype, player: Player, options: anytype) !TriAttack {
        const status: TriAttack = if (options.calc.overridden(player, .tri_attack)) |val|
            @enumFromInt(@intFromEnum(val) - 1)
        else if (showdown)
            @enumFromInt(battle.rng.range(u2, 0, 2))
        else loop: {
            while (true) {
                const r = std.math.rotr(u8, battle.rng.next(), 4) & 3;
                if (r != 0) break :loop @enumFromInt(r - 1);
            }
        };

        try options.chance.triAttack(player, status);
        return status;
    }

    fn present(battle: anytype, player: Player, options: anytype) !u8 {
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

    fn magnitude(battle: anytype, player: Player, options: anytype) !u8 {
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

    fn tripleKick(battle: anytype, player: Player, options: anytype) !u2 {
        const hits = if (options.calc.overridden(player, .triple_kick)) |val|
            val
        else if (showdown)
            battle.rng.range(u2, 1, 4)
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

    fn spite(battle: anytype, player: Player, options: anytype) !u8 {
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
    var CONVERSION_2: [7]Type = [_]Type{.@"???"} ** 7;

    fn conversion2(battle: anytype, player: Player, mtype: Type, options: anytype) !Type {
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

                const t = Type.conversion2(r);
                if (@intFromEnum(mtype.effectiveness(t)) < neutral) {
                    break :ty t;
                }
            }
        };

        assert(ty != .@"???");
        try options.chance.conversion2(player, ty, mtype, i);
        return ty;
    }

    fn protect(battle: anytype, player: Player, count: u8, options: anytype) !bool {
        assert(count <= 8);
        const num = if (count == 8) 0 else @as(u8, 255) >> @intCast(count);

        const ok = if (options.calc.overridden(player, .protect)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, num, 255)
        else protected: {
            while (true) {
                const r = battle.rng.next();
                if (r != 0) break :protected !(num <= r - 1);
            }
        };

        try options.chance.protect(player, num, ok);
        return ok;
    }

    fn conversion(battle: anytype, player: Player, n: u4, options: anytype) !Type {
        assert(n > 0);

        const active = battle.side(player).active;
        const moves = active.moves;

        // TODO: consider throwing error instead of rerolling?
        const overridden = if (options.calc.overridden(player, .move_slot)) |val|
            if (convertible(active, moves[val - 1].id)) val else null
        else
            null;

        const slot: u4 = overridden orelse slot: {
            if (showdown) {
                var r = battle.rng.range(u4, 0, n) + 1;
                var i: usize = 0;
                while (i < moves.len and r > 0) : (i += 1) {
                    if (convertible(active, moves[i].id)) {
                        r -= 1;
                        if (r == 0) break :slot @intCast(i + 1);
                    }
                }
                break :slot @intCast(i + 1);
            } else {
                while (true) {
                    const r: u4 = @intCast(battle.rng.next() & 3);
                    if (convertible(active, moves[r].id)) break :slot @intCast(r + 1);
                }
            }
        };

        assert(n >= 1 and n <= 4);
        assert(slot >= 1 and slot <= 4);
        try options.chance.moveSlot(player, slot, n);
        return Move.get(active.move(slot).id).type;
    }

    fn sleepTalk(battle: anytype, player: Player, n: u4, mslot: u4, options: anytype) !u4 {
        assert(n > 0);

        const active = battle.side(player).active;
        const moves = active.moves;

        // TODO: consider throwing error instead of rerolling?
        const overridden = if (options.calc.overridden(player, .move_slot)) |val|
            if (val != mslot and Move.get(moves[val - 1].id).extra.sleep_talk) val else null
        else
            null;

        const slot: u4 = overridden orelse slot: {
            if (showdown) {
                var r = battle.rng.range(u4, 0, n) + 1;
                var i: usize = 0;
                while (i < moves.len and r > 0) : (i += 1) {
                    if (i + 1 != mslot and Move.get(moves[i].id).extra.sleep_talk) {
                        r -= 1;
                        if (r == 0) break :slot @intCast(i + 1);
                    }
                }
                break :slot @intCast(i + 1);
            } else {
                while (true) {
                    const r: u4 = @intCast(battle.rng.next() & 3);
                    if (r + 1 == mslot or !Move.get(moves[r].id).extra.sleep_talk) continue;
                    break :slot @intCast(r + 1);
                }
            }
        };

        assert(n >= 1 and n <= 4);
        assert(slot >= 1 and slot <= 4);
        try options.chance.moveSlot(player, slot, n);
        return slot;
    }

    fn forceSwitch(
        battle: anytype,
        player: Player,
        slots: []u4,
        n: u4,
        options: anytype,
    ) !u4 {
        const foe = battle.foe(player);

        assert(slots.len < 5);
        assert(n > 0 and n <= 6);

        // TODO: consider throwing error instead of rerolling?
        const overridden = if (options.calc.overridden(player, .force_switch)) |val| val: {
            for (slots) |slot| if (slot == val) break :val if (foe.get(slot).hp > 0) val else null;
            break :val null;
        } else null;

        const slot: u4 = overridden orelse slot: {
            if (showdown) {
                break :slot slots[battle.rng.range(u4, 0, @as(u4, @intCast(slots.len)))];
            } else {
                while (true) {
                    const r = battle.rng.next() & 7;
                    if (r > n or r == 1) continue;
                    if (foe.get(r).hp > 0) break :slot @intCast(r);
                }
            }
        };

        assert(n >= 1 and n <= 6);
        assert(slot >= 1 and slot <= 6);
        try options.chance.forceSwitch(player, slot, n);
        return slot;
    }

    const DISTRIBUTION = [_]u3{ 2, 2, 2, 3, 3, 3, 4, 5 };

    fn multiHit(battle: anytype, player: Player, options: anytype) !u3 {
        const n: u3 = if (options.calc.overridden(player, .multi_hit)) |val|
            @intCast(val)
        else if (showdown)
            DISTRIBUTION[battle.rng.range(u3, 0, DISTRIBUTION.len)]
        else n: {
            const r = (battle.rng.next() & 3);
            break :n @intCast((if (r < 2) r else battle.rng.next() & 3) + 2);
        };

        assert(n >= 2 and n <= 5);
        try options.chance.multiHit(player, n);
        return n;
    }

    fn psywave(battle: anytype, player: Player, max: u8, options: anytype) !u8 {
        const power = if (options.calc.overridden(player, .psywave)) |val|
            val
        else if (showdown)
            battle.rng.range(u8, 1, max)
        else power: {
            while (true) {
                const r = battle.rng.next();
                if (r != 0 and r < max) break :power r;
            }
        };

        assert(power != 0 and power < max);
        try options.chance.psywave(player, power, max);
        return power;
    }

    fn metronome(battle: anytype, player: Player, options: anytype) !Move {
        const moves = battle.side(player).active.moves;

        var n: u2 = 0;
        for (moves) |m| {
            if (m.id == .None) break;
            if (Move.get(m.id).extra.metronome) n += 1;
        }

        // TODO: consider throwing error instead of rerolling?
        const overridden = if (options.calc.overridden(player, .metronome)) |val| val: {
            for (moves) |m| if (m.id == val) break :val null;
            break :val val;
        } else null;

        const move: Move = overridden orelse move: {
            if (showdown) {
                var r = battle.rng.range(u8, 0, @intCast(Move.METRONOME.len - n));
                for (moves) |m| {
                    if (m.id == .None) break;
                    if (@intFromEnum(m.id) > @intFromEnum(Move.METRONOME[r])) break;
                    if (Move.get(m.id).extra.metronome) r -= 1;
                }
                break :move Move.METRONOME[r];
            } else {
                outer: while (true) {
                    const r = battle.rng.next();
                    if (r == 0 or r >= Move.size) continue;
                    const selected: Move = @enumFromInt(r);
                    if (!Move.get(selected).extra.metronome) continue;
                    for (moves) |m| if (m.id == selected) continue :outer;
                    break :move selected;
                }
            }
        };

        assert(Move.get(move).extra.metronome);
        try options.chance.metronome(player, move, n);
        return move;
    }

    fn sleepDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            battle.rng.range(u3, 1, 7)
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

    fn confusionDuration(battle: anytype, player: Player, self: bool, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            // Pokémon Showdown incorrectly uses the same duration for self-confusion
            battle.rng.range(u3, 2, 6)
        else
            @intCast((battle.rng.next() & if (self) 1 else 3) + 2);

        assert(duration >= 2 and duration <= if (!showdown and self) 3 else 5);
        options.chance.duration(.confusion, player, if (self) player else player.foe(), duration);
        return duration;
    }

    fn disableDuration(battle: anytype, player: Player, options: anytype) u4 {
        const duration: u4 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            // Pokémon Showdown incorrectly inherits Generation III's Disable duration
            battle.rng.range(u4, 2, 6)
        else duration: {
            while (true) {
                const r = battle.rng.next() & 7;
                if (r != 0) break :duration @intCast(r + 1);
            }
        };

        assert(duration >= 2 and duration <= (if (showdown) 5 else 7));
        options.chance.duration(.disable, player, player.foe(), duration);
        return duration;
    }

    fn attackingDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            battle.rng.range(u3, 2, 4)
        else
            @intCast((battle.rng.next() & 1) + 2); // BUG: thrash is + 1 not +2

        assert(duration >= 2 and duration <= 3);
        options.chance.duration(.attacking, player, player, duration);
        return duration;
    }

    fn bindingDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = (if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            // TODO: PS does range(3, 6) here which after subtracting 1 is actually 2-4 not 2-5!
            battle.rng.range(u3, 2, 5)
        else
            @intCast(battle.rng.next() & 3 + 2));

        assert(duration >= 2 and duration <= 5);
        options.chance.duration(.binding, player, player.foe(), duration);
        return duration + 1;
    }

    // TODO: consider sharing implementation with bindingDuration
    fn encoreDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = (if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            battle.rng.range(u3, 2, 6)
        else
            @intCast(battle.rng.next() & 3 + 2));

        assert(duration >= 2 and duration <= 5);
        options.chance.duration(.encore, player, player.foe(), duration);
        return duration + 1;
    }
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

test "Reasons" {
    const moves = [_]Move{ .Bind, .Wrap, .FireSpin, .Clamp, .Whirlpool };
    for (moves) |move| {
        const reason = Move.get(move).extra.protocol - 1;

        const activate: Activate = @enumFromInt(@intFromEnum(Activate.Bind) + reason);
        try expectEqualStrings(@tagName(move), @tagName(activate));

        const damage: Damage = @enumFromInt(@intFromEnum(Damage.Bind) + reason);
        try expectEqualStrings(@tagName(move), @tagName(damage));

        const end: End = @enumFromInt(@intFromEnum(End.Bind) + reason);
        try expectEqualStrings(@tagName(move), @tagName(end));
    }

    const perish_song = [_]Start{ .PerishSong0, .PerishSong1, .PerishSong2, .PerishSong3 };
    for (perish_song, 0..) |ps, i| {
        const reason: Start = @enumFromInt(@intFromEnum(Start.PerishSong0) + i);
        try expectEqualStrings(@tagName(ps), @tagName(reason));
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
                            m.id == .Bide and (m.pp == 0 or active.volatiles.disable.move == slot);
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
                if (active.volatiles.disable.move == slot) continue;
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
