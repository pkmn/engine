# Design

The pkmn engine is able to be much faster and simpler than both Pokemon
Showdown! and the original game cartridge TODO

## Pokemon Red & Blue

The battle engine from the original game code was written for limited, legacy,
hardware while under time pressure and as one aspect in a complete role-playing
game:

- the GB Z80 hardware does not support multiply/divide instructions efficiently
  (and certainly doesn't support modern SIMD instructions)
- the game code's battle engine includes many features that can be removed when
  only emulating the post-game "link" battle system utilized by competitive play
  - the ["Old Man"
    tutorial](https://bulbapedia.bulbagarden.net/wiki/Old_man_(Kanto))
  - the
    [Safari Zone](https://bulbapedia.bulbagarden.net/wiki/Kanto_Safari_Zone)
  - unidentified ghosts
  - in-battle item use
  - "switch" vs. "set" mode
  - badge boosts/disobedience
  - catching Pokemon
  - running from battle
  - experience
- the game's data was created organically and as a result is laid out
  haphazardly instead of in terms of what is most efficient

By streamlining the existing code and updating it for a modern instruction set
it is possible to both reduce complexity and increase performance.

## Pokemon Showdown!

Like the original game code, Pokemon Showdown's codebase has grown organically
and is concerned about a different set of constraints than those that the pkmn
engine is focused on. Pokemon Showdown is a clean room implementation of a
generic Pokemon battling engine focused on extensibility and ease of
development. Pokemon Showdown makes several design tradeoffs which increase
complexity and inhibit performance, but novice coders are able to create custom
formats with ease (and in practice entirely new generations of Pokemon can be
supported within a matter of hours):

- Pokemon Showdown is structured such that the core code reflects the current
  generation of Pokemon games and past generations are implemented as a set of
  "mods" to data files and handlers. This generally means the most relevant code
  is easy to find and modify, though the core flow is substantially more
  complicated as it contains branches and hooks for all other generations (and
  the simpler code for other generations must pay the price for all of the
  modern generation code). Furthermore, it becomes difficult to determine where
  exactly code for a specific older generation lives, as the funtionality may be
  inherited from newer generations (which is counter intuitive to how the game
  mechanics actually evolved)
- Pokemon Showdown is built around a custom generic events system with an
  interactive bubbling and priority system. This system is very powerful, though
  event dispatch is very expensive and the slowest part of the engine. While
  this bottleneck has been improved since it was first
  [identified](https://pkmn.cc/optimize), the pattern of searching for handlers
  is slow and a model where handlers are preregistered instead of searched for
  would be a large improvement (i.e. currently the event loop searches through
  all possible sources for any handlers, despite there usually being 0 or 1
  handler that actually needs to run).
- Pokemon Showdown's most foundational type is an `ID` - a lower case string
  with special characters removed. While this is fairly convenient for
  developers who can easily tell at a glance what object an `ID` is intended to
  reference, it is inefficient as it relies heavily on the assumption of the
  compiler performing string interning and uses up more memory than integers (JS
  numbers are technically all 8 bytes, but JS runtimes usually implement 'Smi'
  optimizations for 32 bit integers). More importantly, Pokemon Showdown
  frequently calls `toID` on strings to convert strings to an `ID` to the point
  where `toID` is Pokemon Showdown's hottest function. Pokemon Showdown should
  be able to leverage TypeScript's type checking to enable only calling `toID`
  on input and not multiple times over the lifetime of the `ID` to minimize this
  cost, but this still does not fully mitigate the issue.
- Pokemon Showdown's data layer is fully featured and designed to support a
  plethora of use cases beyond what is specifically required for implementing
  a Pokemon battle. This data is useful for various additional tools and
  features, but the more general API results in bloat that hinders performance.
  In a similar vein, many of Pokemon Showdown's core classes are designed for
  convenience and for developer ergonomics as opposed to performance (e.g. no
  distinction between the `ActivePokemon`'s fields and a `Pokemon` in the party,
  resulting in redundant data being stored and filling up cache lines).
- Pokemon Showdown does not pay close attention to [monomorphism]() and
  frequently initializes key data objects inefficiently (e.g. the
  `Object.assign(this, data)` pattern used by its foundational types). Always
  ensuring object fields are initialized in the same order becomes even more
  difficult due to the raw size/number of fields involved (i.e. for objects with
  only a few fields it is easier to ensure they are always initialized in the
  same order, but many of Pokemon Showdown's game objects involve 50-100
  fields).
- Most of Pokemon Showdown's core APIs involve looking up keys in a map (e.g.
  lookup by `ID`) which is inherently less efficient than directly indexing into
  an array. While both are ultimately `O(1)` in the average case, the additional
  pointer chasing/redirection result in cache misses and poor performance.
- Pokemon Showdown produces text protocol logs in all cases. While invaluable
  for debugging, the text logs are expensive to produce and parse, and
  importantly, are often wasted work in many use cases where they are simply
  ignored.
- Pokemon Showdown is written in JavaScript/TypeScript which makes it
  unergonomic to have precisely laid out data structures with minimally sized
  fields (as mentioned above, the minimum data size of a number is going to be
  4-8 bytes outside of making all the code manipulate `ArrayBuffer`s),
  substantially larger than what is convenient to use in lower level languages.
  While modern JavaScript engines like V8 and JSC are impressive, there is a
  limit to how much help they can provide when push comes to shove. Furthermore,
  Pokemon Showdown relies on a lot of dynamic memory allocation which is
  inherently slower than repurposing existing objects on the stack would be.
  Finally, being written in JavaScript means third-party developers wishing to
  leverage Pokemon Showdown's engine must either also be written in JavaScript,
  embed a JavaScript runtime (and pay in terms of overhead on the boundary), or
  interface with the engine through standard input/output streams (which incur
  syscall overhead).

Ultimately, the Pokemon Showdown's design choices may result in a flexible
engine which is easy to expand upon, but its architecture is fundamentally at
odds with acheiving peak performance.


## pkmn

The pkmn engine is much more targetted in scope than either the original game
cartridge (which includes code for an entire RPG) or Pokemon Showdown (which
supports a fully featured simulator in addition to a chat server). The engine
more closely approximates a subset of Pokemon Showdown's [`Battle](TODO)` class:

- there is no [`BattleStream`](TODO) equivalent - Pokemon Showdown's stream
  abstraction is asynchronoux and text based, both of which add latency
- the is no support for validating teams/formats/custom rules - these are
  expected to be taken care of at a higher level
- the is input (choice) validation - the engine is expected to be wrapped by
  some form of driver code which either provides the input validation for the
  user or to be driven by code which can only provide valid input.
- pkmn's wire protocol is opt-in, binary, and minimal compared to Pokemon
  Showdown's expressive text protocol.


---

- separate code and data for each gen (despite some duplicated data = still
  smaller/similar code size than PS due only including percisely the required
  data/encoding it more efficiently)
- principle: "no compromises"
  - native endianess
- no dynamic allocations
- NO STRINGS
- no pointers, handles into array and minimal/no searching (sorted arrays,
  perfect hashing)
- able to use smaller integer types
- precise layout

- rng accuracy (2 different)


Much of Pokemon Showdown's performance issues stem from its desire to easily
support "mods" - if Pokemon Showdown only cared about handling solely the data
from the game it would have a fixed 

- [Handles vs. Pointers][handles]
- [Data-Oriented Design][dod] ([book][dodbook])
- [The Lost Art of Structure Packing][packing]
- [Performance Speed Limits][limits]
- [Latency Numbers Reference][numbers]
- [Operation Costs in CPU Clock Cycles][costs]

[dod]: https://github.com/dbartolini/data-oriented-design
[dodbook]: https://www.dataorienteddesign.com/dodbook/
[handles]: https://floooh.github.io/2018/06/17/handles-vs-pointers.html
[packing]: http://www.catb.org/esr/structure-packing/
[limits]: https://travisdowns.github.io/blog/2019/06/11/speed-limits.html
[numbers]: https://github.com/sirupsen/napkin-math#numbers
[costs]: http://ithare.com/infographics-operation-costs-in-cpu-clock-cycles/


TODO Performance

- constraint: engine (but not required for wrapper) does not allocate any dynamic memory
- constraint: no pointers in data representation - must be copyable by `mem.copy`
- native endianess for trivial input/output
- padding, alignment, cache lines
- dont create protocol objects, just write byes directly to stream


- dont pay at all for abstractions etc not used in the gen (gen 2 doesnt pay for inheritance of gen 1, doesnt have to deal with `spc`, etc) = possibly a lot less code reuse! inheritance can be done at compile time (just pointers, no redundant memory). gen 8 doesnt need to pay for gen 1->7









