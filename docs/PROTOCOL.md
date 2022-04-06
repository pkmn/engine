# Protocol

At a high level, the pkmn engine updates a battle's state based on both player's choices, returning
a result which indicates whether the battle has ended and what each player's options are. A
non-terminal result can be fed into a battle's `choices` method which returns all legal choices[^1],
though the state of the engine may also be inspected directly to determine information about the
battle and what choices are possible. By [design](DESIGN.md), each generation's data structures are
different, but the precise layout of the battle information is outlined in the respective
documentation.

More information about a battle can be generated via the `-Dtrace` flag when building the engine.
This flag enables the engine to write the wire protocol described in this document to a `Log`.
Generally, this `Log` should be a `FixedBufferStream` `Writer` backed by a statically allocated
fixed-size array that gets `reset` after each `update` as the maximum number of bytes written by a
single `update` call is bounded to a relatively small number of bytes per generation, though since
any `Writer` implementation is allowed this `Log` could instead write to standard output (**NOTE:**
in Zig, the default writer is not buffered by default - you must use a
[`BufferedWriter`](https://zig.news/kristoff/how-to-add-buffering-to-a-writer-reader-in-zig-7jd)
wrapper to acheive reasonable performance).

The engine's wire protocol essentially amounts to a stripped down binary translation of [Pokémon
Showdown's simulator
protocol](https://github.com/smogon/pokemon-showdown/blob/master/sim/SIM-PROTOCOL.md), with certain
redundant messages (e.g. `|upkeep|` or `|`) removed, and others subtly tweaked (there is no
`|split|` message - the "ominprescient" stream of information is always provided and other streams
must be recreated by driver code). Like the rest of the pkmn engine, the protocol uses
**native-endianess**, and furthermore, is **not backwards-compatible** - the protocol is only
guaranteed to be translatable by the exact version of the library that produced it (i.e. the
protocol does not respect [semantic versioning](https://semver.org) as it is effectively treated as
an internal implementation detail of the engine).

While the protocol may change slightly depending on the generation in question (e.g. a `Move`
requires more than a single byte to encode after Generation I & II), any differences will called out
below where applicable.

[^1]: The `choices` method leaks information in certain cases where legal decisions would not be
known to a user until after having already attempted a choice (e.g. that a Pokémon has been trapped
or has had a move has been blocked due to an opponent's use of
[Imprison](https://bulbapedia.bulbagarden.net/wiki/Imprison_(move))). This is a non-issue for the
use case of games being played out randomly via a machine, but a simulator for human players built
on top of the pkmn engine would need to provide an alternative implementation of the `choices`
function.


## Overview

With `-Dtrace` enabled, [messages](#messages) are written to the `Log` provided. The first byte of
each message is an integer representing the `ArgType` of the message, followed by 0 or more bytes
containing the payload of the message. Game objects such as moves, species, abilities, items, types,
etc are written as their internal identifier which usually matches their public facing number, but
in cases where these differ the [`ids.json`](src/pkg/data/ids.json) can  be used to decode them.
A [`protocol.json`](../src/pkg/data/protocol.json) containing a human-readable lookup for the
`ArgType` and various "reason" enums (see below) is generated from the library code and can be used
for similar purposes.

Because each protocol message is a fixed length, parsing can be terminated when a `0x00` byte is
read when an the leading `ArgType` header byte of a message is expected. Note that a `0x00` byte may
also appear internally within the payload of a message - only the `0x00` in the header of a message
indicates the end.

TODO FIXME finish

- `Reason`
- lastmove/lastmiss
- pokemon ident


## Messages

### `|move|` (`0x03`)

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

### `|switch|` (`0x04`)

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

### `|cant|` (`0x05`)

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

### `|faint|` (`0x06`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x06          | Ident         |
      +---------------+---------------+

### `|turn|` (`0x07`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x07          | Turn                          |
      +---------------+---------------+---------------+

### `|win` (`0x08`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x06          | Player        |
      +---------------+---------------+

### `|tie|` (`0x09`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x09          |
      +---------------+

### `|-damage|` (`0x0A`)

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

### `|-heal|` (`0x0B`)

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

### `|-status|` (`0x0C`)

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

### `|-curestatus|` (`0x0D`)

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

### `|-boost|` (`0x0E`)

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

### `|-unboost|` (`0x0F`)

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

### `|-clearallboost|` (`0x10`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x10          |
      +---------------+

### `|-fail|` (`0x11`)

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

### `|-miss|` (`0x12`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x12          | Source        | Target        |
      +---------------+---------------+---------------+

### `|-hitcount|` (`0x13`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x13          | Ident         | Num           |
      +---------------+---------------+---------------+

### `|-prepare|` (`0x14`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x14          | Source        | Move          |
      +---------------+---------------+---------------+

### `|-mustrecharge|` (`0x15`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x15          | Ident         |
      +---------------+---------------+

### `|-activate|` (`0x16`)

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

### `|-fieldactivate|` (`0x17`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x17          |
      +---------------+

### `|-start|` (`0x18`)

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

### `|-end|` (`0x19`)

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

### `|-ohko|` (`0x1A`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x1A          |
      +---------------+

### `|-crit|` (`0x1B`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1B          | Ident         |
      +---------------+---------------+

### `|-supereffective|` (`0x1C`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1C          | Ident         |
      +---------------+---------------+

### `|-resisted|` (`0x1D`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1D          | Ident         |
      +---------------+---------------+

### `|-immune|` (`0x1E`)

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

### `|-transform|` (`0x1F`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x1F          | Source        | Target        |
      +---------------+---------------+---------------+
