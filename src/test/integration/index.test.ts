import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import * as addon from '../../pkg/addon';
import {run} from './common';

describe('integration', () => {
  (addon.supports(true, true) ? test : test.skip)('test', async () => {
    const gens = new Generations(Dex as any);
    expect(await run(gens, {prng: [1, 2, 3, 4]})).toBe(0);
  });
});
