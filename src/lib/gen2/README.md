# Pokémon Generation II: GSC

## Data Structures

The following information is required to simulate a Generation II Pokémon battle:

==**TODO**==

| pkmn                           | Pokémon Crystal (pret)            | Pokémon Showdown                      |
| ------------------------------ | --------------------------------- | ------------------------------------- |
| `battle.seed`                  | `Random{Add,Sub}`                 | `battle.seed`                         |
| `battle.turn`                  |                                   | `battle.turn`                         |
| `field.weather.id`             | `BattleWeather`                   | `field.weather`                       |
| `field.weather.duration`       | `WeatherCount`                    | `field.weatherState.duration`         |
| `side.{active,pokemon}`        | `BattleMon`                       | `side.active`                         |
| `side.team`                    | `PartyMons`/`PartySpecies`        | `side.pokemon`                        |
| `side.conditions`              | `PlayerScreens`                   | `side.sideConditions`                 |
| `conditions.data.safeguard`    | `PlayerSafeguardCount`            | `sideConditions.safeguard.duration`   |
| `conditions.data.light_screen` | `PlayerLightScreenCount`          | `sideConditions.lightscreen.duration` |
| `conditions.data.reflect`      | `PlayerReflectCount`              | `sideConditions.reflect.duration`     |
| `pokemon.stats`                | `TODO unmodified`                 | `pokemon.baseStoredStats`             |
| `pokemon.position`             | `TODO`                            | `pokemon.position`                    |
| `pokemon.moves`                | `party_struct.{Moves,PP}`         | `pokemon.baseMoveSlots`               |
| `{pokemon,active}.hp`          | `{party,battle}_struct.HP`        | `pokemon.hp`                          |
| `{pokemon,active}.status`      | `{party,battle}_struct.Status`    | `pokemon.status`                      |
| `{pokemon,active}.level`       | `TODO unmodified`                 | `pokemon.level`                       |
| `{pokemon,active}.happiness`   | `{box,battle}_struct.Happiness`   | `pokemon.happiness`                   |
| `{pokemon,active}.ivs.gender`  | `{box,battle}_struct.DVs`         | `pokemon.gender`                      |
| `{pokemon,active}.ivs.type`    | `{box,battle}_struct.DVs`         | `pokemon.hpType`                      |
| `{pokemon,active}.ivs.power`   | `{box,battle}_struct.DVs`         | `pokemon.hpPower`                     |
| `{pokemon,active}.item`        | `{box,battle}_struct.Item`        | `pokemon.item`                        |
| `pokemon.species`              | `party_struct.Species`            | `pokemon.baseSpecies`                 |
| `active.species`               | `battle_struct.Species`           | `pokemon.species`                     |
| `active.stats`                 | `TODO modified`                   | `pokemon.storedStats`                 |
| `active.boosts`                | `PlayerStatLevels`                | `pokemon.boosts`                      |
| `active.volatiles`             | `PlayerBattleStatus{1,2,3}`       | `pokemon.volatiles`                   |
| `volatiles.bide`               | `PlayerDamageTaken`               | `volatiles.bide.totalDamage`          |
| `volatiles.substitute`         | `PlayerSubstituteHP`              | `volatiles.substitute.hp`             |
| `volatiles.rollout`            | `PlayerRolloutCount`              | `volatiles.rollout.hitCount`          |
| `volatiles.confusion`          | `PlayerConfuseCount`              | `volatiles.confusion.duration`        |
| `volatiles.toxic`              | `PlayerToxicCount`                | `volatiles.residualdmg.counter`       |
| `volatiles.disable`            | `PlayerDisableCount`              | `moveSlots.disabled`                  |
| `volatiles.encore`             | `PlayerEncoreCount`               | `volatiles.encore.duration`           |
| `volatiles.perish_song`        | `PlayerPerishCount`               | `volatiles.perishsong.duration`       |
| `volatiles.fury_cutter`        | `PlayerFuryCutterCount`           | `volatiles.furycutter.multiplier`     |
| `volatiles.protect`            | `PlayerProtectCount`              | `volatiles.stall.counter`             |
| `volatiles.future_sight`       | `PlayerFutureSight{Damage,Count}` | `slotConditions[i].futuremove`        |
| `volatiles.rage`               | `PlayerRageCounter`               | **BUG**                               |
| `volatiles.bind`               | `PlayerWrapCount`                 | `volatiles.partiallytrapped.duration` |
| `volatiles.bind_reason`        | `PlayerTrappingMove`              | `volatiles.effectState.sourceEffect`  |
|                                | `PlayerCharging`                  |                                       |
| `volatiles.switched`           | `TODO`                            | `pokemon.switchFlag`                  |
| `volatiles.switching`          | `PlayerIsSwitching`               | `pokemon.switchFlag`                  |
| `volatiles.frozen`             | `PlayerJustGotFrozen`             | `volatiles.frozen`                    |
|                                |                                   |                                       |
| `active.last_used_move`        | `PlayerUsedMove`                  | `side.lastMove`                       |

- Pokémon Showdown doesn't implement the correct Generation II RNG and as such its `seed` is
  different
- `battle.turn` only needs to be tracked to be compatible with the Pokémon Showdown protocol
- Battle results (win, lose, draw) or request states are communicated via the return code of
  `Battle.update`
- Nicknames (`BattleMonNick`/`pokemon.name`) aren't handled by the pkmn engine as they're expected
  to be handled by driver code if required

==**TODO**==

wPlayerMinimized

### `Battle` / `Side`

`Battle` and `Side` are analogous to the classes of the
[same](https://github.com/smogon/pokemon-showdown/blob/master/sim/battle.ts)
[name](https://github.com/smogon/pokemon-showdown/blob/master/sim/side.ts) in Pokémon Showdown and
store general information about the battle. Unlike in Pokémon Showdown there is a distinction
between the data structure for the "active" Pokémon and its party members (see below).

### `Pokemon` / `ActivePokemon`

Similar to the cartridge, to save space different information is stored depending on whether a
[Pokémon](https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_II%29) is actively
participating in battle vs. is switched out (pret's [`battle_struct` vs.
`party_struct`](https://pkmn.cc/pokecrystal/macros/ram.asm)). In Pokémon Showdown, all the Pokemon
are represented by the same
[`Pokemon`](https://github.com/smogon/pokemon-showdown/blob/master/sim/pokemon.ts) class, and static
party information is saved in fields beginning with "`stored`" or "`base`".

==**TODO**==

#### `MoveSlot`

A `MoveSlot` is a data-type for a `(move, current pp)` pair. A pared down version of Pokémon
Showdown's `Pokemon#moveSlot`, it also stores data from the cartridge's `battle_struct::Move` macro
and can be used to replace the `PlayerMove*` data. Move PP is stored as a full byte instead of how
the cartridge (`battle_struct::PP`) stores it (6 bits for current PP and the remaining 2 bits used
to store the number of applied PP Ups). PP Up bits don't actually need to be stored on move slot
as max PP is never relevant in Generation II (the Mystery Berry always increases PP from 0 -> 5).

#### `Status`

Bitfield representation of a Pokémon's major [status
condition](https://pkmn.cc/bulba/Status_condition), mirroring how it's stored on the cartridge. A
value of `0x00` means that the Pokémon isn't affected by any major status, otherwise the lower 3
bits represent the remaining duration for Sleep. Other status are denoted by the presence of
individual bits - at most one status should be set at any given time.

In Generation I & II, the "badly poisoned" status (Toxic) is instead treated as a volatile (see
below).

#### `Volatile` / `VolatileData`

Active Pokémon can have ["volatile" status
conditions](https://pkmn.cc/bulba/Status_condition#Volatile_status) (called ['sub
status'](https://pkmn.cc/pokecrystal/constants/battle_constants.asm#L166-L212) bits in pret), all of
which are boolean flags that are cleared when the Pokémon faints or switches out:

| pkmn          | Pokémon Crystal  (pret) | Pokémon Showdown |
| ------------- | ----------------------- | ---------------- |
| `Bide`        | `BIDE`                  | `bide`           |
| `Thrashing`   | `RAMPAGE`               | `lockedmove`     |
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
| `DestinyBond` | `DESTINY_BOND`          | `destinybond`    |  |

==**TODO**==

- `IN_LOOP` (beatup)

#### `Stats` / `Boosts`

[Stats](https://pkmn.cc/bulba/Stat) and [boosts (stat
modifiers)](https://pkmn.cc/bulba/Stat#Stat_modifiers) are stored logically, with the exception that
boosts should always range from `-6`...`6` instead of `1`...`13` as on the cartridge.

==**TODO**==
  
### `Move` / `Moves`

`Moves` serves as an identifier for a unique [Pokémon move](https://pkmn.cc/bulba/Move) that can be
used to retrieve a `Move` with information regarding base power, accuracy and type. As covered
earlier, PP information isn't strictly necessary in Generation I, but fits neatly into the 4 bits of
padding after noticing that all PP values are multiples of 5. `Moves.None` exists as a special
sentinel value to indicate `null`.

### `Species`

`Species` just serves as an identifier for a unique [Pokémon
species](https://pkmn.cc/bulba/Pokémon_species_data_structure_(Generation_II)) as the base
stats of a species are already accounted for in the computed stats in the `Pokemon` structure and
nothing in battle requires these to be recomputed. Similarly, Type is unnecessary to include as it
is also already present in the `Pokemon` struct. `Species.None` exists as a special sentinel value
to indicate `null`.

### `Type` / `Types` / `Effectiveness`

The [Pokémon types](https://pkmn.cc/bulba/Type) are enumerated by `Type`. `Types` represents a tuple
of 2 types, which takes the form of a packed struct instead of `[2]Type` for symmetry with
Generation I. `Effectiveness` serves as an enum for tracking a moves effectiveness - like the
cartridge, effectiveness is stored as `0`, `5`, `10`, and `20` (technically only a 4-bit value is
required, but Zig only allows a minimum of a byte to be stored at each address of an array).

Type effectiveness modifiers are applied based off of the ordering of the effectiveness table as
opposed to first applying modifiers for a species's first type and then second type. The engine
maintains a `Type.PRECEDENCE` table to allow for reordering type effectiveness modifier application
where necessary.

## Information

The information of each field (in terms of [bits of
entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))) is as follows:

==**TODO**==

| Data           | Range   | Bits |     | Data              | Range    | Bits |
| -------------- | ------- | ---- | --- | ----------------- | -------- | ---- |
| **seed**       | 0...255 | 8    |     | **turn**          | 1...1000 | 7    |
| **team index** | 1...6   | 3    |     | **move index**    | 1...4    | 2    |
| **species**    | 1...251 | 8    |     | **move**          | 1...251  | 8    |
| **stat**       | 1...999 | 10   |     | **boost**         | 0...13   | 4    |
| **level**      | 1...100 | 7    |     | **volatiles**     | *27*     | 27   |
| **bide**       | 0...703 | 11   |     | **substitute**    | 0...179  | 8    |
| **multi hits** | 0...5   | 3    |     | **base power**    | 0...50   | 6    |
| **base PP**    | 1...8   | 3    |     | **PP Ups**        | 0...3    | 2    |
| **PP**         | 0...64  | 7    |     | **HP / damage**   | 0...704  | 10   |
| **status**     | 0...10  | 4    |     | **effectiveness** | 0...3    | 2    |
| **type**       | 0...18  | 5    |     | **accuracy**      | 6...20   | 4    |
| **disabled**   | 0...7   | 3    |     | **DVs**           | 0...15   | 4    |
| **rollout**    | 0...5   | 3    |     | **fury cutter**   | 0..4     | 3    |
| **confusion**  | 0...5   | 3    |     | **toxic**         | 0...15   | 4    |
| **encore**     | 0...6   | 3    |     | **future sight**  | 0...2    | 2    |
| **protect**    | 0...9   | 4    |     | **rage**          | 0...255  | 8    |
| **wrap**       | 0...5   | 3    |     | **perish song**   | 0...4    | 3    |
| **item**       | TODO    | 5?   |     | **gender**        | 0..1     | 1    |

From this one can determine the minimum bits required to store each data structure to determine how
much overhead the preceding representations have after taking into consideration [alignment &
padding](https://en.wikipedia.org/wiki/Data_structure_alignment) and
[denormalization](https://en.wikipedia.org/wiki/Denormalization):

## Details

| pkmn                      | Pokémon Crystal (pret)                            |
| ------------------------- | ------------------------------------------------- |
| `start`                   | `DoBattle`                                        |
| `update`                  | `BattleTurn`                                      |
| `selectMove` / `saveMove` | `CheckPlayerLockedIn` / `ParsePlayerAction`       |
| `switchIn`                | `SwitchPlayerMon` / `SendOutPlayerMon`            |
| `turnOrder`               | `DetermineMoveOrder`                              |
| `doTurn`                  | `DoTurn`                                          |
| `executeMove`             | `DoMove`                                          |
| `beforeMove`              | `CheckTurn`                                       |
| `canMove`                 |                                                   |
| `decrementPP`             |                                                   |
| `doMove`                  |                                                   |
| `checkCriticalHit`        | `BattleCommand_Critical`                          |
| `calcDamage`              | `BattleCommand_DamageCalc` / `PlayerAttackDamage` |
| `adjustDamage`            | `BattleCommand_Stab`                              |
| `randomizeDamage`         | `BattleCommand_DamageVariation`                   |
| `specialDamage`           | `BattleCommand_ConstantDamage`                    |
| `applyDamage`             | `BattleCommand_ApplyDamage`                       |
| `checkHit`                | `BattleCommand_CheckHit`                          |
| `checkFaint`              | `CheckFaint`                                      |
| `handleResidual`          | `ResidualDamage`                                  |
| `endTurn`                 | `EndTurn`                                         |

DoBattle
BattleTurn
- HandleBerserkGene
- CheckPlayerLockedIn
- BattleMenu
- ParsePlayerAction
- DetermineMoveOrder
  - CompareMovePriority
  - GetMovePriority
- Battle_*
  - Handle*Switch
    - SwitchPlayerMon
      - BreakAttraction
      - SendOutPlayerMon
    - SpikesDamage
  - *Turn_EndOpponentProtectEndureDestinyBond
    - EndUserDestinyBond
    - Do*Turn
    - EndOpponentProtectEndureDestinyBond
  - ResidualDamage
  - CheckFaint_*
  - HandleBetweenTurnEffects
    - HandleFutureSight
    - HandleWeather
    - HandleWrap
    - HandlePerishSong
    - HandleLeftovers
    - HandleMysteryBerry
    - HandleDefrost
    - HandleSafeguard
    - HandleScreens
    - HandleStatBoostingHeldItems
    - HandleHealingItems
    - HandleEncore

DoTurn
DoMove = executeMove
CheckTurn = beforeMove
BattleCommand_Critical = checkCriticalHit
BattleCommand_Stab = adjustDamage
BattleCommand_DamageVariation = randomizeDamage
BattleCommand_CheckHit = checkHit
BattleCommand_ApplyDamage = applyDamage
BattleCommand_CheckFaint
BattleCommand_BuildOpponentRage = buildRage
BattleCommand_DamageCalc (PlayerAttackDamage / EnemyAttackDamage) = calcDamage
BattleCommand_ConstantDamage = specialDamage
DoEnemyDamage / DoPlayerDamage / DoSubstituteDamage

==**TODO**==

## Protocol

TODO

```txt
-activate: _,  move, name, number
```

## Bugs

- TODO: randomChance rate different than gen 1?
- Twineedle shouldn't be able to inflict poison if it breaks a substitute
- Mail should not be stolen by Thief
- RNG for crit is 1/16 and not 17/256?
- Struggle recoil into Substitute only 1 HP
- Substitute "activates" even though doesnt take damage for jump crash damage
- Pokémon specific items after Transform
- OHKO moves that miss should be Counterable
- Defense lowering after breaking Substitute glitch
- Beserk Gene copies previous mons confusion counter
- Type boosting items w/ Confusion self-hit
- Spikes 0 HP glitch
- PP Up + Disable freeze
- Beat Up partyless should fail but should still be able to trigger Kings Rock
- Beat Up desync
- Lock-on accuracy should be 100 not true, should be passed
- Pain Split 100 accuracy not true
- Foresight ignoring accuracy/evasiveness stages
- Disable duration?
- type effectiveness precedence
