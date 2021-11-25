## Games

### [Gen 1](https://github.com/pret/pokered)

- `constants/`
  - [`battle_constants.asm`](https://pkmn.cc/pokeredconstants/battle_constants.asm)
    - ["battle status" (volatiles)](https://pkmn.cc/pokeredconstants/battle_constants.asm#L73-L100)
  - [`move_constants.asm`](https://pkmn.cc/pokeredconstants/move_constants.asm) /
    [`move_effect_constants.asm`](https://pkmn.cc/pokeredconstants/move_effect_constants.asm)
    (pointers to "handlers" for moves)
  - [`pokedex_constants.asm`](https://pkmn.cc/pokeredconstants/pokedex_constants.asm) /
    [`pokemon_data_constants.asm`](https://pkmn.cc/pokeredconstants/pokemon_data_constants.asm)
  - [`type_constants.asm`](https://pkmn.cc/pokeredconstants/type_constants.asm)
- `data/`
  - [`battle/`](https://github.com/pret/pokered/tree/master/data/battle)
    - [`stat_modifiers.asm`](https://pkmn.cc/pokereddata/battle/stat_modifiers.asm)
    - "special" moves:
      [`residual_effects_1.asm`](https://pkmn.cc/pokereddata/battle/residual_effects_1.asm),
      [`residual_effects_2.asm`](https://pkmn.cc/pokereddata/battle/residual_effects_2.asm)
  - [`moves/`](https://github.com/pret/pokered/tree/master/data/moves)
    - [move data](https://pkmn.cc/pokereddata/moves/moves.asm)
  - [`pokemon/`](https://github.com/pret/pokered/tree/master/data/pokemon)
    - [species data](https://github.com/pret/pokered/tree/master/data/pokemon/base_stats)
    - [learnsets](https://pkmn.cc/pokereddata/pokemon/evos_moves.asm)
  - [`types/`](https://github.com/pret/pokered/tree/master/data/types)
    - [`type_matchups.asm`](https://pkmn.cc/pokereddata/types/type_matchups.asm)
      - typechart, [linear scan to
        lookup](https://pkmn.cc/pokeredengine/battle/core.asm#L5230-L5289)
- [`engine/battle/`](https://pkmn.cc/pokeredengine/battle)
  - [`move_effects/`](https://github.com/pret/pokered/tree/master/engine/battle/move_effects) -
    special handlers (like PS `statuses` / `scripts`)
  - [**`core.asm`**](https://pkmn.cc/pokeredengine/battle/core.asm)
  - [`decrement_pp.asm`](https://pkmn.cc/pokeredengine/battle/decrement_pp.asm)
  - [`effects.asm`](https://pkmn.cc/pokeredengine/battle/effects.asm)
- `wram.asm`
  - [macros](https://pkmn.cc/pokeredmacros/wram.asm)
  - [unmodified stats and mods](https://pkmn.cc/pokeredwram.asm#L525)
  - [active move](https://pkmn.cc/pokeredwram.asm#L1156)
  - [battle data](https://pkmn.cc/pokeredwram.asm#L1232)
    - ["battle status" (volatiles)](https://pkmn.cc/pokeredwram.asm#L1261-L1284)

### [Gen 2](https://github.com/pret/pokecrystal)

- `constants/`
  - [`battle_constants.asm`](https://pkmn.cc/pokecrystalconstants/battle_constants.asm)
  - [`item_constants.asm`](https://pkmn.cc/pokecrystalconstants/item_constants.asm) /
    [`item_data_constants.asm`](https://pkmn.cc/pokecrystalconstants/item_data_constants.asm#L61-L135)
  - [`move_constants.asm`](https://pkmn.cc/pokecrystalconstants/move_constants.asm) /
    [`move_effect_constants.asm`](https://pkmn.cc/pokecrystalconstants/move_effect_constants.asm)
  - [`pokemon_constants.asm`](https://pkmn.cc/pokecrystalconstants/pokemon_constants.asm)
  - [`type_constants.asm`](https://pkmn.cc/pokecrystalconstants/type_constants.asm)
- `data/`
  - [`battle/`](https://github.com/pret/pokecrystal/tree/master/data/battle)
    - [Accuracy](https://pkmn.cc/pokecrystaldata/battle/accuracy_multipliers.asm) / [Critical
      Hits](https://pkmn.cc/pokecrystaldata/battle/critical_hit_chances.asm) / [Stat
      Modifiers](https://pkmn.cc/pokecrystaldata/battle/stat_multipliers.asm) /
      [Weather](https://pkmn.cc/pokecrystaldata/battle/weather_modifiers.asm)
  - [`items/`](https://github.com/pret/pokecrystal/tree/master/data/items)
    - [`attributes`](https://pkmn.cc/pokecrystaldata/items/attributes.asm)
  - [`moves/`](https://github.com/pret/pokecrystal/tree/master/data/moves)
    - [move data](https://pkmn.cc/pokecrystaldata/moves/moves.asm)
    - [**effects**](https://pkmn.cc/pokecrystaldata/moves/effects.asm)
      ([pointers](https://pkmn.cc/pokecrystaldata/moves/effects_pointers.asm),
      [priorities](https://pkmn.cc/pokecrystaldata/moves/effects_priorities.asm))
    - [Flail](https://pkmn.cc/pokecrystaldata/moves/flail_reversal_power.asm) /
      [Magnitude](https://pkmn.cc/pokecrystaldata/moves/magnitude_power.asm) /
      [Present](https://pkmn.cc/pokecrystaldata/moves/present_power.asm) /
      [Metronome](https://pkmn.cc/pokecrystaldata/moves/metronome_exception_moves.asm) / [Hidden
      Power](https://pkmn.cc/pokecrystalengine/battle/hidden_power.asm)
  - [`pokemon/`](https://github.com/pret/pokecrystal/tree/master/data/pokemon)
    - [species data](https://github.com/pret/pokecrystal/tree/master/data/pokemon/base_stats)
    - learnset [level up](https://pkmn.cc/pokecrystaldata/pokemon/evos_attacks.asm) /
      [egg](https://pkmn.cc/pokecrystaldata/pokemon/egg_moves.asm)
  - [`types/`](https://github.com/pret/pokecrystal/tree/master/data/types)
    - [`type_matchups.asm`](https://pkmn.cc/pokecrystaldata/types/type_matchups.asm)
    - [`type_boost_items.asm`](https://pkmn.cc/pokecrystaldata/types/type_boost_items.asm)
- `engine/battle/`
  - [`move_effects/`](https://github.com/pret/pokecrystal/tree/master/engine/battle/move_effects) -
    handlers
  - [**`core.asm`**](https://github.com/pret/pokecrystal/tree/master/engine/battle/core.asm)
  - [`effect_commands.asm`](https://pkmn.cc/pokecrystalengine/battle/effect_commands.asm)
  - [`/home/battle_vars.asm`](https://pkmn.cc/pokecrystalhome/battle_vars.asm)
- `wram.asm`
  - [battle data](https://pkmn.cc/pokecrystalwram.asm#L352-L621),
    [macros](https://pkmn.cc/pokecrystalmacros/wram.asm)
- random ([`Random`](https://pkmn.cc/pokecrystalhome/random.asm),
  [`BattleRandom`](https://pkmn.cc/pokecrystalengine/battle/core.asm#L6881-L6947))

### [Gen 3](https://github.com/pret/pokeemerald)

- `include/`
  - [battle](https://pkmn.cc/pokeemeraldinclude/battle.h)
    ([util](https://pkmn.cc/pokeemeraldinclude/battle_util.h) /
    [scripts](https://pkmn.cc/pokeemeraldinclude/battle_scripts.h) /
    [main](https://pkmn.cc/pokeemeraldinclude/battle_main.h))
  - [random](https://pkmn.cc/pokeemeraldinclude/random.h)
  - [pokemon](https://pkmn.cc/pokeemeraldinclude/pokemon.h#L160-L241)
  - [item](https://pkmn.cc/pokeemeraldinclude/item.h)
- `include/constants/`
  - [abilities](https://pkmn.cc/pokeemeraldinclude/constants/abilities.h)
  - [species](https://pkmn.cc/pokeemeraldinclude/constants/species.h)
  - [types / nature](https://pkmn.cc/pokeemeraldinclude/constants/pokemon.h)
  - [moves](https://pkmn.cc/pokeemeraldinclude/constants/moves.h)/[move
    effects](https://pkmn.cc/pokeemeraldinclude/constants/battle_move_effects.h)
  - [held item effects](https://pkmn.cc/pokeemeraldinclude/constants/hold_effects.h)
  - [battle](https://pkmn.cc/pokeemeraldinclude/constants/battle.h) /
    [misc](https://pkmn.cc/pokeemeraldinclude/constants/battle_script_commands.h)
- `src/data/`
  - [species data](https://pkmn.cc/pokeemeraldsrc/data/pokemon/base_stats.h)
    - [evolutions](https://pkmn.cc/pokeemeraldsrc/data/pokemon/evolution.h)/[egg
      moves](https://pkmn.cc/pokeemeraldsrc/data/pokemon/egg_moves.h)/[level
      up](https://pkmn.cc/pokeemeraldsrc/data/pokemon/level_up_learnsets.h)
  - [move data](https://pkmn.cc/pokeemeraldsrc/data/battle_moves.h)
  - [item data](https://pkmn.cc/pokeemeraldsrc/data/items.h)
- `src/`
  - battle: [main](https://pkmn.cc/pokeemeraldsrc/battle_main.c) /
    [util](https://pkmn.cc/pokeemeraldsrc/battle_util.c)
  - [pokemon](https://pkmn.cc/pokeemeraldsrc/pokemon.c)
  - [random](https://pkmn.cc/pokeemeraldsrc/random.c)
- [`data/battle_scripts_1.s`](https://pkmn.cc/pokeemeralddata/battle_scripts_1.s)

### [Gen 4](https://github.com/pret/pokediamond)

TODO

## Appendix

### Simulators

- [Pokemon Showdown!](https://github.com/smogon/pokemon-showdown): documentation
  ([new](https://gist.github.com/scheibo/c9ef943ef6e01e350940c8429c378e3b) /
  [current](https://raw.githubusercontent.com/smogon/pokemon-showdown/master/simulator-doc.txt) /
  [old](https://raw.githubusercontent.com/smogon/pokemon-showdown/master/old-simulator-doc.txt))
- [pokebattle](https://github.com/sarenji/pokebattle-sim)
- [Pokemon Online](https://github.com/po-devs/pokemon-online)
- [PokemonLab/Shoddy Battle](https://github.com/cathyjf/PokemonLab)

### RNG

- [Pseudorandom number generation in
  Pokémon](https://bulbapedia.bulbagarden.net/wiki/Pseudorandom_number_generation_in_Pokémon)
- [`Admiral-Fish/PokeFinder` RNG
  implementations](https://github.com/Admiral-Fish/PokeFinder/tree/master/Source/Core/RNG)
- [Pokémon Gen 1 RNG
  Mechanics](https://glitchcity.wiki/Luck_manipulation_(Generation_I)#Mechanics_of_the_RNG)
- [Pokémon Yellow DSUM
  Manipulation](http://wiki.pokemonspeedruns.com/index.php/Pokémon_Red/Blue/Yellow_DSum_Manipulation)
- [Pokémon Gen 1 TAS Resources](http://tasvideos.org/GameResources/GBx/PokemonGen1.html)
- [Pokémon Gen 2 TAS Resources](http://tasvideos.org/GameResources/GBx/PokemonGen2.html)
- [Pokémon Gen 3 TAS Resources](http://tasvideos.org/GameResources/GBx/PokemonGen3/RNG.html)

### Glitches

- [List of glitches (Generation
  I)](https://bulbapedia.bulbagarden.net/wiki/List_of_glitches_(Generation_I))
- [Pokémon Crystal - Bugs & Glitches](https://pkmn.cc/pokecrystaldocs/bugs_and_glitches.md)

### Other

- [Technical Machine](https://github.com/davidstone/technical-machine)

### Benchmarks

- **Setup:**
  - [Perf measurement environment on Linux](https://easyperf.net/blog/2019/08/02/Perf-measurement-environment-on-Linux)
  - [LLVM Benchmarking tips](https://llvm.org/docs/Benchmarking.html)
  - [Performance Tracking for Zig](https://github.com/ziglang/gotta-go-fast)
  - [`uarch_bench.sh`](https://github.com/travisdowns/uarch-bench/blob/master/uarch-bench.sh)
- **Tools:**
  - [google/benchmark](https://github.com/google/benchmark)
  - [Benchmark.js](https://benchmarkjs.com/)
  - [`hyperfine`](https://github.com/sharkdp/hyperfine)
  - [`perf`](https://perf.wiki.kernel.org/index.php/Main_Page)
