# TODO

## Experiments

- [ ] bit shuffling stdio between Zig and JS (can JS spawn engine and communicate with it)?
- [ ] `zig-napi-example` based on [`Tigerbeetle-node`](https://github.com/coilhq/tigerbeetle-node)
  - [ ] run on Linus/macOS/Windows
  - [ ] do postinstall of Zig if required (pinned) version is not present + download node headers
- [ ] change `ps/integration` lockstep test to operate on `Battle` directly instead of `BattleStream`

## Driver

- [ ] **integration tests**: run streams in lockstep (like `@pkmn/sim`) and compare output *and*
  ensure binary protocol roundtrips

## Project

- [ ] figure out how to automatically cross-compile release artifacts and cut releases based on
  tags
- [ ] `README.md`
  - [x] installation instructions (move development instructions to alternate section)
  - [ ] feature set
  - [ ] usage
  - [ ] disclaimer (Pokémon Showdown comparison - link to `DESIGN.md` for differences with PS)
- [ ] add big-endian architecture to CI tests (eg. [using
  `qemu-mips`](https://github.com/google/flatbuffers/blob/master/tests/RustTest.sh#L18-L22))
