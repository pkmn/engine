/* eslint-disable @typescript-eslint/no-unused-vars */
import 'source-map-support/register';

import {Buffer} from 'buffer';
import {performance} from 'perf_hooks';

import {
  Battle,
  BattleStreams,
  ID,
  Pokemon,
  PRNG,
  PRNGSeed,
  RandomPlayerAI,
  Side,
  SideID,
  Teams,
} from '@pkmn/sim';

import {Stats, Tracker} from 'trakr';
import minimist from 'minimist';

const TAG = 'time';
const FORMATS = [
  'gen1randombattle',
  // 'gen2randombattle',
  // 'gen3randombattle',
  // 'gen4randombattle',
  // 'gen5randombattle',
  // 'gen6randombattle',
  // 'gen7randombattle',
  // 'gen7randomdoublesbattle',
  // 'gen8randombattle',
  // 'gen8randomdoublesbattle',
] as ID[];

const argv = minimist(process.argv.slice(2), {default: {warmup: 100, iterations: 1000}});
argv.seed = argv.seed
  ? argv.seed.split(',').map((s: string) => Number(s))
  : [1, 2, 3, 4];

const newSeed = (prng: PRNG) => [
  prng.next(0x10000),
  prng.next(0x10000),
  prng.next(0x10000),
  prng.next(0x10000),
] as PRNGSeed;

const getPRNGs = () => {
  const prng = new PRNG(argv.seed.slice());
  const p1 = new PRNG(newSeed(prng));
  const p2 = new PRNG(newSeed(prng));
  return {p1, p2, battle: new PRNG(argv.seed)};
};

const ps = async (format: ID, prng: { battle: PRNG; p1: PRNG; p2: PRNG }, tracker?: Tracker) => {
  const seed = prng.battle.seed;
  const battleStream = new PRNGOverrideBattleStream(prng.battle);
  const streams = BattleStreams.getPlayerStreams(battleStream);

  const p1 = (new RandomPlayerAI(streams.p1, {seed: prng.p1})).start();
  const p2 = (new RandomPlayerAI(streams.p2, {seed: prng.p2})).start();

  const spec = {formatid: format, seed};
  const p1spec = {
    name: 'Bot 1',
    team: Teams.pack(Teams.generate(format, {seed: prng.p1.seed.slice() as PRNGSeed})),
  };
  const p2spec = {
    name: 'Bot 2',
    team: Teams.pack(Teams.generate(format, {seed: prng.p2.seed.slice() as PRNGSeed})),
  };

  const start = `>start ${JSON.stringify(spec)}\n` +
    `>player p1 ${JSON.stringify(p1spec)}\n` +
    `>player p2 ${JSON.stringify(p2spec)}`;

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

// TODO: make this the PS implementation and actually implement a @pkmn/engine function
const pkmn = (format: ID, prng: { battle: PRNG; p1: PRNG; p2: PRNG }, tracker?: Tracker) => {
  const battle = new DirectBattle({formatid: format, seed: prng.battle.seed}, prng.battle);
  // TODO: can we skip choice parsing entirely?
  const p1 = new RandomPlayerAI(null!, {seed: prng.p1});
  p1.choose = choice => battle.choose('p1', choice);
  const p2 = new RandomPlayerAI(null!, {seed: prng.p2});
  p2.choose = choice => battle.choose('p2', choice);

  const p1spec = {
    name: 'Bot 1',
    team: Teams.generate(format, {seed: prng.p1.seed.slice() as PRNGSeed}),
  };
  const p2spec = {
    name: 'Bot 2',
    team: Teams.generate(format, {seed: prng.p2.seed.slice() as PRNGSeed}),
  };

  battle.setPlayer('p1', p1spec);
  const begin = performance.now();
  try {
    battle.setPlayer('p2', p2spec);
    while (!battle.ended) {
      if (battle.p1.activeRequest) p1.receiveRequest(battle.p1.activeRequest);
      if (battle.p2.activeRequest) p2.receiveRequest(battle.p2.activeRequest);
    }
    return battle.turn;
  } finally {
    if (tracker) tracker.add(TAG, performance.now() - begin);
  }
};

class DirectBattle extends Battle {
  constructor(options: any, prng: PRNG) {
    super(options);
    this.prng = prng;
  }

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

const pct = (a: number, b: number) => `${(-(a - b) * 100 / a).toFixed(2)}%`;

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

(async () => {
  const totals: { [format: string]: number } = {};
  const trackers: { [format: string]: { [name: string]: Tracker } } = {};

  for (const format of FORMATS) {
    const control = {turns: 0, seed: [0, 0, 0, 0]};
    trackers[format] = {};

    for (const [name, engine] of [['Pokémon Showdown!', ps], ['@pkmn/engine', pkmn]] as const) {
      const prngs = getPRNGs();
      let turns = 0;
      for (let i = 0; i < argv.warmup; i++) {
        turns += await engine(format, prngs);
      }
      // @ts-ignore
      if (global.gc) global.gc();

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
