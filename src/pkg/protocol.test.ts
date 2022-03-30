import {Dex} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {Data, Lookup, PROTOCOL} from './data';
import {Log} from './protocol';
import {Protocol} from '@pkmn/protocol';

const ArgType = PROTOCOL.ArgType;

const NAMES = {
  p1: {
    player: "Player A" as Protocol.Username,
    team: ["Fushigidane", "Hitokage", "Zenigame", "Pikachuu", "Koratta", "Poppo"],
  },
  p2: {
    player: "Player B" as Protocol.Username,
    team: ["Kentarosu", "Rakkii", "Kabigon", "Nasshii", "Sutaamii", "Fuudin"],
  }
}

const parse = (chunk: string) =>
  Array.from(Protocol.parse(chunk)).map(({args, kwArgs}) => ({args, kwArgs}));

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) break;

    describe(`Protocol (Gen ${gen.num})`, () => {
      const log = new Log(gen, Lookup.get(gen), NAMES);

      it.todo('|move|');
      it.todo('|switch|');
      it.todo('|cant|');
      it.todo('|faint|');
      it.todo('|turn|');
      it.todo('|win|');
      it.todo('|tie|');
      it.todo('|-damge|');
      it.todo('|-heal|');
      it.todo('|-status|');
      it.todo('|-curestatus|');
      it.todo('|-boost|');
      it.todo('|-unboost|');
      it.todo('|-clearallboost|');
      it.todo('|-fail|');
      it.todo('|-miss|');
      it.todo('|-hitcount|');
      it.todo('|-prepare|');
      it.todo('|-mustrecharge|');
      it.todo('|-activate|');
      it.todo('|-fieldactivate|');
      it.todo('|-start|');
      it.todo('|-end|');
      it('|-ohko|', () => {
        const data = Data.view([ArgType.OHKO]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-ohko'));
      });
      it.todo('|-crit|');
      it.todo('|-supereffective|');
      it.todo('|-resisted|');
      it.todo('|-immune|');
      it.todo('|-transform|');
    });
}
