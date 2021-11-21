| Pokémon Crystal          | Pokémon Showdown |
| ------------------------ | ---------------- |
| `SUBSTATUS_BIDE`         | `bide`           |
| `SUBSTATUS_RAMPAGE`      | `lockedmove`     |
| `SUBSTATUS_FLINCHED`     | `flinch`         |
| `SUBSTATUS_CHARGED`      | `twoturnmove`    |
| `SUBSTATUS_UNDERGROUND`  | `dig`            |
| `SUBSTATUS_FLYING`       | `fly`            |
| `SUBSTATUS_CONFUSED`     | `confusion`      |
| `SUBSTATUS_MIST`         | `mist`           |
| `SUBSTATUS_FOCUS_ENERGY` | `focusenergy`    |
| `SUBSTATUS_SUBSTITUTE`   | `substitute`     |
| `SUBSTATUS_RECHARGE`     | `mustrecharge`   |
| `SUBSTATUS_RAGE`         | `rage`           |
| `SUBSTATUS_LEECH_SEED`   | `leechseed`      |
| `SUBSTATUS_TOXIC`        | `toxic`          |
| `SUBSTATUS_TRANSFORMED`  | `transform`      |
|                          |                  |
| `SUBSTATUS_NIGHTMARE`    | `nightmare`      |
| `SUBSTATUS_CURSE`        | `curse`          |
| `SUBSTATUS_PROTECT`      | `protect`        |
| `SUBSTATUS_IDENTIFIED`   | `foresight`      |
| `SUBSTATUS_PERISH`       | `perishsong`     |
| `SUBSTATUS_ENDURE`       | `endure`         |
| `SUBSTATUS_ROLLOUT`      | `rollout`        |
| `SUBSTATUS_IN_LOVE`      | `attract`        |
| `SUBSTATUS_CURLED`       | `defensecurl`    |
| `SUBSTATUS_ENCORED`      | `encore`         |
| `SUBSTATUS_LOCK_ON`      | `lockon`         |
| `SUBSTATUS_DESTINY_BOND` | `destinybond`    |
| `SUBSTATUS_IN_LOOP`      |                  |
|                          |                  |
|                          | `Move#multihit`  |

```txt
///  - https://pkmn.cc/bulba/Pok%c3%a9mon_data_structure_%28Generation_II%29
///  - https://pkmn.cc/PKHeX/PKHeX.Core/PKM/PK2.cs
///  - https://pkmn.cc/pokecrystal/macros/wram.asm
///


/// *See:* https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_II%29



/// A structure for storing information for each `Boost` (cf. Pokémon Showdown's `BoostTable`).
/// **NOTE**: `Boost(i4)` should likely always be used, as boosts should always range from -6...6.
```
