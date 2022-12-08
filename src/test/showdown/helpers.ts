import {Battle, ID, PRNG, PRNGSeed} from '@pkmn/sim';
import {Generation, PokemonSet} from '@pkmn/data';

export interface Roll {
  key: string;
  value: number;
}

export const MIN = 0;
export const MAX = 0xFFFFFFFF;
export const NOP = 42;

export const ROLLS = {
  basic(keys: {hit: string; crit: string; dmg: string}) {
    return {
      HIT: {key: keys.hit, value: MIN},
      MISS: {key: keys.hit, value: MAX},
      CRIT: {key: keys.crit, value: MIN},
      NO_CRIT: {key: keys.crit, value: MAX},
      MIN_DMG: {key: keys.dmg, value: MIN},
      MAX_DMG: {key: keys.dmg, value: MAX},
      TIE: (n: 1 | 2) =>
        ({key: 'sim/battle-queue.ts:404:15', value: ranged(n, 2) - 1}),
      DRAG: (m: number, n = 5) =>
        ({key: 'sim/battle.ts:1367:36', value: ranged(m - 1, n)}),
    };
  },
  nops: {
    SS_MOD: {key: 'sim/pokemon.ts:1606:40', value: NOP},
    SS_RES: {key: 'sim/battle.ts:471:8', value: NOP},
    SS_EACH: {key: 'sim/battle.ts:441:8', value: NOP},
    INS: {key: 'sim/battle-queue.ts:384:70', value: NOP},
    GLM: {key: 'sim/pokemon.ts:905:34', value: NOP},
  },
  metronome(gen: Generation, exclude: string[]) {
    const all: string[] = Array.from(gen.moves)
      .filter(m => !m.realMove && !exclude.includes(m.name))
      .sort((a, b) => a.num - b.num)
      .map(m => m.name);
    return (move: string, skip: string[] = []) => {
      const moves = all.filter(m => !skip.includes(m));
      const value = ranged(moves.indexOf(move) + 1, moves.length) - 1;
      return {key: 'data/moves.ts:11935:23', value};
    };
  },
};

export const ranged = (n: number, d: number) => n * Math.floor(0x100000000 / d);

const MODS: {[gen: number]: string[]} = {
  1: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
  2: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
};

export function formatFor(gen: Generation) {
  return `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}` as ID;
}

function fix(gen: Generation, set: Partial<PokemonSet>) {
  if (gen.num >= 2) set.gender = set.gender || gen.species.get(set.species!)!.gender || 'M';
  return set as PokemonSet;
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
    battle.setPlayer('p1', {team: p1.map(p => fix(gen, p))});
    battle.setPlayer('p2', {team: p2.map(p => fix(gen, p))});
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
    const n = this.index;
    const where = location();
    if (roll.key !== where) {
      throw new Error(`Expected roll ${n} to be (${roll.key}) but got (${where})`);
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

const METHOD = /^ {4}at ((?:\w|\.)+) \((.*\d)\)/;
const NON_TERMINAL = new Set([
  'FixedRNG.next', 'FixedRNG.randomChance', 'FixedRNG.sample', 'FixedRNG.shuffle',
  'Battle.random', 'Battle.randomChance', 'Battle.sample', 'location', 'Battle.speedSort',
  'Battle.runEvent',
]);

function location() {
  for (const line of new Error().stack!.split('\n').slice(1)) {
    const match = METHOD.exec(line);
    if (!match) continue;
    if (!NON_TERMINAL.has(match[1])) return match[2].replace(/.*@pkmn\/sim\//, '');
  }
  throw new Error('Unknown location');
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
