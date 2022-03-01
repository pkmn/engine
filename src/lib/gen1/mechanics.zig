const std = @import("std");
const build_options = @import("build_options");

const data = @import("./data.zig");
const Side = data.Side;
const Choice = data.Choice;
const Result = data.Result;
const Status = data.Status;

const protocol = @import("./protocol.zig");

const assert = std.debug.assert;

pub fn start(battle: anytype, c1: Choice, c2: Choice) Result {
    _ = battle;
    _ = c1;
    _ = c2;

    if (battle.turn == 0) {} else {}

    // find first alive mon and send out for both sides, if either dead then game over
    return .None;
}

pub fn execute(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    _ = battle;
    _ = c1;
    _ = c2;
    _ = log;

    // Start
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

pub fn findFirstAlive(side: *const Side) u8 {
    var i: u8 = 0;
    while (i < side.team.len) : (i += 1) {
        if (side.team[i].hp > 0) {
            return i + 1; // index -> slot
        }
    }
    return 0;
}

pub fn beforeMove(p1: *Side, p2: *const Side, log: anytype) !bool {
    if (Status.is(p1.pokemon.status, .SLP)) {
        p1.pokemon.status -= 1;
        if (!Status.any(p1.pokemon.status)) try log.cant(p1.active, .Sleep);
        return false;
    } else if (Status.is(p1.pokemon.status, .FRZ)) {
        try log.cant(p1.active, .Freeze);
        return false;
    } else if (p2.pokemon.volatiles.PartialTrap) {
        try log.cant(p1.active, .PartialTrap);
        return false;
    } else if (p1.pokemon.volatiles.Flinch) {
        p1.pokemon.volatiles.Flinch = false;
        try log.cant(p1.active, .Flinch);
        return false;
    } else if (p1.pokemon.volatiles.Recharging) {
        p1.pokemon.volatiles.Recharging = false;
        try log.cant(p1.active, .Recharging);
        return false;
        // FIXME: disabled
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
