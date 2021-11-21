## Games

### [Gen 1](https://github.com/pret/pokered)

- `constants/`
  - [`battle_constants.asm`](https://github.com/pret/pokered/blob/master/constants/battle_constants.asm)
    - ["battle status" (volatiles)](https://github.com/pret/pokered/blob/master/constants/battle_constants.asm#L73-L100)
  - [`move_constants.asm`](https://github.com/pret/pokered/blob/master/constants/move_constants.asm)/ [`move_effect_constants.asm`](https://github.com/pret/pokered/blob/master/constants/move_effect_constants.asm) (pointers to "handlers" for moves)
  - [`pokedex_constants.asm`](https://github.com/pret/pokered/blob/master/constants/pokedex_constants.asm)/ [`pokemon_data_constants.asm`](https://github.com/pret/pokered/blob/master/constants/pokemon_data_constants.asm)
  - [`type_constants.asm`](https://github.com/pret/pokered/blob/master/constants/type_constants.asm)
- `data/`
  - [`battle/`](https://github.com/pret/pokered/tree/master/data/battle)
    - [`stat_modifiers.asm`](https://github.com/pret/pokered/blob/master/data/battle/stat_modifiers.asm)
    - "special" moves:  [`residual_effects_1.asm`](https://github.com/pret/pokered/blob/master/data/battle/residual_effects_1.asm), [`residual_effects_2.asm`](https://github.com/pret/pokered/blob/master/data/battle/residual_effects_2.asm),
  - [`moves/`](https://github.com/pret/pokered/tree/master/data/moves)
    - [move data](https://github.com/pret/pokered/blob/master/data/moves/moves.asm)
  - [`pokemon/`](https://github.com/pret/pokered/tree/master/data/pokemon)
    - [species data](https://github.com/pret/pokered/tree/master/data/pokemon/base_stats)
    - [learnsets](https://github.com/pret/pokered/blob/master/data/pokemon/evos_moves.asm)
  - [`types/`](https://github.com/pret/pokered/tree/master/data/types)
    - [`type_matchups.asm`](https://github.com/pret/pokered/blob/master/data/types/type_matchups.asm) - typechart, [linear scan to lookup](https://github.com/pret/pokered/blob/master/engine/battle/core.asm#L5230-L5289)
- [`engine/battle/`](https://github.com/pret/pokered/blob/master/engine/battle)
  - [`move_effects/`](https://github.com/pret/pokered/tree/master/engine/battle/move_effects) - special handlers (like PS `statuses`/`scripts`)
  - [**`core.asm`**](https://github.com/pret/pokered/blob/master/engine/battle/core.asm)
  - [`decrement_pp.asm`](https://github.com/pret/pokered/blob/master/engine/battle/decrement_pp.asm)
  - [`effects.asm`](https://github.com/pret/pokered/blob/master/engine/battle/effects.asm)
- `wram.asm`
  - [macros](https://github.com/pret/pokered/blob/master/macros/wram.asm)
  - [unmodified stats and mods](https://github.com/pret/pokered/blob/master/wram.asm#L525)
  - [active move](https://github.com/pret/pokered/blob/master/wram.asm#L1156)
  - [battle data](https://github.com/pret/pokered/blob/master/wram.asm#L1232)
    - ["battle status" (volatiles)](https://github.com/pret/pokered/blob/master/wram.asm#L1261-L1284)

### [Gen 2](https://github.com/pret/pokecrystal)

- `constants/`
  - [`battle_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/battle_constants.asm)
  - [`item_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/item_constants.asm)/[`item_data_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/item_data_constants.asm#L61-L135)
  - [`move_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/move_constants.asm)/[`move_effect_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/move_effect_constants.asm)
  - [`pokemon_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/pokemon_constants.asm)
  - [`type_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/type_constants.asm)
- `data/`
  - [`battle/`](https://github.com/pret/pokecrystal/tree/master/data/battle)
    - [Accuracy](https://github.com/pret/pokecrystal/blob/master/data/battle/accuracy_multipliers.asm)/[Critical Hits](https://github.com/pret/pokecrystal/blob/master/data/battle/critical_hit_chances.asm)/[Stat Modifiers](https://github.com/pret/pokecrystal/blob/master/data/battle/stat_multipliers.asm)/[Weather](https://github.com/pret/pokecrystal/blob/master/data/battle/weather_modifiers.asm)
  - [`items/`](https://github.com/pret/pokecrystal/tree/master/data/items)
    - [`attributes`](https://github.com/pret/pokecrystal/blob/master/data/items/attributes.asm)
  - [`moves/`](https://github.com/pret/pokecrystal/tree/master/data/moves)
    - [move data](https://github.com/pret/pokecrystal/blob/master/data/moves/moves.asm)
    - [**effects**](https://github.com/pret/pokecrystal/blob/master/data/moves/effects.asm) ([pointers](https://github.com/pret/pokecrystal/blob/master/data/moves/effects_pointers.asm), [priorities](https://github.com/pret/pokecrystal/blob/master/data/moves/effects_priorities.asm))
    - [Flail](https://github.com/pret/pokecrystal/blob/master/data/moves/flail_reversal_power.asm)/[Magnitude](https://github.com/pret/pokecrystal/blob/master/data/moves/magnitude_power.asm)/[Present](https://github.com/pret/pokecrystal/blob/master/data/moves/present_power.asm)/[Metronome](https://github.com/pret/pokecrystal/blob/master/data/moves/metronome_exception_moves.asm)/[Hidden Power](https://github.com/pret/pokecrystal/blob/master/engine/battle/hidden_power.asm)
  - [`pokemon/`](https://github.com/pret/pokecrystal/tree/master/data/pokemon)
    - [species data](https://github.com/pret/pokecrystal/tree/master/data/pokemon/base_stats)
    - learnset [level up](https://github.com/pret/pokecrystal/blob/master/data/pokemon/evos_attacks.asm)/[egg](https://github.com/pret/pokecrystal/blob/master/data/pokemon/egg_moves.asm)
  - [`types/`](https://github.com/pret/pokecrystal/tree/master/data/types)
    - [`type_matchups.asm`](https://github.com/pret/pokecrystal/blob/master/data/types/type_matchups.asm)
    - [`type_boost_items.asm`](https://github.com/pret/pokecrystal/blob/master/data/types/type_boost_items.asm)
- `engine/battle/`
  - [`move_effects/`](https://github.com/pret/pokecrystal/tree/master/engine/battle/move_effects) - handlers
  - [**`core.asm`**](https://github.com/pret/pokecrystal/tree/master/engine/battle/core.asm)
  - [`effect_commands.asm`](https://github.com/pret/pokecrystal/blob/master/engine/battle/effect_commands.asm)
  - [`/home/battle_vars.asm`](https://github.com/pret/pokecrystal/blob/master/home/battle_vars.asm)
- `wram.asm`
  - [battle data](https://github.com/pret/pokecrystal/blob/master/wram.asm#L352-L621),[macros](https://github.com/pret/pokecrystal/blob/master/macros/wram.asm)
- random ([`Random`](https://github.com/pret/pokecrystal/blob/master/home/random.asm), [`BattleRandom`](https://github.com/pret/pokecrystal/blob/master/engine/battle/core.asm#L6881-L6947))

### [Gen 3](https://github.com/pret/pokeemerald)

- `include/`
  - [battle](https://github.com/pret/pokeemerald/blob/master/include/battle.h) ([util](https://github.com/pret/pokeemerald/blob/master/include/battle_util.h)/[scripts](https://github.com/pret/pokeemerald/blob/master/include/battle_scripts.h)/[main](https://github.com/pret/pokeemerald/blob/master/include/battle_main.h))
  - [random](https://github.com/pret/pokeemerald/blob/master/include/random.h)
  - [pokemon](https://github.com/pret/pokeemerald/blob/master/include/pokemon.h#L160-L241)
  - [item](https://github.com/pret/pokeemerald/blob/master/include/item.h)
- `include/constants/`
  - [abilities](https://github.com/pret/pokeemerald/blob/master/include/constants/abilities.h)
  - [species](https://github.com/pret/pokeemerald/blob/master/include/constants/species.h)
  - [types/nature](https://github.com/pret/pokeemerald/blob/master/include/constants/pokemon.h)
  - [moves](https://github.com/pret/pokeemerald/blob/master/include/constants/moves.h)/[move effects](https://github.com/pret/pokeemerald/blob/master/include/constants/battle_move_effects.h)
  - [held item effects](https://github.com/pret/pokeemerald/blob/master/include/constants/hold_effects.h)
  - [battle](https://github.com/pret/pokeemerald/blob/master/include/constants/battle.h)/[misc](https://github.com/pret/pokeemerald/blob/master/include/constants/battle_script_commands.h)
- `src/data/`
  - [species data](https://github.com/pret/pokeemerald/blob/master/src/data/pokemon/base_stats.h)
    - [evolutions](https://github.com/pret/pokeemerald/blob/master/src/data/pokemon/evolution.h)/[egg moves](https://github.com/pret/pokeemerald/blob/master/src/data/pokemon/egg_moves.h)/[level up](https://github.com/pret/pokeemerald/blob/master/src/data/pokemon/level_up_learnsets.h)
  - [move data](https://github.com/pret/pokeemerald/blob/master/src/data/battle_moves.h)
  - [item data](https://github.com/pret/pokeemerald/blob/master/src/data/items.h)
- `src/`
  - battle: [main](https://github.com/pret/pokeemerald/blob/master/src/battle_main.c)/[util](https://github.com/pret/pokeemerald/blob/master/src/battle_util.c)
  - [pokemon](https://github.com/pret/pokeemerald/blob/master/src/pokemon.c)
  - [random](https://github.com/pret/pokeemerald/blob/master/src/random.c)
- [`data/battle_scripts_1.s`](https://github.com/pret/pokeemerald/blob/master/data/battle_scripts_1.s)

### [Gen 4](https://github.com/pret/pokediamond)

### Gen 7

## Simulators

### [Pokemon Showdown!](https://github.com/smogon/pokemon-showdown)

- Simulator Documentation: [New](https://gist.github.com/scheibo/c9ef943ef6e01e350940c8429c378e3b)/[Current](https://raw.githubusercontent.com/smogon/pokemon-showdown/master/simulator-doc.txt)/[Old](https://raw.githubusercontent.com/smogon/pokemon-showdown/master/old-simulator-doc.txt)

Stream flow:

- `Battle.sendUpdates`: sends and update with current `log`, possibly sends `end` if ended
  - `Battle.send`: hooked up in `BattleStream` to send updates to stream updates
- `Battle.setPlayer`: creates a `Side` or updates a player, writes to `log`/`inputLog`, starts
  battle when all players have been added
  - `Battle.getTeam`: unpacks or generates a team
  - `Battle.start`: adds boilerplate messages, triggers format(s) specific `onBegin`/`onTeamPreview` if present, calls go to start prrocessing loop
    - `Battle.go`: processes queued choices, advances to the next turn
      - `Battle.nextTurn`: handles end of turn, runs events, checks for EBC, emits `|request|`
- `Battle.choose`
- `Battle.undoChoice`
- `Battle.destroy`
- `Battle.extractUpdateForSide`

### [pokebattle](https://github.com/sarenji/pokebattle-sim)

### [Pokemon Online](https://github.com/po-devs/pokemon-online)

### [PokemonLab/Shoddy Battle](https://github.com/cathyjf/PokemonLab)

### rsbot/gsbot

## Other

### [Technical Machine](https://github.com/davidstone/technical-machine)

## Appendix

### RNG

- [Pseudorandom number generation in Pokémon](https://bulbapedia.bulbagarden.net/wiki/Pseudorandom_number_generation_in_Pokémon)
- [`Admiral-Fish/PokeFinder` RNG implementations](https://github.com/Admiral-Fish/PokeFinder/tree/master/Source/Core/RNG)
- [Pokémon Gen 1 RNG Mechanics](https://glitchcity.wiki/Luck_manipulation_(Generation_I)#Mechanics_of_the_RNG)
- [Pokémon Yellow DSUM Manipulation](http://wiki.pokemonspeedruns.com/index.php/Pokémon_Red/Blue/Yellow_DSum_Manipulation)
- [Pokémon Gen 1 TAS Resources](http://tasvideos.org/GameResources/GBx/PokemonGen1.html)
- [Pokémon Gen 2 TAS Resources](http://tasvideos.org/GameResources/GBx/PokemonGen2.html)
- [Pokémon Gen 3 TAS Resources](http://tasvideos.org/GameResources/GBx/PokemonGen3/RNG.html)

### Glitches

- [List of glitches (Generation I)](https://bulbapedia.bulbagarden.net/wiki/List_of_glitches_(Generation_I))
- [Pokémon Crystal - Bugs & Glitches](https://github.com/pret/pokecrystal/blob/master/docs/bugs_and_glitches.md)
