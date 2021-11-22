https://llvm.org/docs/Benchmarking.html
https://easyperf.net/blog/2019/08/02/Perf-measurement-environment-on-Linux
https://github.com/ziglang/gotta-go-fast

use multi random runner, n random (seeded) battles across various formats, dont measure setup time  
  
benchmark 1: 3 way “drop in replacement”  
simualte-battle binary in @pkmn/engine which is compatible with PS (per gen, n random battles)  
  
simulate-battle = API  
BattleStream = in memory (after warmup, best case)  

benchmark 2: “serde”  
usecase mcts playouts: (playouts in engine vs. out, full serialize deserialize)  

graphs have 16 bars, pkmn vs PS for each gen  
  
[https://esbuild.github.io/faq/#benchmark-details](https://esbuild.github.io/faq/#benchmark-details)  
[https://github.com/sharkdp/hyperfine](https://github.com/sharkdp/hyperfine)  
[https://github.com/Jarred-Sumner/bun/tree/main/bench/hot-module-reloading/css-stress-test](https://github.com/Jarred-Sumner/bun/tree/main/bench/hot-module-reloading/css-stress-test)  
  
warmup code several times to make sure optimized by JS first? => can't really do for simulate-battle binary which has startup overhead etc  

PERFORMANCE

1. [benchmark.md](http://benchmark.md/) ([https://easyperf.net/blog/2019/08/02/Perf-measurement-environment-on-Linux#2-disable-hyper-threading](https://easyperf.net/blog/2019/08/02/Perf-measurement-environment-on-Linux#2-disable-hyper-threading)), covers benchmarking approach, [desing.md](http://desing.md/) has performance section [https://github.com/ziglang/gotta-go-fast](https://github.com/ziglang/gotta-go-fast)  [https://llvm.org/docs/Benchmarking.html](https://llvm.org/docs/Benchmarking.html)
2. comments in readme header are graph, link to details  
3. in src/tools/benchmark.ts, add logic for harness with trakr (eventually - include trakkr?)
4. need ability to display results - figure out svg approach used by esbuild or other project

PATTERN

- BattlePlayer.receiveLine to skip logging
- get rid of battle.destroy() as its unnecessary

----

4 AIs:

- random player (all choices) for traditional PS
- random player (all choices) for direct PS (JS)
- random player (all choices) for engine and 0 ERROR select (zig)
- random player (fastpath abort) for 0 ERROR playout (zig)

Phase 1:

- traditional (stream) PS vs. stripped down (direct) PS
  - use correct RNG for gen
  - use correct AIs
  - direct queries `Battle` directly and turns off `log` where possible? (just reset `.log = []`? or override `add` to do nothing? etc)
  - don't include `encode` (ie. `pack`) time in total

Phase 2:

- engine vs. direct PS

----

Results

- per gen or average battles across all (supported) gens?
- normalize to turns per second vs. battles per second? (both)

```txt


```