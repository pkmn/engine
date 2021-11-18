//! Fundamental Pokémon data types required for battle simulation.
//! Data not strictly required for battles is elided at this layer.
//! **NOTE**: code in `data/` is generated and re-exported below.

const std = @import("std");
const util = @import("../common/util.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const types = @import("data/types.zig");
const moves = @import("data/moves.zig");
const species = @import("data/species.zig");

const bit = util.bit;

/// The name of each stat (cf. Pokémon Showdown's `StatName`).
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L5-L12
///
pub const Stat = enum(u3) {
    hp,
    atk,
    def,
    spe,
    spc,
};

test "State" {
    try expectEqual(3, @bitSizeOf(Stat));
}

/// A structure for storing information for each `Stat` (cf. Pokémon Showdown's `StatTable`).
pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,
    };
}

test "Stats" {
    try expectEqual(5 * 8, @bitSizeOf(Stats(u8)));
    const stats = Stats(u4){ .atk = 2, .spe = 3 };
    try expectEqual(2, stats.atk);
    try expectEqual(0, stats.def);
}

/// The name of each boost/mod (cf. Pokémon Showdown's `BoostName`).
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L14-L23
///
pub const Boost = enum(u3) {
    atk,
    def,
    spe,
    spc,
    accuracy,
    evasion,

    comptime {
        assert(@bitSizeOf(Boost) == 3);
    }
};

/// A structure for storing information for each `Boost` (cf. Pokémon Showdown's `BoostTable`).
/// **NOTE**: `Boost(i4)` should likely always be used, as boosts should always range from -6...6.
pub fn Boosts(comptime T: type) type {
    return packed struct {
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,
        accuracy: T = 0,
        evasion: T = 0,
    };
}

test "Boosts" {
    try expectEqual(3 * 8, @bitSizeOf(Boosts(i4)));
    const boosts = Boosts(i4){ .spc = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spc);
}

pub const Moves = moves.Moves;

/// *See:* https://pkmn.cc/pokered/data/moves/moves.asm
pub const Move = packed struct {
    bp: u8,
    accuracy: u8,
    type: Type,
    pp: u4, // = pp / 5

    comptime {
        assert(@bitSizeOf(Move) == 3 * 8);
    }
};

test "Moves" {
    try expectEqual(2, @enumToInt(Moves.KarateChop));
    const move = Moves.get(.Pound);
    try expectEqual(@as(u8, 35 / 5), move.pp);
}

pub const Species = species.Species;

/// *See:* https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_I%29
pub const Specie = packed struct {
    types: Types,
    stats: Stats(u8),

    comptime {
        assert(@bitSizeOf(Specie) == 6 * 8);
    }
};

test "Species" {
    try expectEqual(2, @enumToInt(Species.Ivysaur));
    try expectEqual(@as(u8, 100), Species.get(.Mew).stats.def);
}

pub const Type = types.Type;
pub const Types = types.Types;
pub const Efffectiveness = types.Efffectiveness;

test "Types" {
    try expectEqual(14, @enumToInt(Type.Dragon));
    try expectEqual(20, @enumToInt(Efffectiveness.Super));
    try expectEqual(Efffectiveness.Immune, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Efffectiveness.Super, Type.effectiveness(.Water, .Fire));
    try expectEqual(Efffectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Efffectiveness.Neutral, Type.effectiveness(.Normal, .Grass));
}

/// A data-type for a `(move, pp)` pair. A pared down version of Pokémon Showdown's
/// `Pokemon#moveSlot`, it also stores data from the cartridge's `battle_struct::Move`
/// macro and can be used to replace the `w{Player,Enemy}Move*` data. Move PP is stored
/// in the same way as on the cartridge (`battle_struct::PP`), with 6 bits for current
/// PP and the remaining 2 bits used to store the number of applied PP Ups. TODO
const MoveSlot = packed struct {
    id: Moves = .None,
    pp: u4 = 0,
    pp_ups: u4 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
    }

    pub fn init(id: Moves) MoveSlot {
        if (id == .None) return MoveSlot{};
        const move = Moves.get(id);
        return MoveSlot{
            .id = id,
            .pp = move.pp,
            .pp_ups = 3,
        };
    }

    // `AddBonusPP`: https://pkmn.cc/pokered/engine/items/item_effects.asm
    pub fn maxpp(self: *const MoveSlot) u8 {
        const pp = Moves.get(self.id).pp;
        return self.pp_ups * @as(u8, @maximum(pp, 7)) + (@as(u8, pp) * 5);
    }
};

test "MoveSlot" {
    const ms = MoveSlot.init(.Pound);
    try expectEqual(@as(u6, 35 / 5), ms.pp);
    try expectEqual(@as(u8, 56), ms.maxpp());
    try expectEqual(Moves.Pound, ms.id);
    try expectEqual(@as(u16, 0), @bitCast(u16, MoveSlot.init(.None)));
}

/// Bitfield respresentation of a Pokémon's DVs, stored as a 16-bit integer like on cartridge
/// with the HP DV being computered by taking the least-signficant bit of each of the other DVs.
const DVs = packed struct {
    atk: u4 = 15,
    def: u4 = 15,
    spe: u4 = 15,
    spc: u4 = 15,

    comptime {
        assert(@sizeOf(DVs) == @sizeOf(u16));
    }

    pub fn hp(self: *const DVs) u4 {
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

/// Bitfield representation of a Pokémon's major status condition, mirroring how it is stored on
/// the cartridge. A value of `0x00` means that the Pokémon is not affected by any major status,
/// otherwise the lower 3 bits represent the remaining duration for SLP. Other status are denoted
/// by the presence of individual bits - at most one status should be set at any given time.
///
/// **NOTE:** in Generation 1, the "badly poisoned" status (TOX) is volatile and gets dropped
/// upon switching out - see `Volatiles` below.
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L60-L65
///
const Status = enum(u8) {
    SLP = 0b111,
    PSN = 3,
    BRN = 4,
    FRZ = 5,
    PAR = 6,

    pub fn is(num: u8, status: Status) bool {
        if (status == .SLP) return Status.duration(num) > 0;
        return bit.isSet(u8, num, @intCast(u3, @enumToInt(status)));
    }

    pub fn init(status: Status) u8 {
        assert(status != .SLP);
        return bit.set(u8, 0, @intCast(u3, @enumToInt(status)));
    }

    pub fn sleep(dur: u3) u8 {
        assert(dur > 0);
        return @as(u8, dur);
    }

    pub fn duration(num: u8) u3 {
        return @intCast(u3, num & @enumToInt(Status.SLP));
    }
};

test "Status" {
    try expect(!Status.is(0, .SLP));
    try expect(Status.is(Status.sleep(5), .SLP));
    try expect(!Status.is(Status.sleep(7), .PSN));
    try expectEqual(@as(u3, 5), Status.duration(Status.sleep(5)));
    try expect(Status.is(Status.init(.PSN), .PSN));
    try expect(!Status.is(Status.init(.PSN), .PAR));
    try expect(Status.is(Status.init(.BRN), .BRN));
    try expect(!Status.is(Status.init(.FRZ), .SLP));
    try expect(Status.is(Status.init(.FRZ), .FRZ));
}

/// The core representation of a Pokémon in a battle. Comparable to Pokémon Showdown's `Pokemon`
/// type, this struct stores the data stored in the cartridge's `battle_struct` information stored
/// in `w{Battle,Enemy}Mon` as well as parts of the `party_struct` in the `stored` field. The fields
/// map to the following types:
///
///   - in most places the data representation defaults to the same as the cartridge, with the
///     notable exception that `boosts` range from `-6...6` like in Pokémon Showdown instead of
///     `1..13`
///   - nicknames are not handled within the engine and are expected to instead be managed by
///     whatever is driving the engine code
///
/// **References:**
///
///  - https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_I%29
///  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK1.cs
///  - https://pkmn.cc/pokered/macros/wram.asm
///
const Pokemon = packed struct {
    stored: packed struct {
        level: u8,
        stats: Stats(u16),
        moves: [4]MoveSlot,
        dvs: DVs,
    },
    stats: Stats(u16),
    moves: [4]MoveSlot,
    volatiles_data: packed struct {
        bide: u16,
        substitute: u8,
        confusion: u4,
        toxic: u4,
        multihit: packed struct {
            hits: u4,
            left: u4,
        },
    },
    volatiles: Volatile,
    boosts: Boosts(i4),
    hp: u16,
    status: Status,
    species: Species,
    types: Types,
    disabled: packed struct {
        move: u4,
        duration: u4,
    },
    _pad: u64,

    comptime {
        assert(@bitSizeOf(Pokemon) == 64 * 8);
    }

     pub fn level(self: *const Pokemon) u8 {
        return self.stored.level;
    }
};

/// Bitfield for the various non-major statuses that Pokémon can have, commonly
/// known as 'volatile' statuses as they disappear upon switching out. In pret/pokered
/// these are referred to as 'battle status' bits.
///
/// **NOTE:** all of the bits are packed into an 18 byte bitfield which uses up 3 bytes
/// after taking into consideration alignment. This is the same as on cartridge, though
/// there the bits are split over three distinct bytes (`w{Player,Enemy}BattleStatus{1,2,3}`).
/// We dont attempt to match the same bit locations, and `USING_X_ACCURACY` is dropped as
/// in-battle item-use is not supported in link battles.
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L73
///
const Volatile = packed struct {
    Bide: bool = false,
    Locked: bool = false,
    MultiHit: bool = false,
    Flinch: bool = false,
    Charging: bool = false,
    PartialTrap: bool = false,
    Invulnerable: bool = false,
    Confusion: bool = false,
    Mist: bool = false,
    FocusEnergy: bool = false,
    Substitute: bool = false,
    Recharging: bool = false,
    Rage: bool = false,
    LeechSeed: bool = false,
    Toxic: bool = false,
    LightScreen: bool = false,
    Reflect: bool = false,
    Transform: bool,
    _pad: u6 = 0,

    comptime {
        assert(@bitSizeOf(Volatile) == 24);
    }
};

// TODO
// wPlayerMonNumber (pret) & Side#active[0] (PS)
// wInHandlePlayerMonFainted (pret) & Side#faintedThisTurn (PS)
// w{Player,Enemy}UsedMove (pret) & Side#lastMove (PS)
// w{Player,Enemy}SelectedMove (pret) & Side#lastSelectedMove (PS)
const Side = packed struct {
    pokemon: [6]Pokemon,

    active: u4,
    fainted_last_turn: u4,

    last_used_move: Moves,
    last_selected_move: Moves,

    // pub fn get(self: *Side, pokemon: u4) *Pokemon {
    //     assert(pokemon >= 1 and pokemon <= 7);
    //     return self.pokemon[pokemon - 1];
    // }

    comptime {
        assert(@bitSizeOf(Side) == 387 * 8);
    }
};


// // TODO
const Battle = packed struct {
    seed: u8,
    turn: u8,
    sides: [2]Side,

    comptime {
        assert(@bitSizeOf(Battle) == 776 * 8);
    }

    pub fn p1(self: *Battle) *Side {
        return &self.sides[0];
    }

    pub fn p2(self: *Battle) *Side {
        return &self.sides[1];
    }
};

// TODO
comptime {
    std.testing.refAllDecls(@This());
}