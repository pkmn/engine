import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import {run} from '.';

// Simple smoke tests just to confirm things are wired up correctly and actually execute
for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) break;
  for (const showdown of [false, true]) {
    describe(`Gen ${gen.num} (${showdown ? 'showdown' : 'pkmn'})`, () => {
      test('run', () =>
        expect(run(gen, showdown, '1s', 123456789n, true)).resolves.toBe(true),
      60 * 1000);
    });
  }
}
