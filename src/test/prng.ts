import {PRNG, PRNGSeed} from '@pkmn/sim';

export class Gen12PRNG extends PRNG {
  constructor(seed: PRNGSeed) {
    super([0, 0, 0, (Math.floor(seed[3]) & 0xFF) >>> 0]);
  }

  next(from?: number, to?: number): number {
    const result = (this.seed[3] = (this.seed[3] * 5 + 1) & 0xFF);
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
}

export class Gen34PRNG extends PRNG {
  constructor(seed: PRNGSeed) {
    super([0, 0, 0, (seed[2] << 16 >>> 0) + seed[3]]);
  }

  next(from?: number, to?: number): number {
    this.seed[3] = (this.seed[3] * 0x41C64E6D + 0x6073) >>> 0;
    const result = this.seed[3] >>> 16;
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
}
