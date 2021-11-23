import {GBRNG, GBARNG} from './rng';

describe('RNG', () => {
  it('GB', () => {
    const data = [
      [1, 1, 6], [2, 3, 25], [3, 5, 172],
      [4, 7, 255], [5, 9, 82], [6, 11, 229],
    ];
    for (const [seed, n, expected] of data) {
      const gb = new GBRNG([0, 0, 0, seed]);
      expect(gb.advance(seed, n)).toBe(expected);
    }
  });

  it('GBA', () => {
    const data = [
      [0x00000000, 5, 0x8E425287], [0x00000000, 10, 0xEF2CF4B2],
      [0x80000000, 5, 0x0E425287], [0x80000000, 10, 0x6F2CF4B2],
    ];
    for (const [seed, n, expected] of data) {
      const gba = new GBARNG([0, 0, seed >>> 16, seed & 0xFFFF]);
      expect(gba.advance(seed, n)).toBe(expected);
    }
  });
});
