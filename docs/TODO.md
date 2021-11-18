# TODO

## Experiments

- [ ] bit shuffling stdio between Zig and JS (can JS spawn engine and communicate with it)?
- [ ] determine domain/range in each gen of possible protocol `Args` and `KWArgs`
- [ ] `zig-napi-example` based on [`Tigerbeetle-node`](https://github.com/coilhq/tigerbeetle-node)
  - [ ] run on Linus/macOS/Windows
  - [ ] do postinstall of Zig if required (pinned) version is not present + download node headers
  - [ ] (stretch)) `prebuild` approach
- [ ] change `ps/integration` lockstep test to operate on `Battle` directly instead of `BattleStream`

## `@pkmn/ids`
  
- [ ] create `@pkmn/ids` private package within `pkmn/ps` with a generate script which packages ids: `gen.moves.ids.get(surf)` & `get.moves.ids.getbyid(1)`;
- [ ] `import` script depends on `@pkmn/ids`, has logic for augmenting data files (might need to add entries if were purely inheriting or not mentioned! also, IDs for formes cause earlier mons to shift, so IDs are not stable between generations)  
- [ ] change `Dex` (`@pkmn/sim` and `@pkmn/dex`) logic to build up IDs `DexTable` while implementing file loading/inheritance
- [ ] make respective tests depend on `@pkmn/ids` to verify matching for every gen and data type
- [ ] update `@pkmn/sim` docs to call out the engine IDs addition as a difference
- [ ] expose engine IDs via `@pkmn/data` APIs  
- [ ] update docs, cut release as `v0.5.0`

## Protocol

- [ ] consider [`serialization.zig`](https://github.com/ziglang/std-lib-orphanage/blob/master/std/serialization.zig)

## Performance

## Driver

- [ ] support both stdio (reading and writing buffers across stdio) and Node-API
- [ ] implements binary protocol encode/decode
- [ ] turn `Battle.update` responses into `|request|` (can consider moving down a layer into an
  optional piece of the engine)
- [ ] `BattleStream` wrapper (and `BattleTextStream`)
- [ ] ship `simulate-battle` stripped down drop-in
- [ ] **integration tests**: run streams in lockstep (like `@pkmn/sim`) and compare output *and*
  ensure binary protocol roundtrips
  - [ ] override PS `PRNG` to match `@pkmn/engine` for the specific gens!

## Engine

- [ ] evaluate writer APIs - use [buffered writing](https://github.com/ziglang/zig/issues/4358) -
  ensure protocol is a single syscall (`write`? `writev`? `mmap`?)
- [ ] update code-generation to use `mustache` and templates in `lib/common/data`
- [ ] generate all data for Gen 1 - 8 once `@pkmn/data` has support for IDs (will need different
  templates based on generation ranges)
- [ ] implement binary protocol *encoding* via 0-copy low overhead approach that can be compiled
  out of the library
- [ ] add datatypes (`pokemon.zig`, `side.zig`, etc) for Gen 2
- [ ] move `stored` out of `Pokemon` and into `party`/`team`, justify `level` duplication
- [ ] add tests to ensure each documented glitch either works or is deliberately not implemented
  (eg. desyncs)
- [ ] watch out for [packed](https://github.com/ziglang/zig/issues/9943)
  [struct](https://github.com/ziglang/zig/issues/10104) issues
- [ ] ensure trace is 0 overhead in MCTS build (use `@import("build_options")` to mark as dead code)

## Project

- [ ] add `Makefile` to handle orchestrating `npm` vs. `zig` build management (generate, build,
  install, lint, fix, test, etc)
- [ ] figure out how to automatically cross-compile release artifacts and cut releases based on
  tags
- [ ] `README.md`
  - [ ] installation instructions (move development instructions to alternate section)
  - [ ] feature set
  - [ ] usage
  - [ ] disclaimer (Pokémon Showdown comparison - link to `DESIGN.md` for differences with PS)
- [ ] add big-endian architecture to CI tests (eg. [using
  `qemu-mips`](https://github.com/google/flatbuffers/blob/master/tests/RustTest.sh#L18-L22))

## Design

- [ ] definition goes in the first gen it was relevant, subsequent gens forward definition (eg. Gen
  5 imports Gen 2's `Type`/`Types`)
