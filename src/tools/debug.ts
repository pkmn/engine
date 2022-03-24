import 'source-map-support/register';

import * as fs from 'fs';

import {Dex} from '@pkmn/sim';
import {Generations} from '@pkmn/data';
import {Battle} from '../pkg';

const gens = new Generations(Dex as any);

fs.open(process.argv[2], 'r', (_, fd) => {
  const buf = Buffer.alloc(384);
  fs.read(fd, buf, 0, 384, 0, () => {
    const battle = Battle.create(gens.get(1), buf.buffer);
    console.log(battle.lastDamage, battle.side('p2').lastSelectedMove);
  });
});
