# Testing

In addition to [unit tests](#unit), the code in [`src/test`](../src/test) contains harnesses for
[integration testing](#integration) and [benchmarking](#benchmarking) against Pokémon Showdown.

## Unit

Due to the `-Dshowdown` and `-Dtrace` build options and the stochastic nature of Pokémon as a game,
testing the pkmn engine requires a little extra work. Helper functions exist to remove the majority
of the boilerplate from the library's unit tests:

- `Test`: the main helper type for testing, a test can be initialized with `Test(rolls).init(p1,
  p2)` (`Test.deinit()` should be `defer`-ed immediatley after initialization to free resources),
  expected updates and logs can be tracked on the `expected` fields and finally the `actual` state
  can be `verify`-ed at the end of the test.
- `Battle.fixed`: under the hood, `Test` uses this helper to create a battle with a `FixedRNG` that
  returns a fixed sequence of results ("rolls") - this provides complete control over whether or not
  events should occur. One problem is that `-Dshowdown` Pokemon Showdown compatibility mode requires
  a different number and order of rolls, meaning both must be specified. Furthermore, at the end of
  the test it is important to verify that all of the rolls provided were actually required with `try
  expect(battle.rng.exhausted())` - unexpectedly unused rolls could point to bugs (`Test.verify()`
  will automatically check that the `rng` is exhausted).

### `showdown.test.ts`

In order to verify Pokémon Showdown's behavior, many of the pkmn engine's unit tests are mirrored in
[`showdown.test.ts`](../src/test/showdown.test.ts). It should be emphasized that these are tests
against Pokémon Showdown, **not** the pkmn engine (engine code is not being tested). Pokémon
Showdown's own unit tests are inadequate for the pkmn engine's purposes as they mostly cover the
latest generation, do not use a fixed RNG, and do not verify logs (both of which are crucial for
matching Pokémon Showdown's RNG and output).

## Integration

The [integration test](../src/test/integration.test.ts) exists to ensure the pkmn engine compiled in
Pokémon Showdown compatibility mode with `-Dshowdown` produces comparable output to Pokémon
Showdown. For each supported generation, both Pokémon Showdown and the pkmn engine are run with an
[`ExhaustiveRunner`](https://github.com/smogon/pokemon-showdown/blob/master/sim/tools/exhaustive-runner.ts)
that attempts to use as many different effects as possible in the battles it randomly simulates and
the results are collected. While Pokémon Showdown always produces its text protocol streams, pkmn
must be built specially to opt-in to introspection support (`-Dtrace`).

The pkmn [binary protocol](PROTOCOL.md) is not expected to be equivalent to Pokémon Showdown for
several reasons:

- pkmn does not have any notion of a
  ['format'](https://github.com/smogon/pokemon-showdown/blob/master/config/formats.ts) or [custom
  'rules'](https://github.com/smogon/pokemon-showdown/blob/master/config/CUSTOM-RULES.md)
- the ordering of keyword arguments in Pokémon Showdown not strictly defined
- several of Pokémon Showdown's protocol messages are redundant/implementation specific
- pkmn always returns a single 'stream' and always includes exact HP (ie. Pokémon Showdown's
  "omniscient stream") - other streams of information must be computed from this
- [despite what it may claim](https://pokemonshowdown.com/pages/rng), Pokémon Showdown does **not**
  implement the correct pseudo-random number generator for each format (it implements the Generation
  V & VI PRNG and applies it to all generations and performs a different amount of calls, with
  different arguments and in different order than the cartridge).

The integration test contains logic to configure Pokémon Showdown to produce the correct results and
for massaging the output from the pkmn engine into something which can be compared to Pokémon
Showdown. Care is taken to ensure that where they disagree the actual cartridge decompilations are
used as the arbiter of correctness, but it is still possible that since Pokémon Showdown and the
pkmn engine are both independent implementations of the actual Pokémon cartridge logic  despite
being in agreement **they may both be incorrect** when it comes to the actual cartridge.

### `blocklist.json`

Some of Pokémon Showdown's bugs are too convoluted to be implemented in the pkmn engine. The engine
tries its best to reproduce the behavior of even the most misunderstood and broken mechanics of
Pokémon Showdown, but in the same way that implementing the cartridge behavior correctly is
difficult starting from Pokémon Showdown's architecture, implementing Pokémon Showdown's mechanics
is also difficult starting from an architecture that mirrors the cartridge.

In cases where the pkmn engine cannot reproduce 100% of the behavior of Pokémon Showdown for the
purposes of lockstep integration tests or benchmarking, the offending Pokémon / Items / Abilities /
Moves will be blocked from inclusion by their presence in the
[`blocklist.json`](../src/test/blocklist.json) file. Note that the pkmn engine implements as much
of Pokémon Showdown's behavior for these effects as possible, it is usually just the extreme edge
cases which would require large amounts of coding or additional state to implement the same faulty
behavior where these effects break down.

## Benchmark

Benchmarking the pkmn engine vs. Pokémon Showdown is slightly more complicated than simply using a
tool like [`hyperfine`](https://github.com/sharkdp/hyperfine) due to the need to account for the
runtime overhead and warmup period required by V8 (`hyperfine --warmup` is intended to help with
disk caching, not JIT warmup). As such, a [custom benchmark tool](`../src/tools/benchmark`) exists
which can be used to run the benchmark. The benchmark measures how long it takes to play M playouts
of N randomly generated battles, excluding any set up time and time spent warming up the JS
configurations. This benchmark scenario is useful for approximating the [Monte Carlo tree search
(MCTS)](https://en.wikipedia.org/wiki/Monte_Carlo_tree_search) use case where various battles are
played out each turn to the end numerous times to determine the best course of action.

Before running the benchmark, care needs to be taken to set up the environment to be as stable as
possible, eg. [disabling CPU performance scaling, Intel Turbo Boost,
etc](https://github.com/travisdowns/uarch-bench/blob/master/uarch-bench.sh). The benchmark tool
measures 4 different configurations:

- **`BattleStream`**: this configuration attempts to use Pokémon Showdown's
`BattleStream`/`BattlePlayer` APIs mostly as intended, with 2 tweaks:

  1. A special `RandomPlayerAI` is used that directly inspects the `Battle` to avoid making
     unavailable choices and matches the AI used by all of the other configurations.
  2. The `Battle` within the `BattleStream` is directly inspected in order to more easily grab the
     turn count.

  Pokémon Showdown's root `pokemon-showdown` binary is technically the blessed approach to using
  the simulator, but `BattleStream` is effectively the same thing but without the (sizeable) I/O
  overhead. Attempting to use the actual `pokemon-showdown` binary is deemed too difficult as there
  would then be no way to inspect the `Battle` in order to avoid making unavailable choices[^1],
  meaning it would be difficult to keep in sync with the other configurations.

- **`DirectBattle`**: this configuration introduces the concept of a `DirectBattle` which
  overrides the Pokémon Showdown `Battle` class to strip out unused functionality:

    1. methods which add to the battle log are overriden to drop any messages immediately
    2. `sendUpdates` is overridden to not send any updates
    3. `makeRequest` avoids serializing the request for each side  
  
  The `DirectBattle` is then used synchronously as opposed to via the async `BattleStream` which is
  about 10% faster and obviates needing to care about races. This configuration minimizes string
  processing overhead and unnecessary delays due to `async` calls and is as close to as fast as
  Pokémon Showdown can be run (there is room for further optimization by simplifying choice parsing
  to to not perform any verification, though this is signficantly less trivial than the
  aforementioned optimizations). This is closer to how the pkmn engine runs with `-Dtrace` disabled.

- **`@pkmn/engine`**: this configuration uses the `@pmn/engine` driver package to run battles with
  the pkmn engine.

- **`libpkmn`**: this configuration runs battles directly with the `libpkmn` library and does not
  interface with JS at all. The benchmark runner invokes
  [`benchmark.zig`](../src/test/benchmark.zig) to directly run the benchmark and report the results.

Both pkmn engine configurations are intended to be used `-Dshowdown` build option but with tracing
disabled. Both of the Pokémon Showdown configurations are run beforehand for a warmup period to
ensure the measured duration is representative of the actual best case runtime.

In order to ensure all configurations are testing the same thing, we need to ensure that the exact
same battles are generated, the same sequence of moves are chosen, and the battle results are match.
As such, all benchmarks are run with the same PRNGs that have been initialized with the same seeds,
and the logic for generating battles/randomly choosing moves is duplicated across  both the Zig and
TypeScript implementations. Finally, in addition to total duration, the benchmarking tool tracks and
compares the total number of turns across all battles and the final RNG seed to serve as a
"checksum" and verify that all of the configurations are in agreement - Pokémon Showdown requires
that we:

- serialize the player's teams passed to the `Battle` constructor, as Pokémon Showdown mutates
  them
- drive both players with separate PRNGs from each other and from the `Battle`, as there is no
  guarantee around the order of operations (Pokémon Showdown has numerous races and
  [unpleasantries](https://github.com/smogon/pokemon-showdown/issues/8546))

Note that how long a given battle takes is heavily dependent on the teams in question. The benchmark
runs on teams that have effectively been generated using ["Challenge
Cup"](https://bulbapedia.bulbagarden.net/wiki/Challenge_Cup) semantics, and because this includes
numerous sub-optimal moves (eg. Thunder Shock in addition to Thunderbolt, instead of just the
latter) it is expected to take substantially longer than more traditional ["Random Battle"
sets](https://github.com/pkmn/randbats) or handcrafted teams. **Experimentally the random sets used
by the benchmark are expected to be roughly 2-3× slower than what would be typical in practice.**

[^1]: It is possible to remain in sync between configurations which can inspect `Battle` and those
that can't by always saving the raw result returned by the last RNG call and reapplying it to the
next request in the event of an "[Unavailable choice]" error (eg. call the RNG and get back `r`,
attempt to choose the `r % N`-th choice, get rejected, on the next request do not generate a new `r`
but instead now make the `r % M`-th choice where `M` is the actual available choices post
rejection). Since it isn't especially important to demonstrate how much slower the (already slow)
async `BattleStream` API when you introduce syscall overhead into the mix, this workaround is left
as an exercise to the reader.

### Results

The benchmarks are run on a Intel(R) Xeon(R) CPU E5-2690 v3 @ 2.60GHz on 64-bit x86 Linux which has
undergone the pre-benchmark tuning detailed above via the command  `npm run benchmark -- 1000`:

| Generation | `libpkmn` | `@pkmn/engine` | `DirectBattle` | `BattleStream` |
| ---------- | --------- | -------------- | -------------- | -------------- |
| **RBY**    | 1ms       | 2ms (2x)       | 3ms (3x)       | 4ms (4x)       |
| **GSC**    | 1ms       | 2ms (2x)       | 3ms (3x)       | 4ms (4x)       |
| **ADV**    | 1ms       | 2ms (2x)       | 3ms (3x)       | 4ms (4x)       |
| **DPP**    | 1ms       | 2ms (2x)       | 3ms (3x)       | 4ms (4x)       |

<details><summary>CPU Details</summary><pre>
Architecture:            x86_64
  CPU op-mode(s):        32-bit, 64-bit
  Address sizes:         46 bits physical, 48 bits virtual
  Byte Order:            Little Endian
CPU(s):                  48
  On-line CPU(s) list:   0-47
Vendor ID:               GenuineIntel
  Model name:            Intel(R) Xeon(R) CPU E5-2690 v3 @ 2.60GHz
    CPU family:          6
    Model:               63
    Thread(s) per core:  2
    Core(s) per socket:  12
    Socket(s):           2
    Stepping:            2
    CPU max MHz:         3500.0000
    CPU min MHz:         1200.0000
    BogoMIPS:            5188.40
    Flags:               fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep
                         _good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline
                         _timer aes xsave avx f16c rdrand lahf_lm abm cpuid_fault epb invpcid_single pti intel_ppin ssbd ibrs ibpb stibp tpr_shadow vnmi flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2
                         smep bmi2 erms invpcid cqm xsaveopt cqm_llc cqm_occup_llc dtherm ida arat pln pts md_clear flush_l1d
Virtualization features:
  Virtualization:        VT-x
Caches (sum of all):
  L1d:                   768 KiB (24 instances)
  L1i:                   768 KiB (24 instances)
  L2:                    6 MiB (24 instances)
  L3:                    60 MiB (2 instances)
NUMA:
  NUMA node(s):          2
  NUMA node0 CPU(s):     0-11,24-35
  NUMA node1 CPU(s):     12-23,36-47
Vulnerabilities:
  Itlb multihit:         KVM: Mitigation: VMX disabled
  L1tf:                  Mitigation; PTE Inversion; VMX conditional cache flushes, SMT vulnerable
  Mds:                   Mitigation; Clear CPU buffers; SMT vulnerable
  Meltdown:              Mitigation; PTI
  Spec store bypass:     Mitigation; Speculative Store Bypass disabled via prctl and seccomp
  Spectre v1:            Mitigation; usercopy/swapgs barriers and __user pointer sanitization
  Spectre v2:            Mitigation; Full generic retpoline, IBPB conditional, IBRS_FW, STIBP conditional, RSB filling
  Srbds:                 Not affected
  Tsx async abort:       Not affected
<pre></details>
