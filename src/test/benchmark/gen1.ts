import {PRNG} from '@pkmn/sim';
import {Generation, PokemonSet, StatsTable} from '@pkmn/data';

import * as engine from '../../pkg';
import {Lookup} from '../../pkg/data';

export const Battle = new class {
  static random(gen: Generation, prng: PRNG): engine.Battle {
    return engine.Battle.create(gen, this.options(gen, prng));
  }

  private static options(gen: Generation, prng: PRNG): engine.CreateOptions {
    return {
      seed: [
        prng.next(0x10000),
        prng.next(0x10000),
        prng.next(0x10000),
        prng.next(0x10000),
      ],
      p1: Player.options(gen, prng),
      p2: Player.options(gen, prng),
      showdown: true,
      log: false,
    };
  }
};

const Player = new class {
  options(gen: Generation, prng: PRNG): Omit<engine.PlayerOptions, 'name'> {
    const lookup = Lookup.get(gen);

    const team: Partial<PokemonSet>[] = [];
    const n = prng.randomChance(1, 100) ? prng.next(1, 5 + 1) : 6;
    for (let i = 0; i < n; i++) {
      const species = lookup.specieByNum(prng.next(1, 151 + 1));
      const level = prng.randomChance(1, 20) ? prng.next(1, 99 + 1) : 100;

      const ivs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'hp' || stat === 'spd') continue;
        ivs[stat] = gen.stats.toIV(prng.randomChance(1, 5) ? prng.next(1, 15 + 1) : 15);
      }
      ivs.hp = gen.stats.toIV(gen.stats.getHPDV(ivs));
      ivs.spd = ivs.spa;

      const evs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'spd') break;
        ivs[stat] = prng.randomChance(1, 20) ? prng.next(0, 255 + 1) : 255;
      }
      evs.spd = evs.spa;

      const moves: string[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 165 + 1))))) {}
        moves.push(move);
      }

      team.push({species, level, ivs, evs, moves});
    }

    return {team};
  }
};
