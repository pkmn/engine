
import {execFile} from 'child_process';

import {Dex, PRNG} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {Lookup, Data} from '../pkg/data';
import * as gen1 from '../pkg/gen1';

const N = 100;

const run = async (cmd: string, args: string[]): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    execFile(cmd, args, {encoding: 'buffer'}, (error, stdout) =>
      error ? reject(error) : resolve(stdout));
  });

describe('serialize/deserialize', () => {
  it.todo('create');

  it('restore', async () => {
    const rng = new PRNG([1, 2, 3, 4]);
    for (const gen of new Generations(Dex as any)) {
      if (gen.num > 1) break;

      const lookup = Lookup.get(gen);
      for (let i = 0; i < N; i++) {
        for (const showdown of [true, false]) {
          const opt = `-Dshowdown=${showdown ? 'true' : 'false'}`;
          const seed = rng.next(0, Number.MAX_SAFE_INTEGER).toString();
          const buf = await run('zig', ['build', opt, 'serde', '--', gen.num.toString(), seed]);
          // NOTE: buf.buffer is garbage data because Node is dumb ¯\_(ツ)_/¯
          const data = new DataView(Data.buffer(Array.from(buf)).buffer);

          const battle = new gen1.Battle(lookup, data, {showdown});
          const restored = gen1.Battle.restore(gen, lookup, battle, {showdown});

          expect(JSON.stringify(restored, null, 2)).toEqual(JSON.stringify(battle, null, 2));
        }
      }
    }
  }, N * 5000);
});
