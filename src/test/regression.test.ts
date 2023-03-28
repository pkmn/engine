import * as fs from 'fs';
import * as path from 'path';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import * as addon from '../pkg/addon';

import {run} from './integration';

const FIXTURES = path.join(__dirname, 'fixtures');

(addon.supports(true, true) ? describe : describe.skip)('regression', () => {
  const gens = new Generations(Dex as any);
  for (const name of fs.readdirSync(FIXTURES)) {
    test(`${name.slice(0, -10)}`, async () => {
      expect(await run(gens, path.join(FIXTURES, name))).toBe(0);
    });
  }
});
