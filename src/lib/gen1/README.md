# Pokémon Generation I: RBY

This document exists to describe the design of pkmn's Generation I ("RBY") engine. A high level
overview of the project's design can be found in the [top level design
document](../../../docs/DESIGN.md). The Generation I engine is implemented and tested across the
following files:

- [`data.zig`](data.zig) ([`data`](data)): contains definitions of all of the data structures used
  to implement the core mechanics of the engine, described in detail [below](#data-structures)
- [`chance.zig`](chance.zig): TODO
- [`calc.zig`](calc.zig): TODO
- [`helpers.zig`](helpers.zig): helpers used to construct complex data types with
  sensible defaults (internally used by tests and tools)
- [`mechanics.zig`](mechanics.zig): code which manipulates the data structures to implement the
  mechanics of the game
- [`test.zig`](test.zig): unit tests for `mechanics.zig` (the code is also tested by [integration
  tests](../../../docs/TESTING.md) at a higher level)

The engine also relies on the [data types](../common/data.zig), [protocol](../common/protocol.zig),
and [RNG](../common/rng.zig) logic which is shared across generations and lives in
[`lib/common`](../common).

Covered below is a description of the [**data structures**](#data-structures) used including the
[**information**](#information) they contain and their [**layout**](#layout), a list of
[**bugs**](#bugs) that are introduced by `-Dshowdown` for Pokémon Showdown compatibility, an
[**RNG**](#rng) table, high level [**details**](#details) about the control flow of the engine and a
list of additional reference [**resources**](#resources).

## Data Structures

The following information is required to simulate a Generation I Pokémon battle:

| pkmn                                 | Pokémon Red (pret)                 | Pokémon Showdown                       |
| ------------------------------------ | ---------------------------------- | -------------------------------------- |
| `battle.seed`                        | `Random{Add,Sub}`                  | `battle.seed`                          |
| `battle.turn`                        | -                                  | `battle.turn`                          |
| `battle.last_damage`                 | `Damage`                           | `battle.lastDamage`                    |
| `side.{active,pokemon}`              | `PlayerMonNumber`/`BattleMon`      | `side.active`                          |
| `side.team`                          | `PartyMons`                        | `side.pokemon`                         |
| `side.last_used_move`                | `PlayerUsedMove`                   | `pokemon.lastMove`                     |
| `side.last_selected_move`            | `PlayerSelectedMove`               | `side.lastSelectedMove`                |
| `battle.last_moves.index`            | `PlayerMoveListIndex`              | -                                      |
| `battle.last_moves.counterable`      | -                                  | `side.lastMove`                        |
| `side.order`                         | -                                  | `pokemon.position`                     |
| `{pokemon,active}.moves`             | `{party,battle}_struct.{Moves,PP}` | `pokemon.{baseMoveSlots,moveSlots}`    |
| `pokemon.hp`                         | `{party,battle}_struct.HP`         | `pokemon.hp`                           |
| `{pokemon,active}.status`            | `{party,battle}_struct.Status`     | `pokemon.status`                       |
| `{pokemon,active}.level`             | `PlayerMonUnmodifiedLevel`         | `pokemon.level`                        |
| `pokemon.species`                    | `party_struct.Species`             | `pokemon.baseSpecies`                  |
| `pokemon.stats`                      | `box_struct.Stats`                 | `pokemon.baseStoredStats`              |
| `active.stats`                       | `battle_struct.Stats`              | `pokemon.modifiedStats`                |
| `volatiles.transform`                | `PlayerMonUnmodified*`             | `pokemon.storedStats`                  |
| `active.species`                     | `battle_struct.Species`            | `pokemon.species`                      |
| `{pokemon,active}.types`             | `{party,battle}_struct.Type`       | `pokemon.types`                        |
| `active.boosts`                      | `PlayerMon*Mod`                    | `pokemon.boosts`                       |
| `active.volatiles`                   | `PlayerBattleStatus{1,2,3}`        | `pokemon.volatiles`                    |
| `volatiles.state`                    | `PlayerBideAccumulatedDamage`      | `volatiles.bide.totalDamage`           |
| `volatiles.attacks`                  | `PlayerNumAttacksLeft`             | `volatiles.{bide,lockedmove}.duration` |
| `volatiles.confusion`                | `PlayerConfusedCounter`            | `volatiles.confusion.duration`         |
| `volatiles.toxic`                    | `PlayerToxicCounter`               | `volatiles.residualdmg.counter`        |
| `volatiles.substitute`               | `PlayerSubstituteHP`               | `volatiles.substitute.hp`              |
| `volatiles.disabled_{move,duration}` | `PlayerDisabledMove{,Number}`      | `volatiles.disable.{move,time}`        |

- Pokémon Showdown [doesn't implement the correct Generation I RNG](#rng) and as such its `seed` is
  different
- `battle.turn` only needs to be tracked to be compatible with the Pokémon Showdown protocol
- Pokémon Showdown tracks several last used move variables (`Battle.lastMove`, `Side.lastMove`, and
  `Pokemon.lastMove`), none of which accurately match the `PlayerUsedMove` variable from the
  cartridge (`Side.lastMove` should be what's used, but is used by Pokémon Showdown only for Counter
  and isn't set and cleared in the correct locations. `Pokemon.lastMove` matches `PlayerUsedMove`
  more often so is what the engine attempts to model, despite the implications for Counter)
- `battle.last_moves` doesn't map precisely to cartridge concepts because it's used to track desyncs
  which instead are represented on the cartridge as discrepancies between the two separate battle
  states that exist in the link battle.
- Pokémon Showdown doesn't implement the [partial-trapping move Mirror Move
  glitch](https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch) and as such
  doesn't need to keep track of a player's last selected move index (`PlayerMoveListIndex`)
- Battle results (win, lose, draw) and request states are communicated via the return value of
  `Battle.update`
- Nicknames (`BattleMonNick`/`pokemon.name`) aren't handled by the pkmn engine as they're expected
  to be handled by driver code if required
- Pokémon Red's `LastSwitchInEnemyMonHP`, `InHandlePlayerMonFainted`, `PlayerNumHits`,
  `PlayerMonMinimized`, and `Move{DidntMiss,Missed}` are relevant for messaging/UI only
- Pokémon Red's `TransformedEnemyMonOriginalDVs` is only relevant for the [Transform DV manipulation
  glitch](https://pkmn.cc/bulba/Transform_glitches#Transform_DV_manipulation_glitch)
- Pokémon Red's `PlayerMove*` tracks information that's stored in the `Move` class
- Pokémon Red's `PlayerStatsToDouble`/`PlayerStatsToHalve` are constants which are always 0
- pkmn doesn't store the DVs/stat experience of Pokémon as they're expected to already be accounted
  for in the `Pokemon` `stats` and never need to be referenced in-battle (though a `DVs` struct
  exists to simplify generating legal test data)
- Instead of storing unmodified stats like Pokémon Red or Pokémon Showdown, pkmn simply tracks the
  identity of the Pokémon that has been transformed into in the `active.volatiles.transform` field
- pkmn uses `volatiles.state` for total accumulated damage for Bide but also for implementing
  accuracy overwrite mechanics for certain moves (this glitch is present on the device but isn't
  correctly implemented by Pokémon Showdown currently)

### `Battle` / `Side`

`Battle` and `Side` are analogous to the classes of the
[same](https://github.com/smogon/pokemon-showdown/blob/master/sim/battle.ts)
[name](https://github.com/smogon/pokemon-showdown/blob/master/sim/side.ts) in Pokémon Showdown and
store general information about the battle. Unlike in Pokémon Showdown there is a distinction
between the data structure for the "active" Pokémon and its party members (see below).

Due to layout constraints, details about the last moves for a side are stored in what would
otherwise be the padding bytes of `Battle` (the `last_moves` field) instead of in `Side`.

### `Pokemon` / `ActivePokemon`

Similar to the cartridge, to save space different information is stored depending on whether a
[Pokémon](https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_I%29) is actively
participating in battle vs. is switched out (pret's [`battle_struct` vs.
`party_struct`](https://pkmn.cc/pokered/macros/ram.asm)). In Pokémon Showdown, all the Pokémon in a
battle are represented by the same
[`Pokemon`](https://github.com/smogon/pokemon-showdown/blob/master/sim/pokemon.ts) class, and static
party information is saved in fields beginning with "`stored`" or "`base`".

#### `MoveSlot`

A `MoveSlot` is a data-type for a `(move, current pp)` pair. A pared down version of Pokémon
Showdown's `Pokemon.moveSlot`, it also stores data from the cartridge's `battle_struct::Move` macro
and can be used to replace the `PlayerMove*` data. Move PP is stored as a full byte instead of how
the cartridge (`battle_struct::PP`) stores it (6 bits for current PP and the remaining 2 bits used
to store the number of applied PP Ups). PP Up bits don't actually need to be stored on move slot
as max PP is never relevant in Generation I.

#### `Status`

Bitfield representation of a Pokémon's major [status
condition](https://pkmn.cc/bulba/Status_condition), mirroring how it's stored on the cartridge. A
value of `0x00` means that the Pokémon isn't affected by any major status, otherwise the lower 3
bits represent the remaining duration for Sleep. Other status are denoted by the presence of
individual bits - at most one status should be set at any given time.

In Generation I & II, the "badly poisoned" status (Toxic) is instead treated as a volatile (see
below), so the upper most bit of `Status` is instead used to track state required to implement Pokémon
quirks:

  - when combined with a valid sleep duration (or 0), it indicates that the `SLP` status was
    self-inflicted (required to implement Pokémon Showdown's "Sleep Clause Mod")
  - when combined with `PSN` it indicates that the Pokémon is actually badly poisoned (required in
    order to send the same incorrect protocol messages as Pokémon Showdown - the Toxic volatile
    alone isn't sufficient in compatibility mode because it gets lost on switch)

#### `Volatiles`

Active Pokémon can have ["volatile" status
conditions](https://pkmn.cc/bulba/Status_condition#Volatile_status) (called ["battle
status"](https://pkmn.cc/pokered/constants/battle_constants.asm#L73) bits in pret), all of which are
boolean flags that are cleared when the Pokémon faints or switches out:

| pkmn           | Pokémon Red (pret)         | Pokémon Showdown   |
| -------------- | -------------------------- | ------------------ |
| `Bide`         | `STORING_ENERGY`           | `bide`             |
| `Thrashing`    | `TRASHING_ABOUT`           | `lockedmove`       |
| `MultiHit`     | `ATTACKING_MULTIPLE_TIMES` | `Move#multihit`    |
| `Flinch`       | `FLINCHED`                 | `flinch`           |
| `Charging`     | `CHARGING_UP`              | `twoturnmove`      |
| `Binding`      | `USING_TRAPPING_MOVE`      | `partiallytrapped` |
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
[Confusion](https://pkmn.cc/bulba/Confusion_(status_condition)) (duration),
[Toxic](https://pkmn.cc/bulba/Toxic_(move)) (counter),
[Transform](https://pkmn.cc/bulba/Transform_(move)) (identity), and
[Disable](https://pkmn.cc/bulba/Disable_(move)) (move and duration), and multi-hit attacks all
require additional information that's also stored in the `Volatiles` structure. `MultiHit` isn't
strictly required to be stored as it should always be 0 after updates barring errors, however it's
convenient to maintain as it maps neatly to the cartridge and is effectively "free" space-wise due
to padding.

The `state` field of `Volatiles` is effectively treated as a union:

- if `volatiles.Bide` is set, `volatiles.data.state` reflects the total accumulated Bide damage
- otherwise, `volatiles.data.state` reflects the last computed move accuracy (required to implement
  the [Rage and Thrash / Petal Dance accuracy bug](https://www.youtube.com/watch?v=NC5gbJeExbs))

#### `Stats` / `Boosts`

[Stats](https://pkmn.cc/bulba/Stat) and [boosts (stat
modifiers)](https://pkmn.cc/bulba/Stat#Stat_modifiers) are stored logically, with the exception that
boosts should always range from `-6`...`6` instead of `1`...`13` as on the cartridge.

### `Move` / `Move.Data`

`Move` serves as an identifier for a unique [Pokémon move](https://pkmn.cc/bulba/Move) that can be
used to retrieve `Move.Data` with information regarding base power, accuracy, and type. As covered
earlier, PP information isn't strictly necessary in Generation I so is dropped. `Move.None` exists
as a special sentinel value to indicate `null`. Move PP data is only included for testing and isn't
necessary for the actual engine implementation.

In order to workaround various [Pokémon Showdown bugs](#bugs) and to support its protocol in logs,
additional information is stored in `Move.Data` (`targets`) about what Pokémon Showdown believes the
`Move.Target` to be (despite the concept of targeting not existing until Generation III when Double
battles were introduced). More specifically, a move's "targeting" status is required in various
places to determine which protocol messages to print.

| pkmn        | Pokémon Showdown |
| ----------- | ---------------- |
| `AllOthers` | `allAdjacent`    |
| (`Self`)    | `allyTeam`       |
| `Any`       | `any`            |
| `Other`     | `normal`         |
| `RandomFoe` | `randomNormal`   |
| `Depends`   | `scripted`       |
| `Self`      | `self`           |

### `Species` / `Species.Data`

`Species` just serves as an identifier for a unique [Pokémon
species](https://pkmn.cc/bulba/Pokémon_species_data_structure_(Generation_I)) as the base stats of a
species are already accounted for in the computed stats in the `Pokemon` structure and nothing in
battle requires these to be recomputed. Similarly, Type is unnecessary to include as it's also
already present in the `Pokemon` struct. `Species.None` exists as a special sentinel value to
indicate `null`. `Species.Data` is only included for testing and isn't necessary for the actual
engine implementation, outside of `Species.CHANCES` which is required as the base speed / 2 of the
species is necessary for computing critical hit probability.

### `Type` / `Types` / `Effectiveness`

The [Pokémon types](https://pkmn.cc/bulba/Type) are enumerated by `Type`. `Types` represents a tuple
of 2 types, but due to limitations in Zig this can't be represented as a `[2]Type` array and thus
instead takes the form of a packed struct. `Effectiveness` serves as an enum for tracking a moves
effectiveness - like the cartridge, effectiveness is stored as `0`, `5`, `10`, and `20`
(technically only a 2-bit value is required, but as with `Types` Zig only allows a minimum of a byte
to be stored at each address of an array).

The 'precedence' of the various type match-ups matters beyond just the [dual-type damage
misinformation
glitch](https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Dual-type_damage_misinformation) -
type effectiveness modifiers are applied based on the (haphazard) ordering of the effectiveness
table as opposed to first applying modifiers for a species's first type and then second type. The
engine maintains a `Type.PRECEDENCE` table with just the match-ups that are relevant in game
(certain type combinations can't crop up with the limited Generation I species pool and as such are
pruned for efficiency) and only looks up precedence when necessary to minimize expensive searches.
Pokémon Showdown doesn't implement type precedence.

### `Chance` / `Actions` / `Action` / `Durations` / `Duration`

TODO

### `Calc` / `Overrides` / `Summaries` / `Summary`

TODO

## Information

The information of each field required for mechanics (in terms of [bits of
entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))) is as follows:

| Data            | Range     | Bits |     | Data              | Range    | Bits |
| --------------- | --------- | ---- | --- | ----------------- | -------- | ---- |
| **seed**        | 0...255   | 8    |     | **turn**          | 1...1000 | 10   |
| **team index**  | 1...6     | 3    |     | **move index**    | 1...4    | 2    |
| **species**     | 1...151   | 8    |     | **move**          | 1...165  | 8    |
| **stat**        | 1...999   | 10   |     | **boost**         | 0...13   | 4    |
| **level**       | 1...100   | 7    |     | **volatiles**     | *17*     | 17   |
| **bide**        | 0...65635 | 16   |     | **substitute**    | 0...179  | 8    |
| **confusion**   | 0...5     | 3    |     | **toxic**         | 0...31   | 5    |
| **multi hits**  | 0...5     | 3    |     | **base power**    | 0...40   | 6    |
| **base PP**     | 1...8     | 3    |     | **PP Ups**        | 0...3    | 2    |
| **PP**          | 0...64    | 7    |     | **HP / damage**   | 0...704  | 10   |
| **status**      | 0...13    | 4    |     | **effectiveness** | 0...3    | 2    |
| **type**        | 0...15    | 4    |     | **accuracy**      | 6...20   | 4    |
| **disabled**    | 0...8     | 4    |     | **DVs**           | 0...15   | 4    |
| **move effect** | 0..66     | 7    |     | **attacks**       | 0..4     | 3    |
| **crit chance** | 7..65     | 6    |     | **transform**     | 0..15    | 4    |
| **target**      | 0..4      | 3    |     |                   |          |      |

From this one can determine the minimum bits[^1] required to store each data structure to determine
how much overhead the preceding representations have after taking into consideration [alignment &
padding](https://en.wikipedia.org/wiki/Data_structure_alignment) and
[denormalization](https://en.wikipedia.org/wiki/Denormalization):

- **`Pokemon`**: 5× stats (`50`) + 4× move slot (`60`) + HP (`10`) + status (`4`) + species (`8`) +
  types (`8`) + level (`7`)
- **`ActivePokemon`**: 4× stats (`40`) + 4× move slot (`60`) + 6× boosts (`24`) + volatile data
  (`35`) + volatiles (`17`) + species (`8`) + types (`8`) + disabled (`6`) + transform (`4`)
  - the active Pokémon's stats/species/move slots/types may change in the case of Transform
  - the active Pokémon's types may change due to Conversion
  - the active Pokémon's level and current and max HP can always be referred to the `Pokemon`
    struct
- **`Side`**: `ActivePokemon` + 6× `Pokemon` + active (`3`) + last used (`8`) + last selected
  (`8`) + counterable (`1`) + last move index (`3`)
  - `order` doesn't need to be stored as the party can always be rearranged as switches occur
- **`Battle`**: 6× `Side` + seed (9× `8` + `4`) + turn (`10`) + last damage (`10`)
- **`Type.CHART`**: attacking types (`15`) × defending types (`15`) × effectiveness (`2`)[^2]
- **`Type.PRECEDENCE`**: 29× attacking type (`4`) + defending type (`4`) pairs
- **`Moves.DATA`**: 165× base power (`6`) + effect (`7`) + accuracy (`4`) + type (`4`) + target
  (`3`)
- **`Species.CHANCES`**: 151× crit chance (`6`)

| Data              | Actual bits | Minimum bits | Overhead |
| ----------------- | ----------- | ------------ | -------- |
| `Pokemon`         | 192         | 147          | 30.6%    |
| `ActivePokemon`   | 256         | 202          | 26.7%    |
| `Side`            | 1472        | 1107         | 33.0%    |
| `Battle`          | 3088        | 2310         | 33.7%    |
| `Type.CHART`      | 1800        | 450          | 300.0%   |
| `Type.PRECEDENCE` | 232         | 232          | 0.0%     |
| `Moves.DATA`      | 5280        | 3960         | 33.3%    |
| `Species.CHANCES` | 1208        | 906          | 33.3%    |

In the case of `Type.CHART`/`Type.PRECEDENCE`/`Moves.DATA`/`Species.CHANCES`, technically only the
values which are used by any given simulation are required, which could be as low as 1 in both
circumstances (e.g. all Normal Pokémon each only using the single move Tackle), though taking into
consideration the worst case all Pokémon types are required and 48 moves. The `Moves.DATA` array
could be eliminated and instead the `Move` data actually required by each `Pokemon` could be placed
beside the `MoveSlot`, though this is both less general and adds unnecessary complexity.

[^1]: For data with lower cardinality it's possible to save memory by ordinalizing the values and
turning them into indices into a lookup table (e.g. encode all possible move base powers in a lookup
table and store the index into that table instead of the actual base power). While this approach may
minimize the absolute memory used, performance is more likely to suffer as the goal is to minimize
un-cached memory lookups, not total memory usage.

[^2]: Instead of storing as a sparse multi-dimensional array the type chart could instead only
[store values which are not normal
effectiveness](https://github.com/pret/pokered/blob/master/data/types/type_matchups.asm) in 820 bits
as 82× attacking type (`4`) + defending type (`4`) + non-Normal effectiveness (`2`). This would
avoid having to do two memory lookups at the cost of a longer time scanning, but the second lookup
should already be fast due to locality of reference meaning it's likely to already be in the cache.
This approach would also render `Type.PRECEDENCE` unnecessary.

## Layout

The precise layout of the engine's data structures is important to those implementing driver code,
as clients must directly probe the engine's state through these structures (i.e. the pkmn engine
doesn't produce an equivalent to Pokémon Showdown's `|request|` protocol message, this information
must be gleaned through the `Battle` state). Useful size and offset information can be found in
the [`layout.json`](../../data/layout.json) which exists to simplify writing driver code.

Documentation of the wire protocol used for protocol message logging when `-Dlog` is enabled can be
found in [PROTOCOL.md](../../../docs/PROTOCOL.md). Note that the
[`pkmn-debug`](../../../README.md#pkmn-debug) tool exists to display the binary protocol and battle
data in the browser for ease of debugging.

### `Battle`

| Start   | End     | Data                | Description                                            |
| ------- | ------- | ------------------- | ------------------------------------------------------ |
| 0       | 184     | [`sides[0]`](#side) | Player 1's side                                        |
| 184     | 368     | [`sides[1]`](#side) | Player 2's side                                        |
| 368     | 370     | `turn`              | The current turn number                                |
| 370     | 372     | `last_damage`       | The last damage dealt by either side                   |
| 372     | 374-376 | `last_moves`        | Details about the last move selected/used by each side |
| 374-376 | 384     | `rng`               | The RNG state                                          |

- the current `turn` is 2 bytes, written in native-endianness
- `last_moves` layout depends on whether or not Pokémon Showdown compatibility mode is enabled
  (`-Dshowdown`). In either case it stores the last selected move index and last executed move for
  each player (required to detect desyncs). In the case of the move index, 0 is used as an empty
  value and 1-4 represent actual moves:
  - if `showdown` is enabled byte 372 is used to store the last selected move index of `side[0]` and
    byte 373 is used to store whether or not the side's last executed move would have been considered
    "counterable"; and bytes 374 and 375 store the same information for `side[1]`
  - otherwise the first 4 bits of byte 372 stores the last selected move index of `side[0]` and the
    next 4 bits store whether that side's last executed move would have been considered
    "counterable", with the same information for `side[1]`'s being stored in the second byte
- the `rng` depends on whether or not Pokémon Showdown compatibility mode is enabled (`-Dshowdown`):
  - if `showdown` is enabled, the RNG state begins on byte 376 and consists of a 64-bit seed,
    written in native-endianness
  - otherwise the RNG state begins on byte 374 and consists of the 9 bytes of the seed followed by
    the index pointing to which byte of the seed is currently being used

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

- `order` is a 6 byte array where `order[i]` represents the "slot" of `pokemon[i]`, where the slot
  is usually a unique value from 1 to 6 but can be 0 in situations where a player brings less than six
  Pokémon to battle (note however that if `order[i]` is 0 than for all j > 0 `order[i+j]` **must**
  equal 0)

### `ActivePokemon`

| Start | End | Data                               | Description                                                |
| ----- | --- | ---------------------------------- | ---------------------------------------------------------- |
| 0     | 2   | `stats.hp`                         | The active Pokémon's computed max HP stat                  |
| 2     | 4   | `stats.atk`                        | The active Pokémon's modified Attack stat                  |
| 4     | 6   | `stats.def`                        | The active Pokémon's modified Defense stat                 |
| 6     | 8   | `stats.spe`                        | The active Pokémon's modified Speed stat                   |
| 8     | 10  | `stats.spc`                        | The active Pokémon's modified Special stat                 |
| 10    | 11  | `species`                          | The active Pokémon's species                               |
| 11    | 12  | `type1`/`type2`                    | The active Pokémon's types                                 |
| 12    | 13  | `boosts.atk`/`boosts.def`          | The active Pokémon's Attack and Defense boosts             |
| 13    | 14  | `boosts.spe`/`boosts.spd`          | The active Pokémon's Speed and Special boosts              |
| 14    | 15  | `boosts.accuracy`/`boosts.evasion` | The active Pokémon's Accuracy and Evasion boosts           |
| 15    | 16  | -                                  | *Zero padding*                                             |
| 16    | 24  | [`volatiles`](#volatiles-1)        | The active Pokémon's volatile statuses and associated data |
| 24    | 25  | `moves[0].id`                      | The active Pokémon's second move                           |
| 25    | 26  | `moves[0].pp`                      | The PP of the active Pokémon's first move                  |
| 26    | 27  | `moves[1].id`                      | The active Pokémon's second move                           |
| 27    | 28  | `moves[1].pp`                      | The PP of the active Pokémon's second move                 |
| 28    | 29  | `moves[2].id`                      | The active Pokémon's third move                            |
| 29    | 30  | `moves[2].pp`                      | The PP of the active Pokémon's third move                  |
| 30    | 31  | `moves[3].id`                      | The active Pokémon's fourth move                           |
| 31    | 32  | `moves[3].pp`                      | The PP of the active Pokémon's fourth move                 |

- the active Pokémon's `stats.hp` is always identical to the corresponding stored Pokémon's `stats.hp`
- `boosts` and `types` includes bytes which store two 4-bit fields each

#### `Volatiles`

> **NOTE:** The offsets in the following table represent *bits* and **not** bytes.

| Start | End | Data                | Description                                                 |
| ----- | --- | ------------------- | ----------------------------------------------------------- |
| 0     | 1   | `Bide`              | Whether the "Bide" volatile status is present               |
| 1     | 2   | `Thrashing`         | Whether the "Thrashing" volatile status is present          |
| 2     | 3   | `MultiHit`          | Whether the "MultiHit" volatile status is present           |
| 3     | 4   | `Flinch`            | Whether the "Flinch" volatile status is present             |
| 4     | 5   | `Charging`          | Whether the "Charging" volatile status is present           |
| 5     | 6   | `Binding`           | Whether the "Binding" volatile status is present            |
| 6     | 7   | `Invulnerable`      | Whether the "Invulnerable" volatile status is present       |
| 7     | 8   | `Confusion`         | Whether the "Confusion" volatile status is present          |
| 8     | 9   | `Mist`              | Whether the "Mist" volatile status is present               |
| 9     | 10  | `FocusEnergy`       | Whether the "FocusEnergy" volatile status is present        |
| 10    | 11  | `Substitute`        | Whether the "Substitute" volatile status is present         |
| 11    | 12  | `Recharging`        | Whether the "Recharging" volatile status is present         |
| 12    | 13  | `Rage`              | Whether the "Rage" volatile status is present               |
| 13    | 14  | `LeechSeed`         | Whether the "LeechSeed" volatile status is present          |
| 14    | 15  | `Toxic`             | Whether the "Toxic" volatile status is present              |
| 15    | 16  | `LightScreen`       | Whether the "LightScreen" volatile status is present        |
| 16    | 17  | `Reflect`           | Whether the "Reflect" volatile status is present            |
| 17    | 18  | `Transform`         | Whether the "Transform" volatile status is present          |
| 18    | 21  | `confusion`         | The remaining turns of confusion                            |
| 21    | 24  | `attacks`           | The number of attacks remaining                             |
| 24    | 40  | `state`             | A union of either: <ul><li>the total accumulated damage from Bide</li><li>the overwritten accuracy of certain moves</li></ul> |
| 40    | 48  | `substitute`        | The remaining HP of the Substitute                          |
| 48    | 52  | `transform`         | The identity of whom the active Pokémon is transformed into |
| 52    | 56  | `disabled_duration` | The remaining turns the move is disabled                    |
| 56    | 59  | `disabled_move`     | The move slot (1-4) that's disabled                        |
| 59    | 64  | `toxic`             | The number of turns toxic damage has been accumulating      |

### `Pokemon`

| Start | End | Data            | Description                                |
| ----- | --- | --------------- | ------------------------------------------ |
| 0     | 2   | `stats.hp`      | The Pokémon's computed max HP stat         |
| 2     | 4   | `stats.atk`     | The Pokémon's unmodified Attack stat       |
| 4     | 6   | `stats.def`     | The Pokémon's unmodified Defense stat      |
| 6     | 8   | `stats.spe`     | The Pokémon's unmodified Speed stat        |
| 8     | 10  | `stats.spc`     | The Pokémon's unmodified Special stat      |
| 10    | 11  | `moves[0].id`   | The Pokémon's first stored move            |
| 11    | 12  | `moves[0].pp`   | The PP of the Pokémon's first stored move  |
| 12    | 13  | `moves[1].id`   | The Pokémon's second stored move           |
| 13    | 14  | `moves[1].pp`   | The PP of the Pokémon's second stored move |
| 14    | 15  | `moves[2].id`   | The Pokémon's third stored move            |
| 15    | 16  | `moves[2].pp`   | The PP of the Pokémon's third stored move  |
| 16    | 17  | `moves[3].id`   | The Pokémon's fourth stored move           |
| 17    | 18  | `moves[3].pp`   | The PP of the Pokémon's fourth stored move |
| 18    | 20  | `hp`            | The Pokémon's current HP                   |
| 20    | 21  | `status`        | The Pokémon's current status               |
| 21    | 22  | `species`       | The Pokémon's stored species               |
| 22    | 23  | `type1`/`type2` | The Pokémon's stored types                 |
| 23    | 24  | `level`         | The Pokémon's level                        |


### `Action`

`Actions` consist of an `Action` for Player 1 followed by an `Action` for Player 2.

> **NOTE:** The offsets in the following table represent *bits* and **not** bytes.

| Start | End | Data                     | Description                                                                     |
| ----- | --- | ------------------------ | ------------------------------------------------------------------------------- |
| 0     | 8   | `damage`                 | The roll to be returned damage (217-255).                                       |
| 8     | 10  | `hit`                    | The roll to be returned for accuracy (1 for miss, 2 for hit).                   |
| 10    | 12  | `critical_hit`           | The roll to be returned for critical hits (1 for no, 2 for yes).                |
| 12    | 14  | `secondary_chance`       | The roll to be returned for secondary chance rolls (1 for no-proc, 2 for proc). |
| 14    | 16  | `speed_tie`              | The player to return for speed ties (1 for Player 1, 2 for Player 2).           |
| 16    | 18  | `confused`               | The roll to be returned for confusion self-hits (1 for no-proc, 2 for proc).    |
| 18    | 20  | `paralyzed`              | The roll to be returned for full paralysis (1 for no-proc, 2 for proc).         |
| 20    | 24  | `duration`               | The roll to be returned for the duration (including for binding moves).         |
| 24    | 40  | [`durations`](#duration) | Values of various durations.                                                    |
| 40    | 44  | `move_slot`              | The roll to be returned for the move slot (1-4, invalid values ignored).        |
| 44    | 48  | `move_slot`              | The roll to be returned for a multi-hit move distribution (2-5).                |
| 48    | 56  | `psywave`                | One greater than the roll to be returned for Psywave damage.                    |
| 56    | 64  | `metronome`              | The move to return for Metronome.                                               |

- for any field a value of 0 is considered to be unset
- **both Player 1 and Player 2 must set the same value for `speed_tie`.**
- `duration` determines the roll for any effect which lasts over multiple turns, whereas `durations` can either be used to
  track how long these effects have lasted (for the purposes of computing probablities with `-Dchance`) or can be used to
  [override](#overrides) (extend or end) the duration of specfic effects with `-Dcalc`.

#### `Duration`

> **NOTE:** The offsets in the following table represent *bits* and **not** bytes.

| Start | End | Data        |
| ----- | --- | ----------- |
| 0     | 3   | `sleep`     |
| 3     | 6   | `confusion` |
| 4     | 10  | `disable`   |
| 10    | 13  | `attacking` |
| 13    | 16  | `binding`   |

- the meaning of each field depends on the context in which `Duration` appears:
  - within `Chance` `actions`, the durations tracked refer to the number of turns a Pokémon has been
    observed to be under an effect
  - within `Overrides` `actions`, the durations refer to the value the next `Chance` `actions`
    should be made to take on
  - within `Overrides` `durations`, the durations serve as a mask to determine to whether or not the
    durations in `Overrides` `actions` should be considered to be set or not
◊
### `Overrides`

| Start | End | Data                        | Description                                                                           |
| ----- | --- | --------------------------- | ------------------------------------------------------------------------------------- |
| 0     | 8   | [`action.p1`](#action)      | Rolls to force Player 1's RNG to return for specific events.                          |
| 8     | 16  | [`action.p2`](#action)      | Rolls to force Player 2's RNG to return for specific events.                          |
| 16    | 18  | [`durations.p1`](#duration) | Whether or not to modify Player 1's effect durations to match `actions.p1.durations`. |
| 18    | 20  | [`durations.p2`](#duration) | Whether or not to modify Player 2's effect durations to match `actions.p1.durations`. |
| 20    | 24  | -                           | *Zero padding*                                                                        |

### `Summaries`

| Start | End | Data               | Description                                                                     |
| ----- | --- | ------------------ | ------------------------------------------------------------------------------- |
| 0     | 2   | `p1.damage.base`   | Player 1's base computed damage before the damage roll is applied.              |
| 2     | 4   | `p1.damage.final`  | Player 1's final computed damage that gets applied to the Pokémon.              |
| 4     | 6   | `p1.damage.capped` | Whether higher damage from Player 1 will saturate / result in the same outcome. |
| 6     | 8   | `p2.damage.base`   | Player 2's base computed damage before the damage roll is applied.              |
| 8     | 10  | `p2.damage.final`  | Player 2's final computed damage that gets applied to the Pokémon.              |
| 10    | 12  | `p2.damage.capped` | Whether higher damage from Player 2 will saturate / result in the same outcome. |

## Bugs

In addition to its alternative [RNG semantics](#rng), Pokémon Showdown's implementation of the first
generation of Pokémon contains a number bugs, [many of which are known and have been documented on
Smogon](https://www.smogon.com/forums/posts/5933177/show):

- moves on Pokémon Showdown can do 0 damage instead of failing or causing a [division-by-zero
  freeze](https://pkmn.cc/bulba-glitch-1#Division_by_0).
- Pokémon Showdown doesn't implement type effectiveness precedence correctly.
- Pokémon Showdown checks for type and OHKO immunity before accuracy.
- Confusion self-hits use the wrong damage formula resulting in off-by-one errors (and also fail to
  account for an opponent's Reflect). Furthermore, the confusion self-hit damage erroneously gets
  inflicted on the confused user's substitute if the confused user had been attempting to use a
  self-targeting move. Finally, Pokémon Showdown erroneously considers the *uncapped* self-hit
  damage for the purposes of tracking the battle's last damage.

Beyond these general bugs, several move effects are implemented incorrectly by Pokémon Showdown.
Some of these moves are [too fundamentally broken to be implemented](#unimplementable) by the pkmn
engine, but the following moves have their broken behavior preserved in `-Dshowdown` mode:

- **Bide**: Bide's damage can overflow if OHKO moves are involved because OHKO moves work by setting
  the damage to 65535 - Pokémon Showdown doesn't implement this overflow and instead lets Bide's
  damage grow unbounded. Additionally, if the opponent faints after Bide inflicts damage on Pokémon
  Showdown residual damage incorrectly still gets applied to Bide's user.
- **Counter**: On Pokémon Showdown choices made while sleeping (which shouldn't have been
  registered) can erroneously cause Counter to trigger Desync Clause Mod behavior. Additionally,
  because Pokémon Showdown neglects to zero the last battle damage if a move misses due to immunity
  or invulnerability Counter occasionally works on Pokémon Showdown when it should fail.
- **Leech Seed**: Leech Seed fails to heal its source side if a seeded target faints due to
  recoil/crash damage on Pokémon Showdown.
- **Pay Day**: Pay Day should still scatter coins if it hits (but doesn't break) and opponent's
  Substitute but doesn't on Pokémon Showdown.
- **Flinch**: Flinching doesn't get cleared during move selection on Pokémon Showdown and is
  instead cleared in Pokémon Showdown's "residual" phase, meaning the flinch status gets erroneously
  preserved across fainting (as fainting triggers Pokémon Showdown's "instaswitch" behavior which
  skips end-of-turn residuals).
- **Rage**: Rage boosts should still result in burn/paralysis [stat modification
  errors](https://pkmn.cc/bulba-glitch-1#Stat_modification_errors) but don't on Pokémon Showdown.
  Furthermore, Pokémon Showdown only builds Rage for Disable/Explosion (hit/miss) when attacking
  into a Substitute instead of all moves. Pokémon Showdown also implements the [Rage and Thrash /
  Petal Dance accuracy bug]( https://www.youtube.com/watch?v=NC5gbJeExbs) incorrectly, as the
  accuracy only gets written when the volatile is present which can lead to incorrect accuracy
  values on turns where Rage is used on the same turn as a move which modifies accuracy or evasion.
- **Thrash** / **Petal Dance**: once a Pokémon is locked into a thrashing move they lose all speed
  ties on Pokémon Showdown (due to the fact that if they win the speed tie their action then gets
  "changed" and inserted back into the queue after their opponent's action). Pokémon Showdown also
  implements accuracy incorrectly, as covered earlier.
- **Freeze** / **Sleep**: Pokémon Showdown requires a move to be selected when a Pokémon is frozen
  or sleeping and uses that in the event that the status is removed while on the cartridge no
  selection is possible and no turn exists for the thawed/woken Pokémon to act except in the case of
  a Fire-type move thawing a slower Pokémon (which should result in the [Freeze top move selection
  glitch](https://glitchcity.wiki/Freeze_top_move_selection_glitch), which isn't implemented and
  would also likely be incorrect if it were to be implemented due to how Pokémon Showdown
  incorrectly saves arbitrary moves with its choice selection semantics). Furthermore, thrashing
  volatiles shouldn't be cleared if the user misses a turn due to freeze / sleep.
- **Hyper Beam**: due to improperly implemented selection mechanics, the [Hyper Beam
  automatic-selection glitch](https://glitchcity.wiki/Hyper_Beam_automatic_selection_glitch) does
  not exist on Pokémon Showdown. Additionally, Hyper Beam being able to cause [Freeze permanent
  helplessness](https://pkmn.cc/bulba-glitch-1#Hyper_Beam_.2B_Freeze_permanent_helplessness) isn't
  implement by Pokémon Showdown.
- **Roar** / **Whirlwind**: these moves can miss on Pokémon Showdown (and advance the RNG when
  checking) which is incorrect (these moves should always fail, but don't check accuracy or advance
  the RNG). More importantly, these moves should *not* cause the tracked last battle damage to be
  zeroed, but on Pokémon Showdown they do. These should also `|-fail|...|[still]` instead of doing
  nothing.
- **Substitute**: in addition to the [Substitute + Confusion
  glitch](https://pkmn.cc/bulba-glitch-1#Substitute_.2B_Confusion_glitch) not being implemented
  correctly (covered earlier), the [Substitute 1/4
  glitch](https://glitchcity.wiki/Substitute_%C2%BC_HP_glitch) also fails in many cases due to
  Pokémon Showdown implementing the health check based on floating point division instead of integer
  division like on the cartridge (meaning the Substitute 1/4 glitch only occurs if the Pokémon's
  maximum HP is evenly divisible by 4). Substitute also incorrectly blocks Dream Eater on
  Pokémon Showdown and incorrectly still heals 1 HP for any draining moves if the attack does 0
  damage. Finally, Pokémon Showdown uses a `subFainted` field to track whether a Substitute was
  broken to know when to nullify a move's effect, only it doesn't get cleared at the end of
  the turn and can result in incorrect behavior on subsequent turns with the moves Mirror Move and
  Metronome that invoke `runMove` (which is where `subFainted` gets cleared) on the user but skips
  calling it for the eventual true target.

In addition to numerous cases where Pokémon Showdown uses the wrong type of message (e.g. `|-fail`
vs. `|-miss|` vs. `|-immune|`, e.g. in the case of Leech Seed) which aren't documented here, Pokémon
Showdown sometimes gets message ordering incorrect (which doesn't effect the outcome of the battle,
only pedantic UI correctness):

- **Rage**: Rage should report the `|-boost|` before the Disable `|-miss|`, not after.
- **Haze**: Haze clears the status/volatiles in an incorrect order.
- **Teleport**: Teleport should `|-fail|...|[still]` instead of doing nothing.
- **Twineedle**: the `|-hitcount|` ("Hit 2 times") should come before the `|-status|` message, not
  after.
- **Thrash** / **Petal Dance**: confusion should silently get applied before the `|move|` message,
  not after.

Pokémon Showdown also implements a number of modifications to the cartridge (usually but not always
called out in the `|rule|` section at the beginning of a battle's log):

- **Sleep Clause Mod**: players are prevented from putting more than one of their opponent's Pokémon
  to sleep at a time (usage of the move fails).
- **Freeze Clause Mod**: players are prevented from freezing more than one of their opponent's
  Pokémon at a time (usage of the move fails).
- **Desync Clause Mod**: If the usage of a move would cause a desync it instead causes a failure.
  However, this mod doesn't trigger for [**division by
  zero**](https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Division_by_0) - instead of failing,
  Pokémon Showdown silently patches the damage calculation to divide by 1 instead of 0. The
  definition of the Desync Clause Mod should be extended or the code should be changed to fail
  instead of succeeding in these cases.
- **Endless Battle Clause**: Prematurely ends the battle in a tie after 1000 turns or in certain
  situations where it's trivially detectable that no progress can be made.
- **Switch Priority Clause Mod**: When both player switch out their Pokémon at the same time the
  faster Pokémon switches first. This mod is **not broadcast at the start of the battle in the
  `|rule|` section** in Generation I (or II) as the actual order of switches here doesn't have
  competitive implications like it does in Generation III, but it's still contrary to how the games
  work where the [host (Player 1)'s Pokemon would switch
  first](https://www.smogon.com/forums/posts/5989318/show).

Pokémon Showdown enforces several clauses *before* the battle: **Cleric Clause** (all Pokémon must
have full HP and PP, and not have any status conditions prior to the battle), **Stat Tradeback
Clause** (Pokémon may not have moves obtained from trading back from Pokémon Gold/Silver/Crystal,
though may have DV spreads which would otherwise be unobtainable), **Species Clause** (players may
not have more than one of the same Pokémon species on their team) and bans specific moves via
**Evasion Clause**, **OHKO Clause**, and the **Invulnerability Clause** - none of these are
implemented by the pkmn engine as they can all be accomplished at a higher level by the client.
Similarly, Pokémon Showdown's UI mods, the **HP Percentage Mod** which displays the HP percentage of
a Pokémon instead of pixel information and the **Move Effectiveness Mod** which corrects for the
[dual-type damage misinformation
glitch](https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Dual-type_damage_misinformation) or
the correction to [Poison/Burn animation with 0
HP](https://pkmn.cc/bulba/List_of_glitches_(Generation_I)#Poison.2FBurn_animation_with_0_HP) are all
left up to a client to support.

### Unimplementable

Numerous moves on Pokémon Showdown are broken not simply due to local issues in the implementation
of their effects but instead due to **global issues** related to fundamental mechanics such as
[broken move selection](https://www.smogon.com/forums/posts/8655897/show), using move name instead
of slot to determine move identity, implementing volatile statuses incorrectly or not understanding
how moves which call other moves work means that it isn't possible to completely implement Pokémon
Showdown's behavior for the following moves (the pkmn engine attempts to reproduce as much of the
behavior that can be reproduced without making data structure changes or dramatically deviating from
the correct control flow):

- **Wrap**: Binding moves like Wrap are implemented on Pokémon Showdown with an artificial
  `partialtrappinglock` volatile as opposed to how it works on the cartridge which simply relies on
  the `Binding` volatile of the opponent. This mistake results in choice locking not being reported
  properly when the binding move was initiated via another move such as Metronome or Mirror Move.
  Binding moves also have some local implementation issues - on Pokémon Showdown a bound Pokémon
  still gets a turn under the [trapping sleep
  glitch](https://glitchcity.wiki/Trapping_move_and_sleep_glitch), Wrap does 0 damage against
  Ghost-type Pokémon instead of properly respecting immunity, and binding effects are handled in the
  wrong order in the code which results in either out of order messaging or, more consequentially,
  Pokémon using Rage/Bide or Thrashing/Charging moves being incorrectly forced to skip a turn when
  the Pokémon using the Binding move switches.
- **Mimic**: Pokémon Showdown checks that the user of Mimic has Mimic in one of their move slots,
  which means Mimic legally called via Metronome or Mirror Move only works if the user also has
  Mimic (and the moved mimicked by Mimic called via Metronome / Mirror Move erroneously overrides
  the Mimic move slot instead of the Metronome / Mirror Move move slot). Furthermore, because
  Pokémon Showdown deducts PP based on a move's name instead of slot, if Mimic copies a move the
  Pokémon already knows, PP deduction for using either the original move of the mimicked move
  instead deducts PP for whichever appears at the lower move slot index and the PP is allowed to go
  negative (effectively allowing for infinite PP use). Pokémon Showdown also doesn't deduct PP from
  using Transform if it was copied by Mimic.
- **Mirror Move**: As covered earlier, both Substitute and Binding moves misbehave when used via
  Mirror Move (though Pokémon Showdown has its own weird behavior and doesn't implement the [partial
  trapping move Mirror Move
  glitch](https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch) that exists
  on the cartridge). Additionally, Pokémon Showdown sets the last used move every turn a Pokémon is
  Thrashing instead of just on the turn it's actually selected meaning Mirror Move sometimes
  successfully mirrors a Thrashing move when it should fail. Finally, if Mirror Move copies Struggle
  it shouldn't deduct PP but on Pokémon Showdown it does.
- **Metronome**: In addition to the issues with binding moves and Substitute, Metronome and Mirror
  Move can't mutually call each other more than 3 times in a row without causing the Pokémon
  Showdown simulator to crash due to defensive safety checks that don't exist on the cartridge.
- **Transform**: Transform screws up the effect of Disable, because on Pokémon Showdown, Disable
  prevents moves of a given *name* from being used (e.g. "Water Gun") as opposed to moves in a
  specific *slot* (e.g. the second move slot), and a Pokémon's moves can change after Transform
  (this isn't an issue with Disable + Mimic because Mimic happens to replace the same slot).
  Transform also has a bad interaction with Pokémon Showdown's buggy Haze implementation, as Haze on
  Pokémon Showdown doesn't copy unmodified stats, leaving the Transformed Pokémon with incorrect
  stats. Furthermore, transforming and then using Mirror Move / Metronome can result in [glitchy
  behavior and
  softlocks](https://pkmn.cc/bulba/Transform_glitches#Transform_.2B_Mirror_Move.2FMetronome_PP_error)
  which Pokémon Showdown doesn't implement.

Importantly, Pokémon Showdown's **speed tie RNG mechanics are unimplementable** in the pkmn engine
as they rely on internal implementation decisions made by Pokémon Showdown that are impossible to
replicate without also mimicking Pokémon Showdown's (incorrect) event and "action" systems (see
below).

## RNG

**The pkmn engine aims to match the cartridge's RNG frame-accurately**, in that provided with the
same initial seed and inputs it should produce the same battle playout as the Pokémon Red cartridge.
**Pokémon Showdown doesn't correctly implement frame-accurate RNG in any generation**, and along
with the [bugs](#bugs) discussed earlier this results in large differences in the codebase. Because
the pkmn engine aims to be as compatible with Pokémon Showdown as possible when in `-Dshowdown`
compatibility mode, the implications of these differences are outlined below:

- **RNG**: Pokémon Showdown uses the RNG from Generation V & VI in every generation, despite
  the seeds and algorithm being different. Pokémon Red uses a simple 8-bit RNG with 9 distinct
  seeds generated when the link connection is established, whereas Pokémon Showdown uses a 64-bit
  RNG with a 32-bit output.
- **Algorithm**: As detailed in the table below, the algorithm used by Pokémon Showdown in the
  places randomness is required is often different than on the cartridge, so even if Pokémon
  Showdown were using the correct RNG the values would still diverge (including using a completely
  incorrect distribution for multi-hit moves).
- **Bias**: Pokémon Showdown often needs to reduce its 32-bit output range to a smaller range in
  order to implement various effects, and does so using a [biased integer multiplication
  method](http://www.pcg-random.org/posts/bounded-rands.html) as opposed to debiasing via rejection
  sampling to ensure uniformity as is done on the cartridge. This means that certain values are
  fractionally more likely to be chosen than others, though this bias is usually quite small (e.g.
  in the case of Metronome instead of selecting moves with an equal $1\over163$ chance, Pokémon
  Showdown selects some with a $1\over2^{32}$ greater chance than others).
- **Order of operations**: RNG calls effectively introduce something similar to a ["memory
  barrier"](https://en.wikipedia.org/wiki/Memory_barrier) in that they must be sequenced correctly
  (though operations which occur between them may happen in any order). Pokémon Showdown violates
  this by introducing additional operations (see below) and changing up the order of existing
  operations (e.g. choosing to check for hit/miss, determine the number of hits for moves with
  multiple hits, determine if a move hit critically and then the damage instead of checking for
  hit/miss and determining number of hits *after* the other two). While it's often desirable to
  rearrange code for performance or to improve readability this can only be done if it doesn't
  affect accuracy.
- **Speed-ties**: In addition to [breaking switch-in speed ties with an RNG
  call](https://www.smogon.com/forums/threads/adv-switch-priority.3622189/), speed ties in Pokémon
  Showdown actually result in a large number of spurious frame advancements due to the internal
  implementation details of Pokémon Showdown's event and "action" systems. Ultimately, without
  keeping track of all of the handlers for the internal events Pokémon Showdown invents and
  implementing the same "action" system, matching Pokémon Showdown's RNG in the presence of speed
  ties proves impossible, and thus the reference Pokémon Showdown implementation pkmn engine aims to
  match has been [patched](../../../docs/TESTING.md#patches) to change this behavior.
- **Effects**: Pokémon Showdown occasionally incorrectly inserts RNG calls in move effect handlers
  when they're not relevant:
  - Roar / Whirlwind roll to hit and can "miss" as opposed to simply failing

Finally, the **initial 9-byte seed for link battles on Pokémon Red can't include bytes larger than
the `SERIAL_PREAMBLE_BYTE`**, so must be in the range $\left[0, 252\right]$. This has implications
on the first 9 random numbers generated during the battle and has [**non-trivial competitive
implications**](https://www.smogon.com/forums/posts/9068411/show) (at the start of the battle move
effects become more likely, the ["1/256-miss" glitch](https://glitchcity.wiki/1/256_miss_glitch)
can't happen, Player 1 is more likely to win speed ties, etc) that Pokémon Showdown can't replicate
due to everything described earlier.

All of places in the link battle code where randomness is required are outlined below:

| Type                     | Location                 | Description                                                                                                                                                                                               |
| ------------------------ | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Speed Tie**            | `turnOrder`              | Player 1 if $X < 127$, otherwise Player 2                                                                                                                                                                 |
| **Critical Hit**         | `checkCriticalHit`       | <dl><dt>Pokémon Red</dt><dd>Inflict a critical hit if $X' < chance$ where $X'$ is $X$ with its bits rotated left three times</dd><dt>Pokémon Showdown</dt><dd>Critical hit if $X < chance$</dd></dl>      |
| **Damage** (range)       | `randomizeDamage`        | <dl><dt>Pokémon Red</dt><dd>Continue generating until $X' \geq  217$ where $X'$ is $X$ with its bits rotated right once</dd><dt>Pokémon Showdown</dt><dd>Generate $X \in \left[217, 256\right)$</dd></dl> |
| **Hit / Miss**           | `checkHit`               | Hit if $X < scaledAccuracy$                                                                                                                                                                               |
| **Burn** (chance)        | `Effects.burnChance`     | Trigger if $X < 26$ ($77$ for Fire Blast)                                                                                                                                                                 |
| **Confusion** (chance)   | `Effects.confusion`      | Trigger if $X< 25$                                                                                                                                                                                        |
| **Confusion** (duration) | `Effects.confusion`      | <dl><dt>Pokémon Red</dt><dd>Last for $\left(X \land 3\right) + 2$ turns</dd><dt>Pokémon Showdown</dt><dd>Last for $X \in \left[2, 6\right)$ turns</dd></dl>                                               |
| **Confusion** (self-hit) | `beforeMove`             | Trigger if $X \geq 128$                                                                                                                                                                                   |
| **Flinch** (chance)      | `Effects.flinchChance`   | Trigger if $X < 26$ ($77$ for Stomp / Headbutt / Rolling Kick / Low Kick)                                                                                                                                 |
| **Freeze** (chance)      | `Effects.freezeChance`   | Trigger if $X < 26$                                                                                                                                                                                       |
| **Paralysis** (chance)   | `Effects.paralyzeChance` | Trigger if $X< 26$ ($77$ for Body Slam / Lick)                                                                                                                                                            |
| **Paralysis** (full)     | `beforeMove`             | Trigger if $X < 63$                                                                                                                                                                                       |
| **Poison** (chance)      | `Effects.poison`         | Trigger if $X < 52$ ($103$ for Smog / Sludge)                                                                                                                                                             |
| **Sleep** (duration)     | `Effects.sleep`          | <dl><dt>Pokémon Red</dt><dd>Continue generating until $X \land 7 \neq 0$</dd><dt>Pokémon Showdown</dt><dd>Generate $X \in \left[1, 8\right)$</dd></dl>                                                    |
| **Bide** (duration)      | `Effects.bide`           | <dl><dt>Pokémon Red</dt><dd>Last for $\left(X \land 1\right) + 2$ turns</dd><dt>Pokémon Showdown</dt><dd>Last for $X \in \left[2, 4\right)$ turns</dd></dl>                                               |
| **Disable** (move)       | `Effects.disable`        | <dl><dt>Pokémon Red</dt><dd>Continue generating until $X \land 3$ is the index of a non-empty move slot</dd><dt>Pokémon Showdown</dt><dd>Generate $X \in \left[0, \|movesSlots\|\right)$</dd></dl>        |
| **Disable** (duration)   | `Effects.disable`        | <dl><dt>Pokémon Red</dt><dd>Last for $\left(X \land 7\right) + 1$ turns</dd><dt>Pokémon Showdown</dt><dd>Last for $X \in \left[1, 9\right)$ turns</dd></dl>                                               |
| **Metronome** (move)     | `metronome`              | <dl><dt>Pokémon Red</dt><dd>Continue generating until $X$ matches the index of a move which isn't Struggle or Metronome</dd><dt>Pokémon Showdown</dt><dd>Generate $X \in \left[0, \|validMoves\|\right)$, where $validMoves$ is ordered set of moves with  Struggle and Metronome removed <i>(indexes of moves > Metronome are shifted down)</i></dd></dl> |
| **Mimic** (move)         | `Effects.mimic`          | <dl><dt>Pokémon Red</dt><dd>Continue generating until $X \land 3$ is the index of a non-empty move slot</dd><dt>Pokémon Showdown</dt><dd>Generate $X \in \left[0, \|movesSlots\|\right)$</dd></dl>        |
| **Psywave** (power)      | `specialDamage`          | <dl><dt>Pokémon Red</dt><dd>Continue generating until $X < {3\over2} \cdot level$</dd><dt>Pokémon Showdown</dt><dd>Generate $X \in \left[0, {3\over2} \cdot level\right)$</dd></dl>                       |
| **Thrash** (rampage)     | `Effects.thrash`         | <dl><dt>Pokémon Red</dt><dd>Last for $\left(X \land 1\right) + 2$ turns</dd><dt>Pokémon Showdown</dt><dd>Last for $X \in \left[2, 4\right)$ turns</dd></dl>                                               |
| **Thrash** (confusion)   | `beforeMove`             | <dl><dt>Pokémon Red</dt><dd>Last for $\left(X \land 3\right) + 2$ turns</dd><dt>Pokémon Showdown</dt><dd>Last for $X \in \left[2, 6\right)$ turns</dd></dl>                                               |
| **Binding** (duration)   | `Effects.binding`        | <dl><dt>Pokémon Red</dt><dd>Last for $\left(X \land 3\right) + 1$ further turns if $\left(X \land 3\right) < 2$<br /> otherwise last for $\left(Y \land 3\right) + 1$ further turns (reroll)</dd><dt>Pokémon Showdown</dt><dd>Last for $X \in \{2, 2, 2, 3, 3, 3, 4, 5\} - 1$ further turns</dd></dl> |
| **Multi-Hit** (hits)     | `Effects.multiHit`       | *Ibid.*                                                                                                                                                                                                   |
| **Unboost** (chance)     | `Effects.unboost`        | Trigger if $X < 85$                                                                                                                                                                                       |

*In the preceding table,* $X$ *is always in the range* $\left[0, 256\right)$ *for Pokémon Red and for
Pokémon Showdown is always **scaled** from the 32-bit output range of the RNG to either be in that
range or to whichever range is specified by the description.*

## Details

The engine's Generation I mechanics code loosely mirrors the structure and naming of the pret
decompilation of the Pokémon Red source, though has been simplified (e.g. a single method for both
sides as opposed to having separate duplicated code for each) and optimized. Furthermore, the
control flow has been modified to handle both the correct Pokémon Red order of operations and
Pokémon Showdown's order when in compatibility mode - as such, there are many `if (showdown)` blocks
which handle Pokémon Showdown's divergent behavior (this is most evident in `doMove`). The following
table provides a rough mapping between pkmn and Pokémon Red methods:

| pkmn                      | Pokémon Red (pret)                                      |
| ------------------------- | ------------------------------------------------------- |
| `start`                   | `StartBattle`                                           |
| `update`                  | `MainInBattleLoop`                                      |
| `findFirstAlive`          | `findFirstAlive*MonLoop` / `AnyPartyAlive`              |
| `selectMove` / `saveMove` | `selectPlayerMove`                                      |
| `switchIn`                | `SwitchPlayerMon` / `SendOutMon`                        |
| `turnOrder`               | `MainInBattleLoop`                                      |
| `doTurn`                  | `MainInBattleLoop`                                      |
| `executeMove`             | `ExecutePlayerMove`                                     |
| `beforeMove`              | `CheckPlayerStatusConditions`                           |
| `canMove`                 | `CheckIfPlayerNeedsToChargeUp` / `PlayerCanExecuteMove` |
| `decrementPP`             | `DecrementPP`                                           |
| `doMove`                  | `PlayerCalcMoveDamage` / `CalculateDamage`              |
| `checkCriticalHit`        | `CriticalHitTest`                                       |
| `calcDamage`              | `GetDamageVarsForPlayerAttack` / `CalculateDamage`      |
| `adjustDamage`            | `AdjustDamageForMoveType`                               |
| `randomizeDamage`         | `RandomizeDamage`                                       |
| `specialDamage`           | `ApplyAttackToEnemyPokemon`                             |
| `counterDamage`           | `HandleCounterMove`                                     |
| `applyDamage`             | `ApplyDamageToEnemyPokemon` / `AttackSubstitute`        |
| `mirrorMove`              | `MirrorMoveCheck` / `MirrorMoveCopyMove`                |
| `metronome`               | `metronomeCheck` / `MetronomePickMove`                  |
| `checkHit` / `moveHit`    | `MoveHitTest`                                           |
| `checkFaint`              | `HasMonFainted` / `HandlePlayerMonFainted`              |
| `faint`                   | `FaintEnemyPokemon`                                     |
| `handleResidual`          | `HandlePoisonBurnLeechSeed`                             |
| `endTurn` / `checkEBC`    | -                                                       |

Pokémon Red groups move effect handlers together into several groups, these have also been renamed
for clarification in the pkmn engine:

| pkmn            | Pokémon Red (pret)        |
| --------------- | ------------------------- |
| `onBeforeMove`  | `ResidualEffects1`        |
| `onEndMove`     | `ResidualEffects2`        |
| `alwaysHappens` | `AlwaysHappensSideEffect` |
| `isSpecial`     | `SpecialEffects`          |

### Naming

The pkmn engine attempts to adhere to certain naming conventions:

- **`p1`** & **`p2`** always correspond to the `Side` of `Player.P1` and `Player.P2` respectively
- **`player`** is the executing turn `Player` (`hWhoseTurn`) and **`player.foe()`** is their
  opponent
- if `player` (executing turn player) is present then **`side`** always corresponds to their
  `Side` and **`foe`** the opposing `Side`, however `side` can refer to an arbitrary `Side` object
  if there is no `player` in scope (e.g. in helper functions)
- **`target_player`** is a target `Player` whose corresponding `Side` is  **`target`**

## Resources

- [pret/pokered](https://github.com/pret/pokered/) disassembly
- [Gen I Main Battle Function](https://www.smogon.com/forums/posts/5878612/show) - Crystal_
- [Pokemon Showdown!](https://github.com/smogon/pokemon-showdown)
- [List of glitches (Generation
  I)](https://bulbapedia.bulbagarden.net/wiki/List_of_glitches_(Generation_I))
- [Pokémon Showdown RBY Bugs](https://www.smogon.com/forums/posts/5933177/show)
