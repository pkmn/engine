const std = @import("std");
const build_options = @import("build_options");

const rng = @import("../common/rng.zig");

const data = @import("./data.zig");
const Side = data.Side;
const Choice = data.Choice;
const Result = data.Result;
const Status = data.Status;
const Move = data.Move;

const protocol = @import("./protocol.zig");

const assert = std.debug.assert;

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
    while (i < side.team.len) : (i += 1) {
        if (side.team[i].hp > 0) {
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

    if (Status.is(p1.pokemon.status, .SLP)) {
        p1.pokemon.status -= 1;
        if (!Status.any(p1.pokemon.status)) try log.cant(p1.active, .Sleep);
        return false;
    }
    if (Status.is(p1.pokemon.status, .FRZ)) {
        try log.cant(p1.active, .Freeze);
        return false;
    }
    if (p2.pokemon.volatiles.PartialTrap) {
        try log.cant(p1.active, .PartialTrap);
        return false;
    }
    if (p1.pokemon.volatiles.Flinch) {
        p1.pokemon.volatiles.Flinch = false;
        try log.cant(p1.active, .Flinch);
        return false;
    }
    if (p1.pokemon.volatiles.Recharging) {
        p1.pokemon.volatiles.Recharging = false;
        try log.cant(p1.active, .Recharging);
        return false;
    }
    if (p1.pokemon.volatiles.data.disabled.duration > 0) {
        p1.pokemon.volatiles.data.disabled.duration -= 1;
        if (p1.pokemon.volatiles.data.disabled.duration == 0) {
            p1.pokemon.volatiles.data.disabled.move = 0;
            try log.end(p1.active, .Disable);
        }
    }
    if (p1.pokemon.volatiles.Confusion) {
        p1.pokemon.volatiles.data.confusion -= 1;
        if (p1.pokemon.volatiles.data.confusion == 0) {
            p1.pokemon.volatiles.Confusion = false;
            try log.end(p1.active, .Confusion);
        } else {
            try log.activate(p1.active, .Confusion);
            // FIXME implement random 50%
            if (false) {
                p1.pokemon.volatiles.Bide = false;
                p1.pokemon.volatiles.Locked = false;
                p1.pokemon.volatiles.MultiHit = false;
                p1.pokemon.volatiles.Flinch = false;
                p1.pokemon.volatiles.Charging = false;
                p1.pokemon.volatiles.PartialTrap = false;
                p1.pokemon.volatiles.Invulnerable = false;
                return false;
            }
        }
    }
    if (p1.pokemon.volatiles.data.disabled.move == mslot) {
        try log.disabled(p1.active, p1.pokemon.volatiles.data.disabled.move);
        return false;
    }
    if (Status.is(p1.pokemon.status, .PAR)) {
        // FIXME: implement random 25%
        if (false) {
            p1.pokemon.volatiles.Bide = false;
            p1.pokemon.volatiles.Locked = false;
            p1.pokemon.volatiles.Charging = false;
            p1.pokemon.volatiles.PartialTrap = false;
            // BUG: Invulnerable is not cleared, resulting in the Fly/Dig glitch
            try log.cant(p1.active, .Paralysis);
            return false;
        }
    }
    if (p1.pokemon.volatiles.Bide) {
        // TODO
    }
    if (p1.pokemon.volatiles.Locked) {
        // TODO
    }
    if (p1.pokemon.volatiles.PartialTrap) {
        // TODO
    }
    if (p1.pokemon.volatiles.Rage) {
        // TODO
    }

    return true;
}

// LoadBattleMonFromParty & SendOutMon
pub fn switchIn(side: *const Side, slot: u8) void {
    assert(slot != 0);
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
