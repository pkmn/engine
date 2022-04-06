import {Generations} from "@pkmn/data";
import {Dex} from "@pkmn/dex";

const gens = new Generations(Dex);
console.log(gens.get(1).species.get('Gengar').baseStats.hp);
