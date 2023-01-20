import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import {run} from './common';

describe('integration', () => {
  it('test', async () => {
    const gens = new Generations(Dex as any);
    expect(await run(gens, [1, 2, 3, 4])).toBe(0);
  });
});
