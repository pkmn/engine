| pkmn                            | Pokémon Red                            | Pokémon Showdown                |
| ------------------------------- | -------------------------------------- | ------------------------------- |
|                                 | `w{Battle,Enemy}MonNick`               | `Pokemon#name`                  |
| `stored.level`                  | `w{Player,Enemy}MonUnmodifiedLevel`    | `Pokemon#level`                 |
| `stored.stats`                  | `w{Player,Enemy}MonUnmodified*`        | `Pokemon#storedStats`           |
| `stored.moves`                  |                                        | `Pokemon#baseMoveSlots`         |
| `stored.dvs`                    |                                        |                                 |
| `stored.evs`                    |                                        |                                 |
| `boosts`                        | `w{Player,Enemy}Mon*Mod`               | `Pokemon#boosts`                |
| `volatiles`                     | `w{Player,Enemy}BattleStatus{1,2,3}`   | `Pokemon#volatiles`             |
| `volatiles_data.bide`           | `w{Player,Enemy}BideAccumulatedDamage` | `volatiles.bide.totalDamage`    |
| `volatiles_data.confusion`      | `w{Player,Enemy}ConfusedCounter`       | `volatiles.confusion.duration`  |
| `volatiles_data.toxic`          | `w{Player,Enemy}ToxicCounter`          | `volatiles.residualdmg.counter` |
| `volatiles_data.substitute`     | `w{Player,Enemy}SubstituteHP`          | `volatiles.substitute.hp`       |
| `volatiles_data.multihit.hits`  | `w{Player,Enemy}NumHits`               |                                 |
| `volatiles_data.multihits.left` | `w{Player,Enemy}NumAttacksLeft`        |                                 |
| `disabled`                      | `w{Player,Enemy}DisabledMove`          | `MoveSlot#disabled`             |

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
