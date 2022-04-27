import {PRNG, PRNGSeed} from '@pkmn/sim';

export const newSeed = (prng: PRNG) => [
  prng.next(0x10000),
  prng.next(0x10000),
  prng.next(0x10000),
  prng.next(0x10000),
] as PRNGSeed;
