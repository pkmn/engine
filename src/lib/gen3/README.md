#### `MoveTarget`

TODO https://pkmn.cc/pokeemerald/include/battle.h#L44-L51

| pkmn             | Pokémon Emerald (pret) | Pokémon Showdown  |
| ---------------- | ---------------------- | ----------------- |
|                  | `SELECTED`             | `normal`          |
| `Depends`        | `DEPENDS`              | `scripted`        |
|                  | *`USER_OR_SELECTED`*   |                   |
| `Random`         | `RANDOM`               | `randomNormal`    |
| `Both`           | `BOTH`                 | `allAdjacentFoes` |
| `User`           | `USER`                 | `self`            |
| `FoesAndAlly`    | `FOES_AND_ALLY`        | `allAdjacent`     |
| `OpponentsField` | `OPPONENTS_FIELD`      | `foeSide`         |

#### `MoveFlags`

TODO https://pkmn.cc/pokeemerald/include/constants/pokemon.h#L285-L290

| pkmn         | Pokémon Emerald (pret) | Pokémon Showdown |
| ------------ | ---------------------- | ---------------- |
| `Contact`    | `MAKES_CONTACT`        | `contact`        |
| `Protect`    | `PROTECT_AFFECTED`     | `protect`        |
| `MagicCoat`  | `MAGIC_COAT_AFFECTED`  | `reflectable`    |
| `Snatch`     | `SNATCH_AFFECTED`      | `snatch`         |
| `MirrorMove` | `MIRROR_MOVE_AFFECTED` | `mirror`         |
| `KingsRock`  | `KINGS_ROCK_AFFECTED`  |                  |

```txt
-ability: _, from, of, silent
-activate: _, ability, ability2, consumed, damage, move, number, of
-anim: _, miss
-block: _
-boost: _, from
-clearallboost: _
-clearnegativeboost: silent
-copyboost: from
-crit: _
-curestatus: from, msg, silent
-cureteam: from
-damage: _, from, of, partiallytrapped
-end: _, from, of, partiallytrapped, silent
-endability: from
-enditem: _, eat, from, of, silent
-fail: _, from, msg, of, weak
-fieldactivate: _
-formechange: from, msg
-heal: _, from, of, silent, wisher
-hint: _
-hitcount: _
-immune: _, from, ohko
-item: from, of
-miss: _
-mustrecharge: _
-notarget: _
-ohko: _
-prepare: _
-resisted: _
-setboost: from
-sethp: from, silent
-sideend: _, from, of
-sidestart: _
-singlemove: _, of
-singleturn: _, of
-start: _, fatigue, from, of, silent, upkeep
-status: _, from, of
-supereffective: _
-transform: _
-unboost: _
-weather: _, from, of, upkeep
cant: _
debug: _
done: _
drag: _
error: _
faint: _
gametype: _
gen: _
move: _, from, miss, notarget, spread, still
player: _
request: _
rule: _
split: _
start: _
switch: _, from
t:: _
teamsize: _
tie: _
tier: _
turn: _
upkeep: _
win: _
```
