<p align="center">
  <img alt="pkmn/engine" width="192" height="192" src="https://pkmn.cc/engine.png" />
  <br />
  <br />
  <a href="https://github.com/pkmn/engine/actions/workflows/test.yml">
    <img alt="Test Status" src="https://github.com/pkmn/engine/workflows/Tests/badge.svg" />
  </a>
  <img alt="WIP" src="https://img.shields.io/badge/status-WIP-red.svg" />
  <a href="https://github.com/pkmn/engine/blob/master/LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-blue.svg" />
  </a>
</p>

A minimal, complete Pokémon battle simulation engine optimized for performance and
designed for tooling, embedded systems, and [artifical
intelligence](https://github.com/pkmn/0-ERROR) use cases.

TODO Features

- feature
- feature
- feature

goals/non-goals disclaimer: not intended to replace PS etc, support mods, arbitrary pokemon
releases. yes for WASM, embedded, minimax, damage calc

## Benchmarks

TODO

<p align="center">
  <img src="https://gist.githubusercontent.com/scheibo/1edecb6e76dd9176691e50819d90e841/raw/f15db8b25ae5a64d3f712fba79416d65c0c9b0e2/benchmark.svg" alt="Bar chart with benchmark results">
</p>

## Installation

The driver code can be installed from [npm](https://www.npmjs.com/package/@pkmn/engine):

```sh
$ npm install @pkmn/engine
```

The `zig` compiler is required to build the actual engine code. The Zig website has [installation
instructions](https://ziglang.org/learn/getting-started/) which walk through how to do this on each
platform - the engine code currently is being built and tested against the latest Zig nightly
development builds (`>= 0.9.0-dev.1583+a7d215759`).

After successfully installing `zig` , clone this repository (optionally with the `--depth` flag set
to `1` to perform a shallow copy) and run `zig build` from within the directory that has been
created by `git`:

```sh
$ git clone https://github.com/pkmn/engine.git # --depth 1
$ cd engine
$ zig build --prefix .
```

All binaries will end up in `bin` and libraries in `lib` . See `zig build --help` for build options.

## Usage

TODO

## License

The pkmn engine is distributed under the terms of the [MIT License](LICENSE).
