# Testing

In addition to unit tests, the code in [`src/test`](../src/test) contains harnesses for [integration
testing](#integration) and [benchmarking](#benchmarking) against Pokémon Showdown.

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
Showdown.  Care is taken to ensure that where they disagree the actual cartridge decompilations are
used as the arbiter of correctness, but it is still possible that since Pokémon Showdown and the
pkmn engine are both independent implementations of the actual Pokémon cartridge logic  despite
being in agreement **they may both be incorrect** when it comes to the actual cartridge.

## Benchmark

### Methodology

TODO setup https://github.com/travisdowns/uarch-bench/blob/master/uarch-bench.sh#L66

### Results

<p align="center">
  <img src="https://gist.githubusercontent.com/scheibo/1edecb6e76dd9176691e50819d90e841/raw/f15db8b25ae5a64d3f712fba79416d65c0c9b0e2/benchmark.svg" alt="Bar chart with benchmark results">
</p>

TODO table

The benchmarks are run on a Intel(R) Xeon(R) CPU E5-2690 v3 @ 2.60GHz on 64-bit x86 Linux which has undergone the pre-benchmark tuning detailed above:

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

TODO compared to PS - time/1000 battles,               avg battles/s

```txt
4 AIs:

- random player (all choices) for traditional PS
- random player (all choices) for direct PS (JS)
- random player (all choices) for engine and 0 ERROR select (zig)
- random player (fastpath abort) for 0 ERROR playout (zig)
Results

- per gen or average battles across all (supported) gens?
- normalize to turns per second vs. battles per second? (both)
```

Stochastic:
  - multi-hit: rolls of 2 and 5
  - two rolls, one without secondary and one with (just to prove it can proc, not which rates)

Can't test: increased rates of already inconsistent things
  - accuracy - could show roll before using increased accuracy does work, doesnt after? (implies accuracy changed)
  - critical hits

TESTING - exhaustive runner

parse directly to @protocol (no json), though allow for protocol to be stringified (though wont match). add logic to compare protocol directly (order insenstivie), filter out fields which arent implement like break or rules

run PS in battle stream and run through protocol parser. run engine synchronously and gather all converted update/sideupdate data, compare

BENCHMARK - custom multi random runner
checksum = final seed pkus sum of turns

generate teams for each (not included in timing)
dont include team packing time for PS, dont include team encoding time for JS (though optionally can)
play out exact same battle using random ai, only disable trace output for engine and use a binary random ai that makes same decisions as ps but purely off the data it reads directly out of the casted bytes of the engines Battle instance

integration test. equals(parsed protcol) , not string line
