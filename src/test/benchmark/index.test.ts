import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import * as addon from '../../pkg/addon';
import {comparison, iterations} from '.';

// Simple smoke tests just to confirm things are wired up correctly and actually execute
describe('benchmark', () => {
  const gens = new Generations(Dex as any);

  // TODO: Unable to spawn D:\...\benchmark-showdown.exe: InvalidExe
  (process.platform !== 'win32' ? test : test.skip)('iterations', () => {
    expect(() => iterations(gens, 10, 10, [1, 2, 3, 4])).not.toThrow();
  });

  (addon.supports(true) && Math.random() > 1 ? test : test.skip)('comparison', async () => {
    await expect(() => comparison(gens, 10, [1, 2, 3, 4])).rejects.toThrow();
  });
});
