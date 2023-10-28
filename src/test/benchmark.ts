import 'source-map-support/register';

import {execFileSync} from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import {Generation, Generations, ID, PokemonSet, StatsTable} from '@pkmn/data';
import {Battle, Dex, PRNG, PRNGSeed, Pokemon, Side, SideID, Teams} from '@pkmn/sim';
import minimist from 'minimist';
import {table} from 'table';
import {Stats} from 'trakr';

import * as engine from '../pkg';

import {newSeed, toBigInt} from './integration';
import {Choices, formatFor, patch} from './showdown';

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
  override add(...parts: (any | (() => { side: SideID; secret: string; shared: string }))[]) { }
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

const compare =
    (name: string, control: {turns: number; seed: string}, turns: number, seed: string) => {
      if (!control.seed) {
        control.turns = turns;
        control.seed = seed;
      } else if (turns !== control.turns) {
        throw new Error(`Expected ${control.turns} turns and received ${turns} (${name})`);
      } else if (seed !== control.seed) {
        throw new Error(`Expected a final seed of ${control.seed} but received ${seed} (${name})`);
      }
    };

// Separate outliers from clean samples using MAD outlier detection with what is
// approximately a three-sigma cutoff (corresponding to roughly ~99.7% of values
// assuming the data is normally distributed), as out forth in "Detecting
// outliers: Do not use standard deviation around the mean, use absolute
// deviation around the median" - C. Leys et al
const clean = (samples: number[], n = 3) => {
  const stats = Stats.compute(samples);
  const deviations = samples.map(s => Math.abs(s - stats.p50));
  const mad = Stats.median(deviations);
  const b = n * 1.4826;
  const cleaned: number[] = [];
  const outliers: number[] = [];
  for (let i = 0; i < samples.length; i++) {
    (deviations[i] / mad > b ? outliers : cleaned).push(samples[i]);
  }
  return [cleaned, outliers];
};

export const iterations = (gens: Generations, num: number, battles: number, seed: number[]) => {
  const data: {[name: string]: number[]} = {};

  for (const showdown of [true, false]) {
    sh('zig', ['build', '-j1', `-Dshowdown=${showdown.toString()}`, 'tools', '-p', 'build']);
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

const summarize = (name: string, samples: number[], summary: 'text' | 'json') => {
  const [cleaned, outliers] = clean(samples);
  const stats = Stats.compute(cleaned);
  let extra = `[${stats.min} .. ${stats.max}]`;
  if (outliers.length) {
    extra += summary === 'text'
      ? ` (${outliers.length})`
      : ` (dropped: ${outliers.sort().join(', ')})`;
  }

  return {
    name,
    unit: 'battles/sec',
    value: Math.round(stats.avg),
    range: isNaN(stats.rme) ? 'N/A' : `±${stats.rme.toFixed(2)}%`,
    extra,
  };
};

// Critical Mann-Whitney U-values for 95% confidence.
// For more info see http://www.saburchill.com/IBbiology/stats/003.html.
/* eslint-disable */
const TABLE = [
  [0, 1, 2],
  [1, 2, 3, 5],
  [1, 3, 5, 6, 8],
  [2, 4, 6, 8, 10, 13],
  [2, 4, 7, 10, 12, 15, 17],
  [3, 5, 8, 11, 14, 17, 20, 23],
  [3, 6, 9, 13, 16, 19, 23, 26, 30],
  [4, 7, 11, 14, 18, 22, 26, 29, 33, 37],
  [4, 8, 12, 16, 20, 24, 28, 33, 37, 41, 45],
  [5, 9, 13, 17, 22, 26, 31, 36, 40, 45, 50, 55],
  [5, 10, 14, 19, 24, 29, 34, 39, 44, 49, 54, 59, 64],
  [6, 11, 15, 21, 26, 31, 37, 42, 47, 53, 59, 64, 70, 75],
  [6, 11, 17, 22, 28, 34, 39, 45, 51, 57, 63, 67, 75, 81, 87],
  [7, 12, 18, 24, 30, 36, 42, 48, 55, 61, 67, 74, 80, 86, 93, 99],
  [7, 13, 19, 25, 32, 38, 45, 52, 58, 65, 72, 78, 85, 92, 99, 106, 113],
  [8, 14, 20, 27, 34, 41, 48, 55, 62, 69, 76, 83, 90, 98, 105, 112, 119, 127],
  [8, 15, 22, 29, 36, 43, 50, 58, 65, 73, 80, 88, 96, 103, 111, 119, 126, 134, 142],
  [9, 16, 23, 30, 38, 45, 53, 61, 69, 77, 85, 93, 101, 109, 117, 125, 133, 141, 150, 158],
  [9, 17, 24, 32, 40, 48, 56, 64, 73, 81, 89, 98, 106, 115, 123, 132, 140, 149, 157, 166, 175],
  [10, 17, 25, 33, 42, 50, 59, 67, 76, 85, 94, 102, 111, 120, 129, 138, 147, 156, 165, 174, 183, 192],
  [10, 18, 27, 35, 44, 53, 62, 71, 80, 89, 98, 107, 117, 126, 135, 145, 154, 163, 173, 182, 192, 201, 211],
  [11, 19, 28, 37, 46, 55, 64, 74, 83, 93, 102, 112, 122, 132, 141, 151, 161, 171, 181, 191, 200, 210, 220, 230],
  [11, 20, 29, 38, 48, 57, 67, 77, 87, 97, 107, 118, 125, 138, 147, 158, 168, 178, 188, 199, 209, 219, 230, 240, 250],
  [12, 21, 30, 40, 50, 60, 70, 80, 90, 101, 111, 122, 132, 143, 154, 164, 175, 186, 196, 207, 218, 228, 239, 250, 261, 272],
  [13, 22, 32, 42, 52, 62, 73, 83, 94, 105, 116, 127, 138, 149, 160, 171, 182, 193, 204, 215, 226, 238, 249, 260, 271, 282, 294],
  [13, 23, 33, 43, 54, 65, 76, 87, 98, 109, 120, 131, 143, 154, 166, 177, 189, 200, 212, 223, 235, 247, 258, 270, 282, 293, 305, 317],
];
/* eslint-enable */

const utest = (control: number[], test: number[]) => {
  if (control === test) return 0;

  const cc = control.length;
  const ct = test.length;
  const max = Math.max(cc, ct);
  const min = Math.min(cc, ct);

  const score = (x: number, ys: number[]) =>
    ys.reduce((sum, y) => sum + (y > x ? 0 : y < x ? 1 : 0.5), 0);
  const U = (xs: number[], ys: number[]) =>
    xs.reduce((sum, x) => sum + score(x, ys), 0);
  const uc = U(control, test);
  const ut = U(test, control);
  const u = Math.min(uc, ut);

  // Reject the null hypothesis the two samples come from the
  // same population (i.e. have the same median) if...
  if (cc + ct > 30) {
    // ...the z-stat is greater than 1.96 or less than -1.96
    // http://www.statisticslectures.com/topics/mannwhitneyu/
    const Z = (v: number) =>
      (v - ((cc * ct) / 2)) / Math.sqrt((cc * ct * (cc + ct + 1)) / 12);
    return Math.abs(Z(u)) > 1.96 ? (u === uc ? 1 : -1) : 0;
  }
  // ...the U value is less than or equal the critical U value.
  const critical = max < 5 || min < 3 ? 0 : TABLE[max - 5][min - 3];
  return u <= critical ? (u === uc ? 1 : -1) : 0;
};

// Percentile bootstrap confidence interval
const bootstrap = (
  control: number[], test: number[],
  random?: (min: number, max: number) => number
) => {
  const N = 1000;
  const d50 = new Array(N);
  const d90 = new Array(N);
  const d95 = new Array(N);
  const d99 = new Array(N);

  if (!random) {
    random = (min: number, max: number) => {
      min = Math.ceil(min);
      max = Math.floor(max);
      return Math.floor(Math.random() * (max - min)) + min;
    };
  }

  const sample = (arr: number[], n: number) => {
    const sampled = [];
    const length = arr.length;
    for (let i = 0; i < n; i++) {
      sampled.push(arr[random!(0, length)]);
    }
    return sampled;
  };

  const percentiles = (arr: number[]) => {
    arr.sort((a, b) => a - b);
    return {
      p50: Stats.ptile(arr, 0.50),
      p90: Stats.ptile(arr, 0.90),
      p95: Stats.ptile(arr, 0.95),
      p99: Stats.ptile(arr, 0.99),
    };
  };

  const cc = Math.floor(control.length / 3);
  const ct = Math.floor(test.length / 3);
  for (let i = 0; i < N; i++) {
    const qc = percentiles(sample(control, cc));
    const qt = percentiles(sample(test, ct));

    d50[i] = qc.p50 - qt.p50;
    d90[i] = qc.p90 - qt.p90;
    d95[i] = qc.p95 - qt.p95;
    d99[i] = qc.p99 - qt.p99;
  }

  const md50 = Stats.mean(d50);
  const md90 = Stats.mean(d90);
  const md95 = Stats.mean(d95);
  const md99 = Stats.mean(d99);

  const ci = (d: number[], m: number) =>
    1.96 * Stats.standardDeviation(d, false, m);

  return {
    d50: md50,
    d90: md90,
    d95: md95,
    d99: md99,
    ci50: ci(d50, md50),
    ci90: ci(d90, md90),
    ci95: ci(d95, md95),
    ci99: ci(d99, md99),
  };
};

const GFM = {
  border: {
    bodyLeft: '|',
    bodyRight: '|',
    bodyJoin: '|',

    joinBody: '-',
    joinLeft: '|',
    joinRight: '|',
    joinJoin: '|',
  },
  drawHorizontalLine: (index: number) => index === 1,
};

const toTable = (header: string[], data: string[][], md?: boolean, maxWidth = 20) => {
  if (md) return table([header.map(s => `${BOLD}${s}${RESET}`), ...data], GFM);

  const maxes = (new Array(header.length)).fill(-Infinity);
  const combined: string[][] = [header, ...data];
  for (const row of combined) {
    for (let i = 0; i < row.length; i++) {
      // const len = Stats.max(row[i].split(' ').map(c => c.length));
      const len = unescape(row[i]).length;
      if (len > maxes[i]) maxes[i] = len;
    }
  }

  return table([header.map(s => `${BOLD}${s}${RESET}`), ...data], {
    columns: maxes.map(max => ({
      wrapWord: true,
      width: Math.min(max, maxWidth),
    })),
  });
};

const pretty = (ns: number | bigint) => {
  if (ns < 1000) return `${dec(Number(ns))} ns`;
  if (ns < 1_000_000n) return `${dec(Number(ns) / 1e3)} μs`;
  if (ns < 1_000_000_000n) return `${dec(Number(ns) / 1e6)} ms`;
  return `${dec(Number(ns) / 1e9, 60)} s`;
};

const dec = (n: number, c = 100) => {
  if (n < 1) return n.toFixed(3);
  if (n < 10) return n.toFixed(2);
  if (n < c) return n.toFixed(1);
  return n.toFixed();
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

const percent = (n: number, d: number) => `${(n * 100 / d).toFixed(2)}%`;

const diff = (num: number, ci: number, percentile: number, md?: boolean) => {
  const diffp = percent(num, percentile);
  const cip = percent(ci, percentile);
  return color(num, ci, md)(`${diffp} ± ${cip}`);
};

const color = (num: number, ci: number, md?: boolean) => {
  const red = (s: string) => md ? s : `${RED}${s}${RESET}`;
  const green = (s: string) => md ? s : `${GREEN}${s}${RESET}`;
  // const gray = (s: string) => md ? `*${s}*` : `${DIM}${s}${RESET}`;
  const none = (s: string) => s;
  return ((num - ci < 0 && num + ci < 0)
    ? green
    : (num - ci > 0 && num + ci > 0) ? red : none);
};

// eslint-disable-next-line
const ESCAPE = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g;
const unescape = (s: string) => s.replaceAll(ESCAPE, '');

const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const BOLD = '\x1b[1m';
const RESET = '\x1b[0m';

const regression = (
  before: {[name: string]: number[]},
  after: {[name: string]: number[]},
  prng: PRNG
) => {
  if (Object.keys(before).length !== Object.keys(after).length) {
    throw new Error('Can\'t compare two incompatible samples');
  }

  const print = (when: string, result: -1 | 0 | 1, summary: ReturnType<typeof summarize>) => {
    const {range, value, unit, extra} = summary;
    const r = range.startsWith('±') ? ` ± ${range.slice(1)}` : '';
    const [b, e] = result === 0 ? ['', ''] : [result < 0
      ? (when === 'After' ? RED : GREEN)
      : (when === 'After' ? GREEN : RED),
    RESET];
    console.log(`${BOLD}${when}${RESET}: ${b}${value}${r} ${unit}${e} ${extra}`);
  };

  const display = (control: number[], test: number[]) => {
    const c = Stats.compute(control);
    const t = Stats.compute(test);

    const result = bootstrap(control, test, (min, max) => prng.next(min, max));
    console.log(toTable(
      ['d50', 'd90', 'd95', 'd99'], [[
        diff(result.d50, result.ci50, c.p50, false),
        diff(result.d90, result.ci90, c.p90, false),
        diff(result.d95, result.ci95, c.p95, false),
        diff(result.d99, result.ci99, c.p99, false),
      ]],
      false
    ));
  };

  console.log();
  for (const name in before) {
    // TODO: consider outlier removal before testing for signficance?
    if (!after[name] || before[name].length !== after[name].length) {
      throw new Error(`Can't compare two incompatible samples for '${name}'`);
    }

    console.log(`${BOLD}${name}\n${'-'.repeat(name.length)}${RESET}\n`);
    const result = utest(before[name], after[name]);
    print('Before', result, summarize(name, before[name], 'text'));
    print('After', result, summarize(name, after[name], 'text'));

    console.log();
    display(before[name], after[name]);
  }
};

export const comparison = async (gens: Generations, battles: number, seed: number[]) => {
  const stats: {[format: string]: {[config: string]: bigint}} = {};
  sh('zig', ['build', '-j1', '-Dshowdown=true', 'tools', '-p', 'build']);

  for (const gen of gens) {
    if (gen.num > 1) break;
    patch.generation(gen);
    const format = formatFor(gen);

    const name = generationName(format);
    stats[name] = {};
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
      stats[name][config] = duration;
    }
  }

  return stats;
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
        regression(previous, data, prng);
      } else {
        for (const [name, samples] of Object.entries(data)) {
          console.log(`${name}\t${samples.join(',')}`);
        }
      }
    } else if (previous) {
      summary(previous);
    } else {
      const stats = await comparison(gens, argv.battles, seed);

      const display = (durations: {[config: string]: bigint}) => {
        const out = {} as {[config: string]: string};
        const min = Object.values(durations).reduce((m, e) => e < m ? e : m);
        for (const config in durations) {
          out[config] = pretty(durations[config]);
          if (durations[config] !== min) {
            out[config] += ` (${dec(Number(durations[config] * 1000n / min) / 1000)}×)`;
          }
        }
        return out;
      };

      let configs: string[] | undefined = undefined;
      for (const name in stats) {
        if (!configs) {
          configs = Object.keys(stats[name]).reverse();
          console.log(`|Generation|\`${configs.join('`|`')}\`|`);
          console.log(`|-|${'-|'.repeat(configs.length)}`);
        }
        const processed = display(stats[name]);
        console.log(`|**${name}**|${configs.map(c => processed[c]).join('|')}|`);
      }
    }
  })().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
