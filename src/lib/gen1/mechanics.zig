const std = @import("std");
const build_options = @import("build_options");

const rng = @import("../common/rng.zig");

const data = @import("./data.zig");
const protocol = @import("./protocol.zig");

const assert = std.debug.assert;

const showdown = build_options.showdown;

const Gen12 = rng.Gen12;

const Side = data.Side;
const Choice = data.Choice;
const Result = data.Result;
const Status = data.Status;
const Move = data.Move;
const Stats = data.Stats;

// FIXME: https://www.smogon.com/forums/threads/self-ko-clause-gens-1-4.3653037/
// FIXME need to prompt c1 and c2 for new choices...? = should be able to tell choice from state?
pub fn update(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    _ = c1;
    _ = c2;

    if (battle.turn == 0) {
        var slot = findFirstAlive(battle.p2());
        if (slot == 0) return if (findFirstAlive(battle.p1()) == 0) .Tie else .Win;
        try switchIn(battle.p2(), slot, log);

        slot = findFirstAlive(battle.p1());
        if (slot == 0) return .Lose;
        try switchIn(battle.p1(), slot, log);

        battle.turn = 1;
        try log.turn(1);
        return .None;
    }

    // TODO

    return .None;
}

pub fn findFirstAlive(side: *const Side) u8 {
    for (side.pokemon) |pokemon, i| {
        if (pokemon.hp > 0) return @truncate(u8, i + 1); // index -> slot
    }
    return 0;
}

pub fn switchIn(side: *Side, slot: u8, log: anytype) !void {
    var active = &side.active;

    assert(slot != 0);
    assert(slot != active.position);
    assert(active.position == 0 or side.get(active.position).position == 1);

    const incoming = side.get(slot);
    if (active.position != 0) side.get(active.position).position = incoming.position;
    incoming.position = 1;

    inline for (std.meta.fields(@TypeOf(active.stats))) |field| {
        @field(active.stats, field.name) = @field(incoming.stats, field.name);
    }
    active.volatiles = .{};
    for (incoming.moves) |move, j| {
        active.moves[j] = move;
    }
    active.boosts = .{};
    active.species = incoming.species;
    active.position = slot;

    if (Status.is(incoming.status, .PAR)) {
        active.stats.spe /= 4;
        if (active.stats.spe == 0) active.stats.spe = 1;
    } else if (Status.is(incoming.status, .BRN)) {
        active.stats.atk /= 2;
        if (active.stats.atk == 0) active.stats.atk = 1;
    }
    // TODO: ld hl, wEnemyBattleStatus1; res USING_TRAPPING_MOVE, [hl]

    const ident = active.position; // FIXME set upper bit of ident to indicate side from perspective
    try log.switched(ident);
}

// TODO return an enum instead of bool to handle multiple cases
pub fn beforeMove(battle: anytype, mslot: u8, log: anytype) !bool {
    var p1 = battle.p1(); // FIXME need perspective to know which side!
    const p2 = battle.p2();
    var active = &p1.active;
    const ident = active.position; // FIXME set upper bit of ident to indicate side from perspective
    var stored = p1.get(active.position);
    var volatiles = &active.volatiles;

    assert(mslot > 0 and mslot <= 4);
    assert(p1.active.moves[mslot - 1].id != .None);

    if (Status.is(stored.status, .SLP)) {
        stored.status -= 1;
        if (!Status.any(stored.status)) try log.cant(ident, .Sleep);
        return false;
    }
    if (Status.is(stored.status, .FRZ)) {
        try log.cant(ident, .Freeze);
        return false;
    }
    if (p2.active.volatiles.PartialTrap) {
        try log.cant(ident, .PartialTrap);
        return false;
    }
    if (volatiles.Flinch) {
        volatiles.Flinch = false;
        try log.cant(ident, .Flinch);
        return false;
    }
    if (volatiles.Recharging) {
        volatiles.Recharging = false;
        try log.cant(ident, .Recharging);
        return false;
    }
    if (volatiles.data.disabled.duration > 0) {
        volatiles.data.disabled.duration -= 1;
        if (volatiles.data.disabled.duration == 0) {
            volatiles.data.disabled.move = 0;
            try log.end(ident, .Disable);
        }
    }
    if (volatiles.Confusion) {
        assert(volatiles.data.confusion > 0);
        volatiles.data.confusion -= 1;
        if (volatiles.data.confusion == 0) {
            volatiles.Confusion = false;
            try log.end(ident, .Confusion);
        } else {
            try log.activate(ident, .Confusion);
            const confused = if (showdown) {
                !battle.rng.chance(128, 256);
            } else {
                battle.rng.next() >= Gen12.percent(50) + 1;
            };
            if (confused) {
                // FIXME: implement self hit
                volatiles.Bide = false;
                volatiles.Locked = false;
                volatiles.MultiHit = false;
                volatiles.Flinch = false;
                volatiles.Charging = false;
                volatiles.PartialTrap = false;
                volatiles.Invulnerable = false;
                return false;
            }
        }
    }
    if (volatiles.data.disabled.move == mslot) {
        volatiles.Charging = false;
        try log.disabled(ident, volatiles.data.disabled.move);
        return false;
    }
    if (Status.is(stored.status, .PAR)) {
        const paralyzed = if (showdown) {
            battle.rng.chance(63, 256);
        } else {
            battle.rng.next() < Gen12.percent(25);
        };
        if (paralyzed) {
            volatiles.Bide = false;
            volatiles.Locked = false;
            volatiles.Charging = false;
            volatiles.PartialTrap = false;
            // NB: Invulnerable is not cleared, resulting in the Fly/Dig glitch
            try log.cant(ident, .Paralysis);
            return false;
        }
    }
    if (volatiles.Bide) {
        // TODO accumulate? overflow?
        volatiles.data.bide += battle.last_damage;
        try log.activate(ident, .Bide);

        assert(volatiles.data.attacks > 0);
        volatiles.data.attacks -= 1;
        if (volatiles.data.attacks != 0) return false;

        volatiles.Bide = false;
        try log.end(ident, .Bide);
        if (volatiles.data.bide > 0) {
            try log.fail(ident);
            return false;
        }
        // TODO unleash energy
    }
    if (volatiles.Locked) {
        assert(volatiles.data.attacks > 0);
        volatiles.data.attacks -= 1;
        // TODO PlayerMoveNum = THRASH
        if (volatiles.data.attacks == 0) {
            volatiles.Locked = false;
            volatiles.Confusion = true;
            // NOTE: these values will diverge
            volatiles.data.confusion = if (showdown) {
                battle.rng.range(3, 5);
            } else {
                (battle.rng.next() & 3) + 2;
            };
            try log.start(ident, .Confusion, true);
        }
        // TODO: skip DecrementPP, call PlayerCalcMoveDamage directly
    }
    if (volatiles.PartialTrap) {
        assert(volatiles.data.attacks > 0);
        volatiles.data.attacks -= 1;
        if (volatiles.data.attacks == 0) {
            // TODO skip DamageCalc/DecrementPP/MoveHitTest
        }
    }
    if (volatiles.Rage) {
        // TODO skip DecrementPP, go to PlayerCanExecuteMove
    }

    return true;
}

// TODO DEBUG
comptime {
    std.testing.refAllDecls(@This());
}
