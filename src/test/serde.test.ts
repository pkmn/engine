
import {execFileSync} from 'child_process';
import * as path from 'path';

import {Dex, PRNG} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {Lookup, Data} from '../pkg/data';
import * as gen1 from '../pkg/gen1';

const N = 100;
const sh = (cmd: string, args: string[]) => execFileSync(cmd, args, {encoding: 'buffer'});
const ROOT = path.resolve(__dirname, '..', '..');

describe('serialize/deserialize', () => {
  test.todo('create');

  test('restore', () => {
    const rng = new PRNG([1, 2, 3, 4]);
    for (const showdown of [true, false]) {
      const opt = `-Dshowdown=${showdown ? 'true' : 'false'}`;
      sh('zig', ['build', opt, 'tools', '-p', 'build']);
      const exe = path.resolve(ROOT, 'build', 'bin', `serde${showdown ? '-showdown' : ''}`);
      for (const gen of new Generations(Dex as any)) {
        if (gen.num > 1) break;

        const lookup = Lookup.get(gen);
        for (let i = 0; i < N; i++) {
          const seed = rng.next(0, Number.MAX_SAFE_INTEGER).toString();
          const buf = sh(exe, [gen.num.toString(), seed]);
          const data = Data.view(Array.from(buf));
          const battle = new gen1.Battle(lookup, data, {showdown});
          const restored = gen1.Battle.restore(gen, lookup, battle, {showdown});

          expect(restored.toJSON()).toEqual(battle.toJSON());
        }
      }
    }
  });
});
