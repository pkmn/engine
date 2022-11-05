import {Battle, ID, PRNG, PRNGSeed} from '@pkmn/sim';
import {Generation, PokemonSet} from '@pkmn/data';

export interface Roll {
  key: string | string[];
  value: number;
}

export const MIN = 0;
export const MAX = 0xFFFFFFFF;
export const NOP = 42;

export const ROLLS: {[category: string]: {[name: string]: Roll}} = {
  basic: {
    HIT: {key: 'BattleActions.tryMoveHit', value: MIN},
    MISS: {key: 'BattleActions.tryMoveHit', value: MAX},
    CRIT: {key: ['Battle.randomChance', 'BattleActions.getDamage'], value: MIN},
    NO_CRIT: {key: ['Battle.randomChance', 'BattleActions.getDamage'], value: MAX},
    MIN_DMG: {key: ['Battle.random', 'BattleActions.getDamage'], value: MIN},
    MAX_DMG: {key: ['Battle.random', 'BattleActions.getDamage'], value: MAX},
  },
  nops: {
    SS_MOD: {key: ['Battle.speedSort', 'Pokemon.setStatus'], value: NOP},
    SS_RES: {key: ['Battle.speedSort', 'Battle.residualEvent'], value: NOP},
    SS_RUN: {key: ['Battle.speedSort', 'Battle.runEvent'], value: NOP},
    SS_EACH: {key: ['Battle.speedSort', 'Battle.eachEvent'], value: NOP},
    INS: {key: ['BattleQueue.insertChoice', 'BattleActions.switchIn'], value: NOP},
    GLM: {key: 'Pokemon.getLockedMove', value: NOP},
  },
};

export const ranged = (n: number, d: number) => n * Math.floor(0x100000000 / d);

const MODS: {[gen: number]: string[]} = {
  1: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
};

export function formatFor(gen: Generation) {
  return `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}` as ID;
}

export function createStartBattle(gen: Generation) {
  const formatid = formatFor(gen);
  return (
    rolls: Roll[],
    p1: Partial<PokemonSet>[],
    p2: Partial<PokemonSet>[],
    fn?: (b: Battle) => void,
  ) => {
    const battle = new Battle({formatid, strictChoices: true});
    (battle as any).debugMode = false;
    (battle as any).prng = new FixedRNG(rolls);
    if (fn) battle.started = true;
    battle.setPlayer('p1', {team: p1 as PokemonSet[]});
    battle.setPlayer('p2', {team: p2 as PokemonSet[]});
    if (fn) {
      fn(battle);
      battle.started = false;
      battle.start();
    } else {
      (battle as any).log = [];
    }
    return battle;
  };
}

export class FixedRNG extends PRNG {
  private readonly rolls: Roll[];
  private index: number;

  constructor(rolls: Roll[]) {
    super([0, 0, 0, 0]);
    this.rolls = rolls;
    this.index = 0;
  }

  next(from?: number, to?: number): number {
    if (this.index >= this.rolls.length) throw new Error('Insufficient number of rolls provided');
    const roll = this.rolls[this.index++];
    const where = locations();
    const locs = where.join(', ');
    if (Array.isArray(roll.key)) {
      if (!roll.key.every(k => where.includes(k))) {
        throw new Error(`Expected roll for (${roll.key.join(', ')}) but got (${locs})`);
      }
    } else if (!where.includes(roll.key)) {
      throw new Error(`Expected roll for (${roll.key}) but got (${locs})`);
    }
    let result = roll.value;
    if (from) from = Math.floor(from);
    if (to) to = Math.floor(to);
    if (from === undefined) {
      result = result / 0x100000000;
    } else if (!to) {
      result = Math.floor(result * from / 0x100000000);
    } else {
      result = Math.floor(result * (to - from) / 0x100000000) + from;
    }
    return result;
  }

  get startingSeed(): PRNGSeed {
    throw new Error('Unsupported operation');
  }

  clone(): PRNG {
    throw new Error('Unsupported operation');
  }

  nextFrame(): PRNGSeed {
    throw new Error('Unsupported operation');
  }

  exhausted(): boolean {
    return this.index === this.rolls.length;
  }
}

const FILTER = new Set([
  '', 't:', 'gametype', 'player', 'teamsize', 'gen', 'message',
  'tier', 'rule', 'start', 'upkeep', '-message', '-hint',
]);

function filter(raw: string[]) {
  const log = Battle.extractUpdateForSide(raw.join('\n'), 'omniscient').split('\n');
  const filtered = [];
  for (const line of log) {
    const i = line.indexOf('|', 1);
    const arg = line.slice(1, i > 0 ? i : line.length);
    if (FILTER.has(arg)) continue;
    filtered.push(line);
  }

  return filtered;
}

const METHOD = /^ {4}at ((?:\w|\.)+) /;
const NON_TERMINAL = new Set([
  'FixedRNG.next', 'FixedRNG.randomChance', 'FixedRNG.sample', 'FixedRNG.shuffle',
  'Battle.random', 'Battle.randomChance', 'Battle.sample', 'locations',
]);

function locations() {
  const results = [];
  let last: string | undefined = undefined;
  for (const line of new Error().stack!.split('\n').slice(1)) {
    const match = METHOD.exec(line);
    if (!match) continue;
    const m = match[1];
    if (NON_TERMINAL.has(m)) {
      last = m;
      continue;
    }
    if (!results.length && last) results.push(last);
    results.push(m);
  }
  return results;
}

export function verify(battle: Battle, expected: string[]) {
  const actual = filter(battle.log);
  try {
    expect(actual).toEqual(expected);
  } catch (err) {
    console.log(actual);
    throw err;
  }
  expect((battle.prng as FixedRNG).exhausted()).toBe(true);
}
