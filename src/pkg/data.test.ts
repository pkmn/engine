import {Dex} from '@pkmn/sim';
import {Generations, ID} from '@pkmn/data';

import {Lookup} from './data';

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 2) break;

  const lookup = Lookup.get(gen);
  describe(`Gen ${gen.num}`, () => {
    it('Lookup.type', () => {
      expect(lookup.typeByName('Rock')).toBe(5);
      expect(lookup.typeByNum(14)).toBe(gen.num === 1 ? 'Dragon' : 'Psychic');
    });

    it('Lookup.species', () => {
      expect(lookup.specieByID('gengar' as ID)).toBe(94);
      expect(lookup.specieByNum(151)).toBe('mew');
    });

    it('Lookup.move', () => {
      expect(lookup.moveByID('lowkick' as ID)).toBe(67);
      expect(lookup.moveByNum(133)).toBe('amnesia');
    });

    if (gen.num > 1) {
      it('Lookup.item', () => {
        expect(lookup.itemByID('leftovers' as ID)).toBe(109);
        expect(lookup.itemByNum(97)).toBe('thickclub');
      });
    }
  });
}
