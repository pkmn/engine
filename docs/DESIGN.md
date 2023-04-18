# Design

> Each individual generation has its own documentation which goes into extensive detail on how they
> are implemented and what their data structures / protocol looks like:
>
> - [Generation I](../src/lib/gen1/README.md)
> - [Generation II](../src/lib/gen2/README.md)
>
> This document exists to provide a high-level overview of the design of the engine in general.

The pkmn engine is first and foremost designed for performance. The engine's most impactful design
principle is that of **"no compromises"** when it comes to performance -
ergonomics/simplicity/convenience are always trumped by performance, and the engine will never
tradeoff performance for any other feature. This principle leads to the following:

- the engine is much **more targeted in scope** than either the original game cartridge (which
  includes code for an entire RPG) or Pokémon Showdown (which supports a fully featured simulator in
  addition to a chat server). The engine more closely approximates a subset of Pokémon Showdown's
  [`Battle`](https://github.com/smogon/pokemon-showdown/blob/master/sim/battle.ts) class:
  - there is no
    [`BattleStream`](https://github.com/smogon/pokemon-showdown/blob/master/sim/battle-stream.ts)
    equivalent - Pokémon Showdown's stream abstraction is asynchronous and text based, both of which
    add latency
  - the is no support for validating teams/formats/custom rules - these are expected to be taken
    care of at a higher level
  - the is no input (choice) validation - the engine is expected to be wrapped by some form of
    driver code which either provides the input validation for the user or to be driven by code
    which can only provide valid input
- [**data-oriented design**](https://github.com/dbartolini/data-oriented-design): in order to
  minimize cache misses / improve data locality, extreme care is taken to [layout data
  structures](http://www.catb.org/esr/structure-packing/) as efficiently as possible, and **pointers
  are eschewed** in favor of
  ['handles'](https://floooh.github.io/2018/06/17/handles-vs-pointers.html) which directly index
  into arrays.
- **each Pokémon generation is implemented separately**, with code or data being shared only in
  cases where there is no overhead. One generation of Pokémon should not have to pay the price of
  dealing with the complexities of other past or future generations. In the worst case, this results
  in some code duplication, but means that any given generation is easy to reason about and
  optimize. Despite this duplication, binary size is still kept down as **data is ruthlessly
  pruned** to contain only the bare minimum.
- serialization either consists of simply treating structures as an array of bytes or, in the case
  of the log [protocol](PROTOCOL.md), writing bytes in the fastest way possible. As a result, the
  engine's **protocol and API changes depending on the system**, as all integers will be written
  using **native-endianness** as that is guaranteed to be the fastest to read and write on any
  particular system.
- **no strings** are used in the engine - strings are to be dealt with by higher levels (e.g. in
  driver code) and as a result the engine just has to deal with small and efficient primitive data
  types. All identifiers can be represented as small `enum` values which can be used to index
  directly into arrays of data where necessary with no additional hashing or indirection required.
- the engine **never dynamically allocates memory** - given the fact the engine only implements the
  existing Pokémon battle systems (which were designed to run on constrained hardware), the engine
  can get away with requiring users to preallocate fixed size buffers and never needs to allocate
  memory on demand.
- data is structured such that in most cases **lookups are not required** (i.e. range checks are
  used instead) or can be done with an efficient linear search. In extreme cases, [perfect
  hashing](https://en.wikipedia.org/wiki/Perfect_hash_function) is utilized to avoid ever having to
  probe.

The biggest challenge resulting from the "no compromises" design principle is that **the engine must
be compiled with specific flags to opt-in to certain behavior**. By default, the pkmn engine
implements Pokémon as dictated by the games themselves. However, the online Pokémon battling
playerbase has agreed to a certain number of small modifications in order to improve the competitive
nature of the game, and these are implemented by the leading simulator, Pokémon Showdown. If
**`-Dshowdown`** is enabled, the pkmn engine will be configured to:

- match Pokémon Showdown's **RNG semantics** instead of the cartridge's. Pokémon Showdown does
  **not** implement the correct pseudo-random number generator for each format (it implements the
  Generation V & VI PRNG and applies it to all generations and performs a different amount of calls,
  with different arguments and in different order than the cartridge)
- implements any **bugs** Pokémon Showdown's codebase includes
- implements the **modifications** required by Pokémon Showdown's "Standard" ruleset (e.g. Endless
  Battle Clause, Sleep/Freeze/Desync/Switch Priority Clause Mod, etc)

As a result, when compiled with `-Dshowdown` enabled the pkmn engine should exactly match the
behavior of Pokémon Showdown instead of the cartridge (this is verified through the integration
tests).

By default, the engine produces no output about the state of a battle, merely communicating progress
and termination via its `Result` type. However, during play on both the cartridges and on Pokémon
Showdown messages about what has happened are displayed, providing additional information to the
participants. Given that not all use cases (e.g. random [Monte Carlo tree search
](https://en.wikipedia.org/wiki/Monte_Carlo_tree_search) playouts) require this information,
enabling this output is also opt-in through **`-Dlog`**. Unlike with the cartridge or Pokémon
Showdown this logging is stripped down and utilizes a native binary [protocol](../PROTOCOL.md),
though contains all of the information required to produce identical logs to either.

## Project Structure

- [`Makefile`](../Makefile): the top-level `Makefile` orchestrates the tasks from `build.zig` and
  `package.json`
  - [`build.zig`](../build.zig): deals with building all Zig code
  - [`package.json`](../package.json): deals with building all JavaScript code
- [`examples`](../src/examples): examples of using the engine across all supported targets
- [`lib`](../src/lib): the Zig code for the `libpkmn` engine
  - [`pkmn.zig`](../src/lib/pkmn.zig): the main entry point for the Zig library
  - [`bindings`](..src/lib/bindings): code which exposes the `libpkmn` API for non-Zig uses
  - [`common`](..src/lib/common): code shared by all generations (common data
    structures/RNG/protocol logic)
  - `gen*`: the code for the respective Pokémon generations implemented by the engine
- [`pkg`](../src/pkg): code for the `@pkmn/engine` JavaScript package with driver code for the
  engine
- [`test`](../src/test): code for high level tests (integration, benchmarking, fuzzing) - unit tests
  live inline/beside the code they implement in the `lib`/`pkg` directories
- [`tools`](../src/tools): miscellaneous scripts and tools useful for working on the pkmn engine

## Appendix

The design of the pkmn engine is heavily influenced by that of both the original game and by the
most popular and influential simulator. Due to a variety of reasons, the pkmn engine code is both
**simpler and faster** than its predecessors.

### Pokémon Red & Blue

The battle engine from the original game code was written for limited, legacy, hardware while under
time pressure and as one aspect in a complete role-playing game:

- the [**GB Z80**](https://rgbds.gbdev.io/docs/v0.5.1/gbz80.7) hardware does not support
  multiply/divide instructions efficiently (and certainly doesn't support modern SIMD instructions)
- the game code's battle engine includes many **features** that can be removed when only emulating
  the post-game "link" battle system utilized by competitive play
  - the ["Old Man" tutorial](https://bulbapedia.bulbagarden.net/wiki/Old_man_(Kanto))
  - the [Safari Zone](https://bulbapedia.bulbagarden.net/wiki/Kanto_Safari_Zone)
  - unidentified ghosts
  - in-battle item use
  - "switch" vs. "set" mode
  - badge boosts / disobedience
  - catching Pokémon
  - running from battle
  - experience
- the game's **data** was created organically and as a result is **laid out haphazardly** instead of
  in terms of what is most efficient

By streamlining the existing code and updating it for a modern instruction set it is possible to
both reduce complexity and increase performance.

## Pokémon Showdown!

Like the original game code, Pokémon Showdown's codebase has grown organically and is **concerned
about a different set of constraints** than those that the pkmn engine is focused on. Pokémon
Showdown is a clean room implementation of a generic Pokémon battling engine **focused on
extensibility and ease of development**. Pokémon Showdown makes several design tradeoffs which
increase complexity and inhibit performance, but novice coders are able to create custom formats
with ease (and in practice entirely new generations of Pokémon can be supported within a matter of
hours):

- Pokémon Showdown is structured such that the core **code reflects the current generation** of
  Pokémon games and past generations are implemented as a set of "mods" to data files and handlers.
  This generally means the most relevant code is easy to find and modify, though the core flow is
  substantially more complicated as it contains branches and hooks for all other generations (and
  the simpler code for other generations must **pay the price for all of the modern generation
  code**). Furthermore, it becomes difficult to determine where exactly code for a specific older
  generation lives, as the functionality may be inherited from newer generations (which is counter
  intuitive to how the game mechanics actually evolved).
- Pokémon Showdown is built around a custom **generic event system** with an intricate bubbling and
  priority system. This system is very powerful, though event dispatch is expensive and the
  slowest part of the engine. While this bottleneck has been improved since it was first
  [identified](https://pkmn.cc/optimize), the pattern of **searching for handlers is slow** and a
  model where handlers are pre-registered instead of searched for would be a large improvement (i.e.
  currently the event loop searches through all possible sources for any handlers, despite there
  usually being 0 or 1 handler that actually needs to run).
- Pokémon Showdown's most foundational type is an **`ID`** - a lower case string with special
  characters removed. While this is fairly convenient for developers who can easily tell at a glance
  what object an `ID` is intended to reference, it is **inefficient** as it relies heavily on the
  assumption of the compiler performing string interning and uses up more memory than integers (JS
  numbers are technically all 8 bytes, but JS runtimes usually implement ['Smi' optimizations for 32
  bit integers](https://github.com/v8/v8/blob/a9e3d9c7/include/v8.h#L253)). More importantly,
  Pokémon Showdown **frequently calls `toID`** on strings to convert strings to an `ID` to the point
  where `toID` is Pokémon Showdown's hottest function. Pokémon Showdown should be
  able to leverage TypeScript's type checking to enable only calling `toID` on input and not
  multiple times over the lifetime of the `ID` to minimize this cost, but this still does not fully
  mitigate the issue.
- Pokémon Showdown's **data layer is fully featured** and designed to support a plethora of use
  cases beyond what is specifically required for implementing a Pokémon battle. This data is useful
  for various additional tools and features, but the more **general API results in bloat** that
  hinders performance. In a similar vein, many of Pokémon Showdown's core classes are designed for
  convenience and for developer ergonomics as opposed to performance (e.g. no distinction between
  the `ActivePokémon`'s fields and a `Pokémon` in the party, resulting in redundant data being
  stored and filling up cache lines).
- Pokémon Showdown does not pay close attention to
  [**monomorphism**](https://mrale.ph/blog/2015/01/11/whats-up-with-monomorphism.html) and
  frequently initializes key data objects inefficiently (e.g. the **`Object.assign(this, data)`
  pattern** used by its foundational types). Always ensuring object fields are initialized in the
  same order becomes even more difficult due to the raw size/number of fields involved (i.e. for
  objects with only a few fields it is easier to ensure they are always initialized in the same
  order, but many of Pokémon Showdown's game objects include 50-100 fields).
- Most of Pokémon Showdown's core APIs involve **looking up keys in a map** (e.g. lookup by `ID`)
  which is inherently less efficient than directly indexing into an array. While both are ultimately
  $\Theta(1)$, the additional pointer chasing / redirection result in cache misses and poor
  performance.
- Pokémon Showdown produces **text protocol logs in all cases**. While invaluable for debugging, the
  text logs are expensive to produce and parse, and importantly, are often wasted work for use cases
  where they are simply ignored.
- Pokémon Showdown is written in JavaScript/TypeScript which makes it **unergonomic to have
  precisely laid out data structures with minimally sized fields** (as mentioned above, the minimum
  data size of a number is going to be 4-8 bytes outside of making all the code manipulate an
  `ArrayBuffer`), substantially larger than what is convenient to use in lower level languages.
  While modern JavaScript engines like V8 and JSC are impressive, there is a limit to how much help
  they can provide when push comes to shove. Furthermore, Pokémon Showdown relies on a lot of
  **dynamic memory allocation** which is inherently slower than repurposing existing objects on the
  stack would be. Finally, being **written in JavaScript** means third-party developers wishing to
  leverage Pokémon Showdown's engine must either also be written in JavaScript, embed a JavaScript
  runtime (and pay in terms of overhead on the boundary), or interface with the engine through
  standard input/output streams (which incurs **syscall overhead**).

Ultimately, the Pokémon Showdown's design choices may result in a flexible engine which is easy to
expand upon, but its architecture is fundamentally at odds with achieving peak performance.
