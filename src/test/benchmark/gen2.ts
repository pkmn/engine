import * as sim from '@pkmn/sim';
import {Generation, PokemonSet, StatsTable, ID} from '@pkmn/data';

import * as engine from '../../pkg';
// import * as gen2 from '../../pkg/gen2';
import {Lookup} from '../../pkg/data';
import {newSeed} from '../integration';

export const Battle = new class {
  random(gen: Generation, prng: sim.PRNG): engine.Battle {
    return engine.Battle.create(gen, this.options(gen, prng));
  }

  options(gen: Generation, prng: sim.PRNG): engine.CreateOptions {
    return {
      seed: newSeed(prng),
      p1: Player.options(gen, prng),
      p2: Player.options(gen, prng),
      showdown: true,
      log: false,
    };
  }
};

const Player = new class {
  options(gen: Generation, prng: sim.PRNG): Omit<engine.PlayerOptions, 'name'> {
    const lookup = Lookup.get(gen);

    const team: Partial<PokemonSet>[] = [];
    const n = prng.randomChance(1, 100) ? prng.next(1, 5 + 1) : 6;
    for (let i = 0; i < n; i++) {
      const species = lookup.speciesByNum(prng.next(1, 251 + 1));
      const level = prng.randomChance(1, 20) ? prng.next(1, 99 + 1) : 100;
      const item = prng.randomChance(1, 10) ? undefined
        : lookup.itemByNum(prng.next(1, 62 + 1));

      const ivs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'hp' || stat === 'spd') continue;
        ivs[stat] = gen.stats.toIV(prng.randomChance(1, 5) ? prng.next(1, 15 + 1) : 15);
      }
      ivs.hp = gen.stats.toIV(gen.stats.getHPDV(ivs));
      ivs.spd = ivs.spa;

      const evs = {} as StatsTable;
      for (const stat of gen.stats) {
        const exp = prng.randomChance(1, 20) ? prng.next(0, 0xFFFF + 1) : 0xFFFF;
        evs[stat] = Math.floor(Math.min(255, Math.ceil(Math.sqrt(exp))) / 4);
      }

      const moves: ID[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move: ID;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 250 + 1)))));
        moves.push(move);
      }

      const happiness = prng.randomChance(1, 10 + 1) ? prng.next(0, 255) : 255;
      team.push({species, level, item, ivs, evs, moves, happiness});
    }

    return {team};
  }
};
