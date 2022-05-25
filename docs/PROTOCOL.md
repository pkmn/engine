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
any `Writer` implementation is allowed this `Log` could instead write to standard output (Note that
in Zig the standard out writer is not buffered by default - you must use a
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

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x09          |
      +---------------+

Player 1 has won the battle.

### `|lose` (`0x09`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x09          |
      +---------------+

Player 2 has won the battle.

### `|tie|` (`0x0A`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x0A          |
      +---------------+

The battle has ended in a tie.

### `|-damage|` (`0x0B`)

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

The Pokémon identified by [`Ident`](#pokemonident) has taken damage and now has the `Current HP`,
`Max HP` and `Status`. If `Reason` is in `0x04` - `0x07` then the following byte indicates the
[`PokemonIdent`](#pokemonident) of the source `[of]` the damage.

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

### `|-heal|` (`0x0C`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0C          | Ident         | Current HP                    |
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

### `|-status|` (`0x0D`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0D          | Ident         | Status        | Reason        |
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

### `|-curestatus|` (`0x0E`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0E          | Ident         | Status        | Reason        |
      +---------------+---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) has recovered from `Status`.

<details><summary>Reason</summary>

| Raw    | Description  |
| ------ | ------------ |
| `0x00` | None         |
| `0x01` | `\|[msg]`    |
| `0x02` | `\|[silent]` |
</details>

### `|-boost|` (`0x0F`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0F          | Ident         | Reason        | Num           |
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

### `|-unboost|` (`0x10`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x0G          | Ident         | Reason        | Num           |
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

### `|-clearallboost|` (`0x11`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x11          |
      +---------------+

Clears all boosts from all Pokémon on both sides.

### `|-fail|` (`0x12`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x12          | Ident         | Reason        |
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

### `|-miss|` (`0x13`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x13          | Ident         |
      +---------------+---------------+

A move used by the Pokémon identified by [`Ident`](#pokemonident) missed.

### `|-hitcount|` (`0x14`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x14          | Ident         | Num           |
      +---------------+---------------+---------------+

A multi-hit move hit the Pokémon identified by [`Ident`](#pokemonident) `Num` times.

### `|-prepare|` (`0x15`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x15          | Ident         | Move          |
      +---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) is preparing to charge `Move`.

### `|-mustrecharge|` (`0x16`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x16          | Ident         |
      +---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) must spend the turn recharging from a previous
move.

### `|-activate|` (`0x17`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x17          | Ident         | Reason        |
      +---------------+---------------+---------------+

A miscellaneous effect indicated by `Reason` has activated on the Pokémon identified by
[`Ident`](#pokemonident).

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

### `|-fieldactivate|` (`0x18`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x18          |
      +---------------+

A field condition has activated.

### `|-start|` (`0x19`)

    Byte/     0       |       1       |       2       |       3       |
       /              |               |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+---------------+
     0| 0x19          | Ident         | Reason        | Move/Types?   |
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

### `|-end|` (`0x1A`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x1A          | Ident         | Reason        |
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

### `|-ohko|` (`0x1B`)

    Byte/     0       |
       /              |
      |0 1 2 3 4 5 6 7|
      +---------------+
     0| 0x1B          |
      +---------------+

A OHKO move was used sucessfully.

### `|-crit|` (`0x1C`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1C          | Ident         |
      +---------------+---------------+

A move has dealt a critical hit against the Pokémon identified by [`Ident`](#pokemonident).

### `|-supereffective|` (`0x1D`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1D          | Ident         |
      +---------------+---------------+

A move was supereffective against the Pokémon identified by [`Ident`](#pokemonident).

### `|-resisted|` (`0x1E`)

    Byte/     0       |       1       |
       /              |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+
     0| 0x1E          | Ident         |
      +---------------+---------------+

A move was not very effective against the Pokémon identified by [`Ident`](#pokemonident).

### `|-immune|` (`0x1F`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x1F          | Ident         | Reason        |
      +---------------+---------------+---------------+

The Pokémon identified by [`Ident`](#pokemonident) is immune to a move.

<details><summary>Reason</summary>

| Raw    | Description |
| ------ | ----------- |
| `0x00` | None        |
| `0x01` | `\|[ohko]`  |
</details>

### `|-transform|` (`0x20`)

    Byte/     0       |       1       |       2       |
       /              |               |               |
      |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
      +---------------+---------------+---------------+
     0| 0x20          | Source        | Target        |
      +---------------+---------------+---------------+

`Source` is the [`PokemonIdent`](#pokemonident) of the Pokémon that transformed into the Pokémon
identified by the `Target` [`PokemonIdent`](#pokemonident).
