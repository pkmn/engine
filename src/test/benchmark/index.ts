import 'source-map-support/register';

import {execFileSync} from 'child_process';

import {Generations, PokemonSet} from '@pkmn/data';
import {
  Battle, BattleStreams, Dex, ID, PRNG, PRNGSeed, Pokemon, Side, SideID, Streams, Teams,
} from '@pkmn/sim';
import minimist from 'minimist';
import {Stats} from 'trakr';

import {PatchedBattleStream, patch} from '../showdown/common';
import {newSeed} from './common';

import * as engine from '../../pkg';
import * as gen1 from './gen1';

const argv = minimist(process.argv.slice(2), {default: {battles: 10000}});
argv.seed = argv.seed
  ? argv.seed.split(',').map((s: string) => Number(s))
  : [1, 2, 3, 4];

const GENS = new Generations(Dex as any);
const FORMATS = ['gen1customgame'] as ID[];

const toMillis = (duration: bigint) => Number(duration / BigInt(1e6));
const serialize = (seed: PRNGSeed) =>
  ((BigInt(seed[0]) << 48n) |
    (BigInt(seed[1]) << 32n) |
    (BigInt(seed[2]) << 16n) |
    BigInt(seed[3])).toString();

interface Configuration {
  warmup?: boolean;
  run(format: ID, prng: PRNG, battles: number):
  Promise<readonly [number, number, string]>;
}

class DirectBattle extends Battle {
  // Drop logs to minimize overhead
  hint(hint: string, once?: boolean, side?: Side) { }
  addSplit(side: SideID, secret: any[], shared?: any[]) { }
  add(...parts: (any | (() => { side: SideID; secret: string; shared: string }))[]) { }
  addMove(...args: any[]) { }
  retargetLastMove(newTarget: Pokemon) { }

  // Override to avoid wasted |update| and |end| work
  sendUpdates() {
    this.sentLogPos = this.log.length;
    if (!this.sentEnd && this.ended) {
      this.sentEnd = true;
    }
  }

  // Override to not call Side#emitRequest to avoid wasted |sideupdate| work
  makeRequest(type?: 'teampreview' | 'move' | 'switch' | '') {
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
  'BattleStream': {
    warmup: true,
    async run(format, prng, battles) {
      const gen = GENS.get(format[3]);
      patch.generation(gen);

      const newAI = (
        playerStream: Streams.ObjectReadWriteStream<string>,
        battleStream: BattleStreams.BattleStream,
        id: engine.Player,
        rand: PRNG
      ): BattleStreams.BattlePlayer => {
        switch (gen.num) {
        case 1: return new gen1.RandomPlayerAI(playerStream, battleStream, id, rand);
        default: throw new Error(`Unsupported gen: ${gen.num}`);
        }
      };

      let duration = 0n;
      let turns = 0;

      for (let i = 0; i < battles; i++) {
        const options = gen1.Battle.options(gen, prng);
        const battleStream = new PatchedBattleStream();
        const streams = BattleStreams.getPlayerStreams(battleStream);

        const spec = {formatid: format, seed: options.seed as PRNGSeed};
        const p1spec = {name: 'Player A', team: Teams.pack(options.p1.team as PokemonSet[])};
        const p2spec = {name: 'Player B', team: Teams.pack(options.p2.team as PokemonSet[])};
        const start = `>start ${JSON.stringify(spec)}\n` +
          `>player p1 ${JSON.stringify(p1spec)}\n` +
          `>player p2 ${JSON.stringify(p2spec)}`;

        const p1 = newAI(streams.p1, battleStream, 'p1', new PRNG(newSeed(prng))).start();
        const p2 = newAI(streams.p2, battleStream, 'p2', new PRNG(newSeed(prng))).start();

        const begin = process.hrtime.bigint();
        try {
          await streams.omniscient.write(start);
          await streams.omniscient.readAll();
          await Promise.all([streams.omniscient.writeEnd(), p1, p2]);
          const battle = battleStream.battle!;
          if (!battle.ended) throw new Error(`Unfinished ${format} battle ${i}`);
          turns += battle.turn;
        } finally {
          duration += process.hrtime.bigint() - begin;
        }
      }

      return [toMillis(duration), turns, serialize(prng.seed)] as const;
    },
  },
  'DirectBattle': {
    warmup: true,
    run(format, prng, battles) {
      const gen = GENS.get(format[3]);
      patch.generation(gen);

      let choices: (battle: Battle, id: engine.Player) => string[];
      switch (gen.num) {
      case 1: choices = gen1.Choices.sim; break;
      default: throw new Error(`Unsupported gen: ${gen.num}`);
      }

      const choose = (battle: Battle, id: engine.Player, rand: PRNG) => {
        const options = choices(battle, id);
        const choice = options[rand.next(options.length)];
        if (choice) battle.choose(id, choice);
      };

      let duration = 0n;
      let turns = 0;

      for (let i = 0; i < battles; i++) {
        const options = gen1.Battle.options(gen, prng);
        const config = {formatid: format, seed: options.seed as PRNGSeed};
        const battle = new DirectBattle(config);
        patch.battle(battle);

        const p1 = new PRNG(newSeed(prng));
        const p2 = new PRNG(newSeed(prng));

        // NOTE: We must serialize the team as PS mutates it which will cause drift
        const team1 = Teams.pack(options.p1.team as PokemonSet[]);
        const team2 = Teams.pack(options.p2.team as PokemonSet[]);

        battle.setPlayer('p1', {name: 'Player A', team: team1});
        const begin = process.hrtime.bigint();
        try {
          battle.setPlayer('p2', {name: 'Player B', team: team2});
          while (!battle.ended) {
            choose(battle, 'p1', p1);
            choose(battle, 'p2', p2);
          }
          turns += battle.turn;
        } finally {
          duration += process.hrtime.bigint() - begin;
        }
      }

      return Promise.resolve([toMillis(duration), turns, serialize(prng.seed)] as const);
    },
  },
  '@pkmn/engine': {
    warmup: true,
    run(format, prng, battles) {
      const gen = GENS.get(format[3]);
      let duration = 0n;
      let turns = 0;

      for (let i = 0; i < battles; i++) {
        const options = gen1.Battle.options(gen, prng);
        const battle = engine.Battle.create(gen, options);

        const p1 = new PRNG(newSeed(prng));
        const p2 = new PRNG(newSeed(prng));

        let c1 = engine.Choice.pass();
        let c2 = engine.Choice.pass();

        const choose = (rand: PRNG, choices: engine.Choice[]) => choices[rand.next(choices.length)];

        let result: engine.Result;
        const begin = process.hrtime.bigint();
        try {
          while (!(result = battle.update(c1, c2)).type) {
            c1 = choose(p1, battle.choices('p1', result));
            c2 = choose(p2, battle.choices('p2', result));
          }
          turns += battle.turn;
        } finally {
          duration += process.hrtime.bigint() - begin;
        }
      }

      return Promise.resolve([toMillis(duration), turns, serialize(prng.seed)] as const);
    },
  },
  'libpkmn': {
    run(format, prng, battles) {
      const [duration, turn, seed] = libpkmn(format, prng, battles);
      return Promise.resolve([toMillis(duration), turn, seed]);
    },
  },
};

const libpkmn = (format: ID, prng: PRNG, battles: number, showdown = true) => {
  const warmup = Math.max(Math.floor(battles / 10));
  const stdout = execFileSync('zig', [
    'build', `-Dshowdown=${showdown.toString()}`, 'benchmark', '--',
    format[3], // TODO: support doubles
    `${warmup}/${battles}`,
    serialize(prng.seed),
  ], {encoding: 'utf8'});
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

// Separate outliers from clean samples using MAD outlier detection with what is approximately a
// three-sigma cutoff (corresponding to roughly ~99.7% of values assuming the data is normally
// distributed), as out forth in "Detecting outliers: Do not use standard deviation around the mean,
// use absolute deviation around the median" - C. Leys et al
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

if (argv.iterations) {
  const entries = [];
  for (const showdown of [true, false]) {
    for (const format of FORMATS) {
      const name = generationName(format, showdown);
      const control = {turns: 0, seed: ''};
      const samples = new Array(argv.iterations);
      for (let i = 0; i < argv.iterations; i++) {
        const prng = new PRNG(argv.seed.slice());
        const [duration, turns, seed] = libpkmn(format, prng, argv.battles, showdown);
        samples[i] = Math.round(1e9 / (Number(duration) / argv.battles));
        compare(name, control, turns, seed);
      }
      const [cleaned, outliers] = clean(samples);
      const stats = Stats.compute(cleaned);
      let extra = `[${stats.min} .. ${stats.max}]`;
      if (outliers.length) {
        extra += argv.text ? ` (${outliers.length})` : ` (dropped: ${outliers.sort().join(', ')})`;
      }
      entries.push({
        name,
        unit: 'battles/sec',
        value: Math.round(stats.avg),
        range: `±${stats.rme.toFixed(2)}%`,
        extra,
      });
    }
  }
  if (argv.text) {
    for (const {name, unit, value, range, extra} of entries) {
      console.log(`${name}: ${value} ± ${range.slice(1)} ${unit} ${extra}`);
    }
  } else {
    console.log(JSON.stringify(entries, null, 2));
  }
} else {
  (async () => {
    const stats: {[format: string]: {[config: string]: number}} = {};
    for (const format of FORMATS) {
      stats[format] = {};
      const control = {turns: 0, seed: ''};

      for (const name in CONFIGURATIONS) {
        const config = CONFIGURATIONS[name];

        if (config.warmup) {
          // Must use a different PRNG than the one used for the actual test
          const prng = new PRNG(argv.seed.slice());
          // We ignore the result - only the data from the actual test matters
          await config.run(format, prng, Math.max(Math.floor(argv.battles / 10), 1));
          // @ts-ignore
          if (global.gc) global.gc();
        }

        const prng = new PRNG(argv.seed.slice());
        const [duration, turns, seed] = await config.run(format, prng, argv.battles);
        compare(name, control, turns, seed);
        stats[format][name] = duration;
      }
    }

    const display = (durations: {[config: string]: number}) => {
      const out = {} as {[config: string]: string};
      const min = Math.min(...Object.values(durations));
      for (const config in durations) {
        out[config] = `${(durations[config] / 1000).toFixed(2)}s`;
        if (durations[config] !== min) out[config] += ` (${(durations[config] / min).toFixed(2)}×)`;
      }
      return out;
    };

    const configs = Object.keys(CONFIGURATIONS).reverse();
    console.log(`|Generation|\`${configs.join('`|`')}\`|`);
    for (const format of FORMATS) {
      const name = generationName(format);
      const processed = display(stats[format]);
      console.log(`|${name}|${configs.map(c => processed[c]).join('|')}|`);
    }
  })();
}
