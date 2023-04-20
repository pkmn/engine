import * as fs from 'fs';
import * as path from 'path';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import * as addon from '../../pkg/addon';
import {run} from '../integration';

const FIXTURES = path.join(__dirname, 'fixtures');

// TODO: uncomment once Leech Seed is fixed upstream
const SKIP = ['0xCDE87ADE2DEA69C'];

(addon.supports(true, true) ? describe : describe.skip)('Gen 1', () => {
  const gens = new Generations(Dex as any);
  for (const file of fs.readdirSync(path.join(FIXTURES, 'gen1'))) {
    const name = file.slice(0, -10);
    (SKIP.includes(name) ? test.skip : test)(`${name}`, async () => {
      expect(await run(gens, path.join(FIXTURES, 'gen1', file))).toBe(0);
    });
  }
});
