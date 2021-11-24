import {Buffer} from 'buffer';
import {performance} from 'perf_hooks';

import {ID, BattleStreams, RandomPlayerAI, Teams, PRNG, PRNGSeed} from '@pkmn/sim';
import {TeamGenerators} from '@pkmn/randoms';

import {Stats, Tracker} from 'trakr';
import minimist from 'minimist';

import {Gen12RNG, Gen34RNG, Gen56RNG} from './rng';

Teams.setGeneratorFactory(TeamGenerators);

const TAG = 'time';
const FORMATS = [
  'gen1randombattle',
  // 'gen2randombattle',
  // 'gen3randombattle',
  // 'gen4randombattle',
  // 'gen5randombattle',
  // 'gen6randombattle',
  // 'gen7randombattle', 'gen7randomdoublesbattle',
  // 'gen8randombattle', 'gen8randomdoublesbattle',
] as ID[];

const argv = minimist(process.argv.slice(2), {default: {warmup: 100, iterations: 1000}});
argv.seed = argv.seed
  ? argv.seed.split(',').map((s: string) => Number(s))
  : [1, 2, 3, 4];

const getPRNGs = (format: ID) => {
  const prng = new PRNG(argv.seed.slice());
  const p1 = new PRNG([
    Math.floor(prng.next() * 0x10000),
    Math.floor(prng.next() * 0x10000),
    Math.floor(prng.next() * 0x10000),
    Math.floor(prng.next() * 0x10000),
  ]);
  const p2 = new PRNG([
    Math.floor(prng.next() * 0x10000),
    Math.floor(prng.next() * 0x10000),
    Math.floor(prng.next() * 0x10000),
    Math.floor(prng.next() * 0x10000),
  ]);
  switch (format) {
  case 'gen1randombattle':
  case 'gen2randombattle':
    return {p1, p2, battle: new Gen12RNG(argv.seed)};
  case 'gen3randombattle':
  case 'gen4randombattle':
    return {p1, p2, battle: new Gen34RNG(argv.seed)};
  case 'gen5randombattle':
  case 'gen6randombattle':
    return {p1, p2, battle: new Gen56RNG(argv.seed)};
  default:
    // TODO: add correct implementations of PRNG for other gens
    return {p1, p2, battle: new PRNG(argv.seed)};
  }
};

const ps = async (format: ID, prng: {battle: PRNG; p1: PRNG; p2: PRNG}, tracker?: Tracker) => {
  const seed = prng.battle.seed;
  const battleStream = new PRNGOverrideBattleStream(prng.battle);
  const streams = BattleStreams.getPlayerStreams(battleStream);
  const spec = {formatid: format, seed};

  const p1spec = {
    name: 'Bot 1',
    team: Teams.pack(Teams.generate(format, {seed: prng.p1.seed.slice() as PRNGSeed})),
  };
  const p2spec = {
    name: 'Bot 2',
    team: Teams.pack(Teams.generate(format, {seed: prng.p2.seed.slice() as PRNGSeed})),
  };
  const start =
    `>start ${JSON.stringify(spec)}\n` +
    `>player p1 ${JSON.stringify(p1spec)}\n` +
    `>player p2 ${JSON.stringify(p2spec)}`;

  const p1 = (new RandomPlayerAI(streams.p1, {seed: prng.p1})).start();
  const p2 = (new RandomPlayerAI(streams.p2, {seed: prng.p1})).start();

  const begin = performance.now();
  try {
    await streams.omniscient.write(start);
    await streams.omniscient.readAll();
    await Promise.all([streams.omniscient.writeEnd(), p1, p2]);
    const battle = battleStream.battle!;
    if (!battle.ended) throw new Error(`Unfinished ${format} battle: [${seed.join(', ')}]`);
    return battleStream.battle!.turn;
  } finally {
    if (tracker) tracker.add(TAG, performance.now() - begin);
  }
};

const pkmn = async (format: ID, prng: {battle: PRNG; p1: PRNG; p2: PRNG}, tracker?: Tracker) =>
  ps(format, prng, tracker); // TODO

const pct = (a: number, b: number) => `${(-(b - a) * 100 / b).toFixed(2)}%`;

const dec = (n: number) => {
  const abs = Math.abs(n);
  if (abs < 1) return n.toFixed(3);
  if (abs < 10) return n.toFixed(2);
  if (abs < 100) return n.toFixed(1);
  return n.toFixed();
};

const report = (a: Stats, b: Stats, turns: number) => {
  const std = (n: Stats) => !isNaN(n.std) ? ` ± ${dec(n.std)}` : '';
  console.log(`total: ${dec(a.sum)} vs ${dec(b.sum)} (${pct(a.sum, b.sum)})`);
  console.log(`turn: ${dec(a.sum / turns)} vs ${dec(b.sum / turns)}` +
    ` (${pct(a.sum / turns, b.sum / turns)})`);
  console.log(`average: ${dec(a.avg)}${std(a)} vs ${dec(b.avg)}${std(b)} (${pct(a.avg, b.avg)})`);
  console.log(`p50: ${dec(a.p50)} vs ${dec(b.p50)} (${pct(a.p50, b.p50)})`);
  console.log(`p95: ${dec(a.p95)} vs ${dec(b.p95)} (${pct(a.p95, b.p95)})`);
};

class PRNGOverrideBattleStream extends BattleStreams.BattleStream {
  readonly prng: PRNG;

  constructor(prng: PRNG) {
    super();
    this.prng = prng;
  }

  _writeLine(type: string, message: string) {
    super._writeLine(type, message);
    if (type === 'start') this.battle!.prng = this.prng;
  }
}

(async () => {
  const totals: {[format: string]: number} = {};
  const trackers: {[format: string]: {[name: string]: Tracker}} = {};

  for (const format of FORMATS) {
    const control = {turns: 0, seed: [0, 0, 0, 0]};
    trackers[format] = {};

    for (const [name, engine] of [['Pokémon Showdown!', ps], ['@pkmn/engine', pkmn]] as const) {
      const prngs = getPRNGs(format);
      let turns = 0;
      for (let i = 0; i < argv.warmup; i++) {
        turns += await engine(format, prngs);
      }
      // @ts-ignore
      if (global.gc()) global.gc();

      const tracker = (trackers[format][name] =
          Tracker.create({buf: Buffer.alloc(argv.iterations * (8 + 1))}));
      for (let i = 0; i < argv.iterations; i++) {
        turns += await engine(format, prngs, tracker);
      }

      if (!control.turns) {
        control.turns = turns;
        control.seed = prngs.battle.seed;
      } else {
        if (control.turns !== turns) {
          throw new Error(`Expected ${control.turns} turns and received ${turns}`);
        }
        const expected = control.seed.join(', ');
        const actual = prngs.battle.seed.join(', ');
        if (expected !== actual) {
          throw new Error(`Expected a final seed of [${expected}] but received [${actual}]`);
        }
      }
      totals[format] = control.turns;
    }
  }

  for (const format in trackers) {
    const [a, b] = Object.values(trackers[format]).map(t => t.stats().get(TAG));
    console.log(`\n${format}\n---`);
    report(a!, b!, totals[format]);
  }
})();
