
import * as path from 'path';
import {execFile} from 'child_process';

import {Dex, PRNG} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {LAYOUT, Lookup} from '../pkg/data';
import * as gen1 from '../pkg/gen1';

const N = 10000;

const BIN = path.resolve(__dirname, '../../build/bin');
const BINS = [[path.join(BIN, 'serde'), false], [path.join(BIN, 'serde-showdown'), true]] as const;

const run = async (cmd: string, args: string[]): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    execFile(cmd, args, {encoding: 'buffer'}, (error, stdout) =>
      error ? reject(error) : resolve(stdout));
  });

describe('serialize/deserialize', () => {
  it.todo('init'); // TODO @pkmn/randoms!
  it.skip('encode', async () => {
    const rng = new PRNG([1, 2, 3, 4]);
    for (const gen of new Generations(Dex as any)) {
      if (gen.num > 1) break; // TODO

      const lookup = Lookup.get(gen);
      for (let i = 0; i < N; i++) {
        for (const [bin, showdown] of BINS) {
          const buf = await run(bin, [gen.num.toString(), rng.next().toString()]);
          const expected = Buffer.alloc(LAYOUT[0].sizes.Battle);
          buf.copy(expected);

          const battle = new gen1.Battle(lookup, new DataView(buf), showdown);
          const actual = gen1.Battle.encode(gen, lookup, battle);

          expect(actual).toEqual(expected);
        }
      }
    }
  });
});
