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
single `update` call is bounded to a [relatively small number of bytes](#size) per generation,
though since any `Writer` implementation is allowed this `Log` could instead write to standard
output (Note that in Zig the standard out writer is not buffered by default - you must use a
[`BufferedWriter`](https://zig.news/kristoff/how-to-add-buffering-to-a-writer-reader-in-zig-7jd)
wrapper to acheive reasonable performance).

The engine's wire protocol essentially amounts to a stripped down binary translation of [Pokémon
Showdown's simulator
protocol](https://github.com/smogon/pokemon-showdown/blob/master/sim/SIM-PROTOCOL.md), with certain
redundant messages (e.g. `|upkeep|` or `|`) removed, and others subtly tweaked (there is no
`|split|` message - the "ominprescient" stream of information is always provided and other streams
must be recreated by driver code). Like the rest of the pkmn engine, the protocol uses
**native-endianess**. While the protocol may change slightly depending on the generation in question
(e.g. a `Move` requires more than a single byte to encode after Generation I & II), any differences
will called out below where applicable.

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
in cases where these differ the [`ids.json`](src/pkg/data/ids.json) can  be used to decode them.  A
[`protocol.json`](../src/pkg/data/protocol.json) containing a human-readable lookup for the
`ArgType` and various "[reason](#reason)" enums (see below) is generated from the library code and
can be used for similar purposes.

Because each protocol message is a fixed length, parsing can be terminated when a `0x00` byte is
read when the leading `ArgType` header byte of a message is expected. Note that a `0x00` byte may
also appear internally within the payload of a message - only the `0x00` in the header of a message
indicates the end. This `0x00` byte will be written even in places where the previous `ArgType`
alone would be sufficient to indicate the end of parsing (e.g. after reading a `|win|` or `|turn|`
message). Unlike the Pokémon Showdown simulator protocol, the pkmn engine's protocol does not
produce a `|request|` message - as outlined above a driver should inspect the raw bytes of the
`Battle` object in addition to the `Result` to determine enough about state to determine which
choices are possible (taking into account privileged information depending on the side in question).

### Reason

Several protocol messages have a "reason" field which provides further information/context about the
message and may indicate that the payload contains additional bytes. Bytes that are only present
when the reason field is a specific value are indicated by a trailing `?`. Messages which contain a
reason field will document each possible value the field can take and whether or not the specific
reason will cause the message to contain additional data. Reason fields are required to be able to
encode the information Pokémon Showdown stores in its "keyword args" (`kwArgs`) mapping (e.g.
`[from]` or `[of]`).

### `PokemonIdent`

Many protocol message types encode the source/target/actor as a `PokemonIdent` (or Pokémon ID). From
Pokémon Showdown's documentation:

> A Pokémon ID is in the form `POSITION: NAME`.
>
> - `POSITION` is the spot that the Pokémon is in: it consists of the `PLAYER` of the player
>   (see `|player|`), followed by a position letter (`a` in singles).
> - `NAME` is the nickname of the Pokémon (or the species name, if no nickname is given).
>
> For example: `p1a: Sparky` could be a Charizard named Sparky. `p1: Dragonite` could be an
> inactive Dragonite being healed by Heal Bell.
>
> For most commands, you can just use the position information in the Pokémon ID to identify
> the Pokémon. Only a few commands actually change the Pokémon in that position (`|switch|`
> switching, `|replace|` illusion dropping, `|drag|` phazing, and `|detailschange|` permanent
> forme changes), and these all specify `DETAILS` for you to perform updates with.

Identity works a little differently in the pkmn engine, given that nicknames are not part of the
engine. While the given player, position letter and identity of the Pokémon in question are all
still encoded, the identity takes the form of a single bit-packed native-endian byte:

- the most significant 3 bits are always `0`
- the 4th most signficiant bit is `0` if the position is `a` and `1` if the position is `b` (only
  relevant in doubles battles)
- the 5th most signficant bit is `0` for player 1 and `1` for player 2.
- the lowest 3 bits represent the slot (`1` through `6` inclusive) of the Pokémon's original
  location within the party (i.e. the order a player's team was initially in when the battle
  started, before any Pokémon were switched).

A Pokémon Showdown-compatible `PokemonIdent` can be translated from the pkmn engine identity
by driver code provided there exists a mapping from the party's original positions and Pokémon
nicknames.

### `LastStill`/`LastMiss`

Unfortunately, Pokémon Showdown's protocol does not allow for translating one message at a time. The
`|move|` message can be modified by a message with the `LastStill` (`0x01`) or `LastMiss` (`0x02`)
`ArgType`. In the Pokémon Showdown simulator the `attrLastStill` method is used to modify a batched
`|move|` message before it is written with other messages as a single chunk, but the pkmn engine
streams out writes immediately and does not perform batching, meaning code parsing the engine's
protocol is required to do the batching instead.

When interepreting a buffer written by the pkmn `Log`, if a `LastStill` (`0x01`) byte is
encountered, if there is a previous `|move|` message in the same buffer that occured earlier, append
a `[still]` keyword arg to it. Similarly, if a `LastMiss` (`0x02`) byte is encountered, append a
`[miss]` to the last seen `|move|` message if present.

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

`Source` is the [`PokemonIdent`](#pokemonident) of the Pokémon that used the `Move` on the
[`PokemonIdent`](#pokemonident) `Target` for `Reason`.  If `Reason` is `0x02` then the following
byte which indicate which `Move` the `|move|` is `[from]`. This message may be modified later on by
a `LastStill` or `LastMiss` message in the same buffer (see above).

<details><summary>Reason</summary>

| Raw    | Description | `[from]`? |
| ------ | ----------- | --------- |
| `0x00` | None        | No        |
| `0x01` | `\|[from]`  | Yes       |
</details>

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

The Pokémon identified by [`Ident`](#pokemonident) has switched in and is a level `Level` `Species`
with `Current HP`, `Max HP` and `Status`.

### `|cant|` (`0x05`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x05          | Ident         | Reason        | Move?         |
      +---------------+---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) could not perform an action due to `Reason`. If
the reason is `0x05` then the following byte indicates which `Move` the Pokémon was unable to
perform.

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

The Pokémon identified by [`Ident`](#pokemonident) has fainted.

### `|turn|` (`0x07`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x07          | Turn                          |
      +---------------+---------------+---------------+

It is now turn `Turn`.

### `|win` (`0x08`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x06          | Player        |
      +---------------+---------------+

The `Player` has won the battle.

### `|tie|` (`0x09`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x09          |
      +---------------+

The battle has ended in a tie.

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

The Pokémon identified by [`Ident`](#pokemonident) has taken damage and now has the `Current HP`,
`Max HP` and `Status`. If `Reason` is in `0x04` then the following byte indicates the
[`PokemonIdent`](#pokemonident) of the source `[of]` the damage.

<details><summary>Reason</summary>

| Raw    | Description              | `[of]`? |
| ------ | ------------------------ | ------- |
| `0x00` | None                     | No      |
| `0x01` | `psn`                    | No      |
| `0x02` | `brn`                    | No      |
| `0x03` | `confusion`              | No      |
| `0x04` | `Recoil\|[of]`           | Yes     |

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

Equivalent to `|-boost|` above, but the Pokémon has healed damage instead. If `Reason` is `0x02`
then the damage was healed `[from]` a draining move indicated by the subsequent byte `[of]`.

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

The Pokémon identified by [`Ident`](#pokemonident) has been inflicted with `Status`. If `Reason` is
`0x02` then the following byte which indicate which `Move` the `Status` is `[from]`.

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

The Pokémon identified by [`Ident`](#pokemonident) has recovered from `Status`.

<details><summary>Reason</summary>

| Raw    | Description  |
| ------ | ------------ |
| `0x00` | None         |
| `0x01` | `\|[msg]`    |
| `0x02` | `\|[silent]` |
</details>

### `|-boost|` (`0x0E`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0E          | Ident         | Reason        | Num           |
      +---------------+---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) has gained `Num` boosts in a stat indicated by
the `Reason`.

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

Equivalent to `|-boost|` above, but for negative stat changes.

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

Clears all boosts from all Pokémon on both sides.

### `|-fail|` (`0x11`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x11          | Ident         | Reason        |
      +---------------+---------------+---------------+

An action denoted by `Reason` used by the Pokémon identified by [`Ident`](#pokemonident) has failed
due to its own mechanics.

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

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x12          | Ident         |
      +---------------+---------------+

A move used by the Pokémon identified by [`Ident`](#pokemonident) missed.

### `|-hitcount|` (`0x13`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x13          | Ident         | Num           |
      +---------------+---------------+---------------+

A multi-hit move hit the Pokémon identified by [`Ident`](#pokemonident) `Num` times.

### `|-prepare|` (`0x14`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x14          | Ident         | Move          |
      +---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) is preparing to charge `Move`.

### `|-mustrecharge|` (`0x15`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x15          | Ident         |
      +---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) must spend the turn recharging from a previous
move.

### `|-activate|` (`0x16`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x16          | Ident         | Reason        |
      +---------------+---------------+---------------+

A miscellaneous effect indicated by `Reason` has activated on the Pokémon identified by
[`Ident`](#pokemonident).

<details><summary>Reason</summary>

| Raw    | Description            |
| ------ | ---------------------- |
| `0x00` | `Bide`                 |
| `0x01` | `confusion`            |
| `0x02` | `move: Haze`           |
| `0x03` | `move: Mist`           |
| `0x04` | `move: Struggle`       |
| `0x05` | `Substitute\|[damage]` |
| `0x06` | `\|\|move: Splash`     |
</details>

### `|-fieldactivate|` (`0x17`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x17          |
      +---------------+

A field condition has activated.

### `|-start|` (`0x18`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x18          | Ident         | Reason        | Move/Types?   |
      +---------------+---------------+---------------+---------------+

A volatile status from `Reason` has been inflicted on the Pokémon identified by
[`Ident`](#pokemonident). If `Reason` is `0x09` then the following byte indicates which `Types` the
Pokémon has changed to. If `Reason` is `0x0A` or `0x0B` then the following byte indicates the `Move`
which has been disabled/mimicked.

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

A volatile status from `Reason` inflicted on the Pokémon identified by [`Ident`](#pokemonident) has
ended.

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

A OHKO move was used sucessfully.

### `|-crit|` (`0x1B`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1B          | Ident         |
      +---------------+---------------+

A move has dealt a critical hit against the Pokémon identified by [`Ident`](#pokemonident).

### `|-supereffective|` (`0x1C`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1C          | Ident         |
      +---------------+---------------+

A move was supereffective against the Pokémon identified by [`Ident`](#pokemonident).

### `|-resisted|` (`0x1D`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1D          | Ident         |
      +---------------+---------------+

A move was not very effective against the Pokémon identified by [`Ident`](#pokemonident).

### `|-immune|` (`0x1E`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x1E          | Ident         | Reason        |
      +---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) is immune to a move.

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

`Source` is the [`PokemonIdent`](#pokemonident) of the Pokémon that transformed into the Pokémon
identified by the `Target` [`PokemonIdent`](#pokemonident).

## Size

As mentioned above, any `Writer` can be used to back the protocol `Log`, and as such something like
an `ArrayList.Writer` can be used to support arbitrary amounts of data being written to the log each
update. For performance reasons it is desirable to be able to preallocate a fixed size buffer for
this, where the recommended size is determined by `pkmn.LOGS_SIZE` which is guaranteed to be able to
handle at least `pkmn.MAX_LOGS` bytes (these constants are defined to be the maximum of all
generations - each generation also has its own parallel constants that can be used instead, e.g.
`pkmn.gen1.LOGS_SIZE`).

Determining the maximum amount of bytes in a single update (i.e. bytes logged by a call to `update`
with each player's `Choice`) per generation is non-trivial and could vary greatly depending on the
constraints:

- **Standard**: The most restrictive constaint supported is one which considers Pokémon Showdown's
  "Standard" restrictions for competitive formats - Species Clause, Cleric Clause, movepool legality
  and bans, etc.
- **Cartridge**: Cartridge legality still enforces anything that can be legitimately obtained on the
  cartridge and used in link battles, but does not enforce any of Pokémon Showdown's clauses or
  mods.
- **"Hackmons"**: A step further than cartridge legality, removing restrictions on moves / items /
  abilities / types / stats / etc - anything which can be hacked into the game before the battle.
- **Fuzzing**: Used for testing, the same "hackmons" constraints but also allowing for arbitrary
  in-battle manipulation as well to be able to set impossible combinations of volatiles statuses or
  side conditions etc.

Furthermore, a **lax** vs. **strict** interpretation of the RNG can be applied - whether or not any
conceivable sequence of events should be considered or only those which can be obtained in practice
via the actual RNG (on either the catridge or Pokémon Showdown).

**"Cartridge" constraints with a lax consideration of the RNG** are used for the purposes of
defining the maximum size constants (though taking a strict intepretation of the RNG is required in
some cases to be able to conservatively set the upper bounds in specific scenarios). The maximum
size of the "fuzzing" use-case is also outlined below (though not encoded in a constant).

*The following maximum log size scenarios were developed with help from
[**@gigalh128**](https://github.com/gigalh128).*

### Generation I

TODO

<details><summary>Details</summary>

In order to maximize log message size in Generation I several observations need to be made:

- `|move`, `|switch|`, `|-damage|`, and `|-heal|` take up the most space in the log
- `|switch|` will result in less bytes than `|move|` because it will not result in any additional
  messages  whereas `|move|` can trigger many others, including `|-damage|` or `|-heal|`
- `|move|` should `|-crit|` and either be `|-supereffective|` or `|-resisted|` in order to use up
  more bytes
- before a `|move|` a Pokémon can activate confusion, and after residual damage from a poison or
  burn status and Leech Seed can be triggered
- only a single Pokémon should `|faint|` at the end. While intially it might seem like having both
  `|faint|` and causing one side to `|win|` would be optimal (two `|faint|` messages and one `|win|`
  is 6 bytes total, a single `|faint|` and a `|turn|` message is 5 bytes), if one side faints you
  miss out on a round of damage and healing from Leech Seed which is 16 bytes
- Substitute activating actually reduces the size of the log as `|-activate|` replaces the larger
  `|-damage|` messages, and in Generation I if the substitute breaks it nullifies the rest of the
  move's effects
- ultimately a `MuliHit` move is optimal as it can generate 5 `|-damage|` messages and a
  `|-hitcount|`

The most important observation is that **Metronome and Mirror Move can be used in tandem to rack up
arbitrary increases in log size via mutual recursion**. Metronome and Mirror Move handlers both
contain checks to prevent infinite self-recursion, but do not check for each other, meaning a
Pokémon can use Metronome to proc Mirror Move to copy their opponent's Metronome to proc Mirror Move
again etc. However, since Mirror Move works off of the `last_used_move` field and Metronome using
a new move overwrites this field, Mirror Move copying an opponent's original Metronome will only
work if a charging move is triggered by the intial Metronome, meaning the other player can not also
perform this loop (and can actually not use a move on their turn at all, as they would then be
locked in by the previous turn's charging move used via Metronome).

With true randomness it seems at face value that with the proper set up the chances of achieving
Metronome → Mirror Move calls would be ${1 \over 163}^N$ (given Metronome can choose 1 out of 163
moves), which while vanishingly small as $N$ increases is still possible. However, both Pokémon Red
and Pokémon Showdown use *pseudo*-random number generators and thus in order to find our way out of
this potential infinite recursion we must strictly consider what is actually possibly with the RNG,
and not just what is possible in theory.

In Pokémon Showdown there are several frame advances between each call (e.g. a consequential roll to
hit, an advance to retarget, etc) and setting up the RNG to accomplish arbitrary recursion is not
feasible in practice. However, in Pokémon Red there is only an inconsequential (i.e. the value is
ignored) critical hit roll for both Metronome and Mirror Move between each roll to determine which
move to use and the seed can be used to set up 10 arbitrary values. Define $X$, $X'$, and $X''$ such
that $X' = 5X+1 \bmod 256$ and $X'' = 5X'+1 \bmod 256$. We want $X'' = 119$ as that will cause
Metronome to use Mirror Move, so $X' = 126$ and $X = 25$.

Thus we can start with a seed of `[126, 119, 25, 126, 119, 25, 126]` to achieve 10 levels of
recursive Metronome → Mirror Move calls. This is an **upper bound** (in reality it would be
impossible to set up the rest of the battle, do 10 rounds of recursion, and still have optimal rolls
on the other side to be able to obtain maximum log size) and only applies to a single player (as
mentioned above the only way to have Mirror Move copy Metronome is if the opponent is locked into a
charging move from a previous Metronome call).

There are then two hypothetical scenarios we need to consider to determine upper bound on the
maximum log size of a single update - one where a single player gets to benefit from the Metronome →
Mirror Move → ... → Metronome → multi hit move and the other side is locked into a charging move or
one where both players simply call a multi hit move through a single iteration of Metronome → Mirror
Move → multi hit.

- **Scenario 1:** recursion + charge move
  - `|-activate|` confusion: 2×3 bytes
  - `|move|` Metronome → `|move|` Mirror Move P1 recursion: 10×6 bytes
  - `|move|` multi-hit: 6 bytes
  - `|move|` P2 turn 2 charging move: 6 bytes
  - `|-crit|`: 2×2 bytes
  - `|supereffective|` or `|resisted|`: 2×2 bytes
  - `|-damage|` multi-hit: 5×8 bytes
  - `|-hitcount|`: 3 bytes
  - `|-damage|` charging: 8 bytes
  - `|-damage|` poison or burn: 2×8 bytes
  - `|-damage|` Leech Seed: 2×8 bytes
  - `|-heal|` Leech Seed: 2×8 bytes
  - `|faint|`: 2 bytes
  - `|turn|`: 3 bytes
  - `0x00`: 1 byte (end of buffer)
- **Scenario 2:** both multi hit
  - `|-activate|` confusion: 2×3 bytes
  - `|move|` Metronome → `|move|` Mirror Move -> `|move|` multi-hit: 6×6 bytes
  - `|-crit|`: 2×2 bytes
  - `|supereffective|` or `|resisted|`: 2×2 bytes
  - `|-damage|` multi-hit: 10×8 bytes
  - `|-hitcount|`: 2×3 bytes
  - `|-damage|` poison or burn: 2×8 bytes
  - `|-damage|` Leech Seed: 2×8 bytes
  - `|-heal|` Leech Seed: 2×8 bytes
  - `|faint|`: 2 bytes
  - `|turn|`: 3 bytes
  - `0x00`: 1 byte (end of buffer)

TODO: setup requires a minimum of 13 rolls. Scenario is 1 byte more, but probably not actually
achievable after set up? Is Scenario 2 achievable?

</details>

### Generation II

TODO
