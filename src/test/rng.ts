import {PRNG, PRNGSeed} from '@pkmn/sim';

export abstract class BaseRNG<Int = number | bigint> implements PRNG {
  protected _seed: Int;
  readonly initialSeed: PRNGSeed;

  constructor(s: Int) {
    this._seed = s;
    this.initialSeed = this.seed;
  }

  get seed(): PRNGSeed {
    return this.toPRNGSeed();
  }

  set seed(seed: PRNGSeed) {
    throw new Error('Illegal operation');
  }

  get startingSeed() {
    return this.initialSeed;
  }

  randomChance(numerator: number, denominator: number): boolean {
    return this.next(denominator) < numerator;
  }

  sample<T>(items: readonly T[]): T {
    if (items.length === 0) {
      throw new RangeError('Cannot sample an empty array');
    }
    const index = this.next(items.length);
    const item = items[index];
    if (item === undefined && !Object.prototype.hasOwnProperty.call(items, index)) {
      throw new RangeError('Cannot sample a sparse array');
    }
    return item;
  }

  shuffle<T>(items: T[], start = 0, end: number = items.length) {
    while (start < end - 1) {
      const nextIndex = this.next(start, end);
      if (start !== nextIndex) {
        [items[start], items[nextIndex]] = [items[nextIndex], items[start]];
      }
      start++;
    }
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  multiplyAdd(a: PRNGSeed, b: PRNGSeed, c: PRNGSeed): PRNGSeed {
    // This should really be a private method on PRNG...
    throw new Error('Unimplemented');
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  nextFrame(seed: PRNGSeed, n: number): PRNGSeed {
    // This should really be a private method on PRNG...
    throw new Error('Unimplemented');
  }

  abstract clone(): PRNG;

  abstract next(from?: number, to?: number): number;

  abstract toPRNGSeed(): PRNGSeed;
}

export class Gen12RNG extends BaseRNG<number> {
  static fromPRNGSeed(seed: PRNGSeed) {
    return new Gen12RNG((Math.floor(seed[3]) & 0xFF) >>> 0);
  }

  toPRNGSeed(): PRNGSeed {
    return [0, 0, 0, this._seed];
  }

  next(from?: number, to?: number): number {
    const result = (this._seed = Gen12RNG.advance(this._seed));
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

  clone() {
    return new Gen12RNG(this._seed);
  }
}

export class Gen34RNG extends BaseRNG<number> {
  static fromPRNGSeed(seed: PRNGSeed) {
    return new Gen34RNG((seed[2] << 16 >>> 0) + seed[3]);
  }

  toPRNGSeed(): PRNGSeed {
    return [0, 0, this._seed >>> 16, this._seed & 0xFFFF];
  }

  next(from?: number, to?: number): number {
    this._seed = Gen34RNG.advance(this._seed);
    const result = this._seed >>> 16; // Use the upper 16 bits
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

  clone() {
    return new Gen34RNG(this._seed);
  }
}

export class Gen56RNG extends BaseRNG<bigint> {
  static fromPRNGSeed(seed: PRNGSeed) {
    return new Gen56RNG(BigInt.asUintN(64,
      (BigInt(seed[0]) << 48n) +
      (BigInt(seed[1]) << 32n) +
      (BigInt(seed[2]) << 16n) +
      BigInt(seed[3])));
  }

  toPRNGSeed(): PRNGSeed {
    return [
      Number((this._seed >> 48n) & 0xFFFFn),
      Number((this._seed >> 32n) & 0xFFFFn),
      Number((this._seed >> 16n) & 0xFFFFn),
      Number((this._seed >> 0n) & 0xFFFFn),
    ];
  }

  next(from?: number, to?: number): number {
    this._seed = Gen56RNG.advance(this._seed);
    const result = Number((this._seed >> 32n) & 0xFFFFFFFFn); // Use the upper 32 bits
    if (from) from = Math.floor(from);
    if (to) to = Math.floor(to);
    if (from === undefined) {
      return result / 0x100000000;
    } else if (!to) {
      return Math.floor(result * from / 0x100000000);
    } else {
      return Math.floor(result * (to - from) / 0x100000000) + from;
    }
  }

  static advance(seed: bigint, n = 1) {
    for (let i = 0; i < n; i++) {
      seed = BigInt.asUintN(64, 0x5D588B656C078965n * seed + 0x0000000000269EC3n);
    }
    return seed;
  }

  clone() {
    return new Gen56RNG(this._seed);
  }
}
