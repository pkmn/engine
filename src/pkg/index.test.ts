import {Dex, PRNG} from '@pkmn/sim';
import {Generation, Generations} from '@pkmn/data';

import {Battle} from './index';

import * as gen1 from '../test/benchmark/gen1';

function random(gen: Generation) {
  switch (gen.num) {
  case 1: return gen1.Battle.options(gen, new PRNG([1, 2, 3, 4]));
  default: throw new Error(`Unsupported gen ${gen.num}`);
  }
}

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) break;

  describe(`Gen ${gen.num}`, () => {
    it('Battle.create/restore', () => {
      const options = random(gen);
      const battle = Battle.create(gen, options);
      const restored = Battle.restore(gen, battle, options);
      // NOTE: Jest object diffing toJSON is super slow so we compare strings instead...
      expect(JSON.stringify(restored)).toEqual(JSON.stringify(battle));
    });
  });
}
