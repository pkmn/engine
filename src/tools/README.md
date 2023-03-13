This directory contains miscellaneous scripts and tools useful for working on the pkmn engine:

- [`generate.ts`](generate.ts): Generate both the data files for the library based on
  [templates](../lib/common/data) and an [`id.json`](../pkg/data/ids.json) lookup file for decoding
  the serialized data. Produces the data based on information fetched from the decompiled sources
  and Pokémon Showdown.

      $ make generate

  Can also be used to generate unit testing stubs:

      $ npm run generate  -- tests <GEN>

  The `--force` flag can be used to ensure that the data is refetched from the source instead of
  from a local `.cache` directory.

- [`lint.zig`](lint.zig): Implements a linter, combining `zig fmt --check` with a custom linter
  that ensures the maximum line length is 100 characters:

      $ zig build lint

- [`protocol.zig`](protocol.zig): Print out offsets and constants required to properly encode and
  decode the pkmn [protocol](../../docs/PROTOCOL.md):

      $ zig build protocol -- markdown > tmp/protocol.md
      $ zig build protocol -- <protocol|layout> > src/data/<protocol|layout>.json

  Results can be found in [`protocol.json`](../data/protocol.json) /
  [`layout.json`](../data/layout.json).

- [`serde.zig`](serde.zig)/[`serde.ts`](serde.ts): Serializes/deserializes a randomly generated
  `Battle` for the provided generation to stdout, optionally for a specific seed. `serde.ts` wraps
  `serde.zig` and pretty prints the buffer so that it can be easily copied and pasted into JS
  source files for testing:

      $ zig build serde -- <GEN> <SEED?>
      $ npm run compile && node build/tools/serde 1
