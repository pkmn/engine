| pkmn                                   | Pokémon Red                   | Pokémon Showdown                |
| -------------------------------------- | ----------------------------- | ------------------------------- |
|                                        | `BattleMonNick`               | `name`                          |
| `team[i].level`                        | `PlayerMonUnmodifiedLevel`    | `level`                         |
| `team[i].stats`                        | `PlayerMonUnmodified*`        | `storedStats`                   |
| `team[i].moves`                        |                               | `baseMoveSlots`                 |
| `pokemon.boosts`                       | `PlayerMon*Mod`               | `boosts`                        |
| `pokemon.volatiles`                    | `PlayerBattleStatus{1,2,3}`   | `volatiles`                     |
| `pokemon.volatiles_data.bide`          | `PlayerBideAccumulatedDamage` | `volatiles.bide.totalDamage`    |
| `pokemon.volatiles_data.confusion`     | `PlayerConfusedCounter`       | `volatiles.confusion.duration`  |
| `pokemon.pokemon.volatiles_data.toxic` | `PlayerToxicCounter`          | `volatiles.residualdmg.counter` |
| `volatiles_data.substitute`            | `PlayerSubstituteHP`          | `volatiles.substitute.hp`       |
|                                        | `PlayerNumHits`               |                                 |
| `pokemon.volatiles_data.multihits`     | `PlayerNumAttacksLeft`        |                                 |
| `pokemon.disabled`                     | `PlayerDisabledMove`          | `moveSlots.disabled`            |

| Pokémon Red                | Pokémon Showdown   |
| -------------------------- | ------------------ |
| `STORING_ENERGY`           | `bide`             |
| `TRASHING_ABOUT`           | `lockedmove`       |
| `ATTACKING_MULTIPLE_TIMES` | `Move#multihit`    |
| `FLINCHED`                 | `flinch`           |
| `CHARGING_UP`              | `twoturnmove`      |
| `USING_TRAPPING_MOVE`      | `partiallytrapped` |
| `INVULNERABLE`             | `Move#onLockMove`  |
| `CONFUSED`                 | `confusion`        |
| `PROTECTED_BY_MIST`        | `mist`             |
| `GETTING_PUMPED`           | `focusenergy`      |
| `HAS_SUBSTITUTE_UP`        | `substitute`       |
| `NEEDS_TO_RECHARGE`        | `mustrecharge`     |
| `USING_RAGE`               | `rage`             |
| `SEEDED`                   | `leechseed`        |
| `BADLY_POISONED`           | `toxic`            |
| `HAS_LIGHT_SCREEN_UP`      | `lightscreen`      |
| `HAS_REFLECT_UP`           | `reflect`          |
| `TRANSFORMED`              | `transform`        |

| Data          | Range    | Bits |
| ------------- | -------- | ---- |
| seed          | 0 - 255  | 8    |
| turn          | 1 - 1000 | 7    |
| team index    | 1 - 6    | 3    |
| move index    | 1 - 4    | 2    |
| species       | 1 - 151  | 8    |
| move          | 1 - 165  | 8    |
| stat          | 1 - 999  | 10   |
| boost         | 0 - 13   | 4    |
| level         | 1 - 100  | 7    |
| volatiles     | 17       | 18   |
| bide          | 2 - 1406 | 11   |
| substitute    | 4 - 179  | 8    |
| confusion     | 2 - 5    | 3    |
| toxic         | 1 - 16   | 4    |
| multi hits    | 2 - 5    | 3    |
| base power    | 0 - 40   | 6    |
| base PP       | 1 - 8    | 3    |
| PP Ups        | 0 - 3    | 2    |
| used PP       | 0 - 63   | 8    |
| HP            | 13 - 704 | 10   |
| status        | 0 - 10   | 4    |
| effectiveness | 0 - 3    | 2    |
| type          | 0 - 15   | 4    |
| accuracy      | 6 - 20   | 4    |
| disabled      | 0 - 7    | 3    |

| Data            | Actual | Minimum | Overhead |
| --------------- | ------ | ------- | -------- |
| `Battle`        | 2768   | 2171    | 21.5%    |
| `Side`          | 1376   | 1078    | 21.6%    |
| `ActivePokemon` | 288    | 198     | 45.4%    |
| `Pokemon`       | 176    | 143     | 18.8%    |

```txt
Pokemon = stats * 5 + move slot * 4 + hp + status + species + level
        = 50 + 64 + 10 + 4 + 8 + 7
        = 143
Active  = stats * 5 + move slot * 4 + volatiles_data + volatiles + boosts * 6 + species (transform) + disabled (index + duration)
        = 50 + 64 + (11 + 8 + 3 + 3 + 4) + 18 + 24 + 8 + (2 + 3)
        = 198
Side    = Active + Pokemon * 6 + active + fainted + last_used + last_selected
        = 200 + 858 + 3 + 3 + 8 + 8
        = 1078
Battle  = Side * 2 + turn + seed
        = 2160 + 7 + 8
        = 2171
```

## `Battle`

## `Side`

## `Pokemon` / `ActivePokemon`

### `MoveSlot`

### `Status`

### `Volatiles` / `VolatileData`

### `Stats` / `Boosts`

## `Move` / `Moves`

## `Species`

## `Type` / `Types` / `Effectiveness`

```txt
// wPlayerMonNumber (pret) & Side#active[0] (PS)
// wInHandlePlayerMonFainted (pret) & Side#faintedThisTurn (PS)
// wPlayerUsedMove (pret) & Side#lastMove (PS)
// wPlayerSelectedMove (pret) & Side#lastSelectedMove (PS)

/// The core representation of a Pokémon in a battle. Comparable to Pokémon Showdown's `Pokemon`
/// type, this struct stores the data stored in the cartridge's `battle_struct` information stored
/// in `w{Battle,Enemy}Mon` as well as parts of the `party_struct` in the `stored` field. The fields
/// map to the following types:
///
///   - in most places the data representation defaults to the same as the cartridge, with the
///     notable exception that `boosts` range from `-6 - .6` like in Pokémon Showdown instead of
///     `1 - 13`
///   - nicknames are not handled within the engine and are expected to instead be managed by
///     whatever is driving the engine code
///
/// **References:**
///
///  - https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_I%29
///  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK1.cs
///  - https://pkmn.cc/pokered/macros/wram.asm
///

/// A data-type for a `(move, pp)` pair. A pared down version of Pokémon Showdown's
/// `Pokemon#moveSlot`, it also stores data from the cartridge's `battle_struct::Move`
/// macro and can be used to replace the `wPlayerMove*` data. Move PP is stored
/// in the same way as on the cartridge (`battle_struct::PP`), with 6 bits for current
/// PP and the remaining 2 bits used to store the number of applied PP Ups.

// `AddBonusPP`: https://pkmn.cc/pokered/engine/items/item_effects.asm

/// *See:* https://pkmn.cc/pokered/data/moves/moves.asm
/// *See:* https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_I%29

/// Bitfield representation of a Pokémon's major status condition, mirroring how it is stored on
/// the cartridge. A value of `0x00` means that the Pokémon is not affected by any major status,
/// otherwise the lower 3 bits represent the remaining duration for SLP. Other status are denoted
/// by the presence of individual bits - at most one status should be set at any given time.
///
/// **NOTE:** in Generation 1 and 2, the "badly poisoned" status (TOX) is volatile and gets dropped
/// upon switching out - see the respective `Volatiles` structs.
///

/// Bitfield for the various non-major statuses that Pokémon can have, commonly
/// known as 'volatile' statuses as they disappear upon switching out. In pret/pokered
/// these are referred to as 'battle status' bits.
///
/// **NOTE:** all of the bits are packed into an 18 byte bitfield which uses up 3 bytes
/// after taking into consideration alignment. This is the same as on cartridge, though
/// there the bits are split over three distinct bytes (`wPlayerBattleStatus{1,2,3}`).
/// We dont attempt to match the same bit locations, and `USING_X_ACCURACY` is dropped as
/// in-battle item-use is not supported in link battles.
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L73
///

/// The name of each stat (cf. Pokémon Showdown's `StatName`).
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L5-L12
///

/// A structure for storing information for each `Boost` (cf. Pokémon Showdown's `BoostTable`).
/// **NOTE**: `Boost(i4)` should likely always be used, as boosts should always range from -6 - .6.

/// The name of each boost/mod (cf. Pokémon Showdown's `BoostName`).
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L14-L23
///
```
