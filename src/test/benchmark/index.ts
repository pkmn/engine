import 'source-map-support/register';

import {execFileSync} from 'child_process';

import {GenerationNum, Generations, PokemonSet} from '@pkmn/data';
import {
  Battle,
  BattleStreams,
  Dex,
  ID,
  PRNG,
  PRNGSeed,
  Pokemon,
  Side,
  SideID,
  Streams,
  Teams,
} from '@pkmn/sim';
import minimist from 'minimist';

import * as gen1 from './gen1';

const argv = minimist(process.argv.slice(2), {default: {battles: 100, playouts: 10}});
argv.seed = argv.seed
  ? argv.seed.split(',').map((s: string) => Number(s))
  : [1, 2, 3, 4];

const GENS = new Generations(Dex as any);

const FORMATS = [
  'gen1customgame',
  // 'gen2customgame',
  // 'gen3customgame', 'gen3doublescustomgame',
  // 'gen4customgame', 'gen4doublescustomgame',
  // 'gen5customgame', 'gen5doublescustomgame',
  // 'gen6customgame', 'gen6doublescustomgame',
  // 'gen7customgame', 'gen7doublescustomgame',
  // 'gen8customgame', 'gen8doublescustomgame',
] as ID[];

export const newSeed = (prng: PRNG) => [
  prng.next(0x10000),
  prng.next(0x10000),
  prng.next(0x10000),
  prng.next(0x10000),
] as PRNGSeed;

const toMillis = (duration: bigint) => Number(duration / BigInt(1e6));
const serialize = (seed: PRNGSeed) =>
  ((BigInt(seed[0]) << 48n) |
    (BigInt(seed[1]) << 32n) |
    (BigInt(seed[2]) << 16n) |
    BigInt(seed[3])).toString();

interface Configuration {
  warmup?: boolean;
  run(format: ID, prng: PRNG, battles: number, playouts: number):
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
      // NOTE: avoiding needlessly stringifying the |sideupdate|
      this.sides[i].activeRequest = requests[i];
    }

    if (this.sides.every(side => side.isChoiceDone())) {
      throw new Error('Choices are done immediately after a request');
    }
  }
}

const CONFIGURATIONS: {[name: string]: Configuration} = {
  // 'pokemon-showdown': {
  // run(format, prng, battles, playouts) {
  // // TODO
  // },
  // },
  'BattleStream': {
    warmup: true,
    async run(format, prng, battles, playouts) {
      const gen = GENS.get(+format[3] as GenerationNum);
      const newAI = (
        playerStream: Streams.ObjectReadWriteStream<string>,
        battleStream: BattleStreams.BattleStream,
        id: SideID,
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
        for (let j = 0; j < playouts; j++) {
          const battleStream = new BattleStreams.BattleStream();
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
            if (!battle.ended) throw new Error(`Unfinished ${format} battle ${i} + ${j}`);
            turns += battle.turn;
          } finally {
            duration += process.hrtime.bigint() - begin;
          }
        }
      }

      return [toMillis(duration), turns, serialize(prng.seed)] as const;
    },
  },
  'DirectBattle': {
    warmup: true,
    run(format, prng, battles, playouts) {
      const gen = GENS.get(+format[3] as GenerationNum);

      let choices: (battle: Battle, id: SideID) => string[];
      switch (gen.num) {
      case 1: choices = gen1.Choices.sim; break;
      default: throw new Error(`Unsupported gen: ${gen.num}`);
      }

      const choose = (battle: Battle, id: SideID, rand: PRNG) => {
        const options = choices(battle, id);
        const choice = options[rand.next(options.length)];
        if (choice) battle.choose(id, choice);
      };

      let duration = 0n;
      let turns = 0;

      for (let i = 0; i < battles; i++) {
        const options = gen1.Battle.options(gen, prng);
        for (let j = 0; j < playouts; j++) {
          const config = {formatid: format, seed: options.seed as PRNGSeed};
          const battle = new Battle(config);

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
      }

      return Promise.resolve([toMillis(duration), turns, serialize(prng.seed)] as const);
    },
  },
  // '@pkmn/engine': {
  // warmup: true,
  // run() {
  // return [0, 0, 'TODO'];
  // },
  // },
  // 'libpkmn': {
  // run(format, prng, battles, playouts) {
  // const stdout = execFileSync('zig', [
  // 'build', '-Dshowdown=true', 'benchmark', '--',
  // format[3], // TODO: support doubles
  // battles.toString(),
  // serialize(prng.seed),
  // playouts.toString(),
  // ], {encoding: 'utf8'});

  // const [duration, turn, seed] = stdout.split(',');
  // return Promise.resolve([toMillis(BigInt(duration)), Number(turn), seed.trim()]);
  // },
  // },
};

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
        await config.run(format, prng, Math.max(Math.floor(argv.battles / 10), 1), argv.playouts);
        // @ts-ignore
        if (global.gc) global.gc();
      }

      const prng = new PRNG(argv.seed.slice());
      const [duration, turns, seed] = await config.run(format, prng, argv.battles, argv.playouts);
      if (!control.seed) {
        control.turns = turns;
        control.seed = seed;
      } else if (turns !== control.turns) {
        throw new Error(`Expected ${control.turns} turns and received ${turns}`);
      } else if (seed !== control.seed) {
        throw new Error(`Expected a final seed of ${control.seed} but received ${seed}`);
      }

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

  const NAMES = ['RBY', 'GSC', 'ADV', 'DPP', 'BW', 'XY', 'SM', 'SS'];
  const configs = Object.keys(CONFIGURATIONS).reverse();
  console.log(`|Generation|\`${configs.join('`|`')}\`|`);
  for (const format of FORMATS) {
    const name = format.includes('doubles')
      ? `${NAMES[+format[3] - 1]} (doubles)`
      : NAMES[+format[3] - 1];
    const processed = display(stats[format]);
    console.log(`|${name}|${configs.map(c => processed[c]).join('|')}|`);
  }
})();
