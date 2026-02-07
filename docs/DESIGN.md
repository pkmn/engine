# Design

> Each individual generation has its own documentation which goes into extensive detail on how they
> are implemented and what their data structures / protocol looks like:
>
> - [Generation I](../src/lib/gen1/README.md)
> - [Generation II](../src/lib/gen2/README.md)
>
> This document exists to provide a high-level overview of the design of the engine in general.

---

https://pkmn.cc/@pkmn/
performance *BUT* accuracy/fidely + generally useful.

like all pkmn projects, engine is partly an "experimental testbed for exploratory research" to help push forward the state of Pokémon battle engines more broadly (aed3, pmariglia), but is a fully formed project that is intended for real world use.


- focused around traditional `update` model as opposed to `all-transitions`/`generate-instructions` for commonly required for AI usecasse etc
  - close adherence to cart/PS = easier to acheive fidelity, can also then intrgration test against reference implementations

- performance of `update` most important which is most relevant for a specific type of MCTS AI, though also because a cheap `update` can be also used as the foundatio of more advanced features

- general purpose
  - bindings to multiple languages
  - can use in the browser(!)
  - can compose well with other pkmn projects (uber binary)
  - can use for a simulator (`-Dlog`)
  - can use for a damage calc or perfect information solver (`-Dchance`/`-Dcalc`)
  - can use for AI (`diff`/`patch`, `Rolls`, `transitions`)

---

Type of engine and tradeoffs (link to pkmn.ai/engines)
Constraints
Fast as possible
Compatible with PS
Optimize for game throughput and accuracy = more like decompiled code / PS as opposed to make/unmake
Forces implementation of Chance/Calc to be a particular way
Talk about “diff” instead of make/unmake

---

## Project Structure

- [`Makefile`](../Makefile): the top-level `Makefile` orchestrates the tasks from `build.zig` and
  `package.json`
  - [`build.zig`](../build.zig): deals with building all Zig code
  - [`package.json`](../package.json): deals with building all JavaScript code
- [`examples`](../examples): examples of using the engine across all supported targets
- [`lib`](../src/lib): the Zig code for the `libpkmn` engine
  - [`pkmn.zig`](../src/lib/pkmn.zig): the main entry point for the Zig library
  - [`c.zig`](..src/lib/c.zig)/[`node.zig`](..src/lib/node.zig)/[`wasm.zig`](..src/lib/wasm.zig):
    code which exposes the `libpkmn` API for non-Zig uses
  - [`common`](..src/lib/common): code shared by all generations (common data
    structures/RNG/protocol logic)
  - `gen*`: the code for the respective Pokémon generations implemented by the engine
- [`pkg`](../src/pkg): code for the `@pkmn/engine` JavaScript package with driver code for the
  engine
- [`test`](../src/test): code for high level tests (integration, benchmarking, fuzzing) - unit tests
  live inline/beside the code they implement in the `lib`/`pkg` directories
- [`tools`](../src/tools): miscellaneous scripts and tools useful for working on the pkmn engine
