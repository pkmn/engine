import {Generations} from '@pkmn/data';
import {Dex, PRNG} from '@pkmn/sim';

import {Options} from '../test/benchmark';

import {Battle, Choice, Result} from './index';

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) {
    describe(`Gen ${gen.num}`, () => {
      test('Battle.create/restore', () => {
        const options = {showdown: true} as any;
        expect(() => Battle.create(gen, options)).toThrow('Unsupported gen');
        expect(() => Battle.restore(gen, {} as any, options)).toThrow('Unsupported gen');
      });
    });
    continue;
  }

  describe(`Gen ${gen.num}`, () => {
    test('Battle.create/restore', () => {
      const options = Options.get(gen, new PRNG([1, 2, 3, 4]));
      const battle = Battle.create(gen, options);
      const restored = Battle.restore(gen, battle, options);
      expect(restored.toJSON()).toEqual(battle.toJSON());
    });

    test('Choice.decode', () => {
      expect(Choice.decode(0b0001_0001)).toEqual(Choice.move(4));
      expect(Choice.decode(0b0001_0110)).toEqual(Choice.switch(5));
    });

    test('Choice.encode', () => {
      expect(Choice.encode()).toBe(Choice.encode(Choice.pass()));
      expect(Choice.encode(Choice.move(4))).toBe(0b0001_0001);
      expect(Choice.encode(Choice.switch(5))).toBe(0b0001_0110);
    });

    test('Choice.parse', () => {
      expect(() => Choice.parse('foo')).toThrow('Invalid choice');
      expect(Choice.parse('pass')).toEqual(Choice.pass());
      expect(() => Choice.parse('pass 2')).toThrow('Invalid choice');
      expect(Choice.parse('move 2')).toEqual(Choice.move(2));
      expect(Choice.parse('move 0')).toEqual(Choice.move(0));
      expect(() => Choice.parse('move 5')).toThrow('Invalid choice');
      expect(Choice.parse('switch 4')).toEqual(Choice.switch(4));
      expect(() => Choice.parse('switch 1')).toThrow('Invalid choice');
    });

    test('Choice.format', () => {
      expect(Choice.format(Choice.pass())).toBe('pass');
      expect(Choice.format(Choice.move(2))).toBe('move 2');
      expect(Choice.format(Choice.switch(4))).toBe('switch 4');
    });

    test('Result.decode', () => {
      expect(Result.decode(0b0101_0000)).toEqual({type: undefined, p1: 'move', p2: 'move'});
      expect(Result.decode(0b1000_0000)).toEqual({type: undefined, p1: 'pass', p2: 'switch'});
    });
  });
}
