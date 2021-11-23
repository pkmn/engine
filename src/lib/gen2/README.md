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

```txt
///  - https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_II%29
///  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK2.cs
///  - https://pkmn.cc/pokecrystal/macros/wram.asm
///


/// *See:* https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_II%29



/// A structure for storing information for each `Boost` (cf. Pokémon Showdown's `BoostTable`).
/// **NOTE**: `Boost(i4)` should likely always be used, as boosts should always range from -6...6.
```
