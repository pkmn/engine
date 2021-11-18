explain difference between engine and simulator (engine: just subset of Battle. no battle stream (driver), no team validator/format awareness etc. minimal protocol support (not full protocol).)

how the engine can be used for the damage calc

- mcts
- damage calc (how? need to give example)

non goal: fully feature data lib - general functionality at odds with performance

```txt
full architecture design docs
goals: speed, accuracy
- dont pay at all for abstractions etc not used in the gen (gen 2 doesnt pay for inheritance of gen 1, doesnt have to deal with `spc`, etc) = possibly a lot less code reuse! inheritance can be done at compile time (just pointers, no redundant memory). gen 8 doesnt need to pay for gen 1->7

text => all text (descriptions, short desc, names, etc) in separate translatable files
IDs (ints) most fundamental -> looking up data should be looking up in array!

1) faster (event dispatch?, use numbers instead of strings)  
2) same protocol? (at least need to be able to translate to ps protocol)  
3) DAMAGE CALC (need to be able to return all randoms with same code, also force events to always proc)  
4) MINMAX (need to be able to proc multiple possibilies)  
5) MCTS (efficient state representation)

- convert to PS protocol (after) for compatibility
- dont include input/ouput logs in text encoding (like trace!) can still rematerialize, just cant display same results

```

TODO Performance

- constraint: engine (but not required for wrapper) does not allocate any dynamic memory
- constraint: no pointers in data representation - must be copyable by `mem.copy`
- native endianess for trivial input/output
- padding, alignment, cache lines
- dont create protocol objects, just write byes directly to stream

PS could be made more perfomant by po/optimize:

```txt
Events - don't go over all the events each time, instead have array of NUMEVEMT and have monsters reg and dereg where appropriate, then just need to look up if theres any handlers. Num handlers for each event could also possibly be fixed to small N (20?), Always use naive insertion sort to keep sorted since small arrays. FULLY STACK.  
- when to add and remove?  
- monsters should not poll over the fields either, can precompute when turning set to Mon which events it needs to reg and dereg? NO SEARching full static lookups
```

also rethinking IDs to be numbers not strings, minimizing string parsing, etc

- binary for each gen, simulate glue script in JS which includes driver `pkmn/simulate gen1` => `pkmn/bin/gen1`
- library `pkmn/lib/pkmn.so` which is `-OReleaseFast` but two modes, one with trace, one without trace

Most inter-gen releases just deal with legality (team validator, handled at a higher level), but can include data changes (Hypnosis in gen 4) and even data presence causes problems - eg trouble implementing `gen8-dlc1` given moves like Metronome etc might depdend on moves which don't exist

- would need to add `Release` to battle and do `if` checks in relevant places like Metronome handler
  
0 error = mcts random playouts over library, no streaming just accumulating stats. however, provided multiple roots (possible instantiations)? , optionally with weights - epoke run in js

also have pure MCTS random playout function - naive (not heavy) playouts, focused on speed: need to be careful about omniscience

```txt
Battle update(u16, ?[BUF]trace) -> info about win or lose and requesttype for either player. if trace is provided will output trace protocol lines (null separated? protocol type plus args plus etc - is chunk and line bounded? run PS a while and figure out chunk arg lenghts and kwargs)  
```

### Resources

- [Handles vs. Pointers][handles]
- [Data-Oriented Design][dod] ([book][dodbook])
- [The Lost Art of Structure Packing][packing]
- [Performance Speed Limits][limits]
- [Latency Numbers Reference][numbers]
- [Operation Costs in CPU Clock Cycles][costs]

  [dod]: https://github.com/dbartolini/data-oriented-design
  [dodbook]: https://www.dataorienteddesign.com/dodbook/
  [handles]: https://floooh.github.io/2018/06/17/handles-vs-pointers.html
  [packing]: http://www.catb.org/esr/structure-packing/
  [limits]: https://travisdowns.github.io/blog/2019/06/11/speed-limits.html
  [numbers]: https://github.com/sirupsen/napkin-math#numbers
  [costs]: http://ithare.com/infographics-operation-costs-in-cpu-clock-cycles/
