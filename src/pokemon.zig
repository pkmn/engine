const std = @import("std");
const data = @import("./data.zig");
const util = @import("./util.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;

const Stat = data.Stat;
const Stats = data.Stats;
const Boosts = data.Boosts;
const Moves = data.Moves;
const Species = data.Species;
const Type = data.Type;

const bit = util.bit;

/// A data-type for a `(move, pp)` pair. A pared down version of Pokémon Showdown's
/// `Pokemon#moveSlot`, it also stores data from the cartridge's `battle_struct::Move`
/// macro and can be used to replace the `w{Player,Enemy}Move*` data. Move PP is stored
/// in the same way as on the cartridge (`battle_struct::PP`), with 6 bits for current
/// PP and the remaining 2 bits used to store the number of applied PP Ups.
const MoveSlot = packed struct {
    id_: u8 = 0,
    pp: u6 = 0,
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

    // `AddBonusPP`: https://pkmn.cc/pokered/engine/items/item_effects.asm
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

    pub inline fn is(num: u8, status: Status) bool {
        if (status == Status.SLP) return Status.duration(num) > 0;
        return bit.isSet(u8, num, @intCast(u3, @enumToInt(status)));
    }

    pub inline fn init(status: Status) u8 {
        assert(status != Status.SLP);
        return bit.set(u8, 0, @intCast(u3, @enumToInt(status)));
    }

    pub inline fn sleep(dur: u3) u8 {
        assert(dur > 0);
        return @as(u8, dur);
    }

    pub inline fn duration(num: u8) u3 {
        return @intCast(u3, num & @enumToInt(Status.SLP));
    }
};

test "Status" {
    try expect(!Status.is(0, Status.SLP));
    try expect(Status.is(Status.sleep(5), Status.SLP));
    try expect(!Status.is(Status.sleep(7), Status.PSN));
    try expectEqual(@as(u3, 5), Status.duration(Status.sleep(5)));
    try expect(Status.is(Status.init(Status.PSN), Status.PSN));
    try expect(!Status.is(Status.init(Status.PSN), Status.PAR));
    try expect(Status.is(Status.init(Status.BRN), Status.BRN));
    try expect(!Status.is(Status.init(Status.FRZ), Status.SLP));
    try expect(Status.is(Status.init(Status.FRZ), Status.FRZ));
}

/// The core representation of a Pokémon in a battle. Comparable to Pokémon Showdown's `Pokemon`
/// type, this struct stores the data stored in the cartridge's `battle_struct` information stored
/// in `w{Battle,Enemy}Mon` as well as parts of the `party_struct` in the `stored` field. The fields
/// map to the following types:
///
/// | pkmn                            | Pokémon Red                            | Pokémon Showdown                |
/// |---------------------------------|----------------------------------------|---------------------------------|
/// |                                 | `w{Battle,Enemy}MonNick`               | `Pokemon#name`                  |
/// | `stored.level`                  | `w{Player,Enemy}MonUnmodifiedLevel`    | `Pokemon#level`                 |
/// | `stored.stats`                  | `w{Player,Enemy}MonUnmodified*`        | `Pokemon#storedStats`           |
/// | `stored.moves`                  |                                        | `Pokemon#baseMoveSlots`         |
/// | `stored.dvs`                    |                                        |                                 |
/// | `stored.evs`                    |                                        |                                 |
/// | `boosts`                        | `w{Player,Enemy}Mon*Mod`               | `Pokemon#boosts`                |
/// | `volatiles`                     | `w{Player,Enemy}BattleStatus{1,2,3}`   | `Pokemon#volatiles`             |
/// | `volatiles_data.bide`           | `w{Player,Enemy}BideAccumulatedDamage` | `volatiles.bide.totalDamage`    |
/// | `volatiles_data.confusion`      | `w{Player,Enemy}ConfusedCounter`       | `volatiles.confusion.duration`  |
/// | `volatiles_data.toxic`          | `w{Player,Enemy}ToxicCounter`          | `volatiles.residualdmg.counter` |
/// | `volatiles_data.substitute`     | `w{Player,Enemy}SubstituteHP`          | `volatiles.substitute.hp`       |
/// | `volatiles_data.multihit.hits`  | `w{Player,Enemy}NumHits`               |                                 |
/// | `volatiles_data.multihits.left` | `w{Player,Enemy}NumAttacksLeft`        |                                 |
/// | `disabled`                      | `w{Player,Enemy}DisabledMove`          | `MoveSlot#disabled`             |
///
///   - in most places the data representation defaults to the same as the cartridge, with the
///     notable exception that `boosts` range from `-6...6` like in Pokémon Showdown instead of
///     `1..13`
///   - nicknames are not handled within the engine and are expected to instead be managed by
///     whatever is driving the engine code
///
/// **References:**
///
///  - https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_(Generation_I)
///  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK1.cs
///  - https://pkmn.cc/pokered/macros/wram.asm
///
const Pokemon = struct {
    species: Species,
    types: [2]Type,
    stored: struct {
        level: u8,
        stats: Stats(u16),
        moves: [4]MoveSlot,
        dvs: DVs,
        evs: Stats(u16),
    },
    stats: Stats(u16),
    boosts: Boosts(i4),
    hp: u16,
    status: Status,
    volatiles: Volatile,
    volatiles_data: struct {
        bide: u16,
        confusion: u8,
        toxic: u8,
        substitute: u8,
        multihit: packed struct {
            hits: u4,
            left: u4,
        },
    },
    moves: [4]MoveSlot,
    disabled: packed struct {
        move: u4,
        duration: u4,
    },
    // FIXME: `wMove{Missed,DidntMiss}` ???

    pub inline fn level(self: *const Pokemon) u8 {
        return self.stored.level;
    }
};

test "Pokemon" {
    // NOTE: if `Pokemon` were `packed` it would be 68 bytes, but is more due to alignment
    try expectEqual(70, @sizeOf(Pokemon));
    try expectEqual(72, @sizeOf(?Pokemon));
}

/// Bitfield for the various non-major statuses that Pokémon can have, commonly
/// known as 'volatile' statuses as they disappear upon switching out. In pret/pokered
/// these are referred to as 'battle status' bits.
///
/// | Pokémon Red                | Pokémon Showdown   |
/// |----------------------------|--------------------|
/// | `STORING_ENERGY`           | `bide`             |
/// | `TRASHING_ABOUT`           | `lockedmove`       |
/// | `ATTACKING_MULTIPLE_TIMES` | `Move#multihit`    |
/// | `FLINCHED`                 | `flinch`           |
/// | `CHARGING_UP`              | `twoturnmove`      |
/// | `USING_TRAPPING_MOVE`      | `partiallytrapped` |
/// | `INVULNERABLE`             | `Move#onLockMove`  |
/// | `CONFUSED`                 | `confusion`        |
/// | `PROTECTED_BY_MIST`        | `mist`             |
/// | `GETTING_PUMPED`           | `focusenergy`      |
/// | `HAS_SUBSTITUTE_UP`        | `substitute`       |
/// | `NEEDS_TO_RECHARGE`        | `mustrecharge`     |
/// | `USING_RAGE`               | `rage`             |
/// | `SEEDED`                   | `leechseed`        |
/// | `BADLY_POISONED`           | `toxic`            |
/// | `HAS_LIGHT_SCREEN_UP`      | `lightscreen`      |
/// | `HAS_REFLECT_UP`           | `reflect`          |
/// | `TRANSFORMED`              | `transform`        |
///
/// **NOTE:** all of the bits are packed into an 18 byte bitfield which uses up 3 bytes
/// after taking into consideration alignment. This is the same as on cartrige, though
/// there the bits are split over three distinct bytes (`w{Player,Enemy}BattleStatus{1,2,3}`).
/// We dont attempt to match the same bit locations, and `USING_X_ACCURACY` is dropped as
/// in-battle item-use is not supported in link battles.
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L73
///
const Volatile = packed struct {
    Bide: bool,
    Locked: bool,
    MultiHit: bool,
    Flinch: bool,
    Charging: bool,
    PartialTrap: bool,
    Invulnerable: bool,
    Confusion: bool,
    Mist: bool,
    FocusEnergy: bool,
    Substitute: bool,
    Recharging: bool,
    Rage: bool,
    LeechSeed: bool,
    Toxic: bool,
    LightScreen: bool,
    Reflect: bool,
    Transform: bool,

    comptime {
        assert(@bitSizeOf(Volatile) == 18);
        assert(@sizeOf(Volatile) == 3);
    }
};
