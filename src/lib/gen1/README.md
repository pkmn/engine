# Pokémon Generation I: RBY

The following information is required to simulate a Generation I Pokémon battle:

| pkmn                        | Pokémon Red (pret)            | Pokémon Showdown                |
| --------------------------- | ----------------------------- | ------------------------------- |
| `battle.seed`               | `Random{Add,Sub}`             | `battle.seed`                   |
| `battle.last_damage`        | `Damage`                      | `battle.lastDamage`             |
| `side.{active,pokemon}`     | `PlayerMonNumber`/`BattleMon` | `side.active`                   |
| `side.team`                 | `PartyMons`                   | `side.pokemon`                  |
| `side.last_used_move`       | `PlayerUsedMove`              | `side.lastMove`                 |
| `side.last_selected_move`   | `PlayerSelectedMove`          | `side.lastSelectedMove`         |
| `pokemon.stats`             | `PlayerMonUnmodified*`        | `pokemon.baseStoredStats`       |
| `pokemon.position`          | `battle_struct.PartyPos`      | `pokemon.position`              |
| `pokemon.moves`             | `party_struct.{Moves,PP}`     | `pokemon.baseMoveSlots`         |
| `{pokemon,active}.hp`       | `battle_struct.HP`            | `pokemon.hp`                    |
| `{pokemon,active}.status`   | `battle_struct.Status`        | `pokemon.status`                |
| `{pokemon,active}.level`    | `PlayerMonUnmodifiedLevel`    | `pokemon.level`                 |
| `pokemon.species`           | `party_struct.Species`        | `pokemon.baseSpecies`           |
| `active.species`            | `battle_struct.Species`       | `pokemon.species`               |
| `active.stats`              | `party_struct.Stats`          | `pokemon.storedStats`           |
| `active.boosts`             | `PlayerMon*Mod`               | `pokemon.boosts`                |
| `active.volatiles`          | `PlayerBattleStatus{1,2,3}`   | `pokemon.volatiles`             |
| `volatiles_data.bide`       | `PlayerBideAccumulatedDamage` | `volatiles.bide.totalDamage`    |
| `volatiles_data.confusion`  | `PlayerConfusedCounter`       | `volatiles.confusion.duration`  |
| `volatiles_data.toxic`      | `PlayerToxicCounter`          | `volatiles.residualdmg.counter` |
| `volatiles_data.substitute` | `PlayerSubstituteHP`          | `volatiles.substitute.hp`       |
| `active.disabled`           | `PlayerDisabledMove{,Number}` | `moveSlots.disabled`            |

- Pokémon Showdown does not implement the correct Generation I RNG and as such its `seed` is
  different
- `battle.turn` only needs to be tracked in order to be compatible with the Pokémon Showdown
  protocol
- Battle results (win, lose, draw) or request states are communiccated via the return code of
  `Battle.update`
- Nicknames (`BattleMonNick`/`pokemon.name`) are not handled by the pkmn engine as they are expected
  to be handled by driver code if required
- Pokémon Red's `LastSwitchInEnemyMonHP`, `InHandlePlayerMonFainted`, `PlayerNumHits`,
  `PlayerMonMinimized`, and `Move{DidntMiss,Missed}` are relevant for messaging/UI only
- Pokémon Red's `TransformedEnemyMonOriginalDVs` is only relevant for the [Transform DV manipulation
  glitch](https://pkmn.cc/bulba/Transform_glitches#Transform_DV_manipulation_glitch)
- Pokémon Red's `PlayerMove*` tracks information that is stored in the `Move` class
- Pokémon Red's `PlayerNumAttacksLeft` is used to implement the multi-hit loop which is handled by
  other means in pkmn and Pokémon Showdown
- Pokémon Red's `PlayerStatsToDouble`/`PlayerStatsToHalve` are constants which are always 0
- pkmn does not store the DVs/stat experience of Pokémon as they are expected to already be
  accounted for in the `Pokemon` `stats` and never need to be referenced in-battle

## Data Structures

### `Battle`

TODO

### `Side`

TODO

### `Pokemon` / `ActivePokemon`

TODO

#### `MoveSlot`

TODO

#### `Status`

TODO

#### `Volatiles` / `VolatileData`

Active Pokémon can have have ["volatile" status
conditions](https://pkmn.cc/bulba/Status_condition#Volatile_status), all of which are boolean flags
that are cleared when the Pokémon faints or switches out:

| pkmn           | Pokémon Red (pret)         | Pokémon Showdown   |
| -------------- | -------------------------- | ------------------ |
| `Bide`         | `STORING_ENERGY`           | `bide`             |
| `Locked`       | `TRASHING_ABOUT`           | `lockedmove`       |
| `MultiHit`     | `ATTACKING_MULTIPLE_TIMES` | `Move#multihit`    |
| `Flinch`       | `FLINCHED`                 | `flinch`           |
| `Charging`     | `CHARGING_UP`              | `twoturnmove`      |
| `PartialTrap`  | `USING_TRAPPING_MOVE`      | `partiallytrapped` |
| `Invulnerable` | `INVULNERABLE`             | `Move#onLockMove`  |
| `Confusion`    | `CONFUSED`                 | `confusion`        |
| `Mist`         | `PROTECTED_BY_MIST`        | `mist`             |
| `FocusEnergy`  | `GETTING_PUMPED`           | `focusenergy`      |
| `Substitute`   | `HAS_SUBSTITUTE_UP`        | `substitute`       |
| `Recharging`   | `NEEDS_TO_RECHARGE`        | `mustrecharge`     |
| `Rage`         | `USING_RAGE`               | `rage`             |
| `LeechSeed`    | `SEEDED`                   | `leechseed`        |
| `Toxic`        | `BADLY_POISONED`           | `toxic`            |
| `LightScreen`  | `HAS_LIGHT_SCREEN_UP`      | `lightscreen`      |
| `Reflect`      | `HAS_REFLECT_UP`           | `reflect`          |
| `Transform`    | `TRANSFORMED`              | `transform`        |

TODO

#### `Stats` / `Boosts`

TODO

### `Move` / `Moves`

TODO

### `Species`

TODO

### `Type` / `Types` / `Effectiveness`

TODO

## Information

The information of each field (in terms of [bits of
entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))) is as follows:

| Data           | Range    | Bits |     | Data              | Range    | Bits |
| -------------- | -------- | ---- | --- | ----------------- | -------- | ---- |
| **seed**       | 0 - 255  | 8    |     | **turn**          | 1 - 1000 | 7    |
| **team index** | 1 - 6    | 3    |     | **move index**    | 1 - 4    | 2    |
| **species**    | 1 - 151  | 8    |     | **move**          | 1 - 165  | 8    |
| **stat**       | 1 - 999  | 10   |     | **boost**         | 0 - 13   | 4    |
| **level**      | 1 - 100  | 7    |     | **volatiles**     | 17       | 18   |
| **bide**       | 2 - 1406 | 11   |     | **substitute**    | 4 - 179  | 8    |
| **confusion**  | 2 - 5    | 3    |     | **toxic**         | 1 - 16   | 4    |
| **multi hits** | 2 - 5    | 3    |     | **base power**    | 0 - 40   | 6    |
| **base PP**    | 1 - 8    | 3    |     | **PP Ups**        | 0 - 3    | 2    |
| **used PP**    | 0 - 63   | 8    |     | **HP / damage**   | 13 - 704 | 10   |
| **status**     | 0 - 10   | 4    |     | **effectiveness** | 0 - 3    | 2    |
| **type**       | 0 - 15   | 4    |     | **accuracy**      | 6 - 20   | 4    |
| **disabled**   | 0 - 7    | 3    |     | **DVs**           | 0 - 15   | 4    |


From this we can determine the minimum bits required to store each data structure to determine how
much overhead the representations above have after taking into consideration [alignment &
padding](https://en.wikipedia.org/wiki/Data_structure_alignment) and
[denormalization](https://en.wikipedia.org/wiki/Denormalization):

- **`Pokemon`**: 5× stats (`50`) + 4× move slot (`56`) + HP (`10`) + status (`4`) + species (`8`) +
  level (`7`)
  - PP Ups bits do not need to be stored on move slot as max PP is never relevant in battle
  - position does not need to be stored as the party can always be rearranged as switches occur
  - `type` can be computed from the base `Species` information
- **`ActivePokemon`**: 5× stats (`50`) + 4× move slot (`56`) + 6× boosts (`24`) + volatile data
  (`29`) + volatiles (`18`) + species (`8`) + disabled (`5`)
  - the active Pokémon's stats/species/move slots may change in the case of Transform
  - the active Pokémon's level and current HP can always be referred to the `Pokemon` struct, and
    types can be computed from its species
- **`Side`**: `ActivePokemon` + 6× `Pokemon` + active (`3`) + lasted used (`8`) + last selected
  (`8`)
- **`Battle`**: 6× `Side` + seed (`8`) + turn (`7`) + last damage (`10`)

| Data            | Actual bits | Minimum bits | Overhead |
| --------------- | ----------- | ------------ | -------- |
| `Pokemon`       | 176         | 135          | 30.4%    |
| `ActivePokemon` | 288         | 190          | 51.6%    |
| `Side`          | 1376        | 1078         | 35.0%    |
| `Battle`        | 2768        | 2181         | 34.2%    |

----
```txt
// wPlayerMonNumber (pret) & Side#active[0] (PS)
// wInHandlePlayerMonFainted (pret) & Side#faintedThisTurn (PS)
// wPlayerUsedMove (pret) & Side#lastMove (PS)
// wPlayerSelectedMove (pret) & Side#lastSelectedMove (PS)

/// The core representation of a Pokémon in a  Comparable to Pokémon Showdown's `Pokemon`
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
