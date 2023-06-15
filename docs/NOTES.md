## Adding a new Generation

1. **[Research](./RESEARCH.md)** the data structures and code flow
2. Add a `data.zig` file with **basic data types** (`Battle`, `Side`, `Pokemon`, ...) and fields
   - un-optimized - exact layout tweaked in step 11
3. **[Generate](../src/tools/generate.ts) data** files
   - reorder enums for performance
   - update [`Lookup`](../src/pkg/data.ts) if necessary
4. **[Generate](../src/tools/generate.ts) test** files
   - reorganize logically and to match previous generations
   - add in cases for known Pokémon Showdown bugs and cartridge glitches
5. **Copy over shared code/files**
   - copy over `README.md` for new generation
   - copy over imports and public function skeletons in `mechanics.zig`
   - copy `Test` infrastructure and rolls into `test.zig`
   - copy over `helpers.zig`
6. Implement **unit [tests](../src/test/showdown/) against Pokémon Showdown** behavior
   - update Bugs section of generation documentation as bugs are discovered
7. Implement **mechanics** in `mechanics.zig` based on cartridge research
   - update [protocol](../src/lib/common/protocol.zig) as necessary, also updating
     [documentation](PROTOCOL.md), [driver](../src/pkg/protocol.ts), and tests
   - [generate](../src/tools/protocol.zig) updated [`protocol.json`](../src/data/protocol.json)
8. Adjust **mechanics for Pokémon Showdown** compatibility
   - track RNG differences and update generation documentation (group all RNG is in `Rolls`)
   - ensure all bugs are tracked in documentation
   - add logic to tests to block any unimplementable effects
9. **Unit test the engine** in both cartridge and Pokémon Showdown compatibility mode
10. Implement a **`MAX_LOGS` unit test**
    - document in [`PROTOCOL.md`](PROTOCOL.md)
    - validate with Z3
11. **Optimize data structures**
    - [generate](../src/tools/protocol.zig) updated [`layout.json`](../src/data/layout.json) and
     [`data.json`](../src/data/data.json)
12. Implement **driver serialization/deserialization** and writes tests
13. **Expose API** for new generation
    - update [`pkmn.zig`](../src/lib/pkmn.zig) and [bindings](../src/lib/bindings)
    - update [`pkmn.h`](../src/include/pkmn.h)
    - update [`index.ts`](../src/pkg/index.ts)
14. Write **`helper.zig`** and implement **`choices`** method
    - matching `Choices` code required in [showdown](../src/test/showdown/index.ts)
15. Ensure **[fuzz tests](../src/test/benchmark.zig)** pass
    - update [`fuzz.ts`](../src/test/fuzz.ts) and [`display.ts`](../src/test/display.ts)
16. Ensure **[integration tests](../src/test/integration.ts)** pass
17. Add **`chance.zig`** and **`calc.zig`** files with data types
18. **Instrument code with `Chance` and `Calc` calls**
19. Update **unit tests with `expectProbability`** and ensure chance/calc overrides roundtrip
20. Implement **`transitions` function**
   - add `Rolls` helpers for new generation
   - include `transitions` function call in fuzz tests
   - determine `MAX_FRONTIER_SIZE` and add constants to API
21. **Add support to the JS driver for `calc` and `chance`**
   - update [`layout.json`](../src/data/layout.json) to include offsets required
22. **[Benchmark](../src/test/benchmark.zig)** new generation
23. Finalize **documentation** for generation

## Updating `@pkmn/sim` dependency

1. **Bump** pinned `@pkmn/sim` version in [`package.json`](../package.json) and run `npm install`
2. Run `npm run test:integration`, **update rolls and behavior of Pokémon Showdown tests** in
   [`src/test/showdown`](src/test/showdown)
3. **Update Zig mechanics tests to match** the updates applied to the integration tests
4. **Update Zig engine code** to cause the updated mechanics tests to pass
5. **Update documentation** to match new behavior/bugs
6. **Remove effects from blocklists** and helpers if necessary
