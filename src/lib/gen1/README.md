| pkmn                            | Pokémon Red                    | Pokémon Showdown                |
| ------------------------------- | ------------------------------ | ------------------------------- |
|                                 | `wBattleMonNick`               | `Pokemon#name`                  |
| `stored.level`                  | `wPlayerMonUnmodifiedLevel`    | `Pokemon#level`                 |
| `stored.stats`                  | `wPlayerMonUnmodified*`        | `Pokemon#storedStats`           |
| `stored.moves`                  |                                | `Pokemon#baseMoveSlots`         |
| `stored.dvs`                    |                                |                                 |
| `stored.evs`                    |                                |                                 |
| `boosts`                        | `wPlayerMon*Mod`               | `Pokemon#boosts`                |
| `volatiles`                     | `wPlayerBattleStatus{1,2,3}`   | `Pokemon#volatiles`             |
| `volatiles_data.bide`           | `wPlayerBideAccumulatedDamage` | `volatiles.bide.totalDamage`    |
| `volatiles_data.confusion`      | `wPlayerConfusedCounter`       | `volatiles.confusion.duration`  |
| `volatiles_data.toxic`          | `wPlayerToxicCounter`          | `volatiles.residualdmg.counter` |
| `volatiles_data.substitute`     | `wPlayerSubstituteHP`          | `volatiles.substitute.hp`       |
| `volatiles_data.multihit.hits`  | `wPlayerNumHits`               |                                 |
| `volatiles_data.multihits.left` | `wPlayerNumAttacksLeft`        |                                 |
| `disabled`                      | `wPlayerDisabledMove`          | `MoveSlot#disabled`             |

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
