// References:
//  - https://pkmn.cc/bulba/Pokémon_data_structure_(Generation_I)
//  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK1.cs
//  - https://pkmn.cc/pokered/macros/wram.asm

const std = @import("std");
const data = @import("./data.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;

const Stat = data.Stat;
const Stats = data.Stats;
const Boosts = data.Boosts;
const Moves = data.Moves;
const Species = data.Species;
const Type = data.Type;

// battle_struct::Moves (pret) & Pokemon#moveSlot (PS)
const MoveSlot = packed struct {
    id_: u8 = 0, // w{Player,Enemy}Move* (pret)
    pp: u6 = 0, // battle_struct::PP (pret)
    pp_ups: u2 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
    }

    pub fn init(mid: Moves) MoveSlot {
        if (mid == Moves.None) return MoveSlot{};
        const move = Moves.get(mid);
        return MoveSlot{
            .id_ = @enumToInt(move.id),
            .pp = move.pp,
            .pp_ups = 3,
        };
    }

    pub inline fn id(self: *const MoveSlot) Moves {
        return @intToEnum(Moves, self.id_);
    }

    // https://pkmn.cc/pokered/engine/items/item_effects.asm AddBonusPP
    pub inline fn maxpp(self: *const MoveSlot) u8 {
        const pp = Moves.get(self.id()).pp;
        return self.pp_ups * @maximum(pp / 5, 7) + pp;
    }
};

test "MoveSlot" {
    const ms = MoveSlot.init(Moves.Pound);
    try expectEqual(@as(u6, 35), ms.pp);
    try expectEqual(@as(u8, 56), ms.maxpp());
    try expectEqual(Moves.Pound, ms.id());
    try expectEqual(@as(u16, 0), @bitCast(u16, MoveSlot.init(Moves.None)));
}

const DVs = packed struct {
    atk: u4 = 15,
    def: u4 = 15,
    spe: u4 = 15,
    spc: u4 = 15,

    comptime {
        assert(@sizeOf(DVs) == @sizeOf(u16));
    }

    pub inline fn hp(self: *const DVs) u4 {
        return (self.atk & 1) << 3 | (self.def & 1) << 2 | (self.spe & 1) << 1 | (self.spc & 1);
    }
};

test "DVs" {
    var dvs = DVs{ .spc = 15, .spe = 15 };
    try expectEqual(@as(u4, 15), dvs.hp());
    dvs = DVs{
        .atk = 5,
        .def = 15,
        .spe = 13,
        .spc = 13,
    };
    try expectEqual(@as(u4, 15), dvs.hp());
    dvs = DVs{
        .def = 3,
        .spe = 10,
        .spc = 11,
    };
    try expectEqual(@as(u4, 13), dvs.hp());
}

const NICKNAME_LENGTH = 18; // NAME_LEN = 11 (pret) & Pokemon#getName = 18 (PS)

const Status = enum(u8) {
    SLP = 0b111,
    PSN = 3,
    BRN = 4,
    FRZ = 5,
    PAR = 6,

    pub inline fn slp(status: u8) bool {
        return Status.duration(status) > 0;
    }

    pub inline fn psn(status: u8) bool {
        return status & (1 << @enumToInt(Status.PSN)) > 0;
    }

    pub inline fn brn(status: u8) bool {
        return status & (1 << @enumToInt(Status.BRN)) > 0;
    }

    pub inline fn frz(status: u8) bool {
        return status & (1 << @enumToInt(Status.FRZ)) > 0;
    }

    pub inline fn par(status: u8) bool {
        return status & (1 << @enumToInt(Status.PAR)) > 0;
    }

    pub inline fn init(status: Status) u8 {
        return @as(u8, 1) << @intCast(u3, @enumToInt(status));
    }

    pub inline fn sleep(dur: u3) u8 {
        assert(dur > 0);
        return @as(u8, dur);
    }

    pub inline fn duration(status: u8) u3 {
        return @intCast(u3, status & @enumToInt(Status.SLP));
    }
};

test "Status" {
    try expect(!Status.slp(0));
    try expect(Status.slp(Status.sleep(5)));
    try expectEqual(@as(u3, 5), Status.duration(Status.sleep(5)));
    try expect(Status.psn(Status.init(Status.PSN)));
    try expect(!Status.par(Status.init(Status.PSN)));
    try expect(Status.brn(Status.init(Status.BRN)));
    try expect(!Status.slp(Status.init(Status.FRZ)));
    try expect(Status.frz(Status.init(Status.FRZ)));
}

// w{Battle,Enemy}Mon battle_struct (pret) & Pokemon (PS)
const Pokemon = struct {
    // TODO: disable nicknames = always just the species (can implement at higher layer)?
    // name: *const [NICKNAME_LENGTH:0]u8, // w{Battle,Enemy}MonNick (pret) & Pokemon#name (PS)
    species: Species,
    types: [2]Type,
    stored: struct {
        level: u8, // w{Player,Enemy}MonUnmodifiedLevel / battle_struct::Level (pret) && Pokemon#level (PS)
        stats: Stats(u16), // w{Player,Enemy}MonUnmodified* (pret) & Pokemon#storedStats (PS)
        moves: [4]MoveSlot, // Pokemon#baseMoveSlots (PS)
        dvs: DVs,
        evs: Stats(u16), // TODO
    },
    stats: Stats(u16),
    // // w{Player,Enemy}Mon*Mod (pret) & Pokemon#boosts (PS)
    boosts: Boosts(i4), // -6 <-> 6 (NOTE: pret = 1 <-> 13)
    hp: u16,
    status: Status, // Status
    volatiles: Volatile, // w{Player,Enemy}BattleStatus* (pret) & Pokemon#volatiles (PS)
    volatiles_data: struct {
        bide: u16, // w{Player,Enemy}BideAccumulatedDamage (pret) & volatiles.bide.totalDamage (PS)
        confusion: u8, // w{Player,Enemy}ConfusedCounter (pret) & volatiles.confusion.duration (PS)
        toxic: u8, // w{Player,Enemy}ToxicCounter (pret) & volatiles.residualdmg.counter (PS)
        substitute: u8, // w{Player,Enemy}SubstituteHP (pret) & volatiles.substitute.hp (PS)
        multihit: packed struct {
            hits: u4, // w{Player,Enemy}NumHits (pret)
            left: u4, // w{Player,Enemy}NumAttacksLeft (pret)
        },
    },
    moves: [4]MoveSlot,
    // w{Player,Enemy}DisabledMove (pret) & MoveSlot#disabled
    disabled: packed struct {
        move: u4,
        duration: u4,
    },

    pub inline fn level(self: *const Pokemon) u8 {
        return self.stored.level;
    }

    // TODO pub fn dv(self: *Pokemon, stat: Stat) u4 {}
};

test "Pokemon" {
    try expectEqual(70, @sizeOf(Pokemon));
    try expectEqual(72, @sizeOf(?Pokemon));
}

// https://pkmn.cc/pokered/constants/battle_constants.asm#L73
const Volatile = packed struct {
    Bide: bool, //  STORING_ENERGY (pret) & bide (PS)
    Locked: bool, //  TRASHING_ABOUT           / lockedmove
    MultiHit: bool, //  ATTACKING_MULTIPLE_TIMES / Move#multihit
    Flinch: bool, //  FLINCHED                 / flinched
    Charging: bool, //  CHARGING_UP              / twoturnmove
    PartialTrap: bool, //  USING_TRAPPING_MOVE      / partiallytrapped & partialtrappinglock
    Invulnerable: bool, //  INVULNERABLE             / Move#onLockMove
    Confusion: bool, //  CONFUSED                 / confusion
    Mist: bool, //  PROTECTED_BY_MIST        / mist
    FocusEnergy: bool, //  GETTING_PUMPED           / focusenergy
    Substitute: bool, //  HAS_SUBSTITUTE_UP        / substitute
    Recharging: bool, //  NEEDS_TO_RECHARGE        / mustrecharge & recharege
    Rage: bool, //  USING_RAGE               / rage
    LeechSeed: bool, //  SEEDED                   / leechseed
    Toxic: bool, //  BADLY_POISONED           / toxic
    LightScreen: bool, //  HAS_LIGHT_SCREEN_UP      / lightscreen
    Reflect: bool, //  HAS_REFLECT_UP           / reflect
    Transform: bool, //  TRANSFORMED              / transform

    comptime {
        assert(@bitSizeOf(Volatile) == 18);
        assert(@sizeOf(Volatile) == 3);
    }
};

// FIXME ???
// wPlayerMonNumber: u8 ; index in party of currently battling mon
// wMoveDidntMiss / wMoveMissed: u8
// wBattleMonSpecies2 / wEnemyMonSpecies2: u8  ???
// wPlayerMoveListIndex / wEnemyMoveListIndex: u8

