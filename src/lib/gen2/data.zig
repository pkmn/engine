//! Fundamental Pokémon data types required for battle simulation.
//! Data not strictly required for battles is elided at this layer.
//! **NOTE**: code in `data/` is generated and re-exported below.

const std = @import("std");

const gen1 = @import("../gen1/data.zig");

const items = @import("data/items.zig");
const moves = @import("data/moves.zig");
const species = @import("data/species.zig");
const types = @import("data/types.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;


/// The name of each stat (cf. Pokémon Showdown's `StatName`).
///
/// *See:* https://pkmn.cc/pokecrystal/constants/battle_constants.asm#L54-L67
///
pub const Stat = enum(u3) {
    hp,
    atk,
    def,
    spe,
    spa,
    spd,

    comptime {
        assert(@bitSizeOf(Stat) == 3);
    }
};

/// A structure for storing information for each `Stat` (cf. Pokémon Showdown's `StatTable`).
pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spa: T = 0,
        spd: T = 0,
    };
}

test "Stats" {
    try expectEqual(6 * 8, @bitSizeOf(Stats(u8)));
    const stats = Stats(u4){ .spd = 2, .spe = 3 };
    try expectEqual(2, stats.spd);
    try expectEqual(0, stats.def);
}


/// The name of each boost/mod (cf. Pokémon Showdown's `BoostName`).
///
/// *See:* https://pkmn.cc/pokecrystal/constants/battle_constants.asm#L30-L39
///
pub const Boost = enum(u3) {
    atk,
    def,
    spe,
    spa,
    spd,
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
        spa: T = 0,
        spd: T = 0,
        accuracy: T = 0,
        evasion: T = 0,
    };
}

test "Boosts" {
    try expectEqual(3 * 8 + 4,  @bitSizeOf(Boosts(i4)));
    const boosts = Boosts(i4){ .spd = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spd);
}

// TODO
pub const IVs = packed struct {
    hp: u5 = 31,
    atk: u5 = 31,
    def: u5 = 31,
    spe: u5 = 31,
    spa: u5 = 31,
    spd: u5 = 31,
    _pad: 2 = 0,

    comptime {
        assert(@bitSizeOf(DVs) == 4 * 8);
    }
};

/// *See:* https://pkmn.cc/pokecrystal/data/moves/moves.asm
pub const Moves = moves.Moves;
pub const Move = packed struct {
    bp: u8,
    accuracy: u8,
    type: Type,
    pp: u4, // pp / 5
    chance: u4, // chance / 10

    comptime {
        assert(@bitSizeOf(Move) == 4 * 8);
    }
};

test "Moves" {
    try expectEqual(240, @enumToInt(Moves.BeatUp));
    const move = Moves.get(.LockOn);
    try expectEqual(@as(u8, 5), move.pp);
}

/// *See:* https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_II%29
pub const Species = species.Species;
pub const Specie = packed struct {
    types: Types,
    stats: Stats(u8),

    comptime {
        assert(@bitSizeOf(Specie) == 8 * 8);
    }
};

test "Species" {
    try expectEqual(152, @enumToInt(Species.Chikorita));
    try expectEqual(@as(u8, 100), Species.get(.Celebi).stats.def);
}

pub const Type = types.Type;
pub const Types = types.Types;
pub const Efffectiveness = gen1.Efffectiveness;

test "Types" {
    try expectEqual(14, @enumToInt(Type.Electric));
    try expectEqual(20, @enumToInt(Efffectiveness.Super));
    try expectEqual(Efffectiveness.Super, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Efffectiveness.Super, Type.effectiveness(.Water, .Fire));
    try expectEqual(Efffectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Efffectiveness.Neutral, Type.effectiveness(.Normal, .Grass));
    try expectEqual(Efffectiveness.Immune, Type.effectiveness(.Poison, .Steel));
}



///  - https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_II%29
///  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK2.cs
///  - https://pkmn.cc/pokecrystal/macros/wram.asm
///
const Pokemon = packed struct {
    // TODO item Items
    // TODO extra 2*Stats+1 Boosts byte = 24
    // TODO happiness u8
    // TODO volatile size change + 8
    // = total 48, 16 padding left

// NOTE: could move volatiles_data to Side... lots of space?

// TODO: some of these could be u3/u4
// wPlayerRolloutCount:: db
// wPlayerConfuseCount:: db
// wPlayerToxicCount:: db
// wPlayerDisableCount:: db
// wPlayerEncoreCount:: db
// wPlayerPerishCount:: db
// wPlayerFuryCutterCount:: db
// wPlayerProtectCount:: db
// wPlayerFutureSightCount:: db
// wPlayerRageCounter:: db
// wPlayerWrapCount:: db
// wPlayerCharging:: db
// wPlayerJustGotFrozen:: db
};

const Volatile = packed struct {
    Nightmare: bool = false,
    Cure: bool = false,
    Protect: bool = false,
    Identified: bool = false,
    PerishSong: bool = false,
    Endure: bool = false,
    Rollout: bool = false,
    Attract: bool = false,
    DefenseCurl: bool = false,
    Bide: bool = false,
    Rampage: bool = false,
    InLoop: bool = false,
    Flinch: bool = false,
    Charging: bool = false,
    Underground: bool = false,
    Flying: bool = false,
    Confusion: bool = false,
    Mist: bool = false,
    FocusEnergy: bool = false,
    Substitute: bool = false,
    Recharging: bool = false,
    Rage: bool = false,
    LeechSeed: bool = false,
    Toxic: bool = false,
    Transform: bool = false,
    Encore: bool = false,
    LockOn: bool = false,
    DestinyBond: bool = false,
    Trapped: bool = false,
    _pad: u3 = 0,

    comptime {
        assert(@bitSizeOf(Volatile) == 32);
    }
};

const Side = packed struct {

    condition: SideCondition,
    // wPlayerDamageTaken:: dw
    // wPlayerTurnsTaken:: db???
    // wLastPlayerCounterMove

// wPlayerSafeguardCount:: db
// wPlayerLightScreenCount:: db
// wPlayerReflectCount:: db
// wPlayerIsSwitching:: db
};

const Battle = packed struct {
    // weather
    // weather duration

// wWhichMonFaintedFirst:: db
};
const SideCondition = packed struct {
    Spikes: bool = false,
    Safeguard: bool = false,
    LightScreen: bool = false,
    Reflect: bool = false,
};

const Weather = enum(u2) {
    None,
    Rain,
    Sun,
    Sandstorm,
};