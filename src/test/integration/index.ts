import 'source-map-support/register';

import {Generations} from '@pkmn/data';
import {Dex, PRNG} from '@pkmn/sim';
import minimist from 'minimist';

import {run} from './common';

(async () => {
  const gens = new Generations(Dex as any);
  const argv = minimist(process.argv.slice(2), {default: {maxFailures: 5, cycles: 10}});
  const unit = typeof argv.duration === 'string' ? argv.duration[argv.duration.length - 1] : undefined;
  const duration =
    unit ? +argv.duration.slice(0, -1) * {s: 1e3, m: 6e4, h: 3.6e6}[unit]! : argv.duration;
  const seed = argv.seed ? argv.seed.split(',').map((s: string) => Number(s)) : null;
  await run(gens, {prng: new PRNG(seed), log: process.stdout.isTTY, ...argv, duration});
})().catch(err => {
  console.error(err);
  process.exit(1);
});
