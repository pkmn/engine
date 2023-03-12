import 'source-map-support/register';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import minimist from 'minimist';

import {comparison, iterations} from './common';

(async () => {
  const gens = new Generations(Dex as any);
  const argv = minimist(process.argv.slice(2), {default: {battles: 10000}});
  const seed = argv.seed ? argv.seed.split(',').map((s: string) => Number(s)) : [1, 2, 3, 4];
  if (argv.iterations) {
    const entries = iterations(gens, argv.iterations, argv.battles, seed, argv.text);
    if (argv.text) {
      for (const {name, unit, value, range, extra} of entries) {
        console.log(`${name}: ${value} ± ${range.slice(1)} ${unit} ${extra}`);
      }
    } else {
      console.log(JSON.stringify(entries, null, 2));
    }
  } else {
    const stats = await comparison(gens, argv.battles, seed);

    const display = (durations: {[config: string]: number}) => {
      const out = {} as {[config: string]: string};
      const min = Math.min(...Object.values(durations));
      for (const config in durations) {
        out[config] = `${(durations[config] / 1000).toFixed(2)}s`;
        if (durations[config] !== min) out[config] += ` (${(durations[config] / min).toFixed(2)}×)`;
      }
      return out;
    };

    let configs: string[] | undefined = undefined;
    for (const name in stats) {
      if (!configs) {
        configs = Object.keys(stats[name]).reverse();
        console.log(`|Generation|\`${configs.join('`|`')}\`|`);
      }
      const processed = display(stats[name]);
      console.log(`|${name}|${configs.map(c => processed[c]).join('|')}|`);
    }
  }
})().catch(err => {
  console.error(err);
  process.exit(1);
});
