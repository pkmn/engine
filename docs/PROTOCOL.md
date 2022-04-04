# Protocol

- `Result`/`Choice`
- data structures serialized in native endianness
- `choices`

[Pokémon Showdown's simulator protocol](https://github.com/smogon/pokemon-showdown/blob/master/sim/SIM-PROTOCOL.md)





---
- Native endianess!
- different (but related) protocol per generation
- if have kwargs change first bit (usually u7, 8th bit is whether kwargs is set) and then second bit is length to indicate the *number* of kwargs
- not guaranteed to be same order as PS, driver code might need to correct
- drop begin of battle message and `|upkeep|`
- **can hp mod be applies at top level, not in engine? just return exact hp always**
  
example docs: https://github.com/couchbase/kv_engine/blob/master/docs/BinaryProtocol.md

```txt
pass
move
switch
team
(shift)

2 bits

2 bits move
3 bits switch

player 1 player 2

continue vs wlt (ended) 2 bits. 2 bits p1 request type 2 bits p2 request type = 6

response 4-5 bits p1, 4-5 p2. team is more complicated… (need u3*6=18 bits each = 40 ttotal)

doubles = 55 55 = 20 bits?
```

---

## `|move|` (`0x03`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x03          | Source        | Move          | Target        |
      +---------------+---------------+---------------+---------------+
     4| Reason        | [from]?       |
      +---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description | `[from]`? |
| ------ | ----------- | --------- |
| `0x00` | None        | No        |
| `0x01` | `recharge`  | No        |
| `0x02` | `\|[from]`  | Yes       |
</details>

TODO: `LastStill`, `LastMove`

## `|switch|` (`0x04`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x04          | Ident         | Species       | Level         |
      +---------------+---------------+---------------+---------------+
     4| Current HP                    | Max HP                        |
      +---------------+---------------+---------------+---------------+
     8| Status        |
      +---------------+

## `|cant|` (`0x05`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x05          | Ident         | Reason        | Move?         |
      +---------------+---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description        | Move? |
| ------ | ------------------ | ----- |
| `0x00` | `slp`              | No    |
| `0x01` | `frz`              | No    |
| `0x02` | `par`              | No    |
| `0x03` | `partiallytrapped` | No    |
| `0x04` | `flinch`           | No    |
| `0x05` | `Disable`          | Yes   |
| `0x06` | `recharge`         | No    |
| `0x07` | `nopp`             | No    |
</details>

## `|faint|` (`0x06`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x06          | Ident         |
      +---------------+---------------+

## `|turn|` (`0x07`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x07          | Turn                          |
      +---------------+---------------+---------------+

## `|win` (`0x08`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x06          | Player        |
      +---------------+---------------+

## `|tie|` (`0x09`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x09          |
      +---------------+

## `|-damage|` (`0x0A`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0A          | Ident         | Current HP                    |
      +---------------+---------------+---------------+---------------+
     4| Max HP                        | Status        | Reason        |
      +---------------+---------------+---------------+---------------+
     8| [of]?         |
      +---------------+

<details><summary>Reason</summary>

| Raw    | Description              | `[of]`? |
| ------ | ------------------------ | ------- |
| `0x00` | None                     | No      |
| `0x01` | `psn`                    | No      |
| `0x02` | `brn`                    | No      |
| `0x03` | `confusion`              | No      |
| `0x04` | `psn\|[of]`              | Yes     |
| `0x05` | `brn\|[of]`              | Yes     |
| `0x06` | `Recoil\|[of]`           | Yes     |
| `0x07` | `move: Leech Seed\|[of]` | Yes     |
</details>

## `|-heal|` (`0x0B`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0B          | Ident         | Current HP                    |
      +---------------+---------------+---------------+---------------+
     4| Max HP                        | Status        | Reason        |
      +---------------+---------------+---------------+---------------+
     8| [of]?         |
      +---------------+

<details><summary>Reason</summary>

| Raw    | Description            | `[of]`? |
| ------ | ---------------------- | ------- |
| `0x00` | None                   | No      |
| `0x01` | `\|[silent]`           | No      |
| `0x02` | `\|[from] drain\|[of]` | Yes     |
</details>

## `|-status|` (`0x0C`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0C          | Ident         | Status        | Reason        |
      +---------------+---------------+---------------+---------------+
     4| [from]?       |
      +---------------+

<details><summary>Reason</summary>

| Raw    | Description  | `[from]`? |
| ------ | ------------ | --------- |
| `0x00` | None         | No        |
| `0x01` | `\|[silent]` | No        |
| `0x02` | `\|[from]`   | Yes       |
</details>

## `|-curestatus|` (`0x0D`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0D          | Ident         | Status        | Reason        |
      +---------------+---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description  |
| ------ | ------------ |
| `0x00` | None         |
| `0x01` | `\|[silent]` |
</details>

## `|-boost|` (`0x0E`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0E          | Ident         | Reason        | Num           |
      +---------------+---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description        |
| ------ | ------------------ |
| `0x00` | `atk\|[from] Rage` |
| `0x01` | `atk`              |
| `0x02` | `def`              |
| `0x03` | `spe`              |
| `0x04` | `spa`              |
| `0x05` | `spd`              |
| `0x06` | `accuracy`         |
| `0x07` | `evasion`          |
</details>

## `|-unboost|` (`0x0F`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0F          | Ident         | Reason        | Num           |
      +---------------+---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description |
| ------ | ----------- |
| `0x01` | `atk`       |
| `0x02` | `def`       |
| `0x03` | `spe`       |
| `0x04` | `spa`       |
| `0x05` | `spd`       |
| `0x06` | `accuracy`  |
| `0x07` | `evasion`   |
</details>

## `|-clearallboost|` (`0x10`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x10          |
      +---------------+

## `|-fail|` (`0x11`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x11          | Ident         | Reason        |
      +---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description                |
| ------ | -------------------------- |
| `0x00` | None                       |
| `0x01` | `slp`                      |
| `0x02` | `psn`                      |
| `0x03` | `brn`                      |
| `0x04` | `frz`                      |
| `0x05` | `par`                      |
| `0x06` | `to`                       |
| `0x07` | `move: Substitute`         |
| `0x08` | `move: Substitute\|[weak]` |
</details>

## `|-miss|` (`0x12`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x12          | Source        | Target        |
      +---------------+---------------+---------------+

## `|-hitcount|` (`0x13`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x13          | Ident         | Num           |
      +---------------+---------------+---------------+

## `|-prepare|` (`0x14`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x14          | Source        | Move          |
      +---------------+---------------+---------------+

## `|-mustrecharge|` (`0x15`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x15          | Ident         |
      +---------------+---------------+

## `|-activate|` (`0x16`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x16          | Ident         | Reason        |
      +---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description            |
| ------ | ---------------------- |
| `0x00` | `confusion`            |
| `0x01` | `Bide`                 |
| `0x02` | `move: Haze`           |
| `0x03` | `move: Struggle`       |
| `0x04` | `Substitute\|[damage]` |
| `0x05` | `\|\|move: Splash`     |
</details>

## `|-fieldactivate|` (`0x17`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x17          |
      +---------------+

## `|-start|` (`0x18`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x18          | Ident         | Reason        | Move/Types?   |
      +---------------+---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description                                      | Move/Types? |
| ------ | ------------------------------------------------ | ----------- |
| `0x00` | `Bide`                                           | No          |
| `0x01` | `confusion`                                      | No          |
| `0x02` | `confusion\|[silent]`                            | No          |
| `0x03` | `move: Focus Energy`                             | No          |
| `0x04` | `move: Leech Seed`                               | No          |
| `0x05` | `Light Screen`                                   | No          |
| `0x06` | `Mist`                                           | No          |
| `0x07` | `Reflect`                                        | No          |
| `0x08` | `Substitute`                                     | No          |
| `0x09` | `typechange\|...\|[from] move: Conversion\|[of]` | Yes         |
| `0x0A` | `Disable\|`                                      | Yes         |
| `0x0B` | `Mimic\|`                                        | Yes         |
</details>

## `|-end|` (`0x19`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x19          | Ident         | Reason        |
      +---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description             |
| ------ | ----------------------- |
| `0x00` | `Disable`               |
| `0x01` | `confusion`             |
| `0x02` | `move: Bide`            |
| `0x03` | `Substitute`            |
| `0x04` | `Disable\|[silent]`     |
| `0x05` | `confusion\|[silent]`   |
| `0x06` | `mist\|[silent]`        |
| `0x07` | `focusenergy\|[silent]` |
| `0x08` | `leechseed\|[silent]`   |
| `0x09` | `toxic\|[silent]`       |
| `0x0A` | `lightscreen\|[silent]` |
| `0x0B` | `reflect\|[silent]`     |
</details>

## `|-ohko|` (`0x1A`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x1A          |
      +---------------+

## `|-crit|` (`0x1B`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1B          | Ident         |
      +---------------+---------------+

## `|-supereffective|` (`0x1C`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1C          | Ident         |
      +---------------+---------------+

## `|-resisted|` (`0x1D`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1D          | Ident         |
      +---------------+---------------+

## `|-immune|` (`0x1E`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x1E          | Source        | Reason        |
      +---------------+---------------+---------------+

<details><summary>Reason</summary>

| Raw    | Description |
| ------ | ----------- |
| `0x00` | None        |
| `0x01` | `\|[ohko]`  |
</details>

## `|-transform|` (`0x1F`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x1F          | Source        | Target        |
      +---------------+---------------+---------------+
