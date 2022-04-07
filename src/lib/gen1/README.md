# Pokémon Generation I: RBY

This document exists to describe the design of pkmn's Generation I ("RBY") engine. A high level
overview of the project's design can be found in the [top level design
document](../../../docs/DESIGN.md). The Gen I engine is implemented and tested across the following
files.

- [`data.zig`](data.zig) ([`data`](data)): contains definitions of all of the data structures used
  by the engine, described in detail [below](#data-structures)
- [`helpers.zig`](helpers.zig): helpers used to construct complex data types with
  sensible defaults (internally used by tests and tools)
- [`mechanics.zig`](mechanics.zig): code which manipulates the data structures in order to implement
  the mechanics of the game
- [`test.zig`](test.zig): unit tests for `mechanics.zig` (the code is also tested by [integration
  tests](../../../docs/TESTING.md) at a higher level)

The engine also relies on the [data types](../common/data.zig), [protocol](../common/protocol.zig),
and [RNG](../common/rng.zig) logic which is shared across generations and lives in
[`lib/common`](../common).

## Data Structures

The following information is required to simulate a Generation I Pokémon battle:

| pkmn                        | Pokémon Red (pret)                 | Pokémon Showdown                       |
| --------------------------- | ---------------------------------- | -------------------------------------- |
| `battle.seed`               | `Random{Add,Sub}`                  | `battle.seed`                          |
| `battle.turn`               |                                    | `battle.turn`                          |
| `battle.last_damage`        | `Damage`                           | `battle.lastDamage`                    |
| `side.{active,pokemon}`     | `PlayerMonNumber`/`BattleMon`      | `side.active`                          |
| `side.team`                 | `PartyMons`                        | `side.pokemon`                         |
| `side.last_used_move`       | `PlayerUsedMove`                   | `side.lastMove`                        |
| `side.last_selected_move`   | `PlayerSelectedMove`               | `side.lastSelectedMove`                |
| `side.order`                |                                    | `pokemon.position`                     |
| `{pokemon,active}.moves`    | `{party,battle}_struct.{Moves,PP}` | `pokemon.{baseMoveSlots,moveSlots}`    |
| `{pokemon,active}.hp`       | `{party,battle}_struct.HP`         | `pokemon.hp`                           |
| `{pokemon,active}.status`   | `{party,battle}_struct.Status`     | `pokemon.status`                       |
| `{pokemon,active}.level`    | `PlayerMonUnmodifiedLevel`         | `pokemon.level`                        |
| `pokemon.species`           | `party_struct.Species`             | `pokemon.baseSpecies`                  |
| `pokemon.stats`             | `PlayerMonUnmodified*`             | `pokemon.baseStoredStats`              |
| `active.stats`              | `battle_struct.Stats`              | `pokemon.storedStats`                  |
| `active.species`            | `battle_struct.Species`            | `pokemon.species`                      |
| `{pokemon,active}.types`    | `{party,battle}_struct.Type`       | `pokemon.types`                        |
| `active.boosts`             | `PlayerMon*Mod`                    | `pokemon.boosts`                       |
| `active.volatiles`          | `PlayerBattleStatus{1,2,3}`        | `pokemon.volatiles`                    |
| `volatiles.data.state`      | `PlayerBideAccumulatedDamage`      | `volatiles.bide.totalDamage`           |
| `volatiles.data.attacks`    | `PlayerNumAttacksLeft`             | `volatiles.{bide,lockedmove}.duration` |
| `volatiles.data.confusion`  | `PlayerConfusedCounter`            | `volatiles.confusion.duration`         |
| `volatiles.data.toxic`      | `PlayerToxicCounter`               | `volatiles.residualdmg.counter`        |
| `volatiles.data.substitute` | `PlayerSubstituteHP`               | `volatiles.substitute.hp`              |
| `volatiles.data.disabled`   | `PlayerDisabledMove{,Number}`      | `moveSlots.disabled`                   |

- Pokémon Showdown does not implement the correct Generation I RNG and as such its `seed` is
  different
- `battle.turn` only needs to be tracked in order to be compatible with the Pokémon Showdown
  protocol
- Battle results (win, lose, draw) and request states are communicated via the return value of
  `Battle.update`
- Nicknames (`BattleMonNick`/`pokemon.name`) are not handled by the pkmn engine as they are expected
  to be handled by driver code if required
- Pokémon Red's `LastSwitchInEnemyMonHP`, `InHandlePlayerMonFainted`, `PlayerNumHits`,
  `PlayerMonMinimized`, and `Move{DidntMiss,Missed}` are relevant for messaging/UI only
- Pokémon Red's `TransformedEnemyMonOriginalDVs` is only relevant for the [Transform DV manipulation
  glitch](https://pkmn.cc/bulba/Transform_glitches#Transform_DV_manipulation_glitch)
- Pokémon Red's `PlayerMove*` tracks information that is stored in the `Move` class
- Pokémon Red's `PlayerStatsToDouble`/`PlayerStatsToHalve` are constants which are always 0
- pkmn does not store the DVs/stat experience of Pokémon as they are expected to already be
  accounted for in the `Pokemon` `stats` and never need to be referenced in-battle (though the `DVs`
  struct exists to simplify generating legal test data)
- pkmn uses `volatiles.data.state` for total accumulated damage for Bide but also for implementing
  accuracy overwrite mechanics for certain moves (this glitch is present on the device but is not
  correctly implemented by Pokémon Showdown currently)

### `Battle` / `Side`

`Battle` and `Side` are analogous to the classes of the
[same](https://github.com/smogon/pokemon-showdown/blob/master/sim/battle.ts)
[name](https://github.com/smogon/pokemon-showdown/blob/master/sim/name.ts) in Pokémon Showdown and
store general information about the battle. Unlike in Pokémon Showdown there is a distinction
between the data structure for the "active" Pokémon and its party members (see below).

### `Pokemon` / `ActivePokemon`

Similar to the cartridge, in order to save space different information is stored depending on
whether a [Pokémon](https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_I%29) is
actively participating in battle vs. is switched out (pret's [`battle_struct` vs.
`party_struct`](https://pkmn.cc/pokered/macros/wram.asm)). In Pokémon Showdown, all the Pokemon are
represented by the same
[`Pokemon`](https://github.com/smogon/pokemon-showdown/blob/master/sim/pokemon.ts) class, and static
party information is saved in fields beginning with "`stored`" or "`base`".

#### `MoveSlot`

A `MoveSlot` is a data-type for a `(move, current pp)` pair. A pared down version of Pokémon
Showdown's `Pokemon#moveSlot`, it also stores data from the cartridge's `battle_struct::Move` macro
and can be used to replace the `PlayerMove*` data. Move PP is stored as a full byte instead of how
the cartridge (`battle_struct::PP`) stores it (6 bits for current PP and the remaining 2 bits used
to store the number of applied PP Ups). PP Up bits do not actually need to be stored on move slot
as max PP is never relevant in Generation I.

#### `Status`

Bitfield representation of a Pokémon's major [status
condition](https://pkmn.cc/bulba/Status_condition), mirroring how it is stored on the cartridge. A
value of `0x00` means that the Pokémon is not affected by any major status, otherwise the lower 3
bits represent the remaining duration for Sleep. Other status are denoted by the presence of
individual bits - at most one status should be set at any given time.

In Generation I & II, the "badly poisoned" status (Toxic) is instead treated as a volatile (see
below).

#### `Volatiles` / `Volatiles.Data`

Active Pokémon can have have ["volatile" status
conditions](https://pkmn.cc/bulba/Status_condition#Volatile_status) (called ['battle
status'](https://pkmn.cc/pokered/constants/battle_constants.asm#L73) bits in pret), all of which are
boolean flags that are cleared when the Pokémon faints or switches out:

| pkmn           | Pokémon Red (pret)         | Pokémon Showdown   |
| -------------- | -------------------------- | ------------------ |
| `Bide`         | `STORING_ENERGY`           | `bide`             |
| `Thrashing`    | `TRASHING_ABOUT`           | `lockedmove`       |
| `MultiHit`     | `ATTACKING_MULTIPLE_TIMES` | `Move#multihit`    |
| `Flinch`       | `FLINCHED`                 | `flinch`           |
| `Charging`     | `CHARGING_UP`              | `twoturnmove`      |
| `Trapping`     | `USING_TRAPPING_MOVE`      | `partiallytrapped` |
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

[Bide](https://pkmn.cc/bulba/Bide_(move)) (damage),
[Substitute](https://pkmn.cc/bulba/Substitute_(move)) (substitute HP),
[Confusion](https://pkmn.cc/bulba/Confusion_(status_condition)) (duration), and
[Toxic](https://pkmn.cc/bulba/Toxic_(move)) (counter) all require additional information to be
stored by the `Volatiles.Data` structure.

The `state` field of `Volatiles.Data` is effectively treated as a union:

- if `volatiles.Bide` is set, `volatiles.data.state` reflects the total accumulated Bide damage
- otherwise, `volatiles.data.state` reflects the last computed move accuracy (required in order to
  implement the [Rage and Thrash / Petal Dance accuracy
  bug](https://www.youtube.com/watch?v=NC5gbJeExbs))

#### `Stats` / `Boosts`

[Stats](https://pkmn.cc/bulba/Stat) and [boosts (stat
modifiers)](https://pkmn.cc/bulba/Stat#Stat_modifiers) are stored logically, with the exception that
boosts should always range from `-6`...`6` instead of `1`...`13` as on the cartridge.
  
### `Move` / `Move.Data`

`Move` serves as an identifier for a unique [Pokémon move](https://pkmn.cc/bulba/Move) that can be
used to retrieve `Move.Data` with information regarding base power, accuracy and type. As covered
above, PP information isn't strictly necessary in Generation I so is dropped. `Move.None` exists as
a special sentinel value to indicate `null`. Move PP data is only included for testing and is not
necessary for the actual engine implementation.

### `Species` / `Species.Data`

`Species` just serves as an identifier for a unique [Pokémon
species](https://pkmn.cc/bulba/Pok%C3%A9mon_species_data_structure_(Generation_I)) as the base stats
of a species are already accounted for in the computed stats in the `Pokemon` structure and nothing
in battle requires these to be recomputed. Similarly, Type is unnecessary to include as it is also
already present in the `Pokemon` struct. `Specie.None` exists as a special sentinel value to
indicate `null`. `Species.Data` is only included for testing and is not necessary for the actual
engine implementation, outside of `Species.chances` which is required as the base speed / 2 of the
species is necessary for computing critical hit probability.

### `Type` / `Types` / `Effectiveness`

The [Pokémon types](https://pkmn.cc/bulba/Type) are enumerated by `Type`. `Types` represents a tuple
of 2 types, but due to limitations in Zig this can't be represented as a `[2]Type` array and thus
instead takes the form of a packed struct. `Effectiveness` serves as an enum for tracking a moves
effectiveness - like the cartridge, effectiveness is stored as as `0`, `5`, `10`, and `20`
(technically only a 2-bit value is required, but as with `Types` Zig only allows a mininum of a byte
to be stored at each address of an array).

## Information

The information of each field (in terms of [bits of
entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))) is as follows:

| Data            | Range   | Bits |     | Data              | Range    | Bits |
| --------------- | ------- | ---- | --- | ----------------- | -------- | ---- |
| **seed**        | 0...255 | 8    |     | **turn**          | 1...1000 | 10   |
| **team index**  | 1...6   | 3    |     | **move index**    | 1...4    | 2    |
| **species**     | 1...151 | 8    |     | **move**          | 1...165  | 8    |
| **stat**        | 1...999 | 10   |     | **boost**         | 0...13   | 4    |
| **level**       | 1...100 | 7    |     | **volatiles**     | *18*     | 18   |
| **bide**        | 0...703 | 11   |     | **substitute**    | 0...179  | 8    |
| **confusion**   | 0...5   | 3    |     | **toxic**         | 0...15   | 4    |
| **multi hits**  | 0...5   | 3    |     | **base power**    | 0...40   | 6    |
| **base PP**     | 1...8   | 3    |     | **PP Ups**        | 0...3    | 2    |
| **PP**          | 0...64  | 7    |     | **HP / damage**   | 0...704  | 10   |
| **status**      | 0...10  | 4    |     | **effectiveness** | 0...3    | 2    |
| **type**        | 0...15  | 4    |     | **accuracy**      | 6...20   | 4    |
| **disabled**    | 0...7   | 3    |     | **DVs**           | 0...15   | 4    |
| **move effect** | 0..66   | 7    |     | **attacks**       | 0..4     | 3    |
| **crit chance** | 7..65   | 6    |     |                   |          |      |

From this we can determine the minimum bits[^1] required to store each data structure to determine
how much overhead the representations above have after taking into consideration [alignment &
padding](https://en.wikipedia.org/wiki/Data_structure_alignment) and
[denormalization](https://en.wikipedia.org/wiki/Denormalization):

- **`Pokemon`**: 5× stats (`50`) + 4× move slot (`60`) + HP (`10`) + status (`4`) + species (`8`) +
  level (`7`)
  - `type` can be computed from the base `Species` information
- **`ActivePokemon`**: 4× stats (`40`) + 4× move slot (`60`) + 6× boosts (`24`) + volatile data
  (`29`) + volatiles (`18`) + species (`8`) + types (`8`) + disabled (`5`)
  - the active Pokémon's stats/species/move slots/types may change in the case of Transform
  - the active Pokémon's types may change due to Conversion
  - the active Pokémon's level and current and max HP can always be referred to the `Pokemon`
    struct, and types can be computed from its species
- **`Side`**: `ActivePokemon` + 6× `Pokemon` + active (`3`) + last used (`8`) + last selected
  (`8`)
  - `order` does not need to be stored as the party can always be rearranged as switches occur
- **`Battle`**: 6× `Side` + seed (10× `8` + `4`) + turn (`10`) + last damage (`10`)
- **`Type.chart`**: attacking types (`15`) × defending types (`15`) × effectiveness (`2`)[^2]
- **`Moves.data`**: 164× base power (`6`) + effect (`7`) + accuracy (`4`) + type: (`4`)
- **`Species.chance`**: 151× crit chance (`6`)

| Data            | Actual bits | Minimum bits | Overhead |
| --------------- | ----------- | ------------ | -------- |
| `Pokemon`       | 192         | 139          | 38.1%    |
| `ActivePokemon` | 256         | 192          | 33.3%    |
| `Side`          | 1472        | 1045         | 40.9%    |
| `Battle`        | 3088        | 2194         | 40.7%    |
| `Type.chart`    | 1800        | 450          | 300.0%   |
| `Moves.data`    | 3636        | 3444         | 14.3%    |
| `Species.speed` | 1208        | 906          | 33.3%    |

In the case of `Type.chart`/`Moves.data`/`Species.chances`, technically only the values which are
used by any given simulation are required, which could be as low as 1 in both circumstances (eg. all
Normal Pokémon each only using the single move Tackle), though taking into consideration the worst
case all Pokémon types are required and 48 moves. The `Moves.data` array could be eliminated and
instead the `Move` data actually required by each `Pokemon` could be placed beside the `MoveSlot`,
though this is both less general and adds unnecessary complexity.

[^1]: For data with lower cardinality it is possible to save memory by ordinalizing the values and
turning them into indices into a lookup table (eg. encode all possible move base powers in a lookup
table and store the index into that table instead of the actual base power). While this approach may
minimize the absolute memory used, performance is more likely to suffer as the goal is to minimize
uncached memory lookups, not total memory usage.

[^2]: Instead of storing as a sparse multi-dimensional array the type chart could instead only
[store values which are not normal
effectiveness](https://github.com/pret/pokered/blob/master/data/types/type_matchups.asm) in 820 bits
as 82× attacking type (`4`) + defending type (`4`) + non-Normal effectiveness (`2`). This would
avoid having to do two memory lookups, but the second lookup should already be fast due to locality
of reference meaning it will likely already be in the cache.

## Layout

The precise layout of the engine's data structures is important to those implementing driver code,
as users must directly probe the engine's state through these structures (i.e. the pkmn engine does
not produce an equivalent to Pokémon Showdown's `|request|` protocol message, this information must
be gleaned through the `Battle` state).

Documentation wire protocol used for logging traces when `-Dtrace` is enabled can be found in
[PROTOCOL.md](../../../docs/PROTOCOL.md).

### `Battle`

| Start | End | Data                | Description                          |
| ----- | --- | ------------------- | ------------------------------------ |
| 0     | 184 | [`sides[0]`](#side) | Player 1's side                      |
| 184   | 368 | [`sides[1]`](#side) | Player 2's side                      |
| 368   | 370 | `turn`              | The current turn number              |
| 370   | 372 | `last_damage`       | The last damage dealt by either side |
| 372   | 384 | `rng`               | The RNG state                        |

- the current `turn` is 2 bytes, written in native-endianess
- the `rng` state depends on whether or not Pokémon Showdown compatibility mode is enabled
  (`-Dshowdown`):
  - if `showdown` is enabled, the RNG state consists of 4 bytes of zero-padding followed by the
    64-bit seed, written in native-endianess
  - otherwise the RNG state consists of 1 bytes of zero-padding, the 10 bytes of the seed, and
    finally the index pointing to which byte of the seed is currently being used

### `Side`

| Start | End | Data                       | Description                             |
| ----- | --- | -------------------------- | --------------------------------------- |
| 0     | 24  | [`pokemon[0]`](#pokemon)   | The player's first Pokémon              |
| 24    | 48  | [`pokemon[1]`](#pokemon)   | The player's second Pokémon             |
| 48    | 72  | [`pokemon[2]`](#pokemon)   | The player's third Pokémon              |
| 72    | 96  | [`pokemon[3]`](#pokemon)   | The player's fourth Pokémon             |
| 96    | 120 | [`pokemon[4]`](#pokemon)   | The player's fifth Pokémon              |
| 120   | 144 | [`pokemon[5]`](#pokemon)   | The player's sixth Pokémon              |
| 144   | 176 | [`active`](#activepokemon) | The player's active Pokémon             |
| 176   | 182 | `order`                    | The current order of the player's party |
| 182   | 183 | `last_selected_move`       | The last move the player selected       |
| 183   | 184 | `last_used_move`           | The last move the player used           |

- `order` is a 6 byte array where `order[i]` represents the position of `pokemon[i]`

### `ActivePokemon`

| Start | End | Data                               | Description                                                 |
| ----- | --- | ---------------------------------- | ----------------------------------------------------------- |
| 0     | 2   | `stats.hp`                         | The active Pokémon's computed max HP stat                   |
| 2     | 4   | `stats.atk`                        | The active Pokémon's modified Attack stat                   |
| 4     | 6   | `stats.def`                        | The active Pokémon's modified Defense stat                  |
| 6     | 8   | `stats.spe`                        | The active Pokémon's modified Speed stat                    |
| 7     | 10  | `stats.spc`                        | The active Pokémon's modified Special stat                  |
| 10    | 19  | [`volatiles`](#volatiles)          | The active Pokémon's volatiles statuses and associated data |
| 19    | 20  | `moves[0].pp`                      | The PP of the active Pokémon's first move                   |
| 20    | 21  | `moves[1].id`                      | The active Pokémon's second move                            |
| 21    | 22  | `moves[1].pp`                      | The PP of the active Pokémon's second move                  |
| 22    | 23  | `moves[2].id`                      | The active Pokémon's third move                             |
| 23    | 24  | `moves[2].pp`                      | The PP of the active Pokémon's third move                   |
| 24    | 25  | `moves[3].id`                      | The active Pokémon's fourth move                            |
| 25    | 26  | `moves[4].pp`                      | The PP of the active Pokémon's fourth move                  |
| 27    | 28  | `boosts.atk`/`boosts.def`          | The active Pokémon's Attack and Defense boosts              |
| 28    | 29  | `boosts.spe`/`boosts.spd`          | The active Pokémon's Speed and Special boosts               |
| 29    | 30  | `boosts.accuracy`/`boosts.evasion` | The active Pokémon's Accuracy and Evasion boosts            |
| 30    | 31  | `species`                          | The active Pokémon's species                                |
| 31    | 32  | `type1`/`type2`                    | The active Pokémon's types                                  |

- the active Pokémon's `stats.hp` is always identical to the the corresponding stored Pokémon's `stats.hp`
- `boosts` and `types` includes bytes which store two 4-bit fields each

#### `Volatiles`

> **NOTE:** The offsets in the following table represent *bits* and **not** bytes.

| Start | End | Data                     | Description                                                                         |
| ----- | --- | ------------------------ | ----------------------------------------------------------------------------------- |
| 0     | 16  | `data.state`             | The total accumulated damage from Bide or the overwritten accuracy of certain moves |
| 16    | 24  | `data.substitute`        | The remaining HP of the Substitute                                                  |
| 24    | 28  | `data.disabled.move`     | The move slot (1-4) the is disabled                                                 |
| 28    | 32  | `data.disabled.duration` | The remaining turns the move is disabled                                            |
| 32    | 36  | `data.confusion`         | The remaining turns of confusion                                                    |
| 36    | 40  | `data.toxic`             | The number of turns toxic damage has been accumulating                              |
| 40    | 44  | `data.attacks`           | The number of attacks remaining                                                     |
| 44    | 48  | `0000`                   | Zero padding                                                                        |
| 48    | 49  | `Bide`                   | Whether the "Bide" volatile status is present                                       |
| 49    | 50  | `Thrashing`              | Whether the "Thrashing" volatile status is present                                  |
| 50    | 51  | `MultiHit`               | Whether the "MultiHit" volatile status is present                                   |
| 51    | 52  | `Flinch`                 | Whether the "Flinch" volatile status is present                                     |
| 52    | 53  | `Charging`               | Whether the "Charging" volatile status is present                                   |
| 53    | 54  | `Trapping`               | Whether the "Trapping" volatile status is present                                   |
| 54    | 55  | `Invulnerable`           | Whether the "Invulnerable" volatile status is present                               |
| 55    | 56  | `Confusion`              | Whether the "Confusion" volatile status is present                                  |
| 56    | 57  | `Mist`                   | Whether the "Mist" volatile status is present                                       |
| 57    | 58  | `FocusEnergy`            | Whether the "FocusEnergy" volatile status is present                                |
| 58    | 59  | `Substitute`             | Whether the "Substitute" volatile status is present                                 |
| 59    | 60  | `Recharging`             | Whether the "Recharging" volatile status is present                                 |
| 60    | 61  | `Rage`                   | Whether the "Rage" volatile status is present                                       |
| 61    | 62  | `LeechSeed`              | Whether the "LeechSeed" volatile status is present                                  |
| 62    | 63  | `Toxic`                  | Whether the "Toxic" volatile status is present                                      |
| 63    | 64  | `LightScreen`            | Whether the "LightScreen" volatile status is present                                |
| 64    | 65  | `Reflect`                | Whether the "Reflect" volatile status is present                                    |
| 65    | 66  | `Transform`              | Whether the "Transform" volatile status is present                                  |
| 66    | 72  | `000000`                 | Zero padding                                                                        |

### `Pokemon`

| Start | End | Data            | Description                                |
| ----- | --- | --------------- | ------------------------------------------ |
| 0     | 2   | `stats.hp`      | The Pokémon's computed max HP stat         |
| 2     | 4   | `stats.atk`     | The Pokémon's unmodified Attack stat       |
| 4     | 6   | `stats.def`     | The Pokémon's unmodified Defense stat      |
| 6     | 8   | `stats.spe`     | The Pokémon's unmodified Speed stat        |
| 7     | 10  | `stats.spc`     | The Pokémon's unmodified Special stat      |
| 10    | 11  | `moves[0].id`   | The Pokémon's first stored move            |
| 11    | 12  | `moves[0].pp`   | The PP of the Pokémon's first stored move  |
| 12    | 13  | `moves[1].id`   | The Pokémon's second stored move           |
| 13    | 14  | `moves[1].pp`   | The PP of the Pokémon's second stored move |
| 14    | 15  | `moves[2].id`   | The Pokémon's third stored move            |
| 15    | 16  | `moves[2].pp`   | The PP of the Pokémon's third stored move  |
| 16    | 17  | `moves[3].id`   | The Pokémon's fourth stored move           |
| 17    | 18  | `moves[4].pp`   | The PP of the Pokémon's fourth stored move |
| 18    | 20  | `hp`            | The Pokémon's current HP                   |
| 20    | 21  | `status`        | The Pokémon's current status               |
| 21    | 20  | `species`       | The Pokémon's stored species               |
| 22    | 22  | `type1`/`type2` | The Pokémon's stored types                 |
| 23    | 24  | `level`         | The Pokémon's level                        |

## Bugs

In addition to its alternative RNG semantics, Pokémon Showdown's implemention of the first
generation of Pokémon contains a number bugs:

- **Haze:** Haze should remove the toxic volatile and leave the toxic counter unchanged, not reset
  the toxic counter. Furthermore, Haze should clear a specific set of volatiles, not clear all
  volatiles indiscriminately (including artificial implementation-defined volatiles like
  `brnattackdrop`).
- **`Battle.getRandomTarget()`**: Pokémon Showdown randomly determines a target (causing the RNG to
  advance a frame) in cases where the target of a move is required but has not been specified,
  though erroneously applies this logic in singles battles where only one target is possible. This
  spuriously and inefficiently advances the RNG and results in inconsistencies if a player specifies
  `move 1 1` instead of `move 1`.
- **Psybeam / Confusion:** the secondary chance of these moves causing confusion is not 26/256 like
  most "10%" chance moves but instead **25/256**.

Finally, in Generation I, checking whether a move has **hit should come *after* determining
damage**, not before. Pokémon Showdown's altered ordering here (which is more in line with how
future generations work) would have consequences on RNG accuracy, though since RNG accuracy is not a
goal for the simulator this bug should not have any implications

## RNG

TODO table

- crit
- dmg
- miss
- secondary
  - breakdown of each
- metronome

## Resources

- [pret/pokered](https://github.com/pret/pokered/) disassembly
- [Gen I Main Battle
  Function](https://www.smogon.com/forums/threads/past-gens-research-thread.3506992/#post-5878612) -
  Crystal_
- [Pokemon Showdown!](https://github.com/smogon/pokemon-showdown)
- [List of glitches (Generation
  I)](https://bulbapedia.bulbagarden.net/wiki/List_of_glitches_(Generation_I))
