import {Dex} from '@pkmn/sim';
import {Generations, ID} from '@pkmn/data';

import {Lookup} from './data';

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 2) break;

  const lookup = Lookup.get(gen);
  describe(`Gen ${gen.num}`, () => {
    test('Lookup.sizes', () => {
      const i = gen.num - 1;
      expect(lookup.sizes).toEqual({
        types: [15, 18][i],
        species: [151, 251][i],
        moves: [165, 251][i],
        items: [0, 195][i],
      });
    });

    test('Lookup.type', () => {
      expect(lookup.typeByName('Rock')).toBe(5);
      expect(lookup.typeByNum(14)).toBe(gen.num === 1 ? 'Dragon' : 'Psychic');
    });

    test('Lookup.species', () => {
      expect(lookup.speciesByID('gengar' as ID)).toBe(94);
      expect(lookup.speciesByNum(151)).toBe('mew');
    });

    test('Lookup.move', () => {
      expect(lookup.moveByID('lowkick' as ID)).toBe(67);
      expect(lookup.moveByNum(133)).toBe('amnesia');
    });

    if (gen.num > 1) {
      test('Lookup.item', () => {
        expect(lookup.itemByID('leftovers' as ID)).toBe(28);
        expect(lookup.itemByNum(24)).toBe('thickclub');
        expect(lookup.itemByID('mail' as ID)).toBe(61);
        expect(lookup.itemByNum(61)).toBe('mail');
      });
    }
  });
}
