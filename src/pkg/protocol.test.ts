import {Dex} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {LE, PROTOCOL, Data, Lookup} from './data';
import {Log} from './protocol';
import {Protocol} from '@pkmn/protocol';

const ArgType = PROTOCOL.ArgType;

const NAMES = {
  p1: {
    name: 'Player A' as Protocol.Username,
    team: ['Fushigidane', 'Hitokage', 'Zenigame', 'Pikachuu', 'Koratta', 'Poppo'],
  },
  p2: {
    name: 'Player B' as Protocol.Username,
    team: ['Kentarosu', 'Rakkii', 'Kabigon', 'Nasshii', 'Sutaamii', 'Fuudin'],
  },
};

const parse = (chunk: string) =>
  Array.from(Protocol.parse(chunk)).map(({args, kwArgs}) => ({args, kwArgs}));

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) break;

  describe(`Gen ${gen.num}`, () => {
    const log = new Log(gen, Lookup.get(gen), NAMES);

    it('|move|', () => {
      const move = (s: string) => gen.moves.get(s)!.num;
      expect(Array.from(log.parse(Data.view(
        [ArgType.Move, 0b1100, move('Thunderbolt'), 0b0101, PROTOCOL.Move.None]
      )))).toEqual(parse('|move|p2a: Nasshii|Thunderbolt|p1a: Koratta'));
      expect(Array.from(log.parse(Data.view(
        [ArgType.Move, 0b1100, move('Wrap'), 0b0101, PROTOCOL.Move.From, move('Wrap')]
      )))).toEqual(parse('|move|p2a: Nasshii|Wrap|p1a: Koratta|[from]Wrap'));
      expect(Array.from(log.parse(Data.view(
        [ArgType.Move, 0b1100, move('Skull Bash'), 0, PROTOCOL.Move.None, ArgType.LastStill]
      )))).toEqual(parse('|move|p2a: Nasshii|Skull Bash||[still]'));
      expect(Array.from(log.parse(Data.view(
        [ArgType.Move, 0b1100, move('Water Gun'), 0b0101, PROTOCOL.Move.None, ArgType.LastMiss]
      )))).toEqual(parse('|move|p2a: Nasshii|Water Gun|p1a: Koratta|[miss]'));
    });

    it('|switch|', () => {
      const start = [ArgType.Switch, 0b1011, gen.species.get('Snorlax')!.num];
      let hp = LE ? [200, 0, 144, 1] : [0, 200, 1, 144];
      expect(Array.from(log.parse(Data.view([...start, 91, ...hp, 0b1000000]))))
        .toEqual(parse('|switch|p2a: Kabigon|Snorlax, L91|200/400 par'));
      hp = LE ? [0, 0, 144, 1] : [0, 0, 1, 144];
      expect(Array.from(log.parse(Data.view([...start, 100, ...hp, 0]))))
        .toEqual(parse('|switch|p2a: Kabigon|Snorlax|0 fnt'));
      hp = LE ? [144, 1, 144, 1] : [1, 144, 1, 144];
      expect(Array.from(log.parse(Data.view([...start, 100, ...hp, 0]))))
        .toEqual(parse('|switch|p2a: Kabigon|Snorlax|400/400'));
    });

    it('|cant|', () => {
      expect(Array.from(log.parse(Data.view([ArgType.Cant, 0b1110, PROTOCOL.Cant.Trapped]))))
        .toEqual(parse('|cant|p2a: Fuudin|partiallytrapped'));
      const eq = gen.moves.get('Earthquake')!.num;
      expect(Array.from(log.parse(Data.view([ArgType.Cant, 0b0010, PROTOCOL.Cant.Disable, eq]))))
        .toEqual(parse('|cant|p1a: Hitokage|Disable|Earthquake'));
    });

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

    it('|-damage|', () => {
      let hp = LE ? [100, 2, 191, 2] : [2, 100, 2, 191];
      expect(Array.from(
        log.parse(Data.view([ArgType.Damage, 0b1010, ...hp, 1, PROTOCOL.Damage.None]))
      )).toEqual(parse('|-damage|p2a: Rakkii|612/703 slp'));
      hp = LE ? [100, 0, 0, 1] : [0, 100, 1, 0];
      expect(Array.from(
        log.parse(Data.view([ArgType.Damage, 0b1010, ...hp, 0, PROTOCOL.Damage.Confusion]))
      )).toEqual(parse('|-damage|p2a: Rakkii|100/256|[from] confusion'));
      expect(Array.from(
        log.parse(Data.view([ArgType.Damage, 0b1010, ...hp, 0b1000, PROTOCOL.Damage.RecoilOf, 1]))
      )).toEqual(parse('|-damage|p2a: Rakkii|100/256 psn|[from] Recoil|[of] p1a: Fushigidane'));
    });

    it('|-heal|', () => {
      let hp = LE ? [100, 2, 191, 2] : [2, 100, 2, 191];
      expect(Array.from(
        log.parse(Data.view([ArgType.Heal, 0b1010, ...hp, 1, PROTOCOL.Heal.None]))
      )).toEqual(parse('|-heal|p2a: Rakkii|612/703 slp'));
      hp = LE ? [100, 0, 0, 1] : [0, 100, 1, 0];
      expect(Array.from(
        log.parse(Data.view([ArgType.Heal, 0b1010, ...hp, 0, PROTOCOL.Heal.Silent]))
      )).toEqual(parse('|-heal|p2a: Rakkii|100/256|[silent]'));
      expect(Array.from(
        log.parse(Data.view([ArgType.Heal, 0b1010, ...hp, 0, PROTOCOL.Heal.Drain, 0b0001]))
      )).toEqual(parse('|-heal|p2a: Rakkii|100/256|[from] drain|[of] p1a: Fushigidane'));
    });

    it('|-status|', () => {
      expect(Array.from(
        log.parse(Data.view([ArgType.Status, 0b1110, 0b10000, PROTOCOL.Status.None]))
      )).toEqual(parse('|-status|p2a: Fuudin|brn'));
      expect(Array.from(
        log.parse(Data.view([ArgType.Status, 0b0010, 0b100000, PROTOCOL.Status.Silent]))
      )).toEqual(parse('|-status|p1a: Hitokage|frz|[silent]'));
      const bs = gen.moves.get('bodyslam')!.num;
      expect(Array.from(
        log.parse(Data.view([ArgType.Status, 0b0001, 0b1000000, PROTOCOL.Status.From, bs]))
      )).toEqual(parse('|-status|p1a: Fushigidane|par|[from] move: Body Slam'));
    });

    it('|-curestatus|', () => {
      expect(Array.from(
        log.parse(Data.view([ArgType.CureStatus, 0b1110, 0b111, PROTOCOL.CureStatus.Message]))
      )).toEqual(parse('|-curestatus|p2a: Fuudin|slp|[msg]'));
      expect(Array.from(
        log.parse(Data.view([ArgType.CureStatus, 0b0010, 0b1000, PROTOCOL.CureStatus.Silent]))
      )).toEqual(parse('|-curestatus|p1a: Hitokage|psn|[silent]'));
    });

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
      const data = Data.view([ArgType.Miss, 0b1100]);
      expect(Array.from(log.parse(data))).toEqual(parse('|-miss|p2a: Nasshii'));
    });

    it('|-hitcount|', () => {
      const data = Data.view([ArgType.HitCount, 0b1001, 5]);
      expect(Array.from(log.parse(data))).toEqual(parse('|-hitcount|p2a: Kentarosu|5'));
    });

    it('|-prepare|', () => {
      const data = Data.view([ArgType.Prepare, 0b1010, gen.moves.get('dig')!.num]);
      expect(Array.from(log.parse(data))).toEqual(parse('|-prepare|p2a: Rakkii|Dig'));
    });

    it('|-mustrecharge|', () => {
      const data = Data.view([ArgType.MustRecharge, 0b0110]);
      expect(Array.from(log.parse(data))).toEqual(parse('|-mustrecharge|p1a: Poppo'));
    });

    it('|-activate|', () => {
      expect(
        Array.from(log.parse(Data.view([ArgType.Activate, 0b0010, PROTOCOL.Activate.Struggle])))
      ).toEqual(parse('|-activate|p1a: Hitokage|move: Struggle'));
      expect(
        Array.from(log.parse(Data.view([ArgType.Activate, 0b1110, PROTOCOL.Activate.Substitute])))
      ).toEqual(parse('|-activate|p2a: Fuudin|Substitute|[damage]'));
      expect(
        Array.from(log.parse(Data.view([ArgType.Activate, 0b0010, PROTOCOL.Activate.Splash])))
      ).toEqual(parse('|-nothing'));
    });

    it('|-fieldactivate|', () => {
      const data = Data.view([ArgType.FieldActivate]);
      expect(Array.from(log.parse(data))).toEqual(parse('|-fieldactivate|move: Pay Day'));
    });

    it('|-start|', () => {
      expect(Array.from(log.parse(Data.view([ArgType.Start, 0b1110, PROTOCOL.Start.Bide]))))
        .toEqual(parse('|-start|p2a: Fuudin|Bide'));
      expect(Array.from(
        log.parse(Data.view([ArgType.Start, 0b0010, PROTOCOL.Start.ConfusionSilent]))
      )).toEqual(parse('|-start|p1a: Hitokage|confusion|[silent]'));
      expect(Array.from(
        log.parse(Data.view([ArgType.Start, 0b1110, PROTOCOL.Start.TypeChange, 0b1000_1000]))
      )).toEqual(parse(
        '|-start|p2a: Fuudin|typechange|Fire|[from] move: Conversion|[of] p2a: Fuudin'
      ));
      expect(Array.from(
        log.parse(Data.view([ArgType.Start, 0b0010, PROTOCOL.Start.TypeChange, 0b0011_0110]))
      )).toEqual(parse(
        '|-start|p1a: Hitokage|typechange|Bug/Poison|[from] move: Conversion|[of] p1a: Hitokage'
      ));
      const surf = gen.moves.get('Surf')!.num;
      expect(Array.from(
        log.parse(Data.view([ArgType.Start, 0b0010, PROTOCOL.Start.Disable, surf]))
      )).toEqual(parse('|-start|p1a: Hitokage|Disable|Surf'));
      expect(Array.from(
        log.parse(Data.view([ArgType.Start, 0b0010, PROTOCOL.Start.Mimic, surf]))
      )).toEqual(parse('|-start|p1a: Hitokage|Mimic|Surf'));
    });

    it('|-end|', () => {
      expect(Array.from(log.parse(Data.view([ArgType.End, 0b1110, PROTOCOL.End.Bide]))))
        .toEqual(parse('|-end|p2a: Fuudin|move: Bide'));
      expect(Array.from(log.parse(Data.view([ArgType.End, 0b0010, PROTOCOL.End.ConfusionSilent]))))
        .toEqual(parse('|-end|p1a: Hitokage|confusion|[silent]'));
    });

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
      expect(Array.from(log.parse(Data.view([ArgType.Immune, 0b0011, PROTOCOL.Immune.None]))))
        .toEqual(parse('|-immune|p1a: Zenigame'));
      expect(Array.from(log.parse(Data.view([ArgType.Immune, 0b1010, PROTOCOL.Immune.OHKO]))))
        .toEqual(parse('|-immune|p2a: Rakkii|[ohko]'));
    });

    it('|-transform|', () => {
      const data = Data.view([ArgType.Transform, 0b1100, 0b0101]);
      expect(Array.from(log.parse(data))).toEqual(parse('|-transform|p2a: Nasshii|p1a: Koratta'));
    });

    it('chunk', () => {
      const data = Data.view([
        ArgType.Cant, 0b1110, PROTOCOL.Cant.Trapped,
        ArgType.Move, 0b0101, 1, 0b1110, PROTOCOL.Move.None,
        ArgType.Miss, 0b0101,
        ArgType.LastMiss,
        ArgType.Move, 0b1110, 2, 0b0101, PROTOCOL.Move.None,
        ArgType.Faint, 0b0101,
        ArgType.LastStill,
      ]);

      const parsed = parse(
        '|cant|p2a: Fuudin|partiallytrapped\n' +
        '|move|p1a: Koratta|Pound|p2a: Fuudin|[miss]\n' +
        '|-miss|p1a: Koratta\n' +
        '|move|p2a: Fuudin|Karate Chop|p1a: Koratta|[still]\n' +
        '|faint|p1a: Koratta\n'
      );

      expect(Array.from(log.parse(data))).toEqual(parsed);
      expect(Array.from(log.parse(Data.view(
        [ArgType.Move, 0b0101, 1, 0b1110, PROTOCOL.Move.None, ArgType.None]
      )))).toEqual(parse('|move|p1a: Koratta|Pound|p2a: Fuudin'));
      expect(() => Array.from(log.parse(Data.view([0xFF])))).toThrow('Expected arg');
    });
  });
}
