# Pokémon Generation II: GSC

## Data Structures

The following information is required to simulate a Generation II Pokémon battle:

==**TODO**==

| pkmn                          | Pokémon Red (pret)            | Pokémon Showdown                |
| ----------------------------- | ----------------------------- | ------------------------------- |
| `battle.seed`                 | `Random{Add,Sub}`             | `battle.seed`                   |
| `battle.last_damage`          | `Damage`                      | `battle.lastDamage`             |
| `side.{active,pokemon}`       | `PlayerMonNumber`/`BattleMon` | `side.active`                   |
| `side.team`                   | `PartyMons`                   | `side.pokemon`                  |
| `side.last_used_move`         | `PlayerUsedMove`              | `side.lastMove`                 |
| `side.last_selected_move`     | `PlayerSelectedMove`          | `side.lastSelectedMove`         |
| `pokemon.stats`               | `PlayerMonUnmodified*`        | `pokemon.baseStoredStats`       |
| `pokemon.position`            | `battle_struct.PartyPos`      | `pokemon.position`              |
| `pokemon.moves`               | `party_struct.{Moves,PP}`     | `pokemon.baseMoveSlots`         |
| `{pokemon,active}.hp`         | `battle_struct.HP`            | `pokemon.hp`                    |
| `{pokemon,active}.status`     | `battle_struct.Status`        | `pokemon.status`                |
| `{pokemon,active}.level`      | `PlayerMonUnmodifiedLevel`    | `pokemon.level`                 |
| `pokemon.species`             | `party_struct.Species`        | `pokemon.baseSpecies`           |
| `active.species`              | `battle_struct.Species`       | `pokemon.species`               |
| `active.stats`                | `party_struct.Stats`          | `pokemon.storedStats`           |
| `active.boosts`               | `PlayerMon*Mod`               | `pokemon.boosts`                |
| `active.volatiles`            | `PlayerBattleStatus{1,2,3}`   | `pokemon.volatiles`             |
| `volatiles.data.bide`         | `PlayerBideAccumulatedDamage` | `volatiles.bide.totalDamage`    |
| `volatiles.data.substitute`   | `PlayerSubstituteHP`          | `volatiles.substitute.hp`       |
|                               |                               |                                 |
| `volatiles.data.rollout`      | `PlayerRolloutCount`          |                                 |
| `volatiles.data.confusion`    | `PlayerConfuseCount`          | `volatiles.confusion.duration`  |
| `volatiles.data.toxic`        | `PlayerToxicCount`            | `volatiles.residualdmg.counter` |
| `volatiles.data.disabled`     | `PlayerDisableCount`          | `moveSlots.disabled`            |
| `volatiles.data.encore`       | `PlayerEncoreCount`           |                                 |
| `volatiles.data.perish_song`  | `PlayerPerishCount`           |                                 |
| `volatiles.data.fury_cutter`  | `PlayerFuryCutterCount`       |                                 |
| `volatiles.data.protect`      | `PlayerProtectCount`          |                                 |
| `volatiles.data.future_sight` | `PlayerFutureSightCount`      |                                 |
| `volatiles.data.rage`         | `PlayerRageCounter`           |                                 |
| `volatiles.data.wrap`         | `PlayerWrapCount`             |                                 |
|                               | `PlayerCharging`              |                                 |
|                               | `PlayerJustGotFrozen`         |                                 |



- Pokémon Showdown does not implement the correct Generation II RNG and as such its `seed` is
  different
- `battle.turn` only needs to be tracked in order to be compatible with the Pokémon Showdown
  protocol
- Battle results (win, lose, draw) or request states are communicated via the return code of
  `Battle.update`
- Nicknames (`BattleMonNick`/`pokemon.name`) are not handled by the pkmn engine as they are expected
  to be handled by driver code if required

==**TODO**==

### `Battle` / `Side`

`Battle` and `Side` are analogous to the classes of the
[same](https://github.com/smogon/pokemon-showdown/blob/master/sim/battle.ts)
[name](https://github.com/smogon/pokemon-showdown/blob/master/sim/name.ts) in Pokémon Showdown and
store general information about the battle. Unlike in Pokémon Showdown there is a distinction
between the data structure for the "active" Pokémon and its party members (see below).

### `Pokemon` / `ActivePokemon`

Similar to the cartridge, in order to save space different information is stored depending on
whether a [Pokémon](https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_II%29) is
actively participating in battle vs. is switched out (pret's [`battle_struct` vs.
`party_struct`](https://pkmn.cc/pokecrystal/macros/wram.asm)). In Pokémon Showdown, all the Pokemon
are represented by the same
[`Pokemon`](https://github.com/smogon/pokemon-showdown/blob/master/sim/pokemon.ts) class, and static
party information is saved in fields beginning with "`stored`" or "`base`".

==**TODO**==

#### `MoveSlot`

A `MoveSlot` is a data-type for a `(move, current pp)` pair. A pared down version of Pokémon
Showdown's `Pokemon#moveSlot`, it also stores data from the cartridge's `battle_struct::Move` macro
and can be used to replace the `PlayerMove*` data. Move PP is stored in the same way as on the
cartridge (`battle_struct::PP`), with 6 bits for current PP and the remaining 2 bits used to store
the number of applied PP Ups. PP Ups bits do not actually need to be stored on move slot as max PP
is never relevant in Generation II (the Mystery Berry always increases PP from 0 -> 5), but since
those two bits would need to be padded anyway and since max PP is necessary in certain
cirmcumstances in future Generations it is preserved for reasons of symmetry.

#### `Status`

Bitfield representation of a Pokémon's major [status
condition](https://pkmn.cc/bulba/Status_condition), mirroring how it is stored on the cartridge. A
value of `0x00` means that the Pokémon is not affected by any major status, otherwise the lower 3
bits represent the remaining duration for Sleep. Other status are denoted by the presence of
individual bits - at most one status should be set at any given time.

In Generation I & II, the "badly poisoned" status (Toxic) is instead treated as a volatile (see
below).

#### `Volatile` / `VolatileData`

Active Pokémon can have have ["volatile" status
conditions](https://pkmn.cc/bulba/Status_condition#Volatile_status) (called ['sub
status'](https://pkmn.cc/pokecrystal/constants/battle_constants.asm#L166-L212) bits in pret), all of
which are boolean flags that are cleared when the Pokémon faints or switches out:

| pkmn          | Pokémon Crystal  (pret) | Pokémon Showdown |
| ------------- | ----------------------- | ---------------- |
| `Bide`        | `BIDE`                  | `bide`           |
| `Locked`      | `RAMPAGE`               | `lockedmove`     |
| `Flinch`      | `FLINCHED`              | `flinch`         |
| `Charging`    | `CHARGED`               | `twoturnmove`    |
| `Underground` | `UNDERGROUND`           | `dig`            |
| `Flying`      | `FLYING`                | `fly`            |
| `Confusion`   | `CONFUSED`              | `confusion`      |
| `Mist`        | `MIST`                  | `mist`           |
| `FocusEnergy` | `FOCUS_ENERGY`          | `focusenergy`    |
| `Substitute`  | `SUBSTITUTE`            | `substitute`     |
| `Recharging`  | `RECHARGE`              | `mustrecharge`   |
| `Rage`        | `RAGE`                  | `rage`           |
| `LeechSeed`   | `LEECH_SEED`            | `leechseed`      |
| `Toxic`       | `TOXIC`                 | `toxic`          |
| `Transform`   | `TRANSFORMED`           | `transform`      |
|               |                         |                  |
| `Nightmare`   | `NIGHTMARE`             | `nightmare`      |
| `Cure`        | `CURSE`                 | `curse`          |
| `Protect`     | `PROTECT`               | `protect`        |
| `Foresight`   | `IDENTIFIED`            | `foresight`      |
| `PerishSong`  | `PERISH`                | `perishsong`     |
| `Endure`      | `ENDURE`                | `endure`         |
| `Rollout`     | `ROLLOUT`               | `rollout`        |
| `Attract`     | `IN_LOVE`               | `attract`        |
| `DefenseCurl` | `CURLED`                | `defensecurl`    |
| `Encore`      | `ENCORED`               | `encore`         |
| `LockOn`      | `LOCK_ON`               | `lockon`         |
| `DestinyBond` | `DESTINY_BOND`          | `destinybond`    |
| `BeatUp`      | `IN_LOOP`               |                  |

==**TODO**==

#### `Stats` / `Boosts`

[Stats](https://pkmn.cc/bulba/Stat) and [boosts (stat
modifiers)](https://pkmn.cc/bulba/Stat#Stat_modifiers) are stored logically, with the exception that
boosts should always range from `-6`...`6` instead of `1`...`13` as on the cartridge.

==**TODO**==
  
### `Move` / `Moves`

`Moves` serves as an identifier for a unique [Pokémon move](https://pkmn.cc/bulba/Move) that can be
used to retrieve a `Move` with information regarding base power, accuracy and type. As covered
above, PP information isn't strictly necessary in Generation I, but fits neatly into the 4 bits of
padding after noticing that all PP values are multiples of 5. `Moves.None` exists as a special
sentinel value to indicate `null`.

### `Species`

`Species` just serves as an identifier for a unique [Pokémon
species](https://pkmn.cc/bulba/Pok%C3%A9mon_species_data_structure_(Generation_II)) as the base
stats of a species are already accounted for in the computed stats in the `Pokemon` structure and
nothing in battle requires these to be recomputed. Similarly, Type is unnecessary to include as it
is also already present in the `Pokemon` struct. `Species.None` exists as a special sentinel value
to indicate `null`.

### `Type` / `Types` / `Effectiveness`

The [Pokémon types](https://pkmn.cc/bulba/Type) are enumerated by `Type`. `Types` represents a tuple
of 2 types, which takes the form of a packed struct isntead of `[2]Type` for symmetry with
Generation I. `Effectiveness` serves as an enum for tracking a moves effectiveness - like the
cartridge, effectiveness is stored as as `0`, `5`, `10`, and `20` (technically only a 4-bit value is
required, but Zig only allows a mininum of a byte to be stored at each address of an array).

## Information

The information of each field (in terms of [bits of
entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))) is as follows:

==**TODO**==

| Data           | Range    | Bits |     | Data              | Range    | Bits |
| -------------- | -------- | ---- | --- | ----------------- | -------- | ---- |
| **seed**       | 0...255  | 8    |     | **turn**          | 1...1000 | 7    |
| **team index** | 1...6    | 3    |     | **move index**    | 1...4    | 2    |
| **species**    | 1...151  | 8    |     | **move**          | 1...165  | 8    |
| **stat**       | 1...999  | 10   |     | **boost**         | 0...13   | 4    |
| **level**      | 1...100  | 7    |     | **volatiles**     | 17       | 18   |
| **bide**       | 2...1406 | 11   |     | **substitute**    | 4...179  | 8    |
| **multi hits** | 0...5    | 3    |     | **base power**    | 0...40   | 6    |
| **base PP**    | 1...8    | 3    |     | **PP Ups**        | 0...3    | 2    |
| **used PP**    | 0...63   | 8    |     | **HP / damage**   | 13...704 | 10   |
| **status**     | 0...10   | 4    |     | **effectiveness** | 0...3    | 2    |
| **type**       | 0...15   | 4    |     | **accuracy**      | 6...20   | 4    |
| **disabled**   | 0...7    | 3    |     | **DVs**           | 0...15   | 4    |
|                |          |      |     |                   |          |      |
| **rollout**    | 0...5    | 3    |     | **fury cutter**   | 0..4     | 3    |
| **confusion**  | 0...5    | 3    |     | **toxic**         | 1...16   | 4    |
| **encore**     | 0...6    | 3    |     | **future sight**  | 0...2    | 2    |
| **protect**    | 1...9    | 4    |     | **TODO rage**     | 0...0    | 0    |
| **wrap**       | 0...5    | 3    |     | **TODO**          | 0...0    | 0    |

From this we can determine the minimum bits required to store each data structure to determine how
much overhead the representations above have after taking into consideration [alignment &
padding](https://en.wikipedia.org/wiki/Data_structure_alignment) and
[denormalization](https://en.wikipedia.org/wiki/Denormalization):

==**TODO**==

## Protocol

TODO
