const std = @import("std");
const build_options = @import("build_options");

const rng = @import("../common/rng.zig");
const Gen12 = rng.Gen12;

const data = @import("./data.zig");
const Side = data.Side;
const Choice = data.Choice;
const Result = data.Result;
const Status = data.Status;
const Move = data.Move;

const protocol = @import("./protocol.zig");

const assert = std.debug.assert;

const showdown = build_options.showdown;

// FIXME need to prompt c1 and c2 for new choices...? = should be able to tell choice from state?
pub fn update(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    _ = battle;
    _ = c1;
    _ = c2;
    _ = log;

    // Start find first alive mon and send out for both sides, if either dead then game over
    // turn = 0, p1.active = 0, p2.active = 0, positions = index
    if (battle.turn == 0) {
        var slot = findFirstAlive(battle.p2());
        // FIXME: https://www.smogon.com/forums/threads/self-ko-clause-gens-1-4.3653037/
        if (slot == 0) return if (findFirstAlive(battle.p1()) == 0) .Tie else .Win;
        switchIn(battle.p2(), slot); // TODO

        slot = findFirstAlive(battle.p1());
        if (slot == 0) return .Lose;
        switchIn(battle.p1(), slot); // TODO
    } else {}

    return .None;
}

pub fn findFirstAlive(side: *const Side) u4 {
    var i: u4 = 0;
    while (i < side.pokemon.len) : (i += 1) {
        if (side.pokemon[i].hp > 0) {
            return i + 1; // index -> slot
        }
    }
    return 0;
}

pub fn beforeMove(battle: anytype, mslot: u8, log: anytype) !bool {
    var p1 = battle.p1();
    const p2 = battle.p2();

    assert(mslot > 0 and mslot <= 4);
    assert(p1.active.moves[mslot - 1].id != .None);

    const stored = p1.pokemon[p1.active.position - 1];
    if (Status.is(stored.status, .SLP)) {
        stored.status -= 1;
        if (!Status.any(stored.status)) try log.cant(p1.active.position, .Sleep);
        return false;
    }
    if (Status.is(stored.status, .FRZ)) {
        try log.cant(p1.active.position, .Freeze);
        return false;
    }
    if (p2.active.volatiles.PartialTrap) {
        try log.cant(p1.active.position, .PartialTrap);
        return false;
    }
    if (p1.active.volatiles.Flinch) {
        p1.active.volatiles.Flinch = false;
        try log.cant(p1.active.position, .Flinch);
        return false;
    }
    if (p1.active.volatiles.Recharging) {
        p1.active.volatiles.Recharging = false;
        try log.cant(p1.active.position, .Recharging);
        return false;
    }
    if (p1.active.volatiles.data.disabled.duration > 0) {
        p1.active.volatiles.data.disabled.duration -= 1;
        if (p1.active.volatiles.data.disabled.duration == 0) {
            p1.active.volatiles.data.disabled.move = 0;
            try log.end(p1.active.position, .Disable);
        }
    }
    if (p1.active.volatiles.Confusion) {
        p1.active.volatiles.data.confusion -= 1;
        if (p1.active.volatiles.data.confusion == 0) {
            p1.active.volatiles.Confusion = false;
            try log.end(p1.active.position, .Confusion);
        } else {
            try log.activate(p1.active.position, .Confusion);
            const confused = if (showdown) {
                !battle.rng.chance(128, 256);
            } else {
                battle.rng.next() >= Gen12.percent(50) + 1;
            };
            if (confused) {
                // FIXME: implement self hit
                p1.active.volatiles.Bide = false;
                p1.active.volatiles.Locked = false;
                p1.active.volatiles.MultiHit = false;
                p1.active.volatiles.Flinch = false;
                p1.active.volatiles.Charging = false;
                p1.active.volatiles.PartialTrap = false;
                p1.active.volatiles.Invulnerable = false;
                return false;
            }
        }
    }
    if (p1.active.volatiles.data.disabled.move == mslot) {
        try log.disabled(p1.active.position, p1.active.volatiles.data.disabled.move);
        return false;
    }
    if (Status.is(stored.status, .PAR)) {
        const paralyzed = if (showdown) {
            battle.rng.chance(63, 256);
        } else {
            battle.rng.next() < Gen12.percent(25);
        };
        if (paralyzed) {
            p1.active.volatiles.Bide = false;
            p1.active.volatiles.Locked = false;
            p1.active.volatiles.Charging = false;
            p1.active.volatiles.PartialTrap = false;
            // BUG: Invulnerable is not cleared, resulting in the Fly/Dig glitch
            try log.cant(p1.active.position, .Paralysis);
            return false;
        }
    }
    if (p1.active.volatiles.Bide) {
        // TODO
    }
    if (p1.active.volatiles.Locked) {
        // TODO
        p1.active.volatiles.Confusion = true;
        // NOTE: these values will diverge
        p1.active.volatiles.data.confusion = if (showdown) {
            battle.rng.range(3, 5);
        } else {
            (battle.rng.next() & 3) + 2;
        };
    }
    if (p1.active.volatiles.PartialTrap) {
        // TODO
    }
    if (p1.active.volatiles.Rage) {
        // TODO
    }

    return true;
}

// LoadBattleMonFromParty & SendOutMon
pub fn switchIn(side: *Side, slot: u8) void {
    assert(slot != 0);
    assert(side.active.position != 0);
    assert(side.pokemon[side.active.position - 1].position == 1);
    // FIXME: assert(slot != side.active.position);

    // TODO: what about pre start - need to apply burn/paralysis

    // const active = side.get(slot);
    // side.pokemon[side.active - 1].position = active.position;
    // active.position = 1;

    // inline for (std.meta.fieldNames(Stats(u16))) |stat| {
    //     @field(side.pokemon.stats, stat) = @field(active.stats, stat);
    // }

    _ = side;

    // make slot active pokemon, clear active pokemons fields (move current active back...)

    // clear stats
    // clear disabled move/move number
    // clear minimized
    // clear player used move

    // 	call ApplyBurnAndParalysisPenaltiesToPlayer
    // QuarterSpeedDueToParalysis
    // HalveAttackDueToBurn

}

//  pub fn switchIn(self: *Side, slot: u8) void {
//     assert(slot != self.active);
//     assert(self.team[self.active - 1].position == 1);

//     const active = self.get(slot);
//     self.team[self.active - 1].position = active.position;
//     active.position = 1;

//     inline for (std.meta.fieldNames(Stats(u16))) |stat| {
//         @field(self.pokemon.stats, stat) = @field(active.stats, stat);
//     }
//     var i = 0;
//     while (i < 4) : (i += 1) {
//         self.pokemon.moves[i] = active.pokemon.moves[i];
//     }
//     self.pokemon.volatiles.zero();
//     inline for (std.meta.fieldNames(Boosts(i4))) |boost| {
//         @field(self.pokemon.boosts, boost) = @field(active.boosts, boost);
//     }
//     self.pokemon.level = active.level;
//     self.pokemon.hp = active.hp;
//     self.pokemon.status = active.status;
//     self.pokemon.types = active.types;
//     self.active = slot;
// }

// TODO DEBUG
comptime {
    std.testing.refAllDecls(@This());
}
