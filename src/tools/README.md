This directory contains miscellaneous scripts and tools useful for working on the pkmn engine:

- [`analyze.zig`](analyze.zig): Analyze LLVM IR to find potential performance issues. To produce
  the LLVM IR used as input for the tool, use the `-Demit-ll` option when building:

      $ zig build -Demit-ll -Dstrip -Doptimize=ReleaseFast

  To detect large copies (defaulting to anything larger than a pointer, but a larger threshold can
  be provided) with comptime-known size:

      $ zig build analyze -- copies <THRESHOLD?> < pkmn.ll 2>&1 | sort -n -k 3

  To print every function name (first column), number of times it was monomorphized (second column)
  and the total size of all monorphizations (third column):

  $ zig build analyze -- sizes < pkmn.ll \
      | awk '{a[$1] += $2; b[$1] += 1} END {for (i in a) print i, b[i], a[i]}' \
      | sort -n -k 3

- [`debug.ts`](debug.ts): Reads a dump of [binary debug protocol](../../docs/PROTOCOL.md#debugging)
  from [standard input](https://en.wikipedia.org/wiki/Standard_streams) and outputs the standalone
  [debug UI webpage](https://pkmn.cc/debug.html):

      $ <cmd> | npm run debug > index.html

  Alternatively, if a single filename argument is passed to the tool it will read from that instead:

      $ npm run debug <file> > index.html

- [`generate.ts`](generate.ts): Generate both the data files for the library based on
  [templates](../lib/common/data) and an [`id.json`](../pkg/data/ids.json) lookup file for decoding
  the serialized data. Produces the data based on information fetched from the decompiled sources
  and Pokémon Showdown.

      $ make generate

  Can also be used to generate unit testing stubs:

      $ npm run generate  -- tests <GEN>

  The `--force` flag can be used to ensure that the data is re-fetched from the source instead of
  from a local `.cache` directory.

- [`dump.zig`](dump.zig): Print out offsets and constants required to properly encode and
  decode the pkmn [protocol](../../docs/PROTOCOL.md):

      $ zig build dump -- markdown > tmp/protocol.md
      $ zig build dump -- <protocol|layout> > src/data/<protocol|layout>.json

  Results can be found in [`protocol.json`](../data/protocol.json) /
  [`layout.json`](../data/layout.json).

- [`release.ts`](release.ts): Builds versions of `libpkmn` and `libpkmn-showdown` for each supported
  platform, packages them into archives, and publishes the resulting artifacts. Can be either run to
  produce a nightly release (which simply uploads to GitHub) or the create an official `--prod`
  release which additionally signs the builds (which can only be done locally)/publishes to npm/add
  a git tag. Supports a `--dryRun` option for just printing out the steps it would take.

      $ npm run release

- [`serde.zig`](serde.zig)/[`serde.ts`](serde.ts): Serializes/deserializes a randomly generated
  `Battle` for the provided generation to standard out, optionally for a specific seed. `serde.ts` wraps
  `serde.zig` and pretty prints the buffer so that it can be easily copied and pasted into JS
  source files for testing:

      $ zig build serde -- <GEN> <SEED?>
      $ npm run compile && node build/tools/serde 1

- [`transitions.zig`](transitions.zig): Runs the specified generation's "transitions" function to
  make it easier to debug or visualize:

      $ zig build transitions -Dcalc -Dchance -- <GEN> <SEED?> 2>/dev/null
