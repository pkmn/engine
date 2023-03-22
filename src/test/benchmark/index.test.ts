import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import * as addon from '../../pkg/addon';

import {comparison, iterations} from '.';

// Simple smoke tests just to confirm things are wired up correctly and actually execute
describe('benchmark', () => {
  const gens = new Generations(Dex as any);

  test('iterations', () => {
    expect(() => iterations(gens, 10, 10, [1, 2, 3, 4])).not.toThrow();
  });

  (addon.supports(true) && Math.random() > 1 ? test : test.skip)('comparison', () =>
    expect(comparison(gens, 10, [1, 2, 3, 4])).resolves.toBeUndefined());
});
