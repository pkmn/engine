const std = @import("std");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const showdown = options.showdown;

const Boost = protocol.Boost;
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

// zig fmt: off
const BOOSTS = &[_][2]u8{
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
// zig fmt: on

const MAX_STAT_VALUE = 999;

pub fn update(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    assert(c1.type != .Pass or c2.type != .Pass or battle.turn == 0);
    if (battle.turn == 0) return start(battle, log);

    var f1: ?Move = null;
    var f2: ?Move = null;

    if (selectMove(battle, .P1, c1, c2, &f1)) |r| return r;
    if (selectMove(battle, .P2, c2, c1, &f2)) |r| return r;

    if (turnOrder(battle, c1, c2) == .P1) {
        if (try doTurn(battle, .P1, c1, f1, .P2, c2, f2, log)) |r| return r;
    } else {
        if (try doTurn(battle, .P2, c2, f2, .P1, c1, f1, log)) |r| return r;
    }

    var p1 = battle.side(.P1);
    if (p1.active.volatiles.attacks == 0) {
        p1.active.volatiles.Binding = false;
    }
    var p2 = battle.side(.P2);
    if (p2.active.volatiles.attacks == 0) {
        p2.active.volatiles.Binding = false;
    }

    return endTurn(battle, log);
}

fn start(battle: anytype, log: anytype) !Result {
    const p1 = battle.side(.P1);
    const p2 = battle.side(.P2);

    var p1_slot = findFirstAlive(p1);
    assert(!showdown or p1_slot == 1);
    if (p1_slot == 0) return if (findFirstAlive(p2) == 0) Result.Tie else Result.Lose;

    var p2_slot = findFirstAlive(p2);
    assert(!showdown or p2_slot == 1);
    if (p2_slot == 0) return Result.Win;

    try switchIn(battle, .P1, p1_slot, true, log);
    try switchIn(battle, .P2, p2_slot, true, log);

    return endTurn(battle, log);
}

fn findFirstAlive(side: *const Side) u8 {
    for (side.pokemon, 0..) |pokemon, i| if (pokemon.hp > 0) return side.order[i];
    return 0;
}

fn selectMove(
    battle: anytype,
    player: Player,
    choice: Choice,
    foe_choice: Choice,
    from: *?Move,
) ?Result {
    if (choice.type == .Pass) return null;

    var side = battle.side(player);
    var volatiles = &side.active.volatiles;
    const stored = side.stored();

    assert(!isForced(side.active) or
        (choice.type == .Move and choice.data == @boolToInt(showdown)));

    // pre-battle menu
    if (volatiles.Recharging) return null;
    if (volatiles.Rage) {
        from.* = side.last_used_move;
        if (showdown) saveMove(battle, player, null);
        return null;
    }
    volatiles.Flinch = false;
    if (volatiles.Thrashing or volatiles.Charging) {
        from.* = side.last_selected_move;
        if (showdown) saveMove(battle, player, null);
        return null;
    }

    // battle menu
    if (choice.type == .Switch) return null;

    // pre-move select
    if (Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP) or volatiles.Bide) {
        assert(showdown or choice.data == 0);
        if (showdown) saveMove(battle, player, choice);
        return null;
    }
    if (volatiles.Binding) {
        from.* = side.last_used_move;
        if (showdown) {
            if (foe_choice.type == .Switch) from.* = null;
            // Pokémon Showdown overwrites Mirror Move with whatever was selected - really this
            // should set side.last_selected_move = last.id to reuse Mirror Move and fail in order
            // to satisfy the conditions of the Desync Clause Mod. However, because Binding is still
            // set the selected move will not actually be used, it will just be reported as having
            // been used (this differs from how Pokémon Showdown works, but its impossible to
            // replicate the incorrect behavior with the correct mechanisms).
            saveMove(battle, player, choice);
        } else {
            assert(choice.data == 0);
            // GLITCH: https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch
            if (foe_choice.type == .Switch) {
                const slot = if (player == .P1)
                    battle.last_selected_indexes.p1
                else
                    battle.last_selected_indexes.p2;
                const last = side.active.move(@intCast(u4, slot));
                if (last.id == .Metronome) side.last_selected_move = last.id;
                if (last.id == .MirrorMove) return Result.Error;
            }
        }
        return null;
    }

    if (battle.foe(player).active.volatiles.Binding) {
        if (showdown) {
            saveMove(battle, player, choice);
        } else {
            assert(choice.data == 0);
            side.last_selected_move = .SKIP_TURN;
        }
        return null;
    }

    // move select
    if (choice.data == 0) {
        const struggle = ok: {
            for (side.active.moves, 0..) |move, i| {
                if (move.pp > 0 and volatiles.disabled_move != i + 1) break :ok false;
            }
            break :ok true;
        };

        assert(struggle);
        saveMove(battle, player, choice);
    } else {
        saveMove(battle, player, choice);
    }

    return null;
}

fn saveMove(battle: anytype, player: Player, choice: ?Choice) void {
    var side = battle.side(player);

    if (choice) |c| {
        assert(c.type == .Move);
        if (c.data == 0) {
            side.last_selected_move = .Struggle;
        } else {
            assert(showdown or side.active.volatiles.disabled_move != c.data);
            const move = side.active.move(c.data);
            // You cannot *select* a move with 0 PP (except on Pokémon Showdown where that is
            // sometimes required...), but a 0 PP move can be used automatically
            assert(showdown or move.pp != 0);

            side.last_selected_move = move.id;
            if (player == .P1) {
                battle.last_selected_indexes.p1 = c.data;
            } else {
                battle.last_selected_indexes.p2 = c.data;
            }
        }
    }
}

fn switchIn(battle: anytype, player: Player, slot: u8, initial: bool, log: anytype) !void {
    var side = battle.side(player);
    var foe = battle.foe(player);
    var active = &side.active;
    const incoming = side.get(slot);

    assert(incoming.hp != 0);
    assert(slot != 1 or initial);

    const out = side.order[0];
    side.order[0] = side.order[slot - 1];
    side.order[slot - 1] = out;

    if (player == .P1) {
        battle.last_selected_indexes.p1 = 1;
    } else {
        battle.last_selected_indexes.p2 = 1;
    }

    side.last_used_move = .None;
    foe.last_used_move = .None;

    active.stats = incoming.stats;
    active.species = incoming.species;
    active.types = incoming.types;
    active.boosts = .{};
    active.volatiles = .{};
    active.moves = incoming.moves;

    statusModify(incoming.status, &active.stats);

    foe.active.volatiles.Binding = false;

    try log.switched(battle.active(player), incoming);
}

fn turnOrder(battle: anytype, c1: Choice, c2: Choice) Player {
    assert(c1.type != .Pass or c2.type != .Pass);

    if (c1.type == .Pass) return .P2;
    if (c2.type == .Pass) return .P1;

    if ((c1.type == .Switch) != (c2.type == .Switch)) return if (c1.type == .Switch) .P1 else .P2;

    const m1 = battle.side(.P1).last_selected_move;
    const m2 = battle.side(.P2).last_selected_move;

    if ((m1 == .QuickAttack) != (m2 == .QuickAttack)) return if (m1 == .QuickAttack) .P1 else .P2;
    if ((m1 == .Counter) != (m2 == .Counter)) return if (m1 == .Counter) .P2 else .P1;

    // https://www.smogon.com/forums/threads/adv-switch-priority.3622189/
    // > In Gen 1 it's irrelevant [which player switches first] because switches happen instantly on
    // > your own screen without waiting for the other player's choice (and their choice will appear
    // > to happen first for them too, unless they attacked in which case your switch happens first)
    // A cartridge-compatible implemention must not advance the RNG so we simply default to P1
    if (!showdown and c1.type == .Switch and c2.type == .Switch) return .P1;

    const spe1 = battle.side(.P1).active.stats.spe;
    const spe2 = battle.side(.P2).active.stats.spe;
    if (spe1 == spe2) {
        // Pokémon Showdown's beforeTurnCallback shenanigans
        if (showdown and m1 == .Counter and m2 == .Counter) battle.rng.advance(1);
        const p1 = if (showdown)
            battle.rng.range(u8, 0, 2) == 0
        else
            battle.rng.next() < Gen12.percent(50) + 1;
        return if (p1) .P1 else .P2;
    }

    return if (spe1 > spe2) .P1 else .P2;
}

fn doTurn(
    battle: anytype,
    player: Player,
    player_choice: Choice,
    player_from: ?Move,
    foe_player: Player,
    foe_choice: Choice,
    foe_from: ?Move,
    log: anytype,
) !?Result {
    assert(player_choice.type != .Pass);

    if (try executeMove(battle, player, player_choice, player_from, log)) |r| return r;
    if (foe_choice.type == .Pass) return null;
    if (try checkFaint(battle, foe_player, log)) |r| return r;
    try handleResidual(battle, player, log);
    if (try checkFaint(battle, player, log)) |r| return r;

    if (try executeMove(battle, foe_player, foe_choice, foe_from, log)) |r| return r;
    if (try checkFaint(battle, player, log)) |r| return r;
    try handleResidual(battle, foe_player, log);
    if (try checkFaint(battle, foe_player, log)) |r| return r;

    return null;
}

fn executeMove(
    battle: anytype,
    player: Player,
    choice: Choice,
    from: ?Move,
    log: anytype,
) !?Result {
    var side = battle.side(player);

    if (choice.type == .Switch) {
        try switchIn(battle, player, choice.data, false, log);
        return null;
    }

    if (side.last_selected_move == .SKIP_TURN) {
        // Pokémon Showdown overwrites the SKIP_TURN sentinel with its botched move select,
        // Binding instead gets handled in beforeMove after sleep and freeze
        assert(!showdown);
        if (battle.foe(player).active.volatiles.Binding) {
            try log.cant(battle.active(player), .Bound);
        }
        return null;
    }

    assert(choice.type == .Move);
    var mslot = choice.data;
    var auto = showdown and side.last_selected_move != .None and
        Move.get(side.last_selected_move).effect == .Binding;

    // GLITCH: Freeze top move selection desync & PP underflow shenanigans
    if (mslot == 0 and side.last_selected_move != .None and side.last_selected_move != .Struggle) {
        // choice.data == 0 only happens with Struggle on Pokémon Showdown
        assert(!showdown);
        mslot = @intCast(u4, if (player == .P1)
            battle.last_selected_indexes.p1
        else
            battle.last_selected_indexes.p2);
        const stored = side.stored();
        // GLITCH: Struggle bypass PP underflow via Hyper Beam / Trapping-switch auto selection
        auto = side.last_selected_move == .HyperBeam or side.active.volatiles.Bide or
            from != null or Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP);
        // If it wasn't Hyper Beam or the continuation of a move effect then we must have just
        // thawed, in which case we will desync unless the last_selected_move happened to be at
        // index 1 and the current Pokémon has the same move in its first slot.
        if (!auto) {
            // side.active.moves(slot) is safe to check even though the slot in question might not
            // technically be from this Pokémon because it must be exactly 1 to not desync and
            // every Pokémon must have at least one move
            if (mslot != 1 or side.active.move(mslot).id != side.last_selected_move) {
                return Result.Error;
            } else {
                auto = true;
            }
        }
    } else if (showdown and side.active.volatiles.Charging) {
        // Incorrect mslot with Pokémon Showdown choice semantics so we need to recover from index
        assert(mslot == 1);
        mslot = @intCast(u4, if (player == .P1)
            battle.last_selected_indexes.p1
        else
            battle.last_selected_indexes.p2);
    }

    var skip_can = false;
    var skip_pp = false;
    switch (try beforeMove(battle, player, from, log)) {
        .done => return null,
        .skip_can => skip_can = true,
        .skip_pp => skip_pp = true,
        .ok => {},
        .err => return @as(?Result, Result.Error),
    }

    if (!skip_can and !try canMove(battle, player, mslot, auto, skip_pp, from, log)) return null;

    return doMove(battle, player, mslot, log);
}

const BeforeMove = union(enum) { done, skip_can, skip_pp, ok, err };

fn beforeMove(battle: anytype, player: Player, from: ?Move, log: anytype) !BeforeMove {
    var side = battle.side(player);
    const foe = battle.foe(player);
    var active = &side.active;
    var stored = side.stored();
    const ident = battle.active(player);
    var volatiles = &active.volatiles;

    if (Status.is(stored.status, .SLP)) {
        const status = stored.status;
        // Even if the SLF bit is set this will still correctly modify the sleep duration
        stored.status -= 1;
        if (Status.duration(stored.status) == 0) {
            try log.curestatus(ident, status, .Message);
            stored.status = 0; // clears SLF if present
        } else {
            try log.cant(ident, .Sleep);
        }
        side.last_used_move = .None;
        return .done;
    }

    if (Status.is(stored.status, .FRZ)) {
        try log.cant(ident, .Freeze);
        side.last_used_move = .None;
        return .done;
    }

    if (foe.active.volatiles.Binding) {
        try log.cant(ident, .Bound);
        return .done;
    }

    if (volatiles.Flinch) {
        volatiles.Flinch = false;
        try log.cant(ident, .Flinch);
        return .done;
    }

    if (volatiles.Recharging) {
        volatiles.Recharging = false;
        try log.cant(ident, .Recharge);
        return .done;
    }

    if (volatiles.disabled_duration > 0) {
        volatiles.disabled_duration -= 1;
        if (volatiles.disabled_duration == 0) {
            volatiles.disabled_move = 0;
            try log.end(ident, .Disable);
        }
    }

    // This can only happen if a Pokémon started the battle frozen/sleeping and was thawed/woken
    // before the side had a selected a move - we simply need to assume this leads to a desync
    if (side.last_selected_move == .None) {
        assert(!showdown);
        return .err;
    }

    if (volatiles.Confusion) {
        assert(volatiles.confusion > 0);

        volatiles.confusion -= 1;
        if (volatiles.confusion == 0) {
            volatiles.Confusion = false;
            try log.end(ident, .Confusion);
        } else {
            try log.activate(ident, .Confusion);

            const confused = if (showdown)
                !battle.rng.chance(u8, 128, 256)
            else
                battle.rng.next() >= Gen12.percent(50) + 1;

            if (confused) {
                volatiles.state = 0;
                volatiles.Bide = false;
                volatiles.Thrashing = false;
                volatiles.MultiHit = false;
                volatiles.Flinch = false;
                volatiles.Charging = false;
                volatiles.Binding = false;
                volatiles.Invulnerable = false;

                // calcDamage just needs a 40 BP physical move, its not actually Pound
                const move = Move.get(.Pound);
                if (!calcDamage(battle, player, player, move, false)) return .err;
                // Skipping adjustDamage / randomizeDamage / checkHit
                _ = try applyDamage(battle, player, player.foe(), .Confusion, log);

                return .done;
            }
        }
    }

    if (volatiles.disabled_move != 0) {
        // A Pokémon that transforms after being disabled may end up with less move slots
        const m = active.moves[volatiles.disabled_move - 1].id;
        if (m != .None and m == side.last_selected_move) {
            try log.disabled(ident, side.last_selected_move);
            return .done;
        }
    }

    if (Status.is(stored.status, .PAR)) {
        const paralyzed = if (showdown)
            battle.rng.chance(u8, 63, 256)
        else
            battle.rng.next() < Gen12.percent(25);

        if (paralyzed) {
            volatiles.state = 0;
            volatiles.Bide = false;
            volatiles.Thrashing = false;
            volatiles.Charging = false;
            volatiles.Binding = false;
            // GLITCH: Invulnerable is not cleared, resulting in permanent Fly/Dig invulnerability
            try log.cant(ident, .Paralysis);
            return .done;
        }
    }

    if (volatiles.Bide) {
        assert(!volatiles.Thrashing and !volatiles.Rage);

        volatiles.state +%= battle.last_damage;

        assert(volatiles.attacks > 0);

        volatiles.attacks -= 1;
        if (volatiles.attacks != 0) {
            try log.activate(ident, .Bide);
            return .done;
        }

        volatiles.Bide = false;
        try log.end(ident, .Bide);

        battle.last_damage = volatiles.state *% 2;
        volatiles.state = 0;

        if (battle.last_damage == 0) {
            try log.fail(ident, .None);
            return .done;
        }

        _ = try applyDamage(battle, player.foe(), player.foe(), .None, log);
        return .done;
    }

    if (volatiles.Thrashing) {
        assert(volatiles.attacks > 0);
        assert(from != null);
        volatiles.attacks -= 1;
        if (!showdown and handleThrashing(battle, active)) {
            try log.start(battle.active(player), .ConfusionSilent);
        }
        try log.move(ident, side.last_selected_move, battle.active(player.foe()), from);
        if (showdown and handleThrashing(battle, active)) {
            try log.start(battle.active(player), .ConfusionSilent);
        }
        return .skip_can;
    }

    if (volatiles.Binding) {
        assert(volatiles.attacks > 0);
        volatiles.attacks -= 1;
        try log.move(
            battle.active(player),
            side.last_selected_move,
            battle.active(player.foe()),
            side.last_selected_move,
        );
        if (showdown or battle.last_damage != 0) {
            _ = try applyDamage(battle, player.foe(), player.foe(), .None, log);
        }
        return .done;
    }

    return if (volatiles.Rage) .skip_pp else .ok;
}

fn canMove(
    battle: anytype,
    player: Player,
    mslot: u4,
    auto: bool,
    skip_pp: bool,
    from: ?Move,
    log: anytype,
) !bool {
    var side = battle.side(player);
    const player_ident = battle.active(player);
    const move = Move.get(side.last_selected_move);

    const foe_last = battle.foe(player).last_used_move;
    const special = from != null and (from.? == .Metronome and
        (from.? == .MirrorMove and !(foe_last == .None or foe_last == .MirrorMove)));

    var skip = skip_pp;
    if (side.active.volatiles.Charging) {
        side.active.volatiles.Charging = false;
        side.active.volatiles.Invulnerable = false;
    } else if (move.effect == .Charge) {
        try log.move(player_ident, side.last_selected_move, .{}, from);
        try Effects.charge(battle, player, log);
        return false;
    }

    if (!showdown or !special) side.last_used_move = side.last_selected_move;
    if (!skip) decrementPP(side, mslot, auto);

    const target = if (move.target == .Self) player else player.foe();
    try log.move(player_ident, side.last_selected_move, battle.active(target), from);

    if (move.effect.onBegin()) {
        try onBegin(battle, player, move, mslot, log);
        return false;
    }

    if (move.effect == .Thrashing) {
        Effects.thrashing(battle, player);
    } else if (!showdown and move.effect == .Binding) {
        // Pokémon Showdown handles this after hit/miss checks and damage calculation
        Effects.binding(battle, player);
    }

    return true;
}

fn decrementPP(side: *Side, mslot: u4, auto: bool) void {
    if (side.last_selected_move == .Struggle) return;

    var active = &side.active;
    const volatiles = &active.volatiles;

    assert(!volatiles.Rage and !volatiles.Thrashing);
    if (volatiles.Bide or volatiles.MultiHit) return;

    assert(active.move(mslot).pp > 0 or auto);
    active.move(mslot).pp = @intCast(u6, active.move(mslot).pp -% 1);
    if (volatiles.Transform) return;

    assert(side.stored().move(mslot).pp > 0 or auto);
    side.stored().move(mslot).pp = @intCast(u6, side.stored().move(mslot).pp -% 1);
    assert(active.move(mslot).pp == side.stored().move(mslot).pp);
}

fn incrementPP(side: *Side, mslot: u4) void {
    var active = &side.active;
    const volatiles = &active.volatiles;

    active.move(mslot).pp +%= 1;
    // GLITCH: No check for Transform means an empty/incorrect stored slot can get incremented
    if (showdown and volatiles.Transform) return;

    assert(mslot > 0 and mslot <= 4);
    side.stored().moves[mslot - 1].pp +%= 1;
}

// Pokémon Showdown does hit/multi/crit/damage instead of crit/damage/hit/multi
fn doMove(battle: anytype, player: Player, mslot: u4, log: anytype) !?Result {
    var side = battle.side(player);
    const foe = battle.foe(player);

    var move = Move.get(side.last_selected_move);
    const special = move.effect == .SuperFang or move.effect == .SpecialDamage;

    var crit = false;
    var ohko = false;
    var immune = false;
    var mist = false;
    var hits: u4 = 1;
    var effectiveness = Effectiveness.neutral;
    const counter = side.last_selected_move == .Counter;

    // Pokémon Showdown runs type and OHKO immunity checks before the accuracy check
    if (showdown and !counter) {
        const m = side.last_selected_move;
        const eff1 = @enumToInt(move.type.effectiveness(foe.active.types.type1));
        const eff2 = @enumToInt(move.type.effectiveness(foe.active.types.type2));
        if (move.target != .Self and (eff1 == 0 or eff2 == 0) and !special or
            (m == .DreamEater and !Status.is(foe.stored().status, .SLP)))
        {
            if (move.effect == .Binding) {
                immune = true;
            } else {
                try log.immune(battle.active(player.foe()), .None);
                if (move.effect == .Explode) {
                    try Effects.explode(battle, player);
                }
                return null;
            }
        }
        if (move.effect == .OHKO and side.active.stats.spe < foe.active.stats.spe) {
            try log.immune(battle.active(player.foe()), .OHKO);
            return null;
        }
    }

    // The cartridge handles set damage moves in applyDamage but we short circuit to simplify things
    if (special) return specialDamage(battle, player, move, log);

    var miss = showdown and (move.target != .Self and
        !(move.effect == .Sleep and foe.active.volatiles.Recharging) and
        !moveHit(battle, player, move, &immune, &mist));
    assert((showdown and move.effect == .Binding) or !immune);

    const skip = (move.bp == 0 and move.effect != .OHKO) or immune;
    if ((!showdown or (!skip or counter)) and !miss) blk: {
        if (showdown and move.effect.isMulti()) {
            Effects.multiHit(battle, player, move);
            hits = side.active.volatiles.attacks;
        }

        // Cartridge rolls for crit even for moves that can't crit (Counter/Metronome/status/OHKO)
        const check = !showdown or (!counter and move.effect != .OHKO); // TODO: skip?
        if (check) crit = checkCriticalHit(battle, player, move);

        if (counter) return counterDamage(battle, player, move, log);

        battle.last_damage = 0;

        // Disassembly does a check to allow 0 BP MultiHit moves but this isn't possible in practice
        assert(move.effect != .MultiHit or move.bp > 0);
        if (!skip) {
            if (move.effect == .OHKO) {
                ohko = if (!showdown) side.active.stats.spe >= foe.active.stats.spe else true;
                // This can overflow after adjustDamage, but will still be sufficient to OHKO
                battle.last_damage = if (ohko) 65535 else 0;
                if (showdown) break :blk; // skip adjustDamage / randomizeDamage
            } else if (!calcDamage(battle, player, player.foe(), move, crit)) {
                return @as(?Result, Result.Error);
            }
            if (battle.last_damage == 0) {
                immune = true;
                effectiveness = 0;
            } else {
                effectiveness = adjustDamage(battle, player);
                immune = effectiveness == 0;
            }
            randomizeDamage(battle);
        }
    }

    // Due to control flow shenanigans we need to clear last_damage for Pokémon Showdown
    if (showdown and skip and move.effect != .Bide) battle.last_damage = 0;

    miss = if (showdown or skip)
        miss
    else
        (!moveHit(battle, player, move, &immune, &mist) or battle.last_damage == 0);

    assert(showdown or miss or battle.last_damage > 0 or skip);
    assert((!showdown and miss) or !(ohko and immune));
    assert(!immune or miss or move.effect == .Binding);

    if (!showdown or !miss) {
        if (move.effect == .MirrorMove) return mirrorMove(battle, player, mslot, log);
        if (move.effect == .Metronome) return metronome(battle, player, mslot, log);
        if (move.effect.onEnd()) {
            try onEnd(battle, player, move, log);
            return null;
        }
    }

    if (miss) {
        const foe_ident = battle.active(player.foe());
        if (!showdown and move.effect == .OHKO and side.active.stats.spe < foe.active.stats.spe) {
            try log.immune(foe_ident, .OHKO);
        } else if (immune) {
            try log.immune(foe_ident, .None);
        } else if (mist) {
            try log.activate(foe_ident, .Mist);
        } else {
            try log.lastmiss();
            try log.miss(battle.active(player));
        }
        if (move.effect == .JumpKick) {
            // Recoil is supposed to be damage/8 but damage will always be 0 here
            assert(battle.last_damage == 0);
            battle.last_damage = 1;
            _ = try applyDamage(battle, player, player.foe(), .None, log);
        } else if (move.effect == .Explode) {
            try Effects.explode(battle, player);
            if (foe.active.volatiles.Rage and foe.active.boosts.atk < 6) {
                try Effects.boost(battle, player.foe(), Move.get(.Rage), log);
            }
        } else if (showdown) {
            if (move.effect == .Disable) {
                if (foe.active.volatiles.Rage and foe.active.boosts.atk < 6) {
                    try Effects.boost(battle, player.foe(), Move.get(.Rage), log);
                }
            }
        }
        return null;
    }

    // On the cartridge MultiHit doesn't get set up until after damage has been applied for the
    // first time but its more convenient and efficient to set it up here (Pokémon Showdown sets
    // it up above before damage calculation).
    if (!showdown and move.effect.isMulti()) {
        Effects.multiHit(battle, player, move);
        hits = side.active.volatiles.attacks;
    }

    var nullified = false;
    var hit: u4 = 0;
    while (hit < hits) {
        if (hit == 0) {
            if (crit) try log.crit(battle.active(player.foe()));
            if (effectiveness > Effectiveness.neutral) {
                try log.supereffective(battle.active(player.foe()));
            } else if (effectiveness < Effectiveness.neutral) {
                try log.resisted(battle.active(player.foe()));
            }
        }
        if (!skip) nullified = try applyDamage(battle, player.foe(), player.foe(), .None, log);
        if (hit == 0 and ohko) try log.ohko();
        hit += 1;
        if (foe.stored().hp == 0) break;
        if (foe.active.volatiles.Rage and foe.active.boosts.atk < 6) {
            try Effects.boost(battle, player.foe(), Move.get(.Rage), log);
        }
        // If the substitute breaks during a multi-hit attack, the attack ends
        if (nullified) break;
    }

    if (side.active.volatiles.MultiHit) {
        side.active.volatiles.MultiHit = false;
        assert(nullified or foe.stored().hp == 0 or side.active.volatiles.attacks - hit == 0);
        side.active.volatiles.attacks = 0;
        if (showdown and move.effect == .Twineedle and !nullified and foe.stored().hp > 0) {
            try Effects.poison(battle, player, Move.get(.PoisonSting), log);
        }
        try log.hitcount(battle.active(player.foe()), hit);
    } else if (showdown) {
        // This should be handled much earlier but Pokémon Showdown does it here... ¯\_(ツ)_/¯
        if (move.effect == .Binding) {
            Effects.binding(battle, player);
            if (immune) {
                battle.last_damage = 0;
                // Pokémon Showdown logs |-damage| here instead of |-immune| because logic...
                try log.damage(battle.active(player.foe()), foe.stored(), .None);
                return null;
            }
        }
    }

    // Substitute being broken nullifies the move's effect completely so even
    // if an effect was intended to "always happen" it will still get skipped.
    if (nullified) return null;

    // On the cartridge, "always happen" effect handlers are called in the applyDamage loop above,
    // but this is only done to setup the MultiHit looping in the first place. Moving the MultiHit
    // setup before the loop means we can avoid having to waste time doing no-op handler searches.
    if (move.effect.alwaysHappens()) try alwaysHappens(battle, player, move, log);

    if (foe.stored().hp == 0) return null;

    if (!move.effect.isSpecial()) {
        // On the cartridge Rage is not considered to be "special" and thus gets executed for a
        // second time here (after being executed in the "always happens" block above) but that
        // doesn't matter since its idempotent (on the cartridge, but not in the implementation
        // below). For Twineedle we change the data to that of one with PoisonChance1 given its
        // MultiHit behavior is complete after the loop above, though Pokémon Showdown handles the
        // Twineedle secondary effect in the MultiHit cleanup block above because it incorrectly
        // puts the |-status| message before |-hitcount| instead of after.
        if (move.effect == .Twineedle) {
            if (!showdown) try Effects.poison(battle, player, Move.get(.PoisonSting), log);
        } else if (move.effect == .Disable) {
            return Effects.disable(battle, player, move, log);
        } else {
            try moveEffect(battle, player, move, log);
        }
    }

    return null;
}

fn checkCriticalHit(battle: anytype, player: Player, move: Move.Data) bool {
    const side = battle.side(player);

    // Base speed is used for the critical hit calculation, even when Transform-ed
    var chance = @as(u16, Species.chance(side.stored().species));
    // GLITCH: Focus Energy reduces critical hit chance instead of increasing it
    chance = if (side.active.volatiles.FocusEnergy) chance / 2 else @min(chance * 2, 255);
    chance = if (move.effect == .HighCritical) @min(chance * 4, 255) else chance / 2;

    if (showdown) return battle.rng.chance(u8, @intCast(u8, chance), 256);
    return std.math.rotl(u8, battle.rng.next(), 3) < chance;
}

fn calcDamage(
    battle: anytype,
    player: Player,
    target_player: Player,
    move: Move.Data,
    crit: bool,
) bool {
    assert(move.bp != 0);

    const side = battle.side(player);
    const target = battle.side(target_player);

    const special = move.type.special();

    // zig fmt: off
    var atk: u32 =
        if (crit)
            if (special) side.stored().stats.spc
            else side.stored().stats.atk
        else
            if (special) side.active.stats.spc
            else side.active.stats.atk;

    var def: u32 =
        if (crit)
            if (special) target.stored().stats.spc
            else target.stored().stats.def
        else
            // GLITCH: not capped to MAX_STAT_VALUE, can be 999 * 2 = 1998
            if (special)
                target.active.stats.spc * @as(u2, if (target.active.volatiles.LightScreen) 2 else 1)
            else
                target.active.stats.def * @as(u2, if (target.active.volatiles.Reflect) 2 else 1);
    // zig fmt: on

    if (atk > 255 or def > 255) {
        atk = @max((atk / 4) & 255, 1);
        // GLITCH: not adjusted to be a min of 1 on cartridge (can lead to division-by-zero freeze)
        def = @max((def / 4) & 255, if (showdown) 1 else 0);
    }

    const lvl = @as(u32, side.stored().level * @as(u2, if (crit) 2 else 1));

    def = @as(u32, if (move.effect == .Explode) @max(def / 2, 1) else def);

    if (def == 0) return false;

    var d: u32 = (lvl * 2 / 5) + 2;
    d *%= @as(u32, move.bp);
    d *%= atk;
    d /= def;
    d /= 50;
    d = @min(997, d);
    d += 2;

    battle.last_damage = @intCast(u16, d);

    return true;
}

fn adjustDamage(battle: anytype, player: Player) u16 {
    const side = battle.side(player);
    const foe = battle.foe(player);
    const types = foe.active.types;
    const move = Move.get(side.last_selected_move);

    var d = battle.last_damage;
    if (side.active.types.includes(move.type)) d +%= d / 2;

    const neutral = @enumToInt(Effectiveness.Neutral);
    const eff1: u16 = @enumToInt(move.type.effectiveness(types.type1));
    const eff2: u16 = @enumToInt(move.type.effectiveness(types.type2));

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

    battle.last_damage = d;
    return if (types.type1 == types.type2) eff1 * neutral else eff1 * eff2;
}

fn randomizeDamage(battle: anytype) void {
    if (battle.last_damage <= 1) return;

    const random = if (showdown)
        battle.rng.range(u8, 217, 256)
    else loop: {
        while (true) {
            const r = std.math.rotr(u8, battle.rng.next(), 1);
            if (r >= 217) break :loop r;
        }
    };

    battle.last_damage = @intCast(u16, @as(u32, battle.last_damage) *% random / 255);
}

fn specialDamage(battle: anytype, player: Player, move: Move.Data, log: anytype) !?Result {
    const side = battle.side(player);

    if (!try checkHit(battle, player, move, log)) return null;

    battle.last_damage = switch (side.last_selected_move) {
        .SuperFang => @max(battle.foe(player).active.stats.hp / 2, 1),
        .SeismicToss, .NightShade => side.stored().level,
        .SonicBoom => 20,
        .DragonRage => 40,
        // GLITCH: if power = 0 then a desync occurs (or a miss on Pokémon Showdown)
        .Psywave => power: {
            const max = @intCast(u8, @as(u16, side.stored().level) * 3 / 2);
            if (showdown) {
                break :power battle.rng.range(u8, 0, max);
            } else {
                // GLITCH: Psywave infinite glitch loop
                if (max <= 1) return Result.Error;
                while (true) {
                    const r = battle.rng.next();
                    if (r < max) break :power r;
                }
            }
        },
        else => unreachable,
    };

    if (battle.last_damage == 0) return if (showdown) null else Result.Error;

    _ = try applyDamage(battle, player.foe(), player.foe(), .None, log);
    return null;
}

fn counterDamage(battle: anytype, player: Player, move: Move.Data, log: anytype) !?Result {
    const foe = battle.foe(player);

    if (battle.last_damage == 0) {
        try log.fail(battle.active(player), .None);
        return null;
    }

    // Pretend Counter was used as a stand-in when no move has been used to fail below with 0 BP
    const foe_last_used_move =
        Move.get(if (foe.last_used_move == .None) .Counter else foe.last_used_move);
    const foe_last_selected_move =
        Move.get(if (foe.last_selected_move == .None or foe.last_selected_move == .SKIP_TURN)
        .Counter
    else
        foe.last_selected_move);

    const used = foe_last_used_move.bp > 0 and
        foe.last_used_move != .Counter and
        (foe_last_used_move.type == .Normal or
        foe_last_used_move.type == .Fighting);

    const selected = foe_last_selected_move.bp > 0 and
        foe.last_selected_move != .Counter and
        (foe_last_selected_move.type == .Normal or
        foe_last_selected_move.type == .Fighting);

    if (!used and !selected) {
        try log.fail(battle.active(player), .None);
        return null;
    }

    if (!used or !selected) {
        // GLITCH: Counter desync (covered by Desync Clause Mod on Pokémon Showdown)
        if (!showdown) return Result.Error;
        try log.fail(battle.active(player), .None);
        return null;
    }

    battle.last_damage = if (battle.last_damage > 0x7FFF) 0xFFFF else battle.last_damage * 2;

    // Pokémon Showdown calls checkHit before Counter
    if (!showdown and !try checkHit(battle, player, move, log)) return null;

    _ = try applyDamage(battle, player.foe(), player.foe(), .None, log);
    return null;
}

fn applyDamage(
    battle: anytype,
    target_player: Player,
    sub_player: Player,
    reason: Damage,
    log: anytype,
) !bool {
    assert(showdown or battle.last_damage != 0);

    var target = battle.side(target_player);
    // GLITCH: Substitute + Confusion glitch
    // We check if the target has a Substitute but then apply damage to the "sub player" which
    // isn't guaranteed to be the same (e.g. crash or confusion damage) or to even have a Substitute
    if (target.active.volatiles.Substitute) {
        var subbed = battle.side(sub_player);
        if (!subbed.active.volatiles.Substitute) return false;
        if (battle.last_damage >= subbed.active.volatiles.substitute) {
            subbed.active.volatiles.substitute = 0;
            subbed.active.volatiles.Substitute = false;
            // battle.last_damage is not updated with the amount of HP the Substitute had
            try log.end(battle.active(sub_player), .Substitute);
            return true;
        } else {
            // Safe to truncate since less than subbed.volatiles.substitute which is a u8
            subbed.active.volatiles.substitute -= @intCast(u8, battle.last_damage);
            try log.activate(battle.active(sub_player), .Substitute);
            return false;
        }
    }

    if (battle.last_damage > target.stored().hp) battle.last_damage = target.stored().hp;
    target.stored().hp -= battle.last_damage;
    try log.damage(battle.active(target_player), target.stored(), reason);
    return false;
}

fn mirrorMove(battle: anytype, player: Player, mslot: u4, log: anytype) !?Result {
    var side = battle.side(player);
    const foe = battle.foe(player);

    side.last_selected_move = foe.last_used_move;

    if (foe.last_used_move == .None or foe.last_used_move == .MirrorMove) {
        try log.fail(battle.active(player), .None);
        return null;
    }

    incrementPP(side, mslot);

    if (!try canMove(battle, player, mslot, false, false, .MirrorMove, log)) return null;
    return doMove(battle, player, mslot, log);
}

fn metronome(battle: anytype, player: Player, mslot: u4, log: anytype) !?Result {
    var side = battle.side(player);

    side.last_selected_move = if (showdown) blk: {
        const r = battle.rng.range(u8, 0, @enumToInt(Move.Struggle) - 2);
        const mod = @as(u2, (if (r < @enumToInt(Move.Metronome) - 1) 1 else 2));
        break :blk @intToEnum(Move, r + mod);
    } else loop: {
        while (true) {
            const r = battle.rng.next();
            if (r == 0 or r == @enumToInt(Move.Metronome)) continue;
            if (r >= @enumToInt(Move.Struggle)) continue;
            break :loop @intToEnum(Move, r);
        }
    };

    incrementPP(side, mslot);

    if (!try canMove(battle, player, mslot, false, false, .Metronome, log)) return null;
    return doMove(battle, player, mslot, log);
}

fn checkHit(battle: anytype, player: Player, move: Move.Data, log: anytype) !bool {
    var immune = false;
    var mist = false;
    if (moveHit(battle, player, move, &immune, &mist)) return true;
    assert(!immune);
    if (mist) {
        assert(!showdown);
        try log.activate(battle.active(player.foe()), .Mist);
    } else {
        try log.lastmiss();
        try log.miss(battle.active(player));
    }
    return false;
}

fn moveHit(battle: anytype, player: Player, move: Move.Data, immune: *bool, mist: *bool) bool {
    var side = battle.side(player);
    const foe = battle.foe(player);

    var miss = miss: {
        assert(!side.active.volatiles.Bide);

        if (move.effect == .DreamEater and !Status.is(foe.stored().status, .SLP)) {
            immune.* = true;
            break :miss true;
        }
        if (move.effect == .Swift) return true;
        if (foe.active.volatiles.Invulnerable) break :miss true;
        // Hyper Beam + Sleep glitch needs to be special cased here due to control flow differences
        if (showdown and move.effect == .Sleep and foe.active.volatiles.Recharging) return true;

        // Conversion / Haze / Light Screen / Reflect qualify but do not call moveHit
        if (foe.active.volatiles.Mist and move.effect.isStatDown()) {
            mist.* = true;
            if (!showdown) break :miss true;
        }

        // GLITCH: Thrash / Petal Dance / Rage get their accuracy overwritten on subsequent hits
        var state = &side.active.volatiles.state;
        const overwritten = (move.effect == .Thrashing or move.effect == .Rage) and state.* > 0;
        assert(!overwritten or (0 < state.* and state.* <= 255 and !side.active.volatiles.Bide));
        var accuracy = if (overwritten) state.* else @as(u16, Gen12.percent(move.accuracy));
        var boost = BOOSTS[@intCast(u4, @as(i8, side.active.boosts.accuracy) + 6)];
        accuracy = accuracy * boost[0] / boost[1];
        boost = BOOSTS[@intCast(u4, @as(i8, -foe.active.boosts.evasion) + 6)];
        accuracy = accuracy * boost[0] / boost[1];
        accuracy = @min(255, @max(1, accuracy));

        state.* = accuracy;

        // GLITCH: max accuracy is 255 so 1/256 chance of miss
        break :miss if (showdown)
            !battle.rng.chance(u8, @intCast(u8, accuracy), 256)
        else
            battle.rng.next() >= accuracy;
    };

    // Pokémon Showdown reports miss instead of fail for moves blocked by Mist that 1/256 miss
    if (showdown and mist.*) {
        mist.* = !miss;
        miss = true;
    }

    if (!miss) return true;
    battle.last_damage = 0;
    side.active.volatiles.Binding = false;
    return false;
}

fn checkFaint(
    battle: anytype,
    player: Player,
    log: anytype,
) @TypeOf(log).Error!?Result {
    const side = battle.side(player);
    if (side.stored().hp > 0) return null;

    const foe = battle.foe(player);
    const foe_fainted = foe.stored().hp == 0;

    const player_out = findFirstAlive(side) == 0;
    const foe_out = findFirstAlive(foe) == 0;
    const tie = player_out and foe_out;
    const more = tie or player_out or foe_out;

    if (try faint(battle, player, log, !(more or foe_fainted))) |r| return r;
    if (foe_fainted) if (try faint(battle, player.foe(), log, !more)) |r| return r;

    if (tie) {
        try log.tie();
        return Result.Tie;
    } else if (player_out) {
        try log.win(player.foe());
        return if (player == .P1) Result.Lose else Result.Win;
    } else if (foe_out) {
        try log.win(player);
        return if (player == .P1) Result.Win else Result.Lose;
    }

    const foe_choice: Choice.Type = if (foe_fainted) .Switch else .Pass;
    if (player == .P1) return Result{ .p1 = .Switch, .p2 = foe_choice };
    return Result{ .p1 = foe_choice, .p2 = .Switch };
}

fn faint(battle: anytype, player: Player, log: anytype, done: bool) !?Result {
    var side = battle.side(player);
    var foe = battle.foe(player);
    assert(side.stored().hp == 0);

    var foe_volatiles = &foe.active.volatiles;
    foe_volatiles.MultiHit = false;
    if (foe_volatiles.Bide) {
        assert(!foe_volatiles.Thrashing and !foe_volatiles.Rage);
        foe_volatiles.state = if (showdown) 0 else foe_volatiles.state & 255;
        if (foe_volatiles.state != 0) return Result.Error;
    }

    side.active.volatiles = .{};
    side.last_used_move = .None;
    try log.faint(battle.active(player), done);
    return null;
}

fn handleResidual(battle: anytype, player: Player, log: anytype) !void {
    var side = battle.side(player);
    var stored = side.stored();
    const ident = battle.active(player);
    var volatiles = &side.active.volatiles;

    const brn = Status.is(stored.status, .BRN);
    if (brn or Status.is(stored.status, .PSN)) {
        var damage = @max(stored.stats.hp / 16, 1);

        if (volatiles.Toxic) {
            volatiles.toxic += 1;
            damage *= volatiles.toxic;
        }

        stored.hp -= @min(damage, stored.hp);
        // Pokémon Showdown uses damageOf here but its not relevant in Generation I
        try log.damage(ident, stored, if (brn) Damage.Burn else Damage.Poison);
    }

    if (volatiles.LeechSeed) {
        var damage = @max(stored.stats.hp / 16, 1);

        // GLITCH: Leech Seed + Toxic glitch
        if (volatiles.Toxic) {
            volatiles.toxic += 1;
            damage *= volatiles.toxic;
        }

        stored.hp -= @min(damage, stored.hp);

        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        // As above, Pokémon Showdown uses damageOf but its not relevant
        try log.damage(ident, stored, .LeechSeed);

        const before = foe_stored.hp;
        // Uncapped damage is added back to the foe
        foe_stored.hp = @min(foe_stored.hp + damage, foe_stored.stats.hp);
        // Pokémon Showdown uses the less specific heal here instead of drain... because reasons?
        if (foe_stored.hp > before) try log.heal(foe_ident, foe_stored, .Silent);
    }
}

fn endTurn(battle: anytype, log: anytype) @TypeOf(log).Error!Result {
    if (showdown and options.ebc and checkEBC(battle)) {
        try log.tie();
        return Result.Tie;
    }

    battle.turn += 1;

    if (showdown and battle.turn >= 1000) {
        try log.tie();
        return Result.Tie;
    } else if (battle.turn >= 65535) {
        return Result.Error;
    }

    try log.turn(battle.turn);

    return Result.Default;
}

fn checkEBC(battle: anytype) bool {
    for (battle.sides, 0..) |side, i| {
        var foe_all_ghosts = true;
        var foe_all_transform = true;

        for (battle.sides[~@intCast(u1, i)].pokemon) |pokemon| {
            if (pokemon.species == .None) continue;

            const ghost = pokemon.hp == 0 or pokemon.types.includes(.Ghost);
            foe_all_ghosts = foe_all_ghosts and ghost;
            foe_all_transform = foe_all_transform and pokemon.hp == 0 or transform: {
                for (pokemon.moves) |m| {
                    if (m.id == .None) break :transform true;
                    if (m.id != .Transform) break :transform false;
                }
                break :transform true;
            };
        }

        for (side.pokemon) |pokemon| {
            if (pokemon.hp == 0 or Status.is(pokemon.status, .FRZ)) continue;
            const transform = foe_all_transform and transform: {
                for (pokemon.moves) |m| {
                    if (m.id == .None) break :transform true;
                    if (m.id != .Transform) break :transform false;
                }
                break :transform true;
            };
            if (transform) continue;
            const no_pp = foe_all_ghosts and no_pp: {
                for (pokemon.moves) |m| {
                    if (m.pp != 0) break :no_pp false;
                }
                break :no_pp true;
            };
            if (no_pp) continue;

            return false;
        }

        if (i == 1) return true;
    }

    return false;
}

inline fn onBegin(battle: anytype, player: Player, move: Move.Data, mslot: u8, log: anytype) !void {
    assert(move.effect.onBegin());
    return switch (move.effect) {
        .Confusion => Effects.confusion(battle, player, move, log),
        .Conversion => Effects.conversion(battle, player, log),
        .FocusEnergy => Effects.focusEnergy(battle, player, log),
        .Haze => Effects.haze(battle, player, log),
        .Heal => Effects.heal(battle, player, log),
        .LeechSeed => Effects.leechSeed(battle, player, move, log),
        .LightScreen => Effects.lightScreen(battle, player, log),
        .Mimic => Effects.mimic(battle, player, move, mslot, log),
        .Mist => Effects.mist(battle, player, log),
        .Paralyze => Effects.paralyze(battle, player, move, log),
        .Poison => Effects.poison(battle, player, move, log),
        .Reflect => Effects.reflect(battle, player, log),
        .Splash => Effects.splash(battle, player, log),
        .Substitute => Effects.substitute(battle, player, log),
        .SwitchAndTeleport => Effects.switchAndTeleport(battle, player, move, log),
        .Transform => Effects.transform(battle, player, log),
        else => unreachable,
    };
}

inline fn onEnd(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
    assert(move.effect.onEnd());
    return switch (move.effect) {
        .Bide => Effects.bide(battle, player, log),
        // zig fmt: off
        .AttackUp1, .AttackUp2, .DefenseUp1, .DefenseUp2,
        .EvasionUp1, .SpecialUp1, .SpecialUp2, .SpeedUp2 =>
            Effects.boost(battle, player, move, log),
        .AccuracyDown1, .AttackDown1, .DefenseDown1, .DefenseDown2, .SpeedDown1 =>
            Effects.unboost(battle, player, move, log),
        // zig fmt: on
        .Sleep => Effects.sleep(battle, player, move, log),
        else => unreachable,
    };
}

inline fn alwaysHappens(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
    assert(move.effect.alwaysHappens());
    return switch (move.effect) {
        .DrainHP, .DreamEater => Effects.drainHP(battle, player, log),
        .Explode => Effects.explode(battle, player),
        .PayDay => Effects.payDay(log),
        .Rage => Effects.rage(battle, player),
        .Recoil => Effects.recoil(battle, player, log),
        .JumpKick, .Binding => {},
        else => unreachable,
    };
}

inline fn moveEffect(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
    return switch (move.effect) {
        .BurnChance1, .BurnChance2 => Effects.burnChance(battle, player, move, log),
        .ConfusionChance => Effects.confusion(battle, player, move, log),
        .FlinchChance1, .FlinchChance2 => Effects.flinchChance(battle, player, move),
        .FreezeChance => Effects.freezeChance(battle, player, move, log),
        .HyperBeam => Effects.hyperBeam(battle, player, log),
        .MultiHit, .DoubleHit, .Twineedle => Effects.multiHit(battle, player, move),
        .ParalyzeChance1, .ParalyzeChance2 => Effects.paralyzeChance(battle, player, move, log),
        .PoisonChance1, .PoisonChance2 => Effects.poison(battle, player, move, log),
        // zig fmt: off
        .AttackDownChance, .DefenseDownChance, .SpecialDownChance, .SpeedDownChance =>
            Effects.unboost(battle, player, move, log),
        // zig fmt: on
        else => {},
    };
}

pub const Effects = struct {
    fn bide(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);

        side.active.volatiles.Bide = true;
        assert(!side.active.volatiles.Thrashing and !side.active.volatiles.Rage);
        side.active.volatiles.state = 0;
        side.active.volatiles.attacks = @intCast(u3, if (showdown)
            battle.rng.range(u4, 2, 4)
        else
            (battle.rng.next() & 1) + 2);

        try log.start(battle.active(player), .Bide);
    }

    fn burnChance(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute) return;

        if (Status.any(foe_stored.status)) {
            if (showdown and !foe.active.types.includes(move.type)) battle.rng.advance(1);
            // GLITCH: Freeze top move selection desync can occur if thawed Pokémon is slower
            if (Status.is(foe_stored.status, .FRZ)) {
                assert(move.type == .Fire);
                try log.curestatus(battle.active(player.foe()), foe_stored.status, .Message);
                foe_stored.status = 0;
            }
            return;
        }

        const chance = !foe.active.types.includes(move.type) and if (showdown)
            battle.rng.chance(u8, @as(u8, if (move.effect == .BurnChance1) 26 else 77), 256)
        else
            battle.rng.next() < 1 + (if (move.effect == .BurnChance1)
                Gen12.percent(10)
            else
                Gen12.percent(30));
        if (!chance) return;

        foe_stored.status = Status.init(.BRN);
        foe.active.stats.atk = @max(foe.active.stats.atk / 2, 1);

        try log.status(battle.active(player.foe()), foe_stored.status, .None);
    }

    fn charge(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        volatiles.Charging = true;
        const move = side.last_selected_move;
        if (move == .Fly or move == .Dig) volatiles.Invulnerable = true;
        try log.laststill();
        try log.prepare(battle.active(player), move);
    }

    fn confusion(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        const sub = foe.active.volatiles.Substitute;

        if (move.effect == .ConfusionChance) {
            const chance = if (showdown)
                battle.rng.chance(u8, 25, 256)
            else
                battle.rng.next() < Gen12.percent(10);
            if (!chance) return;
        } else {
            if (showdown) {
                if (!try checkHit(battle, player, move, log)) {
                    return;
                } else if (sub) {
                    return log.fail(battle.active(player.foe()), .None);
                }
            } else {
                if (sub) {
                    return log.fail(battle.active(player.foe()), .None);
                } else if (!try checkHit(battle, player, move, log)) {
                    return;
                }
            }
        }

        if (foe.active.volatiles.Confusion) return;
        foe.active.volatiles.Confusion = true;
        foe.active.volatiles.confusion = @intCast(u3, if (showdown)
            battle.rng.range(u8, 2, 6)
        else
            (battle.rng.next() & 3) + 2);

        try log.start(battle.active(player.foe()), .Confusion);
    }

    fn conversion(battle: anytype, player: Player, log: anytype) !void {
        const foe = battle.foe(player);

        if (foe.active.volatiles.Invulnerable) {
            try log.lastmiss();
            return log.miss(battle.active(player));
        }

        battle.side(player).active.types = foe.active.types;
        return log.typechange(battle.active(player), foe.active.types);
    }

    fn disable(battle: anytype, player: Player, move: Move.Data, log: anytype) !?Result {
        var foe = battle.foe(player);
        var volatiles = &foe.active.volatiles;
        const foe_ident = battle.active(player.foe());

        // Pokémon Showdown handles hit/miss earlier in doMove
        if (!showdown and !try checkHit(battle, player, move, log)) return null;

        if (volatiles.disabled_move != 0) {
            try log.fail(foe_ident, .None);
            return null;
        }

        var n: u4 = 0;
        var err = true;
        for (foe.active.moves) |m| {
            if (m.pp > 0) {
                n += 1;
                if (m.id != .None) err = false;
            }
        }

        // Technically this is still considered simply a "miss" on the cartridge,
        // but diverging from Pokémon Showdown here would mostly just be pedantic
        if (n == 0) {
            try log.fail(foe_ident, .None);
            return null;
        } else if (err) {
            // GLITCH: Transform + Mirror Move / Metronome PP softlock
            assert(!showdown);
            return Result.Error;
        }

        volatiles.disabled_move = @intCast(u3, randomMoveSlot(&battle.rng, &foe.active.moves, n));
        volatiles.disabled_duration = @intCast(u4, if (showdown)
            battle.rng.range(u8, 1, 9)
        else
            (battle.rng.next() & 7) + 1);

        try log.startEffect(foe_ident, .Disable, foe.active.move(volatiles.disabled_move).id);
        return null;
    }

    fn drainHP(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        var stored = side.stored();

        const drain = @max(battle.last_damage / 2, 1);
        battle.last_damage = drain;

        if (stored.hp == stored.stats.hp) return;
        stored.hp = @min(stored.stats.hp, stored.hp + drain);

        try log.drain(battle.active(player), stored, battle.active(player.foe()));
    }

    fn explode(battle: anytype, player: Player) !void {
        var side = battle.side(player);
        var stored = side.stored();

        stored.hp = 0;
        stored.status = 0;
        side.active.volatiles.LeechSeed = false;
    }

    fn flinchChance(battle: anytype, player: Player, move: Move.Data) void {
        var volatiles = &battle.foe(player).active.volatiles;

        if (volatiles.Substitute) return;

        const chance = if (showdown)
            battle.rng.chance(u8, @as(u8, if (move.effect == .FlinchChance1) 26 else 77), 256)
        else
            battle.rng.next() < 1 + (if (move.effect == .FlinchChance1)
                Gen12.percent(10)
            else
                Gen12.percent(30));
        if (!chance) return;

        volatiles.Flinch = true;
        volatiles.Recharging = false;
    }

    fn focusEnergy(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.FocusEnergy) return;
        side.active.volatiles.FocusEnergy = true;

        try log.start(battle.active(player), .FocusEnergy);
    }

    fn freezeChance(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Substitute) return;

        if (Status.any(foe_stored.status)) {
            return if (showdown and !foe.active.types.includes(move.type)) battle.rng.advance(1);
        }

        const chance = !foe.active.types.includes(move.type) and if (showdown)
            battle.rng.chance(u8, 26, 256)
        else
            battle.rng.next() < 1 + Gen12.percent(10);
        if (!chance) return;

        // Freeze Clause Mod
        if (showdown) for (foe.pokemon) |p| if (Status.is(p.status, .FRZ)) return;

        foe_stored.status = Status.init(.FRZ);
        // GLITCH: Hyper Beam recharging status is not cleared

        try log.status(foe_ident, foe_stored.status, .None);
    }

    fn haze(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        var side_stored = side.stored();
        var foe_stored = foe.stored();

        const player_ident = battle.active(player);
        const foe_ident = battle.active(player.foe());

        side.active.boosts = .{};
        foe.active.boosts = .{};

        side.active.stats = side_stored.stats;
        foe.active.stats = foe_stored.stats;

        try log.activate(player_ident, .Haze);
        try log.clearallboost();

        // Pokémon Showdown clears P1 then P2 instead of status -> side -> foe
        if (showdown) {
            for (&battle.sides, 0..) |*s, i| {
                const p = @intToEnum(Player, i);
                // Pokémon Showdown incorrectly does not prevent sleep/freeze from moving
                if (p != player and Status.any(s.stored().status)) {
                    try log.curestatus(foe_ident, foe_stored.status, .Silent);
                    s.stored().status = 0;
                }
                try clearVolatiles(&s.active, battle.active(p), log);
            }
        } else {
            if (Status.any(foe_stored.status)) {
                if (Status.is(foe_stored.status, .FRZ) or Status.is(foe_stored.status, .SLP)) {
                    foe.last_selected_move = .SKIP_TURN;
                }
                try log.curestatus(foe_ident, foe_stored.status, .Silent);
                foe_stored.status = 0;
            }
            try clearVolatiles(&side.active, player_ident, log);
            try clearVolatiles(&foe.active, foe_ident, log);
        }
    }

    fn heal(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        var stored = side.stored();
        const ident = battle.active(player);

        // GLITCH: HP recovery move failure glitches
        const delta = stored.stats.hp - stored.hp;
        if (delta == 0 or delta & 255 == 255) return try log.fail(ident, .None);

        const rest = side.last_selected_move == .Rest;
        if (rest) {
            // Adding the sleep status runs the sleep condition handler to roll duration
            if (showdown) battle.rng.advance(1);
            stored.status = Status.slf(2);
            try log.statusFrom(ident, stored.status, Move.Rest);
            stored.hp = stored.stats.hp;
        } else {
            stored.hp = @min(stored.stats.hp, stored.hp + (stored.stats.hp / 2));
        }
        try log.heal(ident, stored, if (rest) Heal.Silent else Heal.None);
    }

    fn hyperBeam(battle: anytype, player: Player, log: anytype) !void {
        battle.side(player).active.volatiles.Recharging = true;
        try log.mustrecharge(battle.active(player));
    }

    fn leechSeed(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);

        if (showdown) {
            if (foe.active.types.includes(.Grass)) {
                return log.immune(battle.active(player.foe()), .None);
            }
            if (!try checkHit(battle, player, move, log)) return;
            if (foe.active.volatiles.LeechSeed) return;
        } else {
            if (!try checkHit(battle, player, move, log)) return;
            if (foe.active.types.includes(.Grass) or foe.active.volatiles.LeechSeed) {
                try log.lastmiss();
                return log.miss(battle.active(player));
            }
        }

        foe.active.volatiles.LeechSeed = true;

        try log.start(battle.active(player.foe()), .LeechSeed);
    }

    fn lightScreen(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.LightScreen) return log.fail(battle.active(player), .None);
        side.active.volatiles.LightScreen = true;

        try log.start(battle.active(player), .LightScreen);
    }

    fn mimic(battle: anytype, player: Player, move: Move.Data, mslot: u8, log: anytype) !void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        // Pokémon Showdown incorrectly requires the user to have Mimic (but not necessarily at
        // mslot). In reality, Mimic can also be called via Metronome or Mirror Move
        assert(showdown or side.active.move(mslot).id == .Mimic or
            side.active.move(mslot).id == .Metronome or
            side.active.move(mslot).id == .MirrorMove);

        // Pokémon Showdown incorrectly replaces the existing Mimic's slot instead of mslot
        var oslot = mslot;
        if (showdown) {
            const has_mimic = has_mimic: {
                for (side.active.moves, 0..) |m, i| {
                    if (m.id == .Mimic) {
                        oslot = @intCast(u8, i + 1);
                        break :has_mimic true;
                    }
                }
                break :has_mimic false;
            };
            if (!has_mimic) return;
        }
        if (!try checkHit(battle, player, move, log)) return;

        const rslot = randomMoveSlot(&battle.rng, &foe.active.moves, 0);
        side.active.move(oslot).id = foe.active.move(rslot).id;

        try log.startEffect(battle.active(player), .Mimic, side.active.move(oslot).id);
    }

    fn mist(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.Mist) return;
        side.active.volatiles.Mist = true;

        try log.start(battle.active(player), .Mist);
    }

    fn multiHit(battle: anytype, player: Player, move: Move.Data) void {
        var side = battle.side(player);

        assert(!side.active.volatiles.MultiHit);
        side.active.volatiles.MultiHit = true;

        side.active.volatiles.attacks = if (move.effect == .MultiHit) distribution(battle) else 2;
    }

    fn paralyze(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        // Only Thunder Wave checks for type-immunity, not Glare
        const immune = move.type == .Electric and foe.active.types.immune(move.type);

        if (showdown) {
            if (immune) return log.immune(foe_ident, .None);
            if (!try checkHit(battle, player, move, log)) return;
        }
        if (Status.any(foe_stored.status)) {
            return log.fail(
                foe_ident,
                if (Status.is(foe_stored.status, .PAR)) .Paralysis else .None,
            );
        }
        if (!showdown) {
            if (immune) return log.immune(foe_ident, .None);
            if (!try checkHit(battle, player, move, log)) return;
        }

        foe_stored.status = Status.init(.PAR);
        foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);

        try log.status(foe_ident, foe_stored.status, .None);
    }

    fn paralyzeChance(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute or Status.any(foe_stored.status)) {
            return if (showdown and !foe.active.types.includes(move.type)) battle.rng.advance(1);
        }

        // Body Slam can't paralyze a Normal type Pokémon
        const chance = !foe.active.types.includes(move.type) and if (showdown)
            battle.rng.chance(u8, @as(u8, if (move.effect == .ParalyzeChance1) 26 else 77), 256)
        else
            battle.rng.next() < 1 + (if (move.effect == .ParalyzeChance1)
                Gen12.percent(10)
            else
                Gen12.percent(30));
        if (!chance) return;

        foe_stored.status = Status.init(.PAR);
        foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);

        try log.status(battle.active(player.foe()), foe_stored.status, .None);
    }

    fn payDay(log: anytype) !void {
        try log.fieldactivate();
    }

    fn poison(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());
        const sub = foe.active.volatiles.Substitute;

        if (showdown and move.effect == .Poison and !try checkHit(battle, player, move, log)) {
            return;
        } else if (sub or Status.any(foe_stored.status)) {
            if (move.effect != .Poison) return if (showdown and !sub) battle.rng.advance(1);
            return log.fail(foe_ident, if (Status.is(foe_stored.status, .PSN)) .Poison else .None);
        } else if (foe.active.types.includes(.Poison)) {
            if (move.effect != .Poison) return if (showdown) battle.rng.advance(1);
            return log.immune(foe_ident, .None);
        }

        if (move.effect == .Poison) {
            if (!showdown and !try checkHit(battle, player, move, log)) return;
        } else {
            const chance = if (showdown)
                battle.rng.chance(u8, @as(u8, if (move.effect == .PoisonChance1) 52 else 103), 256)
            else
                battle.rng.next() < 1 + (if (move.effect == .PoisonChance1)
                    Gen12.percent(20)
                else
                    Gen12.percent(40));
            if (!chance) return;
        }

        foe_stored.status = Status.init(.PSN);
        if (battle.side(player).last_selected_move == .Toxic) {
            foe.active.volatiles.Toxic = true;
            foe.active.volatiles.toxic = 0;
        }

        try log.status(foe_ident, foe_stored.status, .None);
    }

    fn rage(battle: anytype, player: Player) !void {
        var volatiles = &battle.side(player).active.volatiles;
        volatiles.Rage = true;
        assert(!volatiles.Bide);
        volatiles.state = 0;
    }

    fn recoil(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        var stored = side.stored();

        const damage = @intCast(i16, @max(battle.last_damage /
            @as(u8, if (side.last_selected_move == .Struggle) 2 else 4), 1));
        stored.hp = @intCast(u16, @max(@intCast(i16, stored.hp) - damage, 0));

        try log.damageOf(battle.active(player), stored, .RecoilOf, battle.active(player.foe()));
    }

    fn reflect(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.Reflect) return log.fail(battle.active(player), .None);
        side.active.volatiles.Reflect = true;

        try log.start(battle.active(player), .Reflect);
    }

    fn sleep(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Recharging) {
            // Hit test not applied if the target is recharging (bypass)
            // The volatile itself actually gets cleared below since on Pokémon Showdown
            // the Sleep Clause Mod might activate, causing us to not actually bypass
        } else {
            if (Status.any(foe_stored.status)) {
                return log.fail(
                    foe_ident,
                    if (Status.is(foe_stored.status, .SLP)) .Sleep else .None,
                );
            }
            // If checkHit in doMove didn't return true Pokémon Showdown wouldn't be in here
            if (!showdown and !try checkHit(battle, player, move, log)) return;
        }

        // Sleep Clause Mod
        if (showdown) {
            for (foe.pokemon) |p| {
                if (Status.is(p.status, .SLP) and !Status.is(p.status, .SLF)) return;
            }
        }
        foe.active.volatiles.Recharging = false;

        const duration = @intCast(u3, if (showdown)
            battle.rng.range(u8, 1, 8)
        else loop: {
            while (true) {
                const r = battle.rng.next() & 7;
                if (r != 0) break :loop r;
            }
        });

        foe_stored.status = Status.slp(duration);
        try log.statusFrom(foe_ident, foe_stored.status, battle.side(player).last_selected_move);
    }

    fn splash(battle: anytype, player: Player, log: anytype) !void {
        try log.activate(battle.active(player), .Splash);
    }

    fn substitute(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        if (side.active.volatiles.Substitute) {
            try log.fail(battle.active(player), .Substitute);
            return;
        }

        assert(side.stored().stats.hp <= 1023);
        // Will be 0 if HP is <= 3 meaning that the user gets a 1 HP Substitute for "free"
        const hp = @intCast(u8, side.stored().stats.hp / 4);
        if (side.stored().hp < hp) {
            try log.fail(battle.active(player), .Weak);
            return;
        }

        // GLITCH: can leave the user with 0 HP (faints later) because didn't check '<=' above
        side.stored().hp -= hp;
        side.active.volatiles.substitute = hp + 1;
        side.active.volatiles.Substitute = true;
        try log.start(battle.active(player), .Substitute);
        if (hp > 0) try log.damage(battle.active(player), side.stored(), .None);
    }

    fn switchAndTeleport(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        if (!showdown or battle.side(player).last_selected_move == .Teleport) return;

        // Whirlwind/Roar should not roll to hit but Pokémon Showdown does anyway
        _ = try checkHit(battle, player, move, log);
    }

    fn thrashing(battle: anytype, player: Player) void {
        var volatiles = &battle.side(player).active.volatiles;
        assert(!volatiles.Thrashing);
        assert(!volatiles.Bide);

        volatiles.Thrashing = true;
        volatiles.state = 0;
        volatiles.attacks = @intCast(u3, if (showdown)
            battle.rng.range(u8, 2, 4)
        else
            (battle.rng.next() & 1) + 2);
    }

    fn transform(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const foe = battle.foe(player);
        const foe_ident = battle.active(player.foe());

        side.active.volatiles.Transform = true;
        // foe could themselves be transformed
        side.active.volatiles.transform = if (foe.active.volatiles.transform != 0)
            foe.active.volatiles.transform
        else
            foe_ident.int();

        // HP is not copied by Transform
        side.active.stats.atk = foe.active.stats.atk;
        side.active.stats.def = foe.active.stats.def;
        side.active.stats.spe = foe.active.stats.spe;
        side.active.stats.spc = foe.active.stats.spc;

        side.active.species = foe.active.species;
        side.active.types = foe.active.types;
        side.active.boosts = foe.active.boosts;
        for (foe.active.moves, 0..) |m, i| {
            side.active.moves[i].id = m.id;
            side.active.moves[i].pp = if (m.id != .None) 5 else 0;
        }

        try log.transform(battle.active(player), foe_ident);
    }

    fn binding(battle: anytype, player: Player) void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        if (side.active.volatiles.Binding) return;
        side.active.volatiles.Binding = true;
        // GLITCH: Hyper Beam automatic selection glitch if Recharging gets cleared on miss
        // (Pokémon Showdown unitentionally patches this glitch, preventing automatic selection)
        if (!showdown) foe.active.volatiles.Recharging = false;

        side.active.volatiles.attacks = distribution(battle) - 1;
    }

    fn boost(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var side = battle.side(player);
        const ident = battle.active(player);

        var stats = &side.active.stats;
        var boosts = &side.active.boosts;

        switch (move.effect) {
            .AttackUp1, .AttackUp2, .Rage => {
                assert(boosts.atk >= -6 and boosts.atk <= 6);
                if (boosts.atk == 6) return try log.fail(ident, .None);
                const n: u2 = if (move.effect == .AttackUp2) 2 else 1;
                boosts.atk = @intCast(i4, @min(6, @as(i8, boosts.atk) + n));
                const reason = if (move.effect == .Rage) Boost.Rage else Boost.Attack;
                if (stats.atk == MAX_STAT_VALUE) {
                    boosts.atk -= 1;
                    if (showdown) {
                        try log.boost(ident, reason, n);
                        try log.boost(ident, reason, -1);
                    } else {
                        try log.fail(ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.atk) + 6)];
                const stat = unmodifiedStats(battle, player).atk;
                stats.atk = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, reason, n);
            },
            .DefenseUp1, .DefenseUp2 => {
                assert(boosts.def >= -6 and boosts.def <= 6);
                if (boosts.def == 6) return try log.fail(ident, .None);
                const n: u2 = if (move.effect == .DefenseUp2) 2 else 1;
                boosts.def = @intCast(i4, @min(6, @as(i8, boosts.def) + n));
                if (stats.def == MAX_STAT_VALUE) {
                    boosts.def -= 1;
                    if (showdown) {
                        try log.boost(ident, .Defense, n);
                        try log.boost(ident, .Defense, -1);
                    } else {
                        try log.fail(ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.def) + 6)];
                const stat = unmodifiedStats(battle, player).def;
                stats.def = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .Defense, n);
            },
            .SpeedUp2 => {
                assert(boosts.spe >= -6 and boosts.spe <= 6);
                if (boosts.spe == 6) return try log.fail(ident, .None);
                boosts.spe = @intCast(i4, @min(6, @as(i8, boosts.spe) + 2));
                if (stats.spe == MAX_STAT_VALUE) {
                    boosts.spe -= 1;
                    if (showdown) {
                        try log.boost(ident, .Speed, 2);
                        try log.boost(ident, .Speed, -1);
                    } else {
                        try log.fail(ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spe) + 6)];
                const stat = unmodifiedStats(battle, player).spe;
                stats.spe = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .Speed, 2);
            },
            .SpecialUp1, .SpecialUp2 => {
                assert(boosts.spc >= -6 and boosts.spc <= 6);
                if (boosts.spc == 6) return try log.fail(ident, .None);
                const n: u2 = if (move.effect == .SpecialUp2) 2 else 1;
                boosts.spc = @intCast(i4, @min(6, @as(i8, boosts.spc) + n));
                if (stats.spc == MAX_STAT_VALUE) {
                    boosts.spc -= 1;
                    if (showdown) {
                        try log.boost(ident, .SpecialAttack, n);
                        try log.boost(ident, .SpecialAttack, -1);
                        try log.boost(ident, .SpecialDefense, n);
                        try log.boost(ident, .SpecialDefense, -1);
                    } else {
                        try log.fail(ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spc) + 6)];
                const stat = unmodifiedStats(battle, player).spc;
                stats.spc = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .SpecialAttack, n);
                try log.boost(ident, .SpecialDefense, n);
            },
            .EvasionUp1 => {
                assert(boosts.evasion >= -6 and boosts.evasion <= 6);
                if (boosts.evasion == 6) return try log.fail(ident, .None);
                boosts.evasion = @intCast(i4, @min(6, @as(i8, boosts.evasion) + 1));
                try log.boost(ident, .Evasion, 1);
            },
            else => unreachable,
        }

        // GLITCH: Stat modification errors glitch
        statusModify(battle.foe(player).stored().status, &battle.foe(player).active.stats);
    }

    fn unboost(battle: anytype, player: Player, move: Move.Data, log: anytype) !void {
        var foe = battle.foe(player);
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Substitute) {
            return if (!move.effect.isStatDownChance()) log.fail(foe_ident, .None);
        }

        if (move.effect.isStatDownChance()) {
            const chance = if (showdown)
                battle.rng.chance(u8, 85, 256)
            else
                battle.rng.next() < Gen12.percent(33) + 1;
            if (!chance or foe.active.volatiles.Invulnerable) return;
        } else if (!showdown and !try checkHit(battle, player, move, log)) {
            return; // checkHit already checks for Invulnerable
        }

        var stats = &foe.active.stats;
        var boosts = &foe.active.boosts;

        switch (move.effect) {
            .AttackDown1, .AttackDownChance => {
                assert(boosts.atk >= -6 and boosts.atk <= 6);
                if (boosts.atk == -6) return try log.fail(foe_ident, .None);
                boosts.atk = @intCast(i4, @max(-6, @as(i8, boosts.atk) - 1));
                if (stats.atk == 1) {
                    boosts.atk += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .Attack, -1);
                        try log.boost(foe_ident, .Attack, 1);
                    } else {
                        try log.fail(foe_ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.atk) + 6)];
                const stat = unmodifiedStats(battle, player.foe()).atk;
                stats.atk = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Attack, -1);
            },
            .DefenseDown1, .DefenseDown2, .DefenseDownChance => {
                assert(boosts.def >= -6 and boosts.def <= 6);
                if (boosts.def == -6) return try log.fail(foe_ident, .None);
                const n: u2 = if (move.effect == .DefenseDown2) 2 else 1;
                boosts.def = @intCast(i4, @max(-6, @as(i8, boosts.def) - n));
                if (stats.def == 1) {
                    boosts.def += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .Defense, -@as(i8, n));
                        try log.boost(foe_ident, .Defense, 1);
                    } else {
                        try log.fail(foe_ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.def) + 6)];
                const stat = unmodifiedStats(battle, player.foe()).def;
                stats.def = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Defense, -@as(i8, n));
            },
            .SpeedDown1, .SpeedDownChance => {
                assert(boosts.spe >= -6 and boosts.spe <= 6);
                if (boosts.spe == -6) return try log.fail(foe_ident, .None);
                boosts.spe = @intCast(i4, @max(-6, @as(i8, boosts.spe) - 1));
                if (stats.spe == 1) {
                    boosts.spe += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .Speed, -1);
                        try log.boost(foe_ident, .Speed, 1);
                    } else {
                        try log.fail(foe_ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spe) + 6)];
                const stat = unmodifiedStats(battle, player.foe()).spe;
                stats.spe = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Speed, -1);
                assert(boosts.spe >= -6);
            },
            .SpecialDownChance => {
                assert(boosts.spc >= -6 and boosts.spc <= 6);
                if (boosts.spc == -6) return try log.fail(foe_ident, .None);
                boosts.spc = @intCast(i4, @max(-6, @as(i8, boosts.spc) - 1));
                if (stats.spc == 1) {
                    boosts.spc += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .SpecialAttack, -1);
                        try log.boost(foe_ident, .SpecialAttack, 1);
                        try log.boost(foe_ident, .SpecialDefense, -1);
                        try log.boost(foe_ident, .SpecialDefense, 1);
                    } else {
                        try log.fail(foe_ident, .None);
                    }
                    return;
                }
                var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spc) + 6)];
                const stat = unmodifiedStats(battle, player.foe()).spc;
                stats.spc = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .SpecialAttack, -1);
                try log.boost(foe_ident, .SpecialDefense, -1);
            },
            .AccuracyDown1 => {
                assert(boosts.accuracy >= -6 and boosts.accuracy <= 6);
                if (boosts.accuracy == -6) return try log.fail(foe_ident, .None);
                boosts.accuracy = @intCast(i4, @max(-6, @as(i8, boosts.accuracy) - 1));
                try log.boost(foe_ident, .Accuracy, -1);
            },
            else => unreachable,
        }

        // GLITCH: Stat modification errors glitch
        statusModify(foe.stored().status, stats);
    }
};

fn unmodifiedStats(battle: anytype, who: Player) *Stats(u16) {
    const side = battle.side(who);
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

fn isForced(active: ActivePokemon) bool {
    return active.volatiles.Recharging or active.volatiles.Rage or
        active.volatiles.Thrashing or active.volatiles.Charging;
}

fn clearVolatiles(active: *ActivePokemon, ident: ID, log: anytype) !void {
    var volatiles = &active.volatiles;
    if (volatiles.disabled_move != 0) {
        volatiles.disabled_move = 0;
        volatiles.disabled_duration = 0;
        try log.end(ident, .DisableSilent);
    }
    if (volatiles.Confusion) {
        // volatiles.confusion is left unchanged
        volatiles.Confusion = false;
        try log.end(ident, .ConfusionSilent);
    }
    if (volatiles.Mist) {
        volatiles.Mist = false;
        try log.end(ident, .Mist);
    }
    if (volatiles.FocusEnergy) {
        volatiles.FocusEnergy = false;
        try log.end(ident, .FocusEnergy);
    }
    if (volatiles.LeechSeed) {
        volatiles.LeechSeed = false;
        try log.end(ident, .LeechSeed);
    }
    if (volatiles.Toxic) {
        volatiles.Toxic = false;
        // volatiles.toxic is left unchanged, except on Pokémon Showdown which clears it
        if (showdown) {
            volatiles.toxic = 0;
            try log.end(ident, .Toxic);
        }
    }
    if (volatiles.LightScreen) {
        volatiles.LightScreen = false;
        try log.end(ident, .LightScreen);
    }
    if (volatiles.Reflect) {
        volatiles.Reflect = false;
        try log.end(ident, .Reflect);
    }
}

fn handleThrashing(battle: anytype, active: *ActivePokemon) bool {
    var volatiles = &active.volatiles;
    assert(volatiles.Thrashing);
    if (volatiles.attacks > 0) return false;

    volatiles.Thrashing = false;
    volatiles.Confusion = true;
    volatiles.confusion = @intCast(u3, if (showdown)
        battle.rng.range(u8, 2, 6)
    else
        (battle.rng.next() & 3) + 2);

    return true;
}

const DISTRIBUTION = [_]u3{ 2, 2, 3, 3, 4, 5 };

fn distribution(battle: anytype) u3 {
    if (showdown) return DISTRIBUTION[battle.rng.range(u8, 0, DISTRIBUTION.len)];
    const r = (battle.rng.next() & 3);
    return @intCast(u3, (if (r < 2) r else battle.rng.next() & 3) + 2);
}

fn randomMoveSlot(rand: anytype, moves: []MoveSlot, check_pp: u4) u4 {
    if (showdown) {
        if (check_pp == 0) {
            var i: usize = moves.len;
            while (i > 0) {
                i -= 1;
                if (moves[i].id != .None) return rand.range(u4, 0, @intCast(u4, i + 1)) + 1;
            }
        } else {
            var r = rand.range(u4, 0, @intCast(u4, check_pp)) + 1;
            var i: usize = 0;
            while (i < moves.len and r > 0) : (i += 1) {
                if (moves[i].pp > 0) {
                    r -= 1;
                    if (r == 0) break;
                }
            }
            return @intCast(u4, i + 1);
        }
    }

    while (true) {
        const r = @intCast(u4, rand.next() & 3);
        if (moves[r].id != .None and (check_pp == 0 or moves[r].pp > 0)) return r + 1;
    }
}

test "RNG agreement" {
    if (!showdown) return;
    var expected: [256]u32 = undefined;
    for (0..expected.len) |i| {
        expected[i] = @intCast(u32, i * 0x1000000);
    }

    var spe = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var cfz = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var par = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var brn = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var eff = rng.FixedRNG(1, expected.len){ .rolls = expected };

    for (0..expected.len) |i| {
        try expectEqual(spe.range(u8, 0, 2) == 0, i < Gen12.percent(50) + 1);
        try expectEqual(!cfz.chance(u8, 128, 256), i >= Gen12.percent(50) + 1);
        try expectEqual(par.chance(u8, 63, 256), i < Gen12.percent(25));
        try expectEqual(brn.chance(u8, 26, 256), i < Gen12.percent(10) + 1);
        try expectEqual(eff.chance(u8, 85, 256), i < Gen12.percent(33) + 1);
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
            const foe = battle.foe(player);

            var active = side.active;
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
                out[n] = .{ .type = .Move, .data = @boolToInt(showdown) };
                n += 1;
                return n;
            }

            var slot: u4 = 2;
            while (slot <= 6) : (slot += 1) {
                const id = side.order[slot - 1];
                if (id == 0 or side.pokemon[id - 1].hp == 0) continue;
                out[n] = .{ .type = .Switch, .data = slot };
                n += 1;
            }

            const limited = active.volatiles.Bide or active.volatiles.Binding;
            // On the cartridge, all of these happen after "FIGHT" (indicating you are not
            // switching) but before you are allowed to select a move. Pokémon Showdown instead
            // either disables all other moves in the case of limited or requires you to select a
            // move normally if sleeping/frozen/bound.
            if (!showdown and (limited or foe.active.volatiles.Binding or
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
                    if (m.id == side.last_selected_move) {
                        // Pokémon Showdown displays Struggle if limited to Bide when out of PP
                        const s = if (m.pp == 0 and m.id == .Bide) 0 else slot;
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
                // GLITCH: Transform + Mirror Move / Metronome PP softlock
                if (!showdown) {
                    while (slot <= 4) : (slot += 1) {
                        if (active.moves[slot - 1].pp != 0) return n;
                    }
                }
                out[n] = .{ .type = .Move, .data = 0 };
                n += 1;
            }
        },
    }
    return n;
}
