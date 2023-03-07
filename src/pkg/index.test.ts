import {Dex, PRNG} from '@pkmn/sim';
import {Generation, Generations} from '@pkmn/data';

import {Battle, Choice, Result} from './index';

import * as gen1 from '../test/benchmark/gen1';

function random(gen: Generation) {
  switch (gen.num) {
  case 1: return gen1.Battle.options(gen, new PRNG([1, 2, 3, 4]));
  default: throw new Error(`Unsupported gen ${gen.num}`);
  }
}

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
      const options = random(gen);
      const battle = Battle.create(gen, options);
      const restored = Battle.restore(gen, battle, options);
      expect(restored.toJSON()).toEqual(battle.toJSON());
    });

    test('Choice.parse', () => {
      expect(Choice.parse(0b0100_0001)).toEqual(Choice.move(4));
      expect(Choice.parse(0b0101_0010)).toEqual(Choice.switch(5));
    });

    test('Choice.encode', () => {
      expect(Choice.encode()).toBe(Choice.encode(Choice.pass()));
      expect(Choice.encode(Choice.move(4))).toBe(0b0100_0001);
      expect(Choice.encode(Choice.switch(5))).toBe(0b0101_0010);
    });

    test('Result.parse', () => {
      expect(Result.parse(0b0101_0000)).toEqual({type: undefined, p1: 'move', p2: 'move'});
      expect(Result.parse(0b1000_0000)).toEqual({type: undefined, p1: 'pass', p2: 'switch'});
    });
  });
}
