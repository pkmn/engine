import 'source-map-support/register';

import {execFileSync} from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import {Generation, Generations, ID, PokemonSet, StatsTable} from '@pkmn/data';
import {Battle, Dex, PRNG, PRNGSeed, Pokemon, Side, SideID, Teams} from '@pkmn/sim';
import minimist from 'minimist';

import * as engine from '../pkg';

import {newSeed, toBigInt} from './integration';
import {Choices, formatFor, patch} from './showdown';
import {decimal, regression, summarize} from './stats';

const BLOCKLIST = ['mimic', 'metronome', 'mirrormove', 'transform'] as ID[];
const ROOT = path.resolve(__dirname, '..', '..');

const serialize = (seed: PRNGSeed) => toBigInt(seed).toString();
const sh = (cmd: string, args: string[]) => execFileSync(cmd, args, {encoding: 'utf8'});

export const Options = new class {
  get(this: void, gen: Generation, prng: PRNG): engine.CreateOptions {
    return {
      seed: newSeed(prng),
      p1: Options.player(gen, prng),
      p2: Options.player(gen, prng),
      showdown: true,
      log: false,
    };
  }

  player(gen: Generation, prng: PRNG): Omit<engine.PlayerOptions, 'name'> {
    switch (gen.num) {
      case 1: return Options.gen1(gen, prng);
      case 2: return Options.gen2(gen, prng);
      default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }

  gen1(this: void, gen: Generation, prng: PRNG): Omit<engine.PlayerOptions, 'name'> {
    const lookup = engine.Lookup.get(gen);

    const team: Partial<PokemonSet>[] = [];
    const n = prng.randomChance(1, 100) ? prng.next(1, 5 + 1) : 6;
    for (let i = 0; i < n; i++) {
      const species = lookup.speciesByNum(prng.next(1, 151 + 1));
      const level = prng.randomChance(1, 20) ? prng.next(1, 99 + 1) : 100;

      const ivs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'hp' || stat === 'spd') continue;
        ivs[stat] = gen.stats.toIV(prng.randomChance(1, 5) ? prng.next(1, 15 + 1) : 15);
      }
      ivs.hp = gen.stats.toIV(gen.stats.getHPDV(ivs));
      ivs.spd = ivs.spa;

      const evs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'spd') break;
        const exp = prng.randomChance(1, 20) ? prng.next(0, 0xFFFF + 1) : 0xFFFF;
        evs[stat] = Math.min(255, Math.trunc(Math.ceil(Math.sqrt(exp))));
      }
      evs.spd = evs.spa;

      const moves: ID[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move: ID;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 164 + 1)))) ||
          BLOCKLIST.includes(move));
        moves.push(move);
      }

      team.push({species, level, ivs, evs, moves});
    }

    return {team};
  }

  gen2(gen: Generation, prng: PRNG): Omit<engine.PlayerOptions, 'name'> {
    const lookup = engine.Lookup.get(gen);

    const team: Partial<PokemonSet>[] = [];
    const n = prng.randomChance(1, 100) ? prng.next(1, 5 + 1) : 6;
    for (let i = 0; i < n; i++) {
      const species = lookup.speciesByNum(prng.next(1, 251 + 1));
      const level = prng.randomChance(1, 20) ? prng.next(1, 99 + 1) : 100;
      const item = prng.randomChance(1, 10) ? undefined
        : lookup.itemByNum(prng.next(1, 62 + 1));

      const ivs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'hp' || stat === 'spd') continue;
        ivs[stat] = gen.stats.toIV(prng.randomChance(1, 5) ? prng.next(1, 15 + 1) : 15);
      }
      ivs.hp = gen.stats.toIV(gen.stats.getHPDV(ivs));
      ivs.spd = ivs.spa;

      const evs = {} as StatsTable;
      for (const stat of gen.stats) {
        const exp = prng.randomChance(1, 20) ? prng.next(0, 0xFFFF + 1) : 0xFFFF;
        evs[stat] = Math.min(255, Math.trunc(Math.ceil(Math.sqrt(exp))));
      }

      const moves: ID[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move: ID;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 250 + 1)))));
        moves.push(move);
      }

      const happiness = prng.randomChance(1, 10 + 1) ? prng.next(0, 255) : 255;
      team.push({species, level, item, ivs, evs, moves, happiness});
    }

    return {team};
  }
};

interface Configuration {
  warmup?: boolean;
  run(gen: Generation, format: ID, prng: PRNG, battles: number):
  Promise<readonly [bigint, number, string]>;
}

class DirectBattle extends Battle {
  // Drop logs to minimize overhead
  override hint(hint: string, once?: boolean, side?: Side) { }
  override addSplit(side: SideID, secret: any[], shared?: any[]) { }
  override add(...parts: (any | (() => {side: SideID; secret: string; shared: string}))[]) { }
  override addMove(...args: any[]) { }
  override retargetLastMove(newTarget: Pokemon) { }

  // Override to avoid wasted |update| and |end| work
  override sendUpdates() {
    this.sentLogPos = this.log.length;
    if (!this.sentEnd && this.ended) {
      this.sentEnd = true;
    }
  }

  // Override to not call Side#emitRequest to avoid wasted |sideupdate| work
  override makeRequest(type?: 'teampreview' | 'move' | 'switch' | '') {
    if (type) {
      this.requestState = type;
      for (const side of this.sides) {
        side.clearChoice();
      }
    } else {
      type = this.requestState;
    }

    for (const side of this.sides) {
      side.activeRequest = null;
    }

    if (type === 'teampreview') {
      const pickedTeamSize = this.ruleTable.pickedTeamSize;
      this.add('teampreview' + (pickedTeamSize ? '|' + pickedTeamSize : ''));
    }

    const requests = this.getRequests(type);
    for (let i = 0; i < this.sides.length; i++) {
      // NOTE: avoiding needlessly stringify-ing the |sideupdate|
      this.sides[i].activeRequest = requests[i];
    }

    if (this.sides.every(side => side.isChoiceDone())) {
      throw new Error('Choices are done immediately after a request');
    }
  }
}

const CONFIGURATIONS: {[name: string]: Configuration} = {
  'DirectBattle': {
    warmup: true,
    run(gen, format, prng, battles) {
      const choices = Choices.get(gen);

      let duration = 0n;
      let turns = 0;

      for (let i = 0; i < battles; i++) {
        const options = Options.get(gen, prng);
        const config = {formatid: format as any, seed: options.seed as PRNGSeed};
        const battle = new DirectBattle(config);
        patch.battle(battle);

        const p1 = new PRNG(newSeed(prng));
        const p2 = new PRNG(newSeed(prng));

        // NOTE: We must clone the team as PS mutates it which will cause drift
        const team1 = Teams.unpack(Teams.pack(options.p1.team as PokemonSet[]));
        const team2 = Teams.unpack(Teams.pack(options.p2.team as PokemonSet[]));

        battle.setPlayer('p1', {name: 'Player A', team: team1});
        const begin = process.hrtime.bigint();
        try {
          battle.setPlayer('p2', {name: 'Player B', team: team2});
          while (!battle.ended) {
            let possible = choices(battle, 'p1');
            const c1 = possible[p1.next(possible.length)];
            possible = choices(battle, 'p2');
            const c2 = possible[p2.next(possible.length)];
            battle.makeChoices(c1, c2);
          }
          turns += battle.turn;
        } finally {
          duration += process.hrtime.bigint() - begin;
        }
      }

      return Promise.resolve([duration, turns, serialize(prng.seed)] as const);
    },
  },
  '@pkmn/engine': {
    warmup: true,
    run(gen, _, prng, battles) {
      let duration = 0n;
      let turns = 0;

      for (let i = 0; i < battles; i++) {
        const options = Options.get(gen, prng);
        const battle = engine.Battle.create(gen, options);

        // The function passed to choose should usually account for the
        // possibility of zero options being returned in Generation I (otherwise
        // it will try to 'pass' when it can't pass which will crash), however,
        // since this code only runs in Pokémon Showdown compatibility mode we
        // can avoid handling that (and save a branch) as it doesn't implement
        // the softlock
        let p = new PRNG(newSeed(prng));
        const p1 = p.next.bind(p);
        p = new PRNG(newSeed(prng));
        const p2 = p.next.bind(p);

        let c1 = engine.Choice.pass();
        let c2 = engine.Choice.pass();

        let result: engine.Result;
        const begin = process.hrtime.bigint();
        try {
          while (!(result = battle.update(c1, c2)).type) {
            c1 = battle.choose('p1', result, p1);
            c2 = battle.choose('p2', result, p2);
          }
          turns += battle.turn;
        } finally {
          duration += process.hrtime.bigint() - begin;
        }
      }

      return Promise.resolve([duration, turns, serialize(prng.seed)] as const);
    },
  },
  'libpkmn': {
    run(_, format, prng, battles) {
      const [duration, turn, seed] = libpkmn(format, prng, battles);
      return Promise.resolve([duration, turn, seed]);
    },
  },
};

const libpkmn = (format: ID, prng: PRNG, battles: number, showdown = true) => {
  const warmup = Math.min(1000, Math.max(Math.floor(battles / 10), 1));
  const exe = path.resolve(ROOT, 'build', 'bin', `benchmark${showdown ? '-showdown' : ''}`);
  const stdout = sh(exe, [format[3], `${warmup}/${battles}`, serialize(prng.seed)]);
  const [duration, turn, seed] = stdout.split(',');
  return [BigInt(duration), Number(turn), seed.trim()] as const;
};

const NAMES = ['RBY', 'GSC', 'ADV', 'DPP', 'BW', 'XY', 'SM', 'SS', 'SV'];
const generationName = (format: ID, showdown?: boolean) => {
  const tags = showdown ? ['showdown'] : [];
  if (format.includes('doubles')) tags.push('doubles');
  return `${NAMES[+format[3] - 1]}${tags.length ? ` (${tags.join(', ')})` : ''}`;
};

const compare = (
  name: string, control: {turns: number; seed: string}, turns: number, seed: string
) => {
  if (!control.seed) {
    control.turns = turns;
    control.seed = seed;
  } else if (turns !== control.turns) {
    throw new Error(`Expected ${control.turns} turns and received ${turns} (${name})`);
  } else if (seed !== control.seed) {
    throw new Error(`Expected a final seed of ${control.seed} but received ${seed} (${name})`);
  }
};

export const iterations = (gens: Generations, num: number, battles: number, seed: number[]) => {
  const data: {[name: string]: number[]} = {};

  for (const showdown of [true, false]) {
    sh('zig', ['build', `-Dshowdown=${showdown.toString()}`, 'tools', '-p', 'build']);
    for (const gen of gens) {
      if (gen.num > 1) break;
      patch.generation(gen);
      const format = formatFor(gen);

      const name = generationName(format, showdown);
      const control = {turns: 0, seed: ''};
      const samples = new Array(num);
      for (let i = 0; i < num; i++) {
        const prng = new PRNG(seed.slice() as PRNGSeed);
        const [duration, turns, final] = libpkmn(format, prng, battles, showdown);
        samples[i] = Math.round(1e9 / (Number(duration) / battles));
        compare(name, control, turns, final);
      }

      data[name] = samples;
    }
  }

  return data;
};

const parse = (file: string) => {
  const data: {[name: string]: number[]} = {};
  const lines = fs.readFileSync(file, 'utf8').trim().split('\n');
  for (const line of lines) {
    const [name, s] = line.split('\t');
    data[name] = s.split(',').map(Number);
  }
  return data;
};

export const comparison = async (gens: Generations, battles: number, seed: number[]) => {
  const results: {[format: string]: {[config: string]: bigint}} = {};
  sh('zig', ['build', '-Dshowdown=true', 'tools', '-p', 'build']);

  for (const gen of gens) {
    if (gen.num > 1) break;
    patch.generation(gen);
    const format = formatFor(gen);

    const name = generationName(format);
    results[name] = {};
    const control = {turns: 0, seed: ''};

    const warmup = Math.min(1000, Math.max(Math.floor(battles / 10), 1));
    for (const config in CONFIGURATIONS) {
      const code = CONFIGURATIONS[config];

      if (code.warmup) {
        // Must use a different PRNG than the one used for the actual test
        const prng = new PRNG(seed.slice() as PRNGSeed);
        // We ignore the result - only the data from the actual test matters
        await code.run(gen, format, prng, warmup);
        // @ts-ignore
        if (global.gc) global.gc();
      }

      const prng = new PRNG(seed.slice() as PRNGSeed);
      const [duration, turns, final] = await code.run(gen, format, prng, battles);
      compare(config, control, turns, final);
      results[name][config] = duration;
    }
  }

  return results;
};

const pretty = (ns: bigint) => {
  if (ns < 1000) return `${decimal(Number(ns))} ns`;
  if (ns < 1_000_000n) return `${decimal(Number(ns) / 1e3)} μs`;
  if (ns < 1_000_000_000n) return `${decimal(Number(ns) / 1e6)} ms`;
  return `${decimal(Number(ns) / 1e9, 60)} s`;
};

if (require.main === module) {
  (async () => {
    const gens = new Generations(Dex as any);
    const argv = minimist(process.argv.slice(2), {default: {battles: 10000}});
    const seed = argv.seed ? argv.seed.split(',').map((s: string) => Number(s)) : [1, 2, 3, 4];
    const previous = argv._.length ? parse(argv._[0]) : undefined;

    if (argv._.length > 1) {
      throw new Error(`Expected at most one file argument, got: ${argv._.join(' ')}`);
    } else if (argv.summary && !['text', 'json'].includes(argv.summary)) {
      throw new Error(`Expected 'text' or 'json' summary format, not '${argv.summary}'`);
    } else if (argv.iterations && argv.summary && previous) {
      throw new Error('Combination of ---iterations, --summary, and a file is illegal');
    } else if (previous && !(argv.iterations || argv.summary)) {
      throw new Error('Expected either --iterations or --summary with a file');
    }

    const summary = (data: {[name: string]: number[]}) => {
      const summaries = Object.entries(data).map(([k, v]) => summarize(k, v, argv.summary));
      if (argv.summary === 'json') {
        console.log(JSON.stringify(summaries, null, 2));
      } else {
        for (const {name, unit, value, range, extra} of summaries) {
          const r = range.startsWith('±') ? ` ± ${range.slice(1)}` : '';
          console.log(`${name}: ${value}${r} ${unit} ${extra}`);
        }
      }
    };

    if (argv.iterations) {
      const data = iterations(gens, argv.iterations, argv.battles, seed);
      if (argv.summary) {
        summary(data);
      } else if (previous) {
        const prng = new PRNG(seed);
        regression(previous, data, (min, max) => prng.next(min, max));
      } else {
        for (const [name, samples] of Object.entries(data)) {
          console.log(`${name}\t${samples.join(',')}`);
        }
      }
    } else if (previous) {
      summary(previous);
    } else {
      const results = await comparison(gens, argv.battles, seed);

      const display = (durations: {[config: string]: bigint}) => {
        const out = {} as {[config: string]: string};
        const min = Object.values(durations).reduce((m, e) => e < m ? e : m);
        for (const config in durations) {
          out[config] = pretty(durations[config]);
          if (durations[config] !== min) {
            out[config] += ` (${decimal(Number(durations[config] * 1000n / min) / 1000)}×)`;
          }
        }
        return out;
      };

      let configs: string[] | undefined = undefined;
      for (const name in results) {
        if (!configs) {
          // TODO: use table from stats.ts
          configs = Object.keys(results[name]).reverse();
          console.log(`|Generation|\`${configs.join('`|`')}\`|`);
          console.log(`|-|${'-|'.repeat(configs.length)}`);
        }
        const processed = display(results[name]);
        console.log(`|**${name}**|${configs.map(c => processed[c]).join('|')}|`);
      }
    }
  })().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
