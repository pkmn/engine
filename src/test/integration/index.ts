import 'source-map-support/register';

import {Generations} from '@pkmn/data';
import {Dex, PRNG} from '@pkmn/sim';
import minimist from 'minimist';

import {run} from './common';

(async () => {
  const gens = new Generations(Dex as any);
  // minimist tries to parse all number-like things into numbers which doesn't work because the
  // seed is actually a bigint, meaning we need to special case this without calling minimist
  if (process.argv.length === 3 && process.argv[2][0] !== '-') {
    process.exit(await run(gens, process.argv[2]));
  }
  const argv = minimist(process.argv.slice(2), {default: {maxFailures: 1}});
  const unit =
    typeof argv.duration === 'string' ? argv.duration[argv.duration.length - 1] : undefined;
  const duration =
    unit ? +argv.duration.slice(0, -1) * {s: 1e3, m: 6e4, h: 3.6e6}[unit]! : argv.duration;
  argv.cycles = argv.cycles ?? duration ? 1 : 10;
  const seed = argv.seed ? argv.seed.split(',').map((s: string) => Number(s)) : null;
  const options = {prng: new PRNG(seed), log: process.stdout.isTTY, ...argv, duration};
  process.exit(await run(gens, options));
})().catch(err => {
  console.error(err);
  process.exit(1);
});
