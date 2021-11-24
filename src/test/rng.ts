import {PRNG, PRNGSeed} from '@pkmn/sim';

export class Gen12RNG extends PRNG {
  constructor(seed: PRNGSeed) {
    super([0, 0, 0, (Math.floor(seed[3]) & 0xFF) >>> 0]);
  }

  next(from?: number, to?: number): number {
    const result = (this.seed[3] = Gen12RNG.advance(this.seed[3]));
    if (from) from = Math.floor(from);
    if (to) to = Math.floor(to);
    if (from === undefined) {
      return result / 0x100;
    } else if (!to) {
      return Math.floor(result * from / 0x100);
    } else {
      return Math.floor(result * (to - from) / 0x100) + from;
    }
  }

  static advance(seed: number, n = 1) {
    for (let i = 0; i < n; i++) {
      seed = (5 * seed) & 0xFF;
      seed = (seed + 1) & 0xFF;
    }
    return seed;
  }
}

export class Gen34RNG extends PRNG {
  constructor(seed: PRNGSeed) {
    super([0, 0, 0, (seed[2] << 16 >>> 0) + seed[3]]);
  }

  next(from?: number, to?: number): number {
    this.seed[3] = (this.seed[3] = Gen34RNG.advance(this.seed[3]));
    const result = this.seed[3] >>> 16; // Use the upper 16 bits
    if (from) from = Math.floor(from);
    if (to) to = Math.floor(to);
    if (from === undefined) {
      return result / 0x10000;
    } else if (!to) {
      return Math.floor(result * from / 0x10000);
    } else {
      return Math.floor(result * (to - from) / 0x1000) + from;
    }
  }

  static advance(seed: number, n = 1) {
    for (let i = 0; i < n; i++) {
      seed = (Math.imul(0x41C64E6D, seed) + 0x00006073) >>> 0;
    }
    return seed;
  }
}

export const Gen56RNG = PRNG;
