const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const showdown = pkmn.options.showdown;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

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

pub fn update(battle: anytype, c1: Choice, c2: Choice, options: anytype) !Result {
    assert(c1.type != .Pass or c2.type != .Pass or battle.turn == 0);
    if (battle.turn == 0) return start(battle, options);

    var s1 = false;
    var s2 = false;

    if (selectMove(battle, .P1, c1, c2, &s1)) |r| return r;
    if (selectMove(battle, .P2, c2, c1, &s2)) |r| return r;

    var p1 = battle.side(.P1);
    var p2 = battle.side(.P2);

    var r1 = showdown and p1.active.volatiles.Binding and c2.type == .Switch;
    var r2 = showdown and p2.active.volatiles.Binding and c1.type == .Switch;

    if (try turnOrder(battle, c1, c2, options) == .P1) {
        if (try doTurn(battle, .P1, c1, r1, s1, .P2, c2, r2, s2, options)) |r| return r;
    } else {
        if (try doTurn(battle, .P2, c2, r2, s2, .P1, c1, r1, s1, options)) |r| return r;
    }

    if (p1.active.volatiles.attacks == 0) p1.active.volatiles.Binding = false;
    if (p2.active.volatiles.attacks == 0) p2.active.volatiles.Binding = false;

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
    for (side.pokemon, 0..) |pokemon, i| if (pokemon.hp > 0) return side.order[i];
    return 0;
}

fn selectMove(
    battle: anytype,
    player: Player,
    choice: Choice,
    foe_choice: Choice,
    skip_turn: *bool,
) ?Result {
    if (choice.type == .Pass) return null;

    var side = battle.side(player);
    var volatiles = &side.active.volatiles;
    const stored = side.stored();

    assert(!isForced(side.active) or
        (choice.type == .Move and choice.data == @intFromBool(showdown)));

    // pre-battle menu
    if (volatiles.Recharging) {
        if (showdown and battle.foe(player).active.volatiles.Binding) skip_turn.* = true;
        return null;
    }
    if (volatiles.Rage) {
        if (showdown) {
            if (battle.foe(player).active.volatiles.Binding) skip_turn.* = true;
            saveMove(battle, player, null);
        }
        return null;
    }
    // Pokémon Showdown removes Flinch at the end-of-turn in its residual handler
    if (!showdown) volatiles.Flinch = false;
    if (volatiles.Thrashing or volatiles.Charging) {
        if (showdown) {
            if (battle.foe(player).active.volatiles.Binding) skip_turn.* = true;
            saveMove(battle, player, null);
        }
        return null;
    }

    // battle menu
    if (choice.type == .Switch) return null;

    // pre-move select
    if (Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP) or volatiles.Bide) {
        assert(showdown or choice.data == 0);
        if (showdown) {
            if (volatiles.Bide and battle.foe(player).active.volatiles.Binding) skip_turn.* = true;
            saveMove(battle, player, choice);
        }
        return null;
    }
    if (volatiles.Binding) {
        if (showdown) {
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
                const last = side.active.move(battle.lastMove(player).index);
                if (last.id == .Metronome) side.last_selected_move = last.id;
                if (last.id == .MirrorMove) return Result.Error;
            }
        }
        return null;
    }

    if (battle.foe(player).active.volatiles.Binding) {
        skip_turn.* = true;
        if (showdown) {
            saveMove(battle, player, choice);
        } else {
            assert(choice.data == 0);
            side.last_selected_move = .SKIP_TURN;
        }
        return null;
    }

    // move select
    volatiles.state = 0;
    if (choice.data == 0) {
        const struggle = ok: {
            for (side.active.moves, 0..) |move, i| {
                if (move.pp > 0 and volatiles.disable_move != i + 1) break :ok false;
            }
            break :ok true;
        };
        assert(struggle);
    }
    saveMove(battle, player, choice);

    return null;
}

fn saveMove(battle: anytype, player: Player, choice: ?Choice) void {
    var side = battle.side(player);

    if (choice) |c| {
        assert(c.type == .Move);
        if (c.data == 0) {
            side.last_selected_move = .Struggle;
        } else {
            assert(showdown or side.active.volatiles.disable_move != c.data);
            const move = side.active.move(c.data);
            // You cannot *select* a move with 0 PP (except on Pokémon Showdown where that is
            // sometimes required...), but a 0 PP move can be used automatically
            assert(showdown or move.pp != 0);

            side.last_selected_move = move.id;
            battle.lastMove(player).index = @intCast(c.data);
        }
    }
}

fn switchIn(battle: anytype, player: Player, slot: u8, initial: bool, options: anytype) !void {
    var side = battle.side(player);
    var foe = battle.foe(player);
    var active = &side.active;
    const incoming = side.get(slot);

    assert(incoming.hp != 0);
    assert(slot != 1 or initial);

    const out = side.order[0];
    side.order[0] = side.order[slot - 1];
    side.order[slot - 1] = out;

    battle.lastMove(player).index = 1;

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

    try options.log.switched(battle.active(player), incoming);
    options.chance.switched(player, side.order[0], out);

    if (showdown and incoming.status == Status.TOX) {
        incoming.status = Status.init(.PSN);
        // Technically, Pokémon Showdown adds these after *both* Pokémon have switched, but we'd
        // rather not clutter up turnOrder just for this (incorrect) log message
        try options.log.status(battle.active(player), incoming.status, .Silent);
    }
}

fn turnOrder(battle: anytype, c1: Choice, c2: Choice, options: anytype) !Player {
    assert(c1.type != .Pass or c2.type != .Pass);

    if (c1.type == .Pass) return .P2;
    if (c2.type == .Pass) return .P1;

    if ((c1.type == .Switch) != (c2.type == .Switch)) return if (c1.type == .Switch) .P1 else .P2;

    // https://www.smogon.com/forums/threads/adv-switch-priority.3622189/
    // > In Gen 1 it's irrelevant [which player switches first] because switches happen instantly on
    // > your own screen without waiting for the other player's choice (and their choice will appear
    // > to happen first for them too, unless they attacked in which case your switch happens first)
    // A cartridge-compatible implemention must not advance the RNG so we simply default to P1
    const double_switch = c1.type == .Switch and c2.type == .Switch;
    if (!showdown and double_switch) return .P1;

    const m1 = battle.side(.P1).last_selected_move;
    const m2 = battle.side(.P2).last_selected_move;
    if (!showdown or !double_switch) {
        if ((m1 == .QuickAttack) != (m2 == .QuickAttack)) {
            return if (m1 == .QuickAttack) .P1 else .P2;
        } else if ((m1 == .Counter) != (m2 == .Counter)) {
            return if (m1 == .Counter) .P2 else .P1;
        }
    }

    const spe1 = battle.side(.P1).active.stats.spe;
    const spe2 = battle.side(.P2).active.stats.spe;
    if (spe1 == spe2) {
        // Pokémon Showdown's beforeTurnCallback shenanigans
        if (showdown and !double_switch and m1 == .Counter and m2 == .Counter) {
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

fn doTurn(
    battle: anytype,
    player: Player,
    player_choice: Choice,
    player_rewrap: bool,
    player_skip: bool,
    foe_player: Player,
    foe_choice: Choice,
    foe_rewrap: bool,
    foe_skip: bool,
    options: anytype,
) !?Result {
    assert(player_choice.type != .Pass);

    var residual = true;
    var replace = battle.side(player).stored().hp == 0;
    if (try executeMove(
        battle,
        player,
        player_choice,
        player_rewrap,
        player_skip,
        &residual,
        options,
    )) |r| return r;
    if (!replace) {
        if (player_choice.type != .Switch) {
            if (try checkFaint(battle, foe_player, options)) |r| return r;
        }
        if (residual) try handleResidual(battle, player, options);
        if (try checkFaint(battle, player, options)) |r| return r;
    } else if (foe_choice.type == .Pass) return null;

    options.chance.clearPending();

    residual = true;
    replace = battle.side(foe_player).stored().hp == 0;
    const calc = pkmn.options.calc and foe_choice.type == .Pass;
    if (if (calc) null else try executeMove(
        battle,
        foe_player,
        foe_choice,
        foe_rewrap,
        foe_skip,
        &residual,
        options,
    )) |r| return r;
    if (!replace) {
        if (!calc and foe_choice.type != .Switch) {
            if (try checkFaint(battle, player, options)) |r| return r;
        }
        if (residual) try handleResidual(battle, foe_player, options);
        if (try checkFaint(battle, foe_player, options)) |r| return r;
    }

    // Flinch is bugged on Pokémon Showdown because it gets implemented with a duration which causes
    // it to get removed in the non-existent "residual" phase instead of during move selection
    if (showdown) {
        battle.side(.P1).active.volatiles.Flinch = false;
        battle.side(.P2).active.volatiles.Flinch = false;
    }

    return null;
}

fn executeMove(
    battle: anytype,
    player: Player,
    choice: Choice,
    rewrap: bool,
    skip: bool,
    residual: *bool,
    options: anytype,
) !?Result {
    var side = battle.side(player);

    if (choice.type == .Switch) {
        try switchIn(battle, player, choice.data, false, options);
        return null;
    }

    // This is the correct place to check for SKIP_TURN and abort early, however since Pokémon
    // Showdown overwrites the SKIP_TURN sentinel with its botched move select we need to add an
    // additional skip boolean to accomplish the same thing in the Binding check of BeforeMove
    if (side.last_selected_move == .SKIP_TURN) {
        assert(!showdown);
        if (battle.foe(player).active.volatiles.Binding) {
            try options.log.cant(battle.active(player), .Bound);
        }
        return null;
    }

    assert(choice.type == .Move);
    var mslot: u4 = @intCast(choice.data);
    // Sadly, we can't even check `Move.get(side.last_selected_move).effect == .Binding` here
    // because Pokémon Showdown's Mirror Move implementation clobbers side.last_selected_move
    var auto = showdown and side.last_selected_move != .None;

    // GLITCH: Freeze top move selection desync & PP underflow shenanigans
    if (mslot == 0 and side.last_selected_move != .None and side.last_selected_move != .Struggle) {
        // choice.data == 0 only happens with Struggle on Pokémon Showdown
        assert(!showdown);
        mslot = @intCast(battle.lastMove(player).index);
        const stored = side.stored();
        // GLITCH: Struggle bypass PP underflow via Hyper Beam / Trapping-switch auto selection
        auto = isForced(&side.active) or
            side.active.volatiles.Binding or side.active.volatiles.Bide or
            side.last_selected_move == .HyperBeam or
            Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP);
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
        mslot = @intCast(battle.lastMove(player).index);
    }

    var skip_can = false;
    var skip_pp = false;
    switch (try beforeMove(battle, player, skip, residual, options)) {
        .done => return null,
        .skip_can => skip_can = true,
        .skip_pp => skip_pp = true,
        .ok => {},
        .err => return @as(?Result, Result.Error),
    }

    const can = skip_can or
        try canMove(battle, player, mslot, auto, skip_pp, .None, residual, options);
    if (!can) return null;

    return doMove(battle, player, mslot, rewrap, auto, residual, options);
}

const BeforeMove = enum { done, skip_can, skip_pp, ok, err };

fn beforeMove(
    battle: anytype,
    player: Player,
    skip: bool,
    residual: *bool,
    options: anytype,
) !BeforeMove {
    var log = options.log;
    var side = battle.side(player);
    const foe = battle.foe(player);
    var active = &side.active;
    var stored = side.stored();
    const ident = battle.active(player);
    var volatiles = &active.volatiles;

    if (Status.is(stored.status, .SLP)) {
        const before = stored.status;
        // Even if the EXT bit is set this will still correctly modify the sleep duration
        if (options.calc.modify(player, .sleep)) |extend| {
            if (!extend) stored.status = 0;
        } else {
            stored.status -= 1;
        }

        const duration = Status.duration(stored.status);
        if (!Status.is(stored.status, .EXT)) {
            try options.chance.sleep(player, duration);
        }

        if (duration == 0) {
            try log.curestatus(ident, before, .Message);
            stored.status = 0; // clears EXT if present
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

    if (skip or foe.active.volatiles.Binding) {
        try log.cant(ident, .Bound);
        return .done;
    }

    if (volatiles.Flinch) {
        // Pokémon Showdown doesn't clear Flinch until its imaginary "residual" phase, meaning
        // Pokémon can sometimes flinch multiple times from the same original hit
        if (!showdown) volatiles.Flinch = false;
        try log.cant(ident, .Flinch);
        return .done;
    }

    if (volatiles.Recharging) {
        volatiles.Recharging = false;
        try log.cant(ident, .Recharge);
        return .done;
    }

    if (volatiles.disable_duration > 0) {
        if (options.calc.modify(player, .disable)) |extend| {
            if (!extend) volatiles.disable_duration = 0;
        } else {
            volatiles.disable_duration -= 1;
        }
        try options.chance.disable(player, volatiles.disable_duration);

        if (volatiles.disable_duration == 0) {
            volatiles.disable_move = 0;
            try log.end(ident, .Disable);
        }
    }
    // Pokémon Showdown's disable condition has a single onBeforeMove handler
    if (showdown and try disabled(side, ident, options)) return .done;

    // This can only happen if a Pokémon started the battle frozen/sleeping and was thawed/woken
    // before the side had a selected a move - we simply need to assume this leads to a desync
    if (side.last_selected_move == .None) {
        assert(!showdown);
        return .err;
    }

    if (volatiles.Confusion) {
        assert(volatiles.confusion > 0);

        if (options.calc.modify(player, .confusion)) |extend| {
            if (!extend) volatiles.confusion = 0;
        } else {
            volatiles.confusion -= 1;
        }
        try options.chance.confusion(player, volatiles.confusion);

        if (volatiles.confusion == 0) {
            volatiles.Confusion = false;
            try log.end(ident, .Confusion);
        } else {
            try log.activate(ident, .Confusion);

            if (try Rolls.confused(battle, player, options)) {
                assert(!volatiles.MultiHit);
                if (!volatiles.Rage) volatiles.state = 0;
                volatiles.Bide = false;
                volatiles.Thrashing = false;
                volatiles.MultiHit = false;
                volatiles.Flinch = false;
                volatiles.Charging = false;
                volatiles.Binding = false;
                volatiles.Invulnerable = false;
                options.chance.clearDurations(player, null);
                {
                    // This feels (and is) disgusting but the cartridge literally just overwrites
                    // the opponent's defense with the user's defense and resets it after. As a
                    // result of this the *opponent's* Reflect impacts confusion self-hit damage
                    const def = foe.active.stats.def;
                    foe.active.stats.def = active.stats.def;
                    defer foe.active.stats.def = def;
                    if (!calcDamage(battle, player, player.foe(), null, false)) return .err;
                }
                // Pokémon Showdown incorrectly changes the "target" of the confusion self-hit based
                // on the targeting behavior of the confused Pokémon's selected move which results
                // in the wrong behavior with respect to the Substitute + Confusion glitch
                const target = if (showdown and Move.get(side.last_selected_move).target == .Self)
                    player
                else
                    player.foe();

                const uncapped = battle.last_damage;
                // Skipping adjustDamage / randomizeDamage / checkHit
                _ = try applyDamage(battle, player, target, .Confusion, options);
                // Pokémon Showdown thinks that confusion damage is uncapped ¯\_(ツ)_/¯
                if (showdown) battle.last_damage = uncapped;

                return .done;
            }
        }
    }

    if (!showdown and try disabled(side, ident, options)) return .done;

    if (Status.is(stored.status, .PAR) and try Rolls.paralyzed(battle, player, options)) {
        if (!volatiles.Rage) volatiles.state = 0;
        volatiles.Bide = false;
        volatiles.Thrashing = false;
        volatiles.Charging = false;
        volatiles.Binding = false;
        options.chance.clearDurations(player, null);
        // GLITCH: Invulnerable is not cleared, resulting in permanent Fly/Dig invulnerability
        try log.cant(ident, .Paralysis);
        return .done;
    }

    if (volatiles.Bide) {
        assert(!volatiles.Thrashing and !volatiles.Rage);

        if (showdown) {
            // Pokémon Showdown doesn't implement Bide potentially overflowing in the event of
            // OHKO-move damage, but we can fake this incorrect behavior by simply saturating the
            // addition because 65535 is sufficient to faint any Pokémon anyway
            volatiles.state +|= battle.last_damage;
        } else {
            volatiles.state +%= battle.last_damage;
        }

        assert(volatiles.attacks > 0);

        if (options.calc.modify(player, .attacking)) |extend| {
            if (!extend) volatiles.attacks = 0;
        } else {
            volatiles.attacks -= 1;
        }
        try options.chance.attacking(player, volatiles.attacks);

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

        const sub = showdown and foe.active.volatiles.Substitute;
        _ = try applyDamage(battle, player.foe(), player.foe(), .None, options);
        if (foe.stored().hp > 0 and !sub) try buildRage(battle, player.foe(), options);

        // For reasons passing understanding, Pokémon Showdown still inflicts residual damage to
        // Bide's user even if the above damage has caused the foe to faint. It's simpler to always
        // run residual here regardless of whether the foe fainted and opt-out of the default flow
        if (showdown) {
            residual.* = false;
            try handleResidual(battle, player, options);
        }

        return .done;
    }

    if (volatiles.Thrashing) {
        assert(volatiles.attacks > 0);

        if (options.calc.modify(player, .attacking)) |extend| {
            if (!extend) volatiles.attacks = 0;
        } else {
            volatiles.attacks -= 1;
        }
        try options.chance.attacking(player, volatiles.attacks);

        if (!showdown and handleThrashing(battle, active, player, options)) {
            try log.start(battle.active(player), .ConfusionSilent);
        }
        try log.move(ident, side.last_selected_move, battle.active(player.foe()));
        if (showdown) {
            // This shouldn't actually set last_used_move, but Pokémon Showdown sets last
            // used in useMove and doesn't have the notion of skipping canMove semantics
            side.last_used_move = side.last_selected_move;
            if (handleThrashing(battle, active, player, options)) {
                try log.start(battle.active(player), .ConfusionSilent);
            }
        }
        return .skip_can;
    }

    if (volatiles.Binding) {
        assert(volatiles.attacks > 0);

        if (options.calc.modify(player, .binding)) |extend| {
            if (!extend) volatiles.attacks = 0;
        } else {
            volatiles.attacks -= 1;
        }
        try options.chance.binding(player, volatiles.attacks);

        try log.move(battle.active(player), side.last_selected_move, battle.active(player.foe()));
        if (showdown or battle.last_damage != 0) {
            const sub = showdown and foe.active.volatiles.Substitute;
            _ = try applyDamage(battle, player.foe(), player.foe(), .None, options);
            if (battle.foe(player).stored().hp > 0 and !sub) {
                try buildRage(battle, player.foe(), options);
            }
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
    from: Move,
    residual: *bool,
    options: anytype,
) !bool {
    var side = battle.side(player);
    const player_ident = battle.active(player);
    const move = Move.get(side.last_selected_move);

    var skip = skip_pp;
    if (side.active.volatiles.Charging) {
        side.active.volatiles.Charging = false;
        side.active.volatiles.Invulnerable = false;
    } else if (move.effect == .Charge) {
        try options.log.moveFrom(player_ident, side.last_selected_move, .{}, from);
        setCounterable(battle, player, side, move);
        try Effects.charge(battle, player, options);
        return false;
    }

    side.last_used_move = side.last_selected_move;
    if (!skip) decrementPP(side, mslot, auto);

    const target = if (move.target == .Self) player else player.foe();
    try options.log.moveFrom(player_ident, side.last_selected_move, battle.active(target), from);
    setCounterable(battle, player, side, move);

    if (move.effect.onBegin()) {
        try onBegin(battle, player, move, mslot, residual, options);
        return false;
    }

    if (move.effect == .Thrashing) {
        Effects.thrashing(battle, player, options);
    } else if (!showdown and move.effect == .Binding) {
        // Pokémon Showdown handles this after hit/miss checks and damage calculation
        try Effects.binding(battle, player, false, options);
    }

    return true;
}

fn setCounterable(battle: anytype, player: Player, side: *Side, move: Move.Data) void {
    // The Counter desync is caused by the cartridge not calling GetCurrentMove until now, meaning
    // in cases where an early return happens the data for a players last selected move does not get
    // reloaded and HandleCounterMove actually bases its success/failure off of stale information.
    // This boolean state we track here doesn't exist on the cartridge because it instead manifests
    // as the desync results from actually having two separate battle states that subtly disagree
    const counterable = side.last_selected_move != .Counter and move.bp > 0 and
        (move.type == .Normal or move.type == .Fighting);
    battle.lastMove(player).counterable = @intFromBool(counterable);
}

fn decrementPP(side: *Side, mslot: u4, auto: bool) void {
    if (side.last_selected_move == .Struggle) return;

    var active = &side.active;
    const volatiles = &active.volatiles;

    assert(!volatiles.Rage and !volatiles.Thrashing and !volatiles.MultiHit);
    if (volatiles.Bide) return;

    var move_slot = active.move(mslot);
    assert(move_slot.pp > 0 or auto);
    move_slot.pp = @as(u6, @intCast(move_slot.pp)) -% 1;
    if (volatiles.Transform) return;

    move_slot = side.stored().move(mslot);
    assert(move_slot.pp > 0 or auto);
    move_slot.pp = @as(u6, @intCast(move_slot.pp)) -% 1;
    assert(active.move(mslot).pp == side.stored().move(mslot).pp);
}

fn incrementPP(side: *Side, mslot: u4) void {
    var active = &side.active;
    const volatiles = &active.volatiles;

    active.move(mslot).pp = @as(u6, @intCast(active.move(mslot).pp)) +% 1;
    // GLITCH: No check for Transform means an empty/incorrect stored slot can get incremented
    if (showdown and volatiles.Transform) return;

    assert(mslot > 0 and mslot <= 4);
    side.stored().moves[mslot - 1].pp = @as(u6, @intCast(side.stored().moves[mslot - 1].pp)) +% 1;
}

// Pokémon Showdown does hit/multi/crit/damage instead of crit/damage/hit/multi
fn doMove(
    battle: anytype,
    player: Player,
    mslot: u4,
    rewrap: bool,
    auto: bool,
    residual: *bool,
    options: anytype,
) !?Result {
    var log = options.log;
    var side = battle.side(player);
    const foe = battle.foe(player);

    var move = Move.get(side.last_selected_move);
    const counter = side.last_selected_move == .Counter;
    const status = move.bp == 0 and move.effect != .OHKO;

    var crit = false;
    var ohko = false;
    var immune = false;
    var mist = false;
    var hits: u4 = 1;
    var effectiveness = Effectiveness.neutral;

    // Due to control flow shenanigans we need to clear last_damage for Pokémon Showdown
    if (showdown and !counter) battle.last_damage = 0;

    // The cartridge handles set damage moves in applyDamage but we short circuit to simplify things
    if (move.effect == .SuperFang or move.effect == .SpecialDamage) {
        return specialDamage(battle, player, move, options);
    }

    // Pokémon Showdown runs invulnerability / immunity checks before checking accuracy - simply
    // calling moveHit early covers most of that but we also need to check type immunity first
    var miss = showdown and miss: {
        immune = move.target != .Self and !status and !counter and
            (@intFromEnum(move.type.effectiveness(foe.active.types.type1)) == 0 or
            @intFromEnum(move.type.effectiveness(foe.active.types.type2)) == 0);
        if (immune and move.effect != .Binding) break :miss true;
        if (move.effect == .OHKO and side.active.stats.spe < foe.active.stats.spe) {
            battle.last_damage = 0;
            break :miss true;
        }
        break :miss (move.target != .Self and
            !moveHit(battle, player, move, &immune, &mist, options));
    };
    assert(!immune or miss or (showdown and move.effect == .Binding));

    var late = showdown and move.effect != .Explode;
    const skip = status or immune;
    if ((!showdown or (!skip or counter)) and !miss) blk: {
        if (showdown and move.effect.isMulti()) {
            try Effects.multiHit(battle, player, move, options);
            hits = side.active.volatiles.attacks;
            late = false;
        }

        // Cartridge rolls for crit even for moves that can't crit (Counter/Metronome/status/OHKO)
        const check = !showdown or (!counter and move.effect != .OHKO);
        if (check) crit = try checkCriticalHit(battle, player, move, options);

        if (counter) return counterDamage(battle, player, move, options);

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
            try randomizeDamage(battle, player, options);
        }
    }

    var zero = battle.last_damage == 0;
    miss = if (showdown or skip)
        miss
    else
        (!moveHit(battle, player, move, &immune, &mist, options) or zero);

    assert(showdown or miss or battle.last_damage > 0 or skip);
    assert((!showdown and miss) or !(ohko and immune));
    assert(!immune or miss or move.effect == .Binding);

    if (!showdown or !miss) {
        if (move.effect == .MirrorMove) {
            return mirrorMove(battle, player, mslot, rewrap, auto, residual, options);
        } else if (move.effect == .Metronome) {
            return metronome(battle, player, mslot, rewrap, auto, residual, options);
        } else if (move.effect.onEnd()) {
            try onEnd(battle, player, move, options);
            return null;
        }
    }

    if (miss) {
        const foe_ident = battle.active(player.foe());
        const invulnerable =
            showdown and foe.active.volatiles.Invulnerable and move.effect != .Swift;
        ohko = (!showdown or (!immune and !invulnerable)) and
            move.effect == .OHKO and side.active.stats.spe < foe.active.stats.spe;
        if (ohko) {
            try log.immune(foe_ident, .OHKO);
        } else if (immune and !invulnerable and (!showdown or move.effect != .Binding)) {
            try log.immune(foe_ident, .None);
        } else if (mist) {
            if (!foe.active.volatiles.Substitute) try log.activate(foe_ident, .Mist);
            try log.fail(foe_ident, .None);
        } else {
            if (showdown or !zero) try options.chance.commit(player, .miss);
            try log.lastmiss();
            try log.miss(battle.active(player));
        }
        if (move.effect == .JumpKick) {
            // Recoil is supposed to be damage/8 but damage will always be 0 here
            assert(showdown or battle.last_damage == 0);
            battle.last_damage = 1;
            _ = try applyDamage(battle, player, player.foe(), .None, options);
            if (showdown and side.stored().hp == 0) residual.* = false;
        } else if (move.effect == .Explode) {
            try Effects.explode(battle, player);
            try buildRage(battle, player.foe(), options);
        } else if (showdown and move.effect == .Disable) {
            try buildRage(battle, player.foe(), options);
        } else if (!showdown and immune and move.effect == .Binding) {
            try options.chance.commit(player, .binding);
        }
        return null;
    } else {
        try options.chance.commit(player, .hit);
    }

    // On the cartridge MultiHit doesn't get set up until after damage has been applied for the
    // first time but its more convenient and efficient to set it up here (Pokémon Showdown sets
    // it up above before damage calculation).
    if (!showdown and move.effect.isMulti()) {
        try Effects.multiHit(battle, player, move, options);
        hits = side.active.volatiles.attacks;
    }

    // Pokémon Showdown only builds Rage for Disable/Explosion (hit/miss) when attacking into a sub
    const sub = showdown and foe.active.volatiles.Substitute;

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
        if (!skip) nullified = try applyDamage(battle, player.foe(), player.foe(), .None, options);
        if (hit == 0 and ohko) try log.ohko();
        hit += 1;
        if (foe.stored().hp == 0) break;
        if (!late and (!sub or move.effect == .Explode)) {
            try buildRage(battle, player.foe(), options);
        }
        // If the substitute breaks during a multi-hit attack, the attack ends
        if (nullified) break;
    }

    if (side.active.volatiles.MultiHit) {
        side.active.volatiles.MultiHit = false;
        assert(nullified or foe.stored().hp == 0 or side.active.volatiles.attacks - hit == 0);
        side.active.volatiles.attacks = 0;
        if (showdown and move.effect == .Twineedle and !nullified and foe.stored().hp > 0) {
            try Effects.poison(battle, player, Move.get(.PoisonSting), options);
        }
        try log.hitcount(battle.active(player.foe()), hit);
    } else if (showdown) {
        // This should be handled much earlier but Pokémon Showdown does it here... ¯\_(ツ)_/¯
        if (move.effect == .Binding) {
            try Effects.binding(battle, player, rewrap, options);
            if (immune) {
                battle.last_damage = 0;
                assert(foe.stored().hp > 0);
                // Pokémon Showdown logs |-damage| here instead of |-immune| because logic...
                if (sub) {
                    try log.activate(battle.active(player.foe()), .Substitute);
                } else {
                    try log.damage(battle.active(player.foe()), foe.stored(), .None);
                    try buildRage(battle, player.foe(), options);
                }
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
    if (move.effect.alwaysHappens()) try alwaysHappens(battle, player, move, residual, options);

    if (foe.stored().hp == 0) return null;

    // Pokémon Showdown builds Rage at the wrong time for non-MultiHit move
    if (late and !sub and move.effect != .Disable) try buildRage(battle, player.foe(), options);

    if (!move.effect.isSpecial()) {
        // On the cartridge Rage is not considered to be "special" and thus gets executed for a
        // second time here (after being executed in the "always happens" block above) but that
        // doesn't matter since its idempotent (on the cartridge, but not in the implementation
        // below). For Twineedle we change the data to that of one with PoisonChance1 given its
        // MultiHit behavior is complete after the loop above, though Pokémon Showdown handles the
        // Twineedle secondary effect in the MultiHit cleanup block above because it incorrectly
        // puts the |-status| message before |-hitcount| instead of after.
        if (move.effect == .Twineedle) {
            if (!showdown) try Effects.poison(battle, player, Move.get(.PoisonSting), options);
        } else if (move.effect == .Disable) {
            const result = try Effects.disable(battle, player, move, options);
            if (showdown) try buildRage(battle, player.foe(), options);
            return result;
        } else {
            try moveEffect(battle, player, move, options);
        }
    }

    return null;
}

fn checkCriticalHit(battle: anytype, player: Player, move: Move.Data, options: anytype) !bool {
    const side = battle.side(player);

    // Base speed is used for the critical hit calculation, even when Transform-ed
    var rate = @as(u16, Species.chance(side.stored().species));
    // GLITCH: Focus Energy reduces critical hit rate instead of increasing it
    rate = if (side.active.volatiles.FocusEnergy) rate / 2 else @min(rate * 2, 255);
    rate = if (move.effect == .HighCritical) @min(rate * 4, 255) else rate / 2;

    return Rolls.criticalHit(battle, player, @intCast(rate), options);
}

fn calcDamage(
    battle: anytype,
    player: Player,
    target_player: Player,
    m: ?Move.Data,
    crit: bool,
) bool {
    // Confusion (indicated when m == null) just needs a 40 BP physical move
    const cfz = m == null;
    const move = m orelse Move.get(.Pound);
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
                target.active.stats.spc *
                    @as(u2, if (target.active.volatiles.LightScreen) 2 else 1)
            // Pokémon Showdown doesn't apply the opponent's Reflect to confusion's self-hit
            else
                target.active.stats.def *
                    @as(u2, if ((!showdown or !cfz) and target.active.volatiles.Reflect) 2 else 1);
    // zig fmt: on

    // Pokémon Showdown erroneously skips this for confusion's self-hit damage, but thankfully we
    // will not overflow because the hit is only 40 BP and unboosted (the highest legal unboosted
    // attack is 366 from a level 100 Dragonite which has a max of 614,880 mid-calculation)
    if ((!showdown or !cfz) and (atk > 255 or def > 255)) {
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

    battle.last_damage = @intCast(d);

    return true;
}

fn adjustDamage(battle: anytype, player: Player) u16 {
    const side = battle.side(player);
    const foe = battle.foe(player);
    const types = foe.active.types;
    const move = Move.get(side.last_selected_move);

    var d = battle.last_damage;
    if (side.active.types.includes(move.type)) d +%= d / 2;

    const neutral = @intFromEnum(Effectiveness.Neutral);
    const eff1: u16 = @intFromEnum(move.type.effectiveness(types.type1));
    const eff2: u16 = @intFromEnum(move.type.effectiveness(types.type2));

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

fn randomizeDamage(battle: anytype, player: Player, options: anytype) !void {
    if (battle.last_damage <= 1) return;
    const random = try Rolls.damage(battle, player, options);
    options.calc.base(player.foe(), battle.last_damage);
    battle.last_damage = @intCast(@as(u32, battle.last_damage) *% random / 255);
    options.calc.final(player.foe(), battle.last_damage);
}

fn specialDamage(battle: anytype, player: Player, move: Move.Data, options: anytype) !?Result {
    const side = battle.side(player);
    const foe = battle.foe(player);

    if (!try checkHit(battle, player, move, options)) return null;
    try options.chance.commit(player, .hit);

    battle.last_damage = switch (side.last_selected_move) {
        .SuperFang => @max(foe.stored().hp / 2, 1),
        .SeismicToss, .NightShade => side.stored().level,
        .SonicBoom => 20,
        .DragonRage => 40,
        // GLITCH: if power = 0 then a desync occurs (or a miss on Pokémon Showdown)
        .Psywave => power: {
            const max: u8 = @intCast(@as(u16, side.stored().level) * 3 / 2);
            // GLITCH: Psywave infinite glitch loop
            if (!showdown and max <= 1) return Result.Error;
            break :power try Rolls.psywave(battle, player, max, options);
        },
        else => unreachable,
    };

    if (battle.last_damage == 0) return if (showdown) null else Result.Error;

    const sub = showdown and foe.active.volatiles.Substitute;
    _ = try applyDamage(battle, player.foe(), player.foe(), .None, options);
    if (battle.foe(player).stored().hp > 0 and !sub) try buildRage(battle, player.foe(), options);

    return null;
}

fn counterDamage(battle: anytype, player: Player, move: Move.Data, options: anytype) !?Result {
    const foe = battle.foe(player);

    if (battle.last_damage == 0) {
        try options.log.fail(battle.active(player), .None);
        return null;
    }

    // Pretend Splash was used as a stand-in when no move has been used to fail below with 0 BP
    const foe_last_selected_move =
        Move.get(if (foe.last_selected_move == .None or foe.last_selected_move == .SKIP_TURN)
        .Splash
    else
        foe.last_selected_move);

    const used = battle.lastMove(player.foe()).counterable != 0;
    const selected = foe_last_selected_move.bp > 0 and
        foe.last_selected_move != .Counter and
        (foe_last_selected_move.type == .Normal or
        foe_last_selected_move.type == .Fighting);

    if (!used and !selected) {
        try options.log.fail(battle.active(player), .None);
        return null;
    }

    if (!used or !selected) {
        // GLITCH: Counter desync (covered by Desync Clause Mod on Pokémon Showdown)
        if (!showdown) return Result.Error;
        try options.log.fail(battle.active(player), .None);
        return null;
    }

    battle.last_damage *|= 2;

    // Pokémon Showdown calls checkHit before Counter
    if (!showdown and !try checkHit(battle, player, move, options)) return null;
    try options.chance.commit(player, .hit);

    const sub = showdown and foe.active.volatiles.Substitute;
    _ = try applyDamage(battle, player.foe(), player.foe(), .None, options);
    if (battle.foe(player).stored().hp > 0 and !sub) try buildRage(battle, player.foe(), options);
    return null;
}

fn applyDamage(
    battle: anytype,
    target_player: Player,
    sub_player: Player,
    reason: Damage,
    options: anytype,
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
            try options.log.end(battle.active(sub_player), .Substitute);
            options.calc.capped(target_player);
            return true;
        } else {
            // Safe to truncate since less than subbed.volatiles.substitute which is a u8
            subbed.active.volatiles.substitute -= @intCast(battle.last_damage);
            try options.log.activate(battle.active(sub_player), .Substitute);
            return false;
        }
    }

    if (battle.last_damage > target.stored().hp) battle.last_damage = target.stored().hp;
    target.stored().hp -= battle.last_damage;
    try options.log.damage(battle.active(target_player), target.stored(), reason);
    return false;
}

fn mirrorMove(
    battle: anytype,
    player: Player,
    mslot: u4,
    rewrap: bool,
    auto: bool,
    residual: *bool,
    options: anytype,
) anyerror!?Result {
    var side = battle.side(player);
    const foe = battle.foe(player);

    side.last_selected_move = foe.last_used_move;

    if (foe.last_used_move == .None or foe.last_used_move == .MirrorMove) {
        try options.log.fail(battle.active(player), .None);
        return null;
    } else if (!showdown or foe.last_used_move != .Struggle) {
        incrementPP(side, mslot);
    }

    if (!try canMove(battle, player, mslot, auto, false, .MirrorMove, residual, options)) {
        return null;
    }
    return doMove(battle, player, mslot, rewrap, auto, residual, options);
}

fn metronome(
    battle: anytype,
    player: Player,
    mslot: u4,
    rewrap: bool,
    auto: bool,
    residual: *bool,
    options: anytype,
) anyerror!?Result {
    var side = battle.side(player);

    side.last_selected_move = try Rolls.metronome(battle, player, options);
    incrementPP(side, mslot);

    if (!try canMove(battle, player, mslot, auto, false, .Metronome, residual, options)) {
        return null;
    }
    return doMove(battle, player, mslot, rewrap, auto, residual, options);
}

fn checkHit(battle: anytype, player: Player, move: Move.Data, options: anytype) !bool {
    var immune = false;
    var mist = false;

    if (moveHit(battle, player, move, &immune, &mist, options)) return true;

    assert(!immune);
    if (mist) {
        assert(!showdown);
        const foe_ident = battle.active(player.foe());
        try options.log.activate(foe_ident, .Mist);
        try options.log.fail(foe_ident, .None);
    } else {
        try options.chance.commit(player, .miss);
        try options.log.lastmiss();
        try options.log.miss(battle.active(player));
    }

    return false;
}

fn moveHit(
    battle: anytype,
    player: Player,
    move: Move.Data,
    immune: *bool,
    mist: *bool,
    options: anytype,
) bool {
    var side = battle.side(player);
    const foe = battle.foe(player);

    var miss = miss: {
        assert(!side.active.volatiles.Bide);

        // Invulnerability trumps everything on Pokémon Showdown
        if (showdown) {
            if (move.effect == .Swift) return true;
            if (foe.active.volatiles.Invulnerable) break :miss true;
        }
        if (move.effect == .DreamEater and (!Status.is(foe.stored().status, .SLP) or
            (showdown and foe.active.volatiles.Substitute)))
        {
            immune.* = true;
            if (showdown) return false;
            break :miss true;
        }
        if (!showdown) {
            if (move.effect == .Swift) return true;
            if (foe.active.volatiles.Invulnerable) break :miss true;
        }

        // Hyper Beam + Sleep glitch needs to be special cased here due to control flow differences
        if (showdown and move.effect == .Sleep and foe.active.volatiles.Recharging) return true;

        // Conversion / Haze / Light Screen / Reflect qualify but do not call moveHit
        if (foe.active.volatiles.Mist and move.effect.isStatDown()) {
            mist.* = true;
            if (!showdown) break :miss true;
        }

        // GLITCH: Thrash / Petal Dance / Rage get their accuracy overwritten on subsequent hits
        const state = side.active.volatiles.state;
        var overwrite = move.effect == .Rage or move.effect == .Thrashing;
        const overwritten = overwrite and state > 0;
        assert(!overwritten or (0 < state and state <= 255 and !side.active.volatiles.Bide));

        var accuracy = if (overwritten) state else @as(u16, move.accuracy);
        var boost = BOOSTS[@as(u4, @intCast(@as(i8, side.active.boosts.accuracy) + 6))];
        accuracy = accuracy * boost[0] / boost[1];
        boost = BOOSTS[@as(u4, @intCast(@as(i8, -foe.active.boosts.evasion) + 6))];
        accuracy = accuracy * boost[0] / boost[1];
        accuracy = @min(255, @max(1, accuracy));

        // Pokémon Showdown only overwrites if the volatile is present
        if (showdown) overwrite = side.active.volatiles.Rage or side.active.volatiles.Thrashing;
        if (overwrite) side.active.volatiles.state = accuracy;

        // GLITCH: max accuracy is 255 so 1/256 chance of miss
        break :miss !Rolls.hit(battle, player, @intCast(accuracy), options);
    };

    // Pokémon Showdown reports miss instead of fail for moves blocked by Mist that 1/256 miss
    if (showdown and mist.*) {
        mist.* = !miss;
        miss = true;
    }

    if (!miss) return true;
    if (!showdown or !foe.active.volatiles.Invulnerable) battle.last_damage = 0;
    side.active.volatiles.Binding = false;
    return false;
}

fn checkFaint(
    battle: anytype,
    player: Player,
    options: anytype,
) @TypeOf(options.log).Error!?Result {
    const side = battle.side(player);
    if (side.stored().hp > 0) return null;

    const foe = battle.foe(player);
    const foe_fainted = foe.stored().hp == 0;

    const player_out = findFirstAlive(side) == 0;
    const foe_out = foe_fainted and findFirstAlive(foe) == 0;
    const more = player_out or foe_out;

    if (try faint(battle, player, !(more or foe_fainted), options)) |r| return r;
    if (foe_fainted) if (try faint(battle, player.foe(), !more, options)) |r| return r;

    assert(!side.active.volatiles.MultiHit);
    assert(!foe.active.volatiles.MultiHit);

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

fn faint(battle: anytype, player: Player, done: bool, options: anytype) !?Result {
    var side = battle.side(player);
    var foe = battle.foe(player);
    assert(side.stored().hp == 0);

    var foe_volatiles = &foe.active.volatiles;
    assert(!foe_volatiles.MultiHit);
    if (foe_volatiles.Bide) {
        assert(!foe_volatiles.Thrashing and !foe_volatiles.Rage);
        foe_volatiles.state = if (showdown) 0 else foe_volatiles.state & 255;
        if (foe_volatiles.state != 0) return Result.Error;
    }

    // Clearing these is not strictly necessary as provided the battle hasn't ended the side that
    // just fainted will need to switch in a replacement and all of this gets cleared in switchIn
    // anyway. However, we would like to ensure the battle state presented to the players at each
    // decision point is consistent so we avoid "optimizing" this out
    // (we do always need to clear status though for Pokémon Showdown's Sleep/Freeze Clause Mod)
    side.active.volatiles = .{};
    side.last_used_move = .None;
    foe.last_used_move = .None;
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
    return null;
}

fn handleResidual(battle: anytype, player: Player, options: anytype) !void {
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
        damage = @min(damage, stored.hp);

        if (!showdown or damage > 0) {
            stored.hp -= damage;
            // Pokémon Showdown uses damageOf here but its not relevant in Generation I
            try options.log.damage(ident, stored, if (brn) Damage.Burn else Damage.Poison);
        }
    }

    if (volatiles.LeechSeed) {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (foe_stored.hp == 0) {
            assert(showdown);
            return;
        }

        var damage = @max(stored.stats.hp / 16, 1);

        // GLITCH: Leech Seed + Toxic glitch
        if (volatiles.Toxic) {
            volatiles.toxic += 1;
            damage *= volatiles.toxic;
        }

        const amount = @min(damage, stored.hp);
        stored.hp -= amount;

        // As above, Pokémon Showdown uses damageOf but its not relevant
        if (amount > 0) try options.log.damage(ident, stored, .LeechSeed);

        const before = foe_stored.hp;
        // Uncapped damage is added back to the foe
        foe_stored.hp = @min(foe_stored.hp + damage, foe_stored.stats.hp);
        // Pokémon Showdown uses the less specific heal here instead of drain... because reasons?
        if (foe_stored.hp > before) try options.log.heal(.{ foe_ident, foe_stored, Heal.Silent });
    }
}

fn endTurn(battle: anytype, options: anytype) @TypeOf(options.log).Error!Result {
    assert(!battle.side(.P1).active.volatiles.MultiHit);
    assert(!battle.side(.P2).active.volatiles.MultiHit);

    battle.turn += 1;

    if (showdown and pkmn.options.ebc and checkEBC(battle)) {
        try options.log.tie();
        return Result.Tie;
    }

    if (showdown and battle.turn >= 1000) {
        try options.log.tie();
        return Result.Tie;
    } else if (battle.turn >= 65535) {
        return Result.Error;
    }

    try options.log.turn(battle.turn);

    return Result.Default;
}

fn checkEBC(battle: anytype) bool {
    for (battle.sides, 0..) |side, i| {
        const foe = battle.sides[~@as(u1, @intCast(i))];

        var foe_all_ghosts = true;
        var foe_all_transform = true;
        for (foe.order, 0..) |id, j| {
            if (id == 0) break;
            const active = j == 0;
            const pokemon = foe.pokemon[id - 1];

            const ghost = pokemon.hp == 0 or
                (if (active) foe.active.types else pokemon.types).includes(.Ghost);
            foe_all_ghosts = foe_all_ghosts and ghost;
            foe_all_transform = foe_all_transform and pokemon.hp == 0 or transform: {
                for (if (active) foe.active.moves else pokemon.moves) |m| {
                    if (m.id == .None) break :transform true;
                    if (m.id != .Transform) break :transform false;
                }
                break :transform true;
            };
        }

        for (side.order, 0..) |id, j| {
            if (id == 0) break;
            const active = j == 0;
            const pokemon = side.pokemon[id - 1];

            if (pokemon.hp == 0 or Status.is(pokemon.status, .FRZ)) continue;
            const transform = foe_all_transform and transform: {
                for (if (active) side.active.moves else pokemon.moves) |m| {
                    if (m.id == .None) break :transform true;
                    if (m.id != .Transform) break :transform false;
                }
                break :transform true;
            };
            if (transform) continue;
            const no_pp = foe_all_ghosts and no_pp: {
                for (if (active) side.active.moves else pokemon.moves) |m| {
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

fn disabled(side: *Side, ident: ID, options: anytype) !bool {
    if (side.active.volatiles.disable_move != 0) {
        // A Pokémon that transforms after being disabled may end up with less move slots
        const m = side.active.moves[side.active.volatiles.disable_move - 1].id;
        // side.last_selected_move can be Struggle here on Pokemon Showdown we need an extra check
        const last = if (showdown and m == .Bide and side.active.volatiles.Bide)
            m
        else
            side.last_selected_move;
        if (m != .None and m == last) {
            side.active.volatiles.Charging = false;
            try options.log.disabled(ident, last);
            return true;
        }
    }
    return false;
}

fn buildRage(battle: anytype, who: Player, options: anytype) !void {
    const side = battle.side(who);
    if (side.active.volatiles.Rage and side.active.boosts.atk < 6) {
        try Effects.boost(battle, who, Move.get(.Rage), options);
    }
}

fn handleThrashing(battle: anytype, active: *ActivePokemon, player: Player, options: anytype) bool {
    var volatiles = &active.volatiles;
    assert(volatiles.Thrashing);
    if (volatiles.attacks > 0) return false;

    volatiles.Thrashing = false;
    volatiles.Confusion = true;
    volatiles.confusion = Rolls.confusionDuration(battle, player, true, options);
    return true;
}

fn onBegin(
    battle: anytype,
    player: Player,
    move: Move.Data,
    mslot: u8,
    residual: *bool,
    options: anytype,
) !void {
    assert(move.effect.onBegin());
    return switch (move.effect) {
        .Confusion => Effects.confusion(battle, player, move, options),
        .Conversion => Effects.conversion(battle, player, options),
        .FocusEnergy => Effects.focusEnergy(battle, player, options),
        .Haze => Effects.haze(battle, player, options),
        .Heal => Effects.heal(battle, player, options),
        .LeechSeed => Effects.leechSeed(battle, player, move, options),
        .LightScreen => Effects.lightScreen(battle, player, options),
        .Mimic => Effects.mimic(battle, player, move, mslot, options),
        .Mist => Effects.mist(battle, player, options),
        .Paralyze => Effects.paralyze(battle, player, move, options),
        .Poison => Effects.poison(battle, player, move, options),
        .Reflect => Effects.reflect(battle, player, options),
        .Splash => Effects.splash(battle, player, options),
        .Substitute => Effects.substitute(battle, player, residual, options),
        .SwitchAndTeleport => Effects.switchAndTeleport(battle, player, move, options),
        .Transform => Effects.transform(battle, player, options),
        else => unreachable,
    };
}

fn onEnd(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
    assert(move.effect.onEnd());
    return switch (move.effect) {
        .Bide => Effects.bide(battle, player, options),
        // zig fmt: off
        .AttackUp1, .AttackUp2, .DefenseUp1, .DefenseUp2,
        .EvasionUp1, .SpecialUp1, .SpecialUp2, .SpeedUp2 =>
            Effects.boost(battle, player, move, options),
        .AccuracyDown1, .AttackDown1, .DefenseDown1, .DefenseDown2, .SpeedDown1 =>
            Effects.unboost(battle, player, move, options),
        // zig fmt: on
        .Sleep => Effects.sleep(battle, player, move, options),
        else => unreachable,
    };
}

fn alwaysHappens(
    battle: anytype,
    player: Player,
    move: Move.Data,
    residual: *bool,
    options: anytype,
) !void {
    assert(move.effect.alwaysHappens());
    return switch (move.effect) {
        .DrainHP, .DreamEater => Effects.drainHP(battle, player, options),
        .Explode => Effects.explode(battle, player),
        .PayDay => Effects.payDay(battle, player, options),
        .Rage => Effects.rage(battle, player),
        .Recoil => Effects.recoil(battle, player, residual, options),
        .JumpKick, .Binding => {},
        else => unreachable,
    };
}

fn moveEffect(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
    return switch (move.effect) {
        .BurnChance1, .BurnChance2 => Effects.burnChance(battle, player, move, options),
        .ConfusionChance => Effects.confusion(battle, player, move, options),
        .FlinchChance1, .FlinchChance2 => Effects.flinchChance(battle, player, move, options),
        .FreezeChance => Effects.freezeChance(battle, player, move, options),
        .HyperBeam => Effects.hyperBeam(battle, player, options),
        .MultiHit, .DoubleHit, .Twineedle => unreachable,
        .ParalyzeChance1, .ParalyzeChance2 => Effects.paralyzeChance(battle, player, move, options),
        .PoisonChance1, .PoisonChance2 => Effects.poison(battle, player, move, options),
        // zig fmt: off
        .AttackDownChance, .DefenseDownChance, .SpecialDownChance, .SpeedDownChance =>
            Effects.unboost(battle, player, move, options),
        // zig fmt: on
        else => {},
    };
}

pub const Effects = struct {
    fn bide(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);

        side.active.volatiles.Bide = true;
        assert(!side.active.volatiles.Thrashing and !side.active.volatiles.Rage);
        side.active.volatiles.state = 0;
        side.active.volatiles.attacks = Rolls.attackingDuration(battle, player, options);

        try options.log.start(battle.active(player), .Bide);
    }

    fn burnChance(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute) return;

        if (Status.any(foe_stored.status)) {
            if (showdown and !foe.active.types.includes(move.type)) battle.rng.advance(1);
            // GLITCH: Freeze top move selection desync can occur if thawed Pokémon is slower
            if (Status.is(foe_stored.status, .FRZ)) {
                assert(move.type == .Fire);
                try options.log.curestatus(
                    battle.active(player.foe()),
                    foe_stored.status,
                    .Message,
                );
                foe_stored.status = 0;
            }
            return;
        }

        if (foe.active.types.includes(move.type)) return;
        if (!try Rolls.secondaryChance(battle, player, move.effect == .BurnChance1, options)) {
            return;
        }

        foe_stored.status = Status.init(.BRN);
        foe.active.stats.atk = @max(foe.active.stats.atk / 2, 1);

        try options.log.status(battle.active(player.foe()), foe_stored.status, .None);
    }

    fn charge(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);
        var volatiles = &side.active.volatiles;

        volatiles.Charging = true;
        const move = side.last_selected_move;
        if (move == .Fly or move == .Dig) volatiles.Invulnerable = true;
        try options.log.laststill();
        try options.log.prepare(battle.active(player), move);
    }

    fn confusion(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var foe = battle.foe(player);
        const sub = foe.active.volatiles.Substitute;

        if (move.effect == .ConfusionChance) {
            if (!try Rolls.confusionChance(battle, player, options)) return;
        } else {
            if (showdown) {
                if (!try checkHit(battle, player, move, options)) {
                    return;
                } else if (sub) {
                    return options.log.fail(battle.active(player.foe()), .None);
                }
            } else {
                if (sub) {
                    return options.log.fail(battle.active(player.foe()), .None);
                } else if (!try checkHit(battle, player, move, options)) {
                    return;
                }
            }
            try options.chance.commit(player, .hit);
        }

        if (foe.active.volatiles.Confusion) return;
        foe.active.volatiles.Confusion = true;
        foe.active.volatiles.confusion = Rolls.confusionDuration(battle, player, false, options);

        try options.log.start(battle.active(player.foe()), .Confusion);
    }

    fn conversion(battle: anytype, player: Player, options: anytype) !void {
        const foe = battle.foe(player);

        if (foe.active.volatiles.Invulnerable) {
            try options.log.lastmiss();
            return options.log.miss(battle.active(player));
        }

        battle.side(player).active.types = foe.active.types;
        return options.log.typechange(
            battle.active(player),
            foe.active.types,
            battle.active(player.foe()),
        );
    }

    fn disable(battle: anytype, player: Player, move: Move.Data, options: anytype) !?Result {
        var foe = battle.foe(player);
        var volatiles = &foe.active.volatiles;
        const foe_ident = battle.active(player.foe());

        // Pokémon Showdown handles hit/miss earlier in doMove
        if (!showdown) {
            if (!try checkHit(battle, player, move, options)) return null;
            try options.chance.commit(player, .hit);
        }

        if (volatiles.disable_move != 0) {
            try options.log.fail(foe_ident, .None);
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
            try options.log.fail(foe_ident, .None);
            return null;
        } else if (err) {
            // GLITCH: Transform + Mirror Move / Metronome PP softlock
            assert(!showdown);
            return Result.Error;
        }

        volatiles.disable_move =
            @intCast(try Rolls.moveSlot(battle, player, &foe.active.moves, n, options));
        volatiles.disable_duration = Rolls.disableDuration(battle, player, options);

        const id = foe.active.move(volatiles.disable_move).id;
        try options.log.startEffect(foe_ident, .Disable, id);
        return null;
    }

    fn drainHP(battle: anytype, player: Player, options: anytype) !void {
        var stored = battle.side(player).stored();

        if (battle.last_damage == 0) {
            assert(showdown);
            if (!battle.foe(player).active.volatiles.Substitute) return;
        }

        const drain = @max(battle.last_damage / 2, 1);
        battle.last_damage = drain;

        if (stored.hp == stored.stats.hp) return;
        stored.hp = @min(stored.stats.hp, stored.hp + drain);

        try options.log.drain(battle.active(player), stored, battle.active(player.foe()));
    }

    fn explode(battle: anytype, player: Player) !void {
        var side = battle.side(player);
        var stored = side.stored();

        stored.hp = 0;
        // Pokémon Showdown sets the status to 0 on faint(), and we need to do the same to be able
        // to correctly implement Pokémon Showdown's dumb speed-based switch mechanics
        if (!showdown) stored.status = 0;
        side.active.volatiles.LeechSeed = false;
    }

    fn flinchChance(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var volatiles = &battle.foe(player).active.volatiles;

        if (volatiles.Substitute) return;
        if (!try Rolls.secondaryChance(battle, player, move.effect == .FlinchChance1, options)) {
            return;
        }

        volatiles.Flinch = true;
        volatiles.Recharging = false;
    }

    fn focusEnergy(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.FocusEnergy) return;
        side.active.volatiles.FocusEnergy = true;

        try options.log.start(battle.active(player), .FocusEnergy);
    }

    fn freezeChance(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Substitute) return;

        if (Status.any(foe_stored.status)) {
            return if (showdown and !foe.active.types.includes(move.type)) battle.rng.advance(1);
        }

        if (foe.active.types.includes(move.type)) return;
        if (!try Rolls.secondaryChance(battle, player, true, options)) return;
        // Freeze Clause Mod
        if (showdown) for (foe.pokemon) |p| if (Status.is(p.status, .FRZ)) return;

        foe_stored.status = Status.init(.FRZ);
        // GLITCH: Hyper Beam recharging status is not cleared

        try options.log.status(foe_ident, foe_stored.status, .None);
    }

    fn haze(battle: anytype, player: Player, options: anytype) !void {
        var log = options.log;
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
                const p: Player = @enumFromInt(i);
                // Pokémon Showdown incorrectly does not prevent sleep/freeze from moving
                if (p != player and Status.any(s.stored().status)) {
                    try log.curestatus(foe_ident, foe_stored.status, .Silent);
                    s.stored().status = 0;
                } else if (showdown and s.stored().status == Status.TOX) {
                    s.stored().status = Status.init(.PSN);
                    try log.status(battle.active(p), s.stored().status, .None);
                }
                try clearVolatiles(battle, p, p != player, options);
            }
        } else {
            if (Status.any(foe_stored.status)) {
                if (Status.is(foe_stored.status, .FRZ) or Status.is(foe_stored.status, .SLP)) {
                    foe.last_selected_move = .SKIP_TURN;
                }
                try log.curestatus(foe_ident, foe_stored.status, .Silent);
                foe_stored.status = 0;
            }
            try clearVolatiles(battle, player, false, options);
            try clearVolatiles(battle, player.foe(), true, options);
        }
    }

    fn heal(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);
        var stored = side.stored();
        const ident = battle.active(player);

        // GLITCH: HP recovery move failure glitches
        const delta = stored.stats.hp - stored.hp;
        if (delta == 0 or (delta & 255 == 255 and stored.hp % 256 != 0)) {
            return options.log.fail(ident, .None);
        }

        const rest = side.last_selected_move == .Rest;
        if (rest) {
            // Adding the sleep status runs the sleep condition handler to roll duration
            if (showdown) battle.rng.advance(1);
            stored.status = Status.slf(2);
            try options.log.statusFrom(ident, stored.status, Move.Rest);
            stored.hp = stored.stats.hp;
        } else {
            stored.hp = @min(stored.stats.hp, stored.hp + (stored.stats.hp / 2));
        }
        try options.log.heal(.{ ident, stored, if (rest) Heal.Silent else Heal.None });
    }

    fn hyperBeam(battle: anytype, player: Player, options: anytype) !void {
        battle.side(player).active.volatiles.Recharging = true;
        try options.log.mustrecharge(battle.active(player));
    }

    fn leechSeed(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var foe = battle.foe(player);

        if (showdown) {
            // Invulnerability trumps type immunity on Pokémon Showdown
            if (!foe.active.volatiles.Invulnerable and foe.active.types.includes(.Grass)) {
                return options.log.immune(battle.active(player.foe()), .None);
            }
            if (!try checkHit(battle, player, move, options)) return;
            if (foe.active.volatiles.LeechSeed) return;
        } else {
            if (!try checkHit(battle, player, move, options)) return;
            if (foe.active.types.includes(.Grass) or foe.active.volatiles.LeechSeed) {
                try options.log.lastmiss();
                return options.log.miss(battle.active(player));
            }
        }

        try options.chance.commit(player, .hit);
        foe.active.volatiles.LeechSeed = true;

        try options.log.start(battle.active(player.foe()), .LeechSeed);
    }

    fn lightScreen(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.LightScreen) {
            return options.log.fail(battle.active(player), .None);
        }
        side.active.volatiles.LightScreen = true;

        try options.log.start(battle.active(player), .LightScreen);
    }

    fn mimic(battle: anytype, player: Player, move: Move.Data, mslot: u8, options: anytype) !void {
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
                        oslot = @intCast(i + 1);
                        break :has_mimic true;
                    }
                }
                break :has_mimic false;
            };
            if (!has_mimic) {
                // Invulnerable foes or 1/256 miss can trigger |-miss| instead of |-fail|
                if (!try checkHit(battle, player, move, options)) return;
                try options.chance.commit(player, .hit);
                return options.log.fail(battle.active(player.foe()), .None);
            }
        }
        if (!try checkHit(battle, player, move, options)) return;
        try options.chance.commit(player, .hit);

        const rslot = try Rolls.moveSlot(battle, player, &foe.active.moves, 0, options);
        side.active.move(oslot).id = foe.active.move(rslot).id;

        try options.log.startEffect(battle.active(player), .Mimic, side.active.move(oslot).id);
    }

    fn mist(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.Mist) return;
        side.active.volatiles.Mist = true;

        try options.log.start(battle.active(player), .Mist);
    }

    fn multiHit(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var side = battle.side(player);

        assert(!side.active.volatiles.MultiHit);
        side.active.volatiles.MultiHit = true;

        side.active.volatiles.attacks = if (move.effect == .MultiHit)
            try Rolls.distribution(battle, .MultiHit, player, options)
        else
            2;
    }

    fn paralyze(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var log = options.log;
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        // Only Thunder Wave checks for type-immunity, not Glare
        const immune = move.type == .Electric and foe.active.types.immune(move.type);

        if (showdown) {
            // Invulnerability trumps type immunity on Pokémon Showdown
            if (immune and !foe.active.volatiles.Invulnerable) return log.immune(foe_ident, .None);
            if (!try checkHit(battle, player, move, options)) return;
        }
        if (Status.any(foe_stored.status)) {
            return log.fail(
                foe_ident,
                if (Status.is(foe_stored.status, .PAR)) .Paralysis else .None,
            );
        }
        if (!showdown) {
            if (immune) return log.immune(foe_ident, .None);
            if (!try checkHit(battle, player, move, options)) return;
        }
        try options.chance.commit(player, .hit);

        foe_stored.status = Status.init(.PAR);
        foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);

        try log.status(foe_ident, foe_stored.status, .None);
    }

    fn paralyzeChance(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();

        if (foe.active.volatiles.Substitute) return;

        if (Status.any(foe_stored.status)) {
            return if (showdown and !foe.active.types.includes(move.type)) battle.rng.advance(1);
        }

        // Body Slam can't paralyze a Normal type Pokémon
        if (foe.active.types.includes(move.type)) return;
        if (!try Rolls.secondaryChance(battle, player, move.effect == .ParalyzeChance1, options)) {
            return;
        }

        foe_stored.status = Status.init(.PAR);
        foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);

        try options.log.status(battle.active(player.foe()), foe_stored.status, .None);
    }

    fn payDay(battle: anytype, player: Player, options: anytype) !void {
        if (!showdown or !battle.foe(player).active.volatiles.Substitute) {
            try options.log.fieldactivate();
        }
    }

    fn poison(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var log = options.log;
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());
        const toxic = battle.side(player).last_selected_move == .Toxic;

        if (showdown and move.effect == .Poison and !try checkHit(battle, player, move, options)) {
            return;
        } else if (foe.active.volatiles.Substitute) {
            if (move.effect != .Poison) return;
            return log.fail(foe_ident, .None);
        } else if (Status.any(foe_stored.status)) {
            if (move.effect != .Poison) return if (showdown) battle.rng.advance(1);
            // Pokémon Showdown considers Toxic to be a status even in Generation I and so
            // will not include a fail reason for Toxic vs. Poison or vice-versa...
            return log.fail(foe_ident, if (Status.is(foe_stored.status, .PSN))
                if (!showdown)
                    .Poison
                else if (toxic == (foe_stored.status == Status.TOX))
                    if (toxic) .Toxic else .Poison
                else
                    .None
            else
                .None);
        } else if (foe.active.types.includes(.Poison)) {
            if (move.effect != .Poison) return if (showdown) battle.rng.advance(1);
            return log.immune(foe_ident, .None);
        }

        if (move.effect == .Poison) {
            if (!showdown and !try checkHit(battle, player, move, options)) return;
            try options.chance.commit(player, .hit);
        } else {
            if (!try Rolls.poisonChance(battle, player, move.effect == .PoisonChance1, options)) {
                return;
            }
        }

        foe_stored.status = Status.init(.PSN);
        if (toxic) {
            if (showdown) foe_stored.status = Status.TOX;
            foe.active.volatiles.Toxic = true;
            foe.active.volatiles.toxic = 0;
        }

        try log.status(foe_ident, foe_stored.status, .None);
    }

    fn rage(battle: anytype, player: Player) !void {
        var volatiles = &battle.side(player).active.volatiles;
        assert(!volatiles.Bide);
        volatiles.Rage = true;
    }

    fn recoil(battle: anytype, player: Player, residual: *bool, options: anytype) !void {
        var side = battle.side(player);
        var stored = side.stored();

        assert(showdown or battle.last_damage > 0);
        if (showdown and battle.last_damage == 0) return;

        const damage: i16 = @intCast(@max(battle.last_damage /
            @as(u8, if (side.last_selected_move == .Struggle) 2 else 4), 1));
        stored.hp = @intCast(@max(@as(i16, @intCast(stored.hp)) - damage, 0));

        try options.log.damageOf(
            battle.active(player),
            stored,
            .RecoilOf,
            battle.active(player.foe()),
        );
        if (showdown and stored.hp == 0) residual.* = false;
    }

    fn reflect(battle: anytype, player: Player, options: anytype) !void {
        var side = battle.side(player);

        if (side.active.volatiles.Reflect) return options.log.fail(battle.active(player), .None);
        side.active.volatiles.Reflect = true;

        try options.log.start(battle.active(player), .Reflect);
    }

    fn sleep(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var foe = battle.foe(player);
        var foe_stored = foe.stored();
        const foe_ident = battle.active(player.foe());

        if (foe.active.volatiles.Recharging) {
            // Hit test not applied if the target is recharging (bypass)
            // The volatile itself actually gets cleared below since on Pokémon Showdown
            // the Sleep Clause Mod might activate, causing us to not actually bypass
        } else {
            if (Status.any(foe_stored.status)) {
                return options.log.fail(
                    foe_ident,
                    if (Status.is(foe_stored.status, .SLP)) .Sleep else .None,
                );
            }
            // If checkHit in doMove didn't return true Pokémon Showdown wouldn't be in here
            if (!showdown and !try checkHit(battle, player, move, options)) return;
            try options.chance.commit(player, .hit);
        }

        // Sleep Clause Mod
        if (showdown) {
            for (foe.pokemon) |p| {
                if (Status.is(p.status, .SLP) and !Status.is(p.status, .EXT)) return;
            }
        }
        foe.active.volatiles.Recharging = false;

        foe_stored.status = Status.slp(Rolls.sleepDuration(battle, player, options));
        const last = battle.side(player).last_selected_move;
        try options.log.statusFrom(foe_ident, foe_stored.status, last);
    }

    fn splash(battle: anytype, player: Player, options: anytype) !void {
        try options.log.activate(battle.active(player), .Splash);
    }

    fn substitute(battle: anytype, player: Player, residual: *bool, options: anytype) !void {
        var side = battle.side(player);
        if (side.active.volatiles.Substitute) {
            return options.log.fail(battle.active(player), .Substitute);
        }

        assert(side.stored().stats.hp <= 1023);
        // Will be 0 if HP is <= 3 meaning that the user gets a 1 HP Substitute for "free"
        const hp: u8 = @intCast(side.stored().stats.hp / 4);
        // Pokénon Showdown incorrectly checks for 1/4 HP based on `target.maxhp / 4` which returns
        // a floating point value and thus only correctly implements the Substitute 1/4 glitch when
        // the target's HP is exactly divisible by 4 (here we're using an inlined divCeil routine to
        // avoid having to convert to floating point)
        const required_hp = if (showdown) @divFloor(side.stored().stats.hp - 1, 4) + 1 else hp;
        if (side.stored().hp < required_hp) return options.log.fail(battle.active(player), .Weak);

        // GLITCH: can leave the user with 0 HP (faints later) because didn't check '<=' above
        side.stored().hp -= hp;
        side.active.volatiles.substitute = hp + 1;
        side.active.volatiles.Substitute = true;
        try options.log.start(battle.active(player), .Substitute);
        if (hp > 0) {
            try options.log.damage(battle.active(player), side.stored(), .None);
            if (showdown and side.stored().hp == 0) residual.* = false;
        }
    }

    fn switchAndTeleport(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        // Whirlwind/Roar should not roll to hit/reset damage but Pokémon Showdown does anyway
        if (showdown) {
            if (battle.side(player).last_selected_move == .Teleport) return;
            if (try checkHit(battle, player, move, options)) {
                try options.chance.commit(player, .hit);
            }
            battle.last_damage = 0;
        } else {
            try options.log.fail(battle.active(player), .None);
            try options.log.laststill();
        }
    }

    fn thrashing(battle: anytype, player: Player, options: anytype) void {
        var volatiles = &battle.side(player).active.volatiles;
        assert(!volatiles.Thrashing);
        assert(!volatiles.Bide);

        volatiles.Thrashing = true;
        volatiles.attacks = Rolls.attackingDuration(battle, player, options);
    }

    fn transform(battle: anytype, player: Player, options: anytype) !void {
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

        try options.log.transform(battle.active(player), foe_ident);
    }

    fn binding(battle: anytype, player: Player, rewrap: bool, options: anytype) !void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        if (side.active.volatiles.Binding) return;
        side.active.volatiles.Binding = true;
        // GLITCH: Hyper Beam automatic selection glitch if Recharging gets cleared on miss
        // (Pokémon Showdown unitentionally patches this glitch, preventing automatic selection)
        if (!showdown) {
            foe.active.volatiles.Recharging = false;
        } else if (foe.stored().hp == 0) return if (!rewrap) battle.rng.advance(1);

        side.active.volatiles.attacks =
            try Rolls.distribution(battle, .Binding, player, options) - 1;
    }

    fn boost(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var log = options.log;
        var side = battle.side(player);
        const ident = battle.active(player);

        var stats = &side.active.stats;
        var boosts = &side.active.boosts;

        switch (move.effect) {
            .AttackUp1, .AttackUp2, .Rage => {
                assert(boosts.atk >= -6 and boosts.atk <= 6);
                if (boosts.atk == 6) return log.fail(ident, .None);
                const n: u2 = if (move.effect == .AttackUp2) 2 else 1;
                boosts.atk = @as(i4, @intCast(@min(6, @as(i8, boosts.atk) + n)));
                const reason = if (move.effect == .Rage) Boost.Rage else Boost.Attack;
                if (stats.atk == MAX_STAT_VALUE) {
                    boosts.atk -= 1;
                    if (showdown) {
                        try log.boost(ident, reason, n);
                        try log.boost(ident, Boost.Attack, -1);
                        if (move.effect == .Rage) return;
                    }
                    return log.fail(ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.atk) + 6))];
                const stat = unmodifiedStats(battle, side).atk;
                stats.atk = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, reason, n);
                // Pokémon Showdown doesn't re-apply status modifiers after Rage boosts
                if (showdown and move.effect == .Rage) return;
            },
            .DefenseUp1, .DefenseUp2 => {
                assert(boosts.def >= -6 and boosts.def <= 6);
                if (boosts.def == 6) return log.fail(ident, .None);
                const n: u2 = if (move.effect == .DefenseUp2) 2 else 1;
                boosts.def = @intCast(@min(6, @as(i8, boosts.def) + n));
                if (stats.def == MAX_STAT_VALUE) {
                    boosts.def -= 1;
                    if (showdown) {
                        try log.boost(ident, .Defense, n);
                        try log.boost(ident, .Defense, -1);
                    }
                    return log.fail(ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.def) + 6))];
                const stat = unmodifiedStats(battle, side).def;
                stats.def = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .Defense, n);
            },
            .SpeedUp2 => {
                assert(boosts.spe >= -6 and boosts.spe <= 6);
                if (boosts.spe == 6) return log.fail(ident, .None);
                boosts.spe = @intCast(@min(6, @as(i8, boosts.spe) + 2));
                if (stats.spe == MAX_STAT_VALUE) {
                    boosts.spe -= 1;
                    if (showdown) {
                        try log.boost(ident, .Speed, 2);
                        try log.boost(ident, .Speed, -1);
                    }
                    return log.fail(ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.spe) + 6))];
                const stat = unmodifiedStats(battle, side).spe;
                stats.spe = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .Speed, 2);
            },
            .SpecialUp1, .SpecialUp2 => {
                assert(boosts.spc >= -6 and boosts.spc <= 6);
                if (boosts.spc == 6) return log.fail(ident, .None);
                const n: u2 = if (move.effect == .SpecialUp2) 2 else 1;
                boosts.spc = @intCast(@min(6, @as(i8, boosts.spc) + n));
                if (stats.spc == MAX_STAT_VALUE) {
                    boosts.spc -= 1;
                    if (showdown) {
                        try log.boost(ident, .SpecialAttack, n);
                        try log.boost(ident, .SpecialAttack, -1);
                        try log.boost(ident, .SpecialDefense, n);
                        try log.boost(ident, .SpecialDefense, -1);
                    }
                    return log.fail(ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.spc) + 6))];
                const stat = unmodifiedStats(battle, side).spc;
                stats.spc = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                try log.boost(ident, .SpecialAttack, n);
                try log.boost(ident, .SpecialDefense, n);
            },
            .EvasionUp1 => {
                assert(boosts.evasion >= -6 and boosts.evasion <= 6);
                if (boosts.evasion == 6) return log.fail(ident, .None);
                boosts.evasion = @intCast(@min(6, @as(i8, boosts.evasion) + 1));
                try log.boost(ident, .Evasion, 1);
            },
            else => unreachable,
        }

        // GLITCH: Stat modification errors glitch
        statusModify(battle.foe(player).stored().status, &battle.foe(player).active.stats);
    }

    fn unboost(battle: anytype, player: Player, move: Move.Data, options: anytype) !void {
        var log = options.log;
        var foe = battle.foe(player);
        const foe_ident = battle.active(player.foe());
        const secondary = move.effect.isStatDownChance();

        if (foe.active.volatiles.Substitute) return if (!secondary) log.fail(foe_ident, .None);

        if (secondary) {
            const proc = try Rolls.unboost(battle, player, options);
            if (!proc or foe.active.volatiles.Invulnerable) return;
        } else {
            // checkHit already checks for Invulnerable
            if (!showdown and !try checkHit(battle, player, move, options)) return;
            try options.chance.commit(player, .hit);
        }

        var stats = &foe.active.stats;
        var boosts = &foe.active.boosts;
        const fail = showdown or !secondary;

        switch (move.effect) {
            .AttackDown1, .AttackDownChance => {
                assert(boosts.atk >= -6 and boosts.atk <= 6);
                if (boosts.atk == -6) return if (fail) try log.fail(foe_ident, .None);
                boosts.atk = @intCast(@max(-6, @as(i8, boosts.atk) - 1));
                if (stats.atk == 1) {
                    boosts.atk += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .Attack, -1);
                        try log.boost(foe_ident, .Attack, 1);
                    }
                    return log.fail(foe_ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.atk) + 6))];
                const stat = unmodifiedStats(battle, foe).atk;
                stats.atk = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Attack, -1);
            },
            .DefenseDown1, .DefenseDown2, .DefenseDownChance => {
                assert(boosts.def >= -6 and boosts.def <= 6);
                if (boosts.def == -6) return if (fail) try log.fail(foe_ident, .None);
                const n: u2 = if (move.effect == .DefenseDown2) 2 else 1;
                boosts.def = @intCast(@max(-6, @as(i8, boosts.def) - n));
                if (stats.def == 1) {
                    boosts.def += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .Defense, -@as(i8, n));
                        try log.boost(foe_ident, .Defense, 1);
                    }
                    return log.fail(foe_ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.def) + 6))];
                const stat = unmodifiedStats(battle, foe).def;
                stats.def = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Defense, -@as(i8, n));
            },
            .SpeedDown1, .SpeedDownChance => {
                assert(boosts.spe >= -6 and boosts.spe <= 6);
                if (boosts.spe == -6) return if (fail) try log.fail(foe_ident, .None);
                boosts.spe = @intCast(@max(-6, @as(i8, boosts.spe) - 1));
                if (stats.spe == 1) {
                    boosts.spe += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .Speed, -1);
                        try log.boost(foe_ident, .Speed, 1);
                    }
                    return log.fail(foe_ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.spe) + 6))];
                const stat = unmodifiedStats(battle, foe).spe;
                stats.spe = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .Speed, -1);
                assert(boosts.spe >= -6);
            },
            .SpecialDownChance => {
                assert(boosts.spc >= -6 and boosts.spc <= 6);
                if (boosts.spc == -6) return if (fail) try log.fail(foe_ident, .None);
                boosts.spc = @intCast(@max(-6, @as(i8, boosts.spc) - 1));
                if (stats.spc == 1) {
                    boosts.spc += 1;
                    if (showdown) {
                        try log.boost(foe_ident, .SpecialAttack, -1);
                        try log.boost(foe_ident, .SpecialAttack, 1);
                        try log.boost(foe_ident, .SpecialDefense, -1);
                        try log.boost(foe_ident, .SpecialDefense, 1);
                    }
                    return log.fail(foe_ident, .None);
                }
                var mod = BOOSTS[@as(u4, @intCast(@as(i8, boosts.spc) + 6))];
                const stat = unmodifiedStats(battle, foe).spc;
                stats.spc = @max(1, stat * mod[0] / mod[1]);
                try log.boost(foe_ident, .SpecialAttack, -1);
                try log.boost(foe_ident, .SpecialDefense, -1);
            },
            .AccuracyDown1 => {
                assert(boosts.accuracy >= -6 and boosts.accuracy <= 6);
                if (boosts.accuracy == -6) return if (fail) try log.fail(foe_ident, .None);
                boosts.accuracy = @intCast(@max(-6, @as(i8, boosts.accuracy) - 1));
                try log.boost(foe_ident, .Accuracy, -1);
            },
            else => unreachable,
        }

        // GLITCH: Stat modification errors glitch
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
        active.volatiles.Thrashing or active.volatiles.Charging;
}

fn clearVolatiles(battle: anytype, who: Player, clear: bool, options: anytype) !void {
    var log = options.log;
    var side = battle.side(who);
    var volatiles = &side.active.volatiles;
    const ident = battle.active(who);

    options.chance.clearDurations(who, clear);

    if (volatiles.disable_move != 0) {
        volatiles.disable_move = 0;
        volatiles.disable_duration = 0;
        try log.end(ident, .DisableSilent);
    }
    if (volatiles.Confusion) {
        // volatiles.confusion is left unchanged
        volatiles.Confusion = false;
        try log.end(ident, .ConfusionSilent);
    }
    if (volatiles.Mist) {
        volatiles.Mist = false;
        try log.end(ident, .MistSilent);
    }
    if (volatiles.FocusEnergy) {
        volatiles.FocusEnergy = false;
        try log.end(ident, .FocusEnergySilent);
    }
    if (volatiles.LeechSeed) {
        volatiles.LeechSeed = false;
        try log.end(ident, .LeechSeedSilent);
    }
    if (!showdown and volatiles.Toxic) {
        volatiles.Toxic = false;
        // volatiles.toxic is left unchanged, except on Pokémon Showdown which clears it (below)
    }
    if (volatiles.LightScreen) {
        volatiles.LightScreen = false;
        try log.end(ident, .LightScreenSilent);
    }
    if (volatiles.Reflect) {
        volatiles.Reflect = false;
        try log.end(ident, .ReflectSilent);
    }
    if (showdown and volatiles.Toxic) {
        volatiles.Toxic = false;
        // Pokémon Showdown erroneously clears the toxic counter
        volatiles.toxic = 0;
        try log.end(ident, .ToxicSilent);
    }
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

    fn criticalHit(battle: anytype, player: Player, rate: u8, options: anytype) !bool {
        const crit = if (options.calc.overridden(player, .critical_hit)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, rate, 256)
        else
            std.math.rotl(u8, battle.rng.next(), 3) < rate;

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

    fn hit(battle: anytype, player: Player, accuracy: u8, options: anytype) bool {
        const ok = if (options.calc.overridden(player, .hit)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, accuracy, 256)
        else
            battle.rng.next() < accuracy;

        options.chance.hit(ok, accuracy);
        return ok;
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

    fn confusionChance(battle: anytype, player: Player, options: anytype) !bool {
        const proc = if (options.calc.overridden(player, .secondary_chance)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 25, 256)
        else
            battle.rng.next() < Gen12.percent(10);

        try options.chance.secondaryChance(player, proc, 25);
        return proc;
    }

    fn secondaryChance(battle: anytype, player: Player, low: bool, options: anytype) !bool {
        const rate: u8 = if (low) 26 else 77;

        const proc = if (options.calc.overridden(player, .secondary_chance)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, rate, 256)
        else
            battle.rng.next() < 1 + (if (low) Gen12.percent(10) else Gen12.percent(30));

        try options.chance.secondaryChance(player, proc, rate);
        return proc;
    }

    fn poisonChance(battle: anytype, player: Player, low: bool, options: anytype) !bool {
        const rate: u8 = if (low) 52 else 103;

        const proc = if (options.calc.overridden(player, .secondary_chance)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, rate, 256)
        else
            battle.rng.next() < 1 + (if (low) Gen12.percent(20) else Gen12.percent(40));

        try options.chance.secondaryChance(player, proc, rate);
        return proc;
    }

    fn unboost(battle: anytype, player: Player, options: anytype) !bool {
        const proc = if (options.calc.overridden(player, .secondary_chance)) |val|
            val == .true
        else if (showdown)
            battle.rng.chance(u8, 85, 256)
        else
            battle.rng.next() < Gen12.percent(33) + 1;

        try options.chance.secondaryChance(player, proc, 85);
        return proc;
    }

    fn metronome(battle: anytype, player: Player, options: anytype) !Move {
        const move: Move = if (options.calc.overridden(player, .metronome)) |val|
            val
        else if (showdown)
            Move.METRONOME[battle.rng.range(u8, 0, Move.METRONOME.len)]
        else move: {
            while (true) {
                const r = battle.rng.next();
                if (r == 0 or r == @intFromEnum(Move.Metronome)) continue;
                if (r >= @intFromEnum(Move.Struggle)) continue;
                break :move @enumFromInt(r);
            }
        };

        try options.chance.metronome(player, move);
        return move;
    }

    fn psywave(battle: anytype, player: Player, max: u8, options: anytype) !u8 {
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

    fn sleepDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            battle.rng.range(u3, 1, 8)
        else duration: {
            while (true) {
                const r = battle.rng.next() & 7;
                if (r != 0) break :duration @intCast(r);
            }
        };

        assert(duration >= 1 and duration <= 7);
        options.chance.duration(.sleep, player, player.foe(), duration);
        return duration;
    }

    fn disableDuration(battle: anytype, player: Player, options: anytype) u4 {
        const duration: u4 = if (options.calc.overridden(player, .duration)) |val|
            val
        else if (showdown)
            battle.rng.range(u4, 1, 9)
        else
            @intCast((battle.rng.next() & 7) + 1);

        assert(duration >= 1 and duration <= 8);
        options.chance.duration(.disable, player, player.foe(), duration);
        return duration;
    }

    fn confusionDuration(battle: anytype, player: Player, self: bool, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            battle.rng.range(u3, 2, 6)
        else
            @intCast((battle.rng.next() & 3) + 2);

        assert(duration >= 2 and duration <= 5);
        options.chance.duration(.confusion, player, if (self) player else player.foe(), duration);
        return duration;
    }

    fn attackingDuration(battle: anytype, player: Player, options: anytype) u3 {
        const duration: u3 = if (options.calc.overridden(player, .duration)) |val|
            @intCast(val)
        else if (showdown)
            battle.rng.range(u3, 2, 4)
        else
            @intCast((battle.rng.next() & 1) + 2);

        assert(duration >= 2 and duration <= 3);
        options.chance.duration(.attacking, player, player, duration);
        return duration;
    }

    const DISTRIBUTION = [_]u3{ 2, 2, 2, 3, 3, 3, 4, 5 };

    fn distribution(
        battle: anytype,
        comptime effect: Move.Effect,
        player: Player,
        options: anytype,
    ) !u3 {
        const roll = if (effect == .Binding) .duration else .multi_hit;
        const n: u3 = if (options.calc.overridden(player, roll)) |val|
            @intCast(val)
        else if (showdown)
            DISTRIBUTION[battle.rng.range(u3, 0, DISTRIBUTION.len)]
        else n: {
            const r = (battle.rng.next() & 3);
            break :n @intCast((if (r < 2) r else battle.rng.next() & 3) + 2);
        };

        assert(n >= 2 and n <= 5);
        if (effect == .Binding) {
            options.chance.duration(.binding, player, player, n);
        } else {
            try options.chance.multiHit(player, n);
        }
        return n;
    }

    fn moveSlot(
        battle: anytype,
        player: Player,
        moves: []MoveSlot,
        check_pp: u4,
        options: anytype,
    ) !u4 {
        // TODO: consider throwing error instead of rerolling?
        const overridden = if (options.calc.overridden(player, .move_slot)) |val|
            if (moves[val - 1].id != .None and (check_pp == 0 or moves[val - 1].pp > 0))
                val
            else
                null
        else
            null;

        const slot: u4 = overridden orelse slot: {
            if (showdown) {
                if (check_pp == 0) {
                    var i: usize = moves.len;
                    while (i > 0) {
                        i -= 1;
                        if (moves[i].id != .None) {
                            break :slot battle.rng.range(u4, 0, @as(u4, @intCast(i + 1))) + 1;
                        }
                    }
                } else {
                    var r = battle.rng.range(u4, 0, check_pp) + 1;
                    var i: usize = 0;
                    while (i < moves.len and r > 0) : (i += 1) {
                        if (moves[i].pp > 0) {
                            r -= 1;
                            if (r == 0) break :slot @intCast(i + 1);
                        }
                    }
                }
            }

            while (true) {
                const r: u4 = @intCast(battle.rng.next() & 3);
                if (moves[r].id != .None and (check_pp == 0 or moves[r].pp > 0)) break :slot r + 1;
            }
        };

        try options.chance.moveSlot(player, slot, moves, check_pp);
        return slot;
    }
};

test "RNG agreement" {
    if (!showdown) return;
    var expected: [256]u32 = undefined;
    for (0..expected.len) |i| {
        expected[i] = @intCast(i * 0x1000000);
    }

    var spe: rng.FixedRNG(1, expected.len) = .{ .rolls = expected };
    var cfz: rng.FixedRNG(1, expected.len) = .{ .rolls = expected };
    var par: rng.FixedRNG(1, expected.len) = .{ .rolls = expected };
    var brn: rng.FixedRNG(1, expected.len) = .{ .rolls = expected };
    var eff: rng.FixedRNG(1, expected.len) = .{ .rolls = expected };

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
                    if (m.id == if (active.volatiles.Bide) .Bide else side.last_selected_move) {
                        // Pokémon Showdown displays Struggle if limited to Bide but unable to pick
                        const struggle =
                            m.id == .Bide and (m.pp == 0 or active.volatiles.disable_move == slot);
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
                if (active.volatiles.disable_move == slot) continue;
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
