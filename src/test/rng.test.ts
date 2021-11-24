import {PRNGSeed} from '@pkmn/sim';
import {Gen12RNG, Gen34RNG, Gen56RNG} from './rng';

describe('RNG', () => {
  it('Generation I & II', () => {
    const data = [
      [1, 1, 6], [2, 3, 25], [3, 5, 172],
      [4, 7, 255], [5, 9, 82], [6, 11, 229],
    ];
    for (const [seed, n, expected] of data) {
      expect(Gen12RNG.advance(seed, n)).toBe(expected);
    }
  });

  it('Generation III & IV', () => {
    const data = [
      [0x00000000, 5, 0x8E425287], [0x00000000, 10, 0xEF2CF4B2],
      [0x80000000, 5, 0x0E425287], [0x80000000, 10, 0x6F2CF4B2],
    ];
    for (const [seed, n, expected] of data) {
      expect(Gen34RNG.advance(seed, n)).toBe(expected);
    }
  });

  it('Generation V & VI', () => {
    const seeds: [PRNGSeed, number, PRNGSeed][] = [
      [[0x0000, 0x0000, 0x0000, 0x0000], 5, [0xC83F, 0xB970, 0x153A, 0x9227]],
      [[0x0000, 0x0000, 0x0000, 0x0000], 10, [0x6779, 0x5501, 0x267F, 0x125A]],
      [[0x8000, 0x0000, 0x0000, 0x0000], 5, [0x483F, 0xB970, 0x153A, 0x9227]],
      [[0x8000, 0x0000, 0x0000, 0x0000], 10, [0xE779, 0x5501, 0x267F, 0x125A]],
    ];
    for (const [seed, n, expected] of seeds) {
      const rng = new Gen56RNG(seed);
      for (let i = 0; i < n; i++) rng.next();
      expect(rng.seed).toEqual(expected);
    }
  });
});
