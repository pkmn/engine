import {Dex} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {LE, PROTOCOL, Data, Lookup} from './data';
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

    // TODO parse multiple lines and last move!
    describe(`Protocol (Gen ${gen.num})`, () => {
      const log = new Log(gen, Lookup.get(gen), NAMES);

      it.todo('|move|');
      it.todo('|switch|'); // 1
      it.todo('|cant|'); // 2
      it('|faint|', () => {
        const data = Data.view([ArgType.Faint, 0b1010]);
        expect(Array.from(log.parse(data))).toEqual(parse('|faint|p2a: Rakkii'));
      });
      it('|turn|', () => {
        const data = Data.view(LE ? [ArgType.Turn, 42, 0] : [ArgType.Turn, 0, 42]);
        expect(Array.from(log.parse(data))).toEqual(parse('|turn|42'));
      });
      it('|win|', () => {
        expect(Array.from(log.parse(Data.view([ArgType.Win, 0])))).toEqual(parse('|win|Player A'));
        expect(Array.from(log.parse(Data.view([ArgType.Win, 1])))).toEqual(parse('|win|Player B'));
      });
      it('|tie|', () => {
        const data = Data.view([ArgType.Tie]);
        expect(Array.from(log.parse(data))).toEqual(parse('|tie'));
      });
      it.todo('|-damage|'); // 2
      it.todo('|-heal|'); // 2
      it.todo('|-status|'); // 2
      it.todo('|-curestatus|'); // 2
      it('|-boost|', () => {
        expect(Array.from(log.parse(Data.view([ArgType.Boost, 0b1110, PROTOCOL.Boost.Speed, 2]))))
          .toEqual(parse('|-boost|p2a: Fuudin|spe|2'));
        expect(Array.from(log.parse(Data.view([ArgType.Boost, 0b0010, PROTOCOL.Boost.Rage, 1]))))
          .toEqual(parse('|-boost|p1a: Hitokage|atk|1|[from]Rage'));
      });
      it('|-unboost|', () => {
        const data = Data.view([ArgType.Unboost, 0b1011, PROTOCOL.Boost.Defense, 2]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-unboost|p2a: Kabigon|def|2'));
      });
      it('|-clearallboost|', () => {
        const data = Data.view([ArgType.ClearAllBoost]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-clearallboost'));
      });
      it('|-fail|', () => {
        expect(Array.from(log.parse(Data.view([ArgType.Fail, 0b1110, PROTOCOL.Fail.None]))))
          .toEqual(parse('|-fail|p2a: Fuudin'));
        expect(Array.from(log.parse(Data.view([ArgType.Fail, 0b1110, PROTOCOL.Fail.Sleep]))))
          .toEqual(parse('|-fail|p2a: Fuudin|slp'));
        expect(Array.from(log.parse(Data.view([ArgType.Fail, 0b1110, PROTOCOL.Fail.Substitute]))))
          .toEqual(parse('|-fail|p2a: Fuudin|move: Substitute'));
        expect(Array.from(log.parse(Data.view([ArgType.Fail, 0b1110, PROTOCOL.Fail.Weak]))))
          .toEqual(parse('|-fail|p2a: Fuudin|move: Substitute|[weak]'));
      });
      it('|-miss|', () => {
        const data = Data.view([ArgType.Miss, 0b1100, 0b0101]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-miss|p2a: Nasshii|p1a: Koratta'));
      });
      it('|-hitcount|', () => {
        const data = Data.view([ArgType.HitCount, 0b1001, 5]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-hitcount|p2a: Kentarosu|5'));
      });
      it.todo('|-prepare|');
      it('|-mustrecharge|', () => {
        const data = Data.view([ArgType.MustRecharge, 0b0110]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-mustrecharge|p1a: Poppo'));
      });
      it.todo('|-activate|'); // 1
      it('|-fieldactivate|', () => {
        const data = Data.view([ArgType.FieldActivate]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-fieldactivate|move: Pay Day'));
      });
      it.todo('|-start|'); // 2
      it.todo('|-end|'); // 1
      it('|-ohko|', () => {
        const data = Data.view([ArgType.OHKO]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-ohko'));
      });
      it('|-crit|', () => {
        const data = Data.view([ArgType.Crit, 0b1101]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-crit|p2a: Sutaamii'));
      });
      it('|-supereffective|', () => {
        const data = Data.view([ArgType.SuperEffective, 0b0001]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-supereffective|p1a: Fushigidane'));
      });
      it('|-resisted|', () => {
        const data = Data.view([ArgType.Resisted, 0b1010]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-resisted|p2a: Rakkii'));
      });
      it('|-immune|', () => {
        const data = Data.view([ArgType.Immune, 0b0011]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-immune|p1a: Zenigame'));
      });
      it('|-transform|', () => {
        const data = Data.view([ArgType.Transform, 0b1100, 0b0101]);
        expect(Array.from(log.parse(data))).toEqual(parse('|-transform|p2a: Nasshii|p1a: Koratta'));
      });
    });
}
