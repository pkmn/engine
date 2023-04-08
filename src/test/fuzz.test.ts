import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import {run} from './fuzz';

// Simple smoke tests just to confirm things are wired up correctly and actually execute
const gens = new Generations(Dex as any);
for (const gen of gens) {
  if (gen.num > 1) break;
  for (const showdown of [false, true]) {
    describe(`Gen ${gen.num} (${showdown ? 'showdown' : 'pkmn'})`, () => {
      test('run', () =>
        expect(run(gens, gen.num, showdown, '1s', 123456789n, true)).resolves.toBe(true),
      60 * 1000);
    });
  }
}
