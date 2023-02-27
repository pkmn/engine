<p align="center">
  <img alt="pkmn/engine" width="192" height="192" src="https://pkmn.cc/engine.svg" />
  <br />
  <br />
  <a href="https://github.com/pkmn/engine/actions/workflows/test.yml">
    <img alt="Test Status" src="https://github.com/pkmn/engine/workflows/Tests/badge.svg" />
  </a>
  <a href="#status">
    <img alt="WIP" src="https://img.shields.io/badge/status-WIP-red.svg" />
  </a>
  <a href="https://github.com/pkmn/engine/blob/master/LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-blue.svg" />
  </a>
</p>
<hr />

A minimal, complete, Pokémon battle simulation engine optimized for performance and
[designed](docs/DESIGN.md) for tooling, embedded systems, and [artificial
intelligence](https://github.com/pkmn/0-ERROR) use cases. This engine aims to be a frame-accurate and
[bug-for-bug compatible](http://www.catb.org/jargon/html/B/bug-for-bug-compatible.html)
implementation of both Pokémon battles as defined by the original game code, and the [Pokémon
Showdown](https://pokemonshowdown.com/)[^1] simulator which represents Pokémon battling as practically
interpreted online.

The pkmn engine is up to [**XXXX× faster**](docs/TESTING.md#results) than the
[patched](docs/TESTING.md#patches) [Pokémon Showdown simulator
code](https://github.com/smogon/pokemon-showdown) when playing out supported formats in
compatibility mode and is extensively [tested](docs/TESTING.md) and [documented](docs). Note,
however, that the engine is **not a fully featured simulator** but is instead a low-level library
which can be used as a building block for more advanced use cases.

## Installation

This repository hosts both the engine code (written in [Zig](https://ziglang.org/)) and driver code
(written in [TypeScript](https://www.typescriptlang.org/)).

### `libpkmn`

Binaries of the engine code can be downloaded from the
[releases](https://github.com/pkmn/engine/releases) tab on GitHub, or you can [download the source
code](https://github.com/pkmn/engine/archive/refs/heads/main.zip) directly and build it with the
latest `zig` compiler, see `zig build --help` for build options:

```sh
$ curl https://github.com/pkmn/engine/archive/refs/heads/main.zip -o engine.zip
$ unzip engine.zip
$ cd engine
$ zig build --prefix /usr/local -Doptimize=ReleaseFast
```

The Zig website has [installation instructions](https://ziglang.org/learn/getting-started/) which
walk through how to install Zig on each platform - the engine code should work on Zig v0.11.0 dev
build 1711 or greater, though tracks Zig's master branch so this may change in the future if
breaking language changes are introduced:

`libpkmn` can be built with `-Dshowdown` to instead produce the Pokémon Showdown compatible
`libpkmn-showdown` library. Furthermore, trace logging can be enabled through `-Dtrace`. The
`libpkmn` and `libpkmn-showdown` objects available in the binary release are compiled with and
without the `-Dtrace` flag respectively.

### `@pkmn/engine`

The driver code can be installed from [npm](https://www.npmjs.com/package/@pkmn/engine):

```sh
$ npm install @pkmn/engine
```

The driver depends on being able to find compiled Node/WASM addons in
`node_modules/@pkmn/engine/build/lib` in order to be useful. When you install the package a
[`postinstall` lifecycle script](https://docs.npmjs.com/cli/v8/using-npm/scripts) will run
[`install-pkmn-engine`](src/bin/install-pkmn-engine) which will check for a compatible `zig`
compiler (see above regarding minimum version) and download one to
`node_module/@pkmn/engine/build/bin` if it can't find one, as well as looking for (and downloading,
if necessary) the required Node headers needed to successfully build the addons natively.

**If you have configured NPM to `--ignore-scripts` you must either run `npm exec
install-pkmn-engine` directly or build the addons manually and place the artifacts in the expected
paths.**

### `pkmn`

Until the [Zig package manager](https://github.com/ziglang/zig/projects/4) is completed, the
recommended way of using the `pkmn` package in Zig is by either copying this repository into your
project or by using [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) and then
adding the following to your `build.zig`:

```zig
const std = @import("std");
const pkmn = @import("lib/pkmn/build.zig");

pub fn build(b: *std.build.Builder) void {
    ...
    exe.addModule("pkmn", pkmn.module(b, .{ .showdown = true, .trace = true }));
    ...
}
```

The engine's `build.zig` exposes a `module` function that takes an options struct to allow for
configuring whether or not Pokémon Showdown compatibility mode or trace logs should be enabled.
Alternatively, you may set options via a `pkmn_options` [root source file
declaration](https://ziglang.org/documentation/master/#Root-Source-File). There are several
undocumented internal options that can be tweaked as well via build or root options, though these
options are not officially supported, affect correctness, and may change meaning or behavior without
warning. Use at your own risk.

```zig
pub const pkmn_options = .{ .showdown = true, .trace = true };
```

## Usage

*The snippets below are meant to merely illustrate in broad strokes how the pkmn engine can be used
\- the [`examples`](src/examples) directory contains fully commented and runnable code.*

### C

[`pkmn.h`](src/include/pkmn.h) exports the C API for `libpkmn`. Symbols are all prefixed with
`pkmn_` to avoid name collisions. If `-Dtrace` is enabled and logging throws an error then the error
will be encoded in the `pkmn_result` and can be checked with `pkmn_error`.

```c
#include <pkmn.h>

pkmn_battle battle = ...;
uint8_t buf[PKMN_LOG_SIZE];
pkmn_result result;
pkmn_choice c1 = 0, c2 = 0;
while (!pkmn_result_type(result = pkmn_battle_update(&battle, c1, c2, buf, PKMN_LOG_SIZE))) {
  c1 = choose(PKMN_PLAYER_P1, pkmn_result_p1(result));
  c2 = choose(PKMN_PLAYER_P2, pkmn_result_p2(result));
}
if (pkmn_error(result)) exit(1);
```

[(full code)](src/examples/c)

### JavaScript / TypeScript

`@pkmn/engine` depends on the [`@pkmn/data`](https://www.npmjs.com/package/@pkmn/data) which
requires a `Dex` implementation to be provided as well. The `Battle.create` function can be used to
initialize a `Battle` from the beginning, or `Battle.restore` can be used to re-instantiate a battle
which is in already progress. If logging is enabled the output can be turned into Pokémon Showdown
protocol via `Log.parse`.

```ts
import {Dex} from '@pkmn/dex';
import {Generations} from '@pkmn/data';
import {Battle} from '@pkmn/engine';

const gens = new Generations(Dex);
const battle = Battle.create(...);

const choose = (cs: Choice[]) => cs[Math.floor(Math.random() * cs.length)];

let result: Result;
let c1: Choice, c2: Choice;
while (!(result = battle.update(c1, c2)).type) {
  c1 = choose(battle.choices('p1', result));
  c2 = choose(battle.choices('p2', result));
}

console.log(result);
```

[(full code)](src/examples/js)

The `Battle` interface is designed to be zero-copy compatible with other `@pkmn` packages -
equivalently named types in [`@pkmn/client`](https://www.npmjs.com/package/@pkmn/client),
[`@pkmn/epoke`](https://www.npmjs.com/package/@pkmn/epoke),
[`@pkmn/dmg`](https://www.npmjs.com/package/@pkmn/dmg) should "just work" (however, until all of
these libraries reach v1.0.0 they are likely to require some massaging).

Despite relying on the native engine code, the `@pkmn/engine` code is designed to also work in
browsers which support [WebAssembly](https://webassembly.org/). Running `npm run start:web` from the
[`examples`](src/examples/js) directory will start a server that can be used to demonstrate the
engine running in the browser.

### Zig

The `pkmn` Zig package should be relatively straightforward to use once installed correctly. Helper
methods exist to simplify state instantiation, and any `Writer` can be used when logging is enabled
to allow for easily printing e.g. to standard out or a buffer.

```zig
const std = @import("std");
const pkmn = @import("pkmn");

var random = std.rand.DefaultPrng.init(seed).random();
var options: [pkmn.OPTIONS_SIZE]pkmn.Choice = undefined;

var battle = ...
var log = ...

var c1 = pkmn.Choice{};
var c2 = pkmn.Choice{};

var result = try battle.update(c1, c2, log);
while (result.type == .None) : (result = try battle.update(c1, c2, log)) {
    c1 = options[random.uintLessThan(u8, battle.choices(.P1, result.p1, &options))];
    c2 = options[random.uintLessThan(u8, battle.choices(.P2, result.p2, &options))];
}

std.debug.print("{}", .{result.type});
```

[(full code)](src/examples/zig)

## Status

The engine is currently expected to be developed over multiple stages:

| Stage   | Deliverables                                    |
| ------- | ----------------------------------------------- |
| **0**   | documentation, integration, benchmark, protocol |
| **1**   | RBY & GSC                                       |
| **2**   | ADV & DPP                                       |
| ***3*** | *modern generations*                            |

Currently, most of the foundational work from stage 0 is done:
  
- [benchmark and integration testing](src/test) infrastructure
- [documentation](docs) about design, research, methodology, etc
- definition and implementation of the [protocol](docs/PROTOCOL.md) that will be used by the engine

**Stage 1 is currently in progress** and will see the implementation of the actual Generation I & II
battle engines, followed by Generation III & IV in stage 2. The implementation of further Pokémon
generations is in scope for the project but should not be considered as part of the immediate
roadmap (i.e. exploring the options for broadening support for old generation APIs will be given
higher priority than implementing more modern generations). Furthermore, implementation of modern
generations is soft-blocked on the [availability of high quality
decompilations](https://github.com/orgs/pret/repositories) of the original games in question.

Certain features will always be deemed **out of scope**:

- team/set validation or custom rule ("format") enforcement
- first-class support for "mods" to core Pokémon data and mechanics
- [battle variants](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_battle#Battle_variants)
  other than single (full) or double battles
- code for exposing the engine to users (input validation, game socket server, etc)

## License

The pkmn engine is distributed under the terms of the [MIT License](LICENSE).

[^1]: In the case of Pokémon Showdown, only bugs which stem from a misimplementation of specific
  effects are reproduced in the engine, bugs which are the result of a misunderstanding of the
  fundamental mechanics of Pokémon or which simply arise due to specific Pokémon Showdown
  implementation details that are not replicable without making the same (incorrect) architectural
  choices are not. Furthermore, the "Pokémon Showdown" code referenced by this project includes
  several [patches](docs/testing.md#patches) to improve accuracy and smooth over some of the more
  egregious implementation issues. In practical terms, the vast majority of games played out in the
  pkmn engine's compatibility mode and on this patched Pokémon Showdown simulator will be the same,
  it is only in a well defined and documented set of circumstances where the two implementations
  diverge.
