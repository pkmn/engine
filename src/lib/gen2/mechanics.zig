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

fn selectMove(battle: anytype) ?Result {
    _ = battle;
    return null;
}

fn saveMove(battle: anytype) void {
    _ = battle;
    return null;
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

    active.stats = incoming.stats;
    active.species = incoming.species;
    active.types = incoming.types;
    active.boosts = .{};
    active.volatiles = .{};
    active.moves = incoming.moves;

    statusModify(incoming.status, &active.stats);

    try options.log.switched(battle.active(player), incoming);
    // TODO: options.chance.switched(player, side.order[0], out);

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

    const m1 = battle.side(.P1).last_selected_move;
    const m2 = battle.side(.P2).last_selected_move;
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
    if (try executeMove(battle, player, player_choice, options)) |r| return r;
    if (try executeMove(battle, foe_player, foe_choice, options)) |r| return r;
    return null;
}

fn executeMove(battle: anytype, player: Player, choice: Choice, options: anytype) !?Result {
    if (choice.type == .Switch) {
        try switchIn(battle, player, choice.data, false, options);
        return null;
    }

    @panic("TODO");
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
