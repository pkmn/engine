import * as path from 'path';

import {Generation, PokemonSet} from '@pkmn/data';
import {
  ActionChoice, Battle, BattleQueue, Effect, Field, ID, PRNG,
  PRNGSeed, Pokemon, Side, SideID, extractChannelMessages,
} from '@pkmn/sim';

export interface Roll {
  key: string;
  value: number;
}

export const MIN = 0;
export const MAX = 0xFFFFFFFF;
export const NOP = 42;

const tie = 'sim/battle-queue.ts:405:15';

export const ROLLS = {
  basic(keys: {hit: string; crit: string; dmg: string}) {
    return {
      HIT: {key: keys.hit, value: MIN},
      MISS: {key: keys.hit, value: MAX},
      CRIT: {key: keys.crit, value: MIN},
      NO_CRIT: {key: keys.crit, value: MAX},
      MIN_DMG: {key: keys.dmg, value: MIN},
      MAX_DMG: {key: keys.dmg, value: MAX},
      TIE: (n: 1 | 2) => ({key: tie, value: ranged(n, 2) - 1}),
      DRAG: (m: number, n = 5) =>
        ({key: 'sim/battle.ts:1409:36', value: ranged(m - 1, n)}),
    };
  },
  metronome(gen: Generation, exclude: string[]) {
    const all: string[] = Array.from(gen.moves)
      .filter(m => !m.realMove && !exclude.includes(m.name))
      .sort((a, b) => a.num - b.num)
      .map(m => m.name);
    return (move: string, skip: string[] = []) => {
      const moves = all.filter(m => !skip.includes(m));
      const value = ranged(moves.indexOf(move) + 1, moves.length) - 1;
      return {key: 'data/moves.ts:12169:23', value};
    };
  },
};

function insertChoice(this: BattleQueue, choices: ActionChoice | ActionChoice[], midTurn = false) {
  if (Array.isArray(choices)) {
    for (const choice of choices) {
      this.insertChoice(choice);
    }
    return;
  }
  const choice = choices;

  if (choice.pokemon) {
    choice.pokemon.updateSpeed();
  }
  const actions = this.resolveAction(choice, midTurn);

  let firstIndex = null;
  let lastIndex = null;
  for (const [i, curAction] of this.list.entries()) {
    const compared = this.battle.comparePriority(actions[0], curAction);
    if (compared <= 0 && firstIndex === null) {
      firstIndex = i;
    }
    if (compared < 0) {
      lastIndex = i;
      break;
    }
  }

  if (firstIndex === null) {
    this.list.push(...actions);
  } else {
    if (lastIndex === null) lastIndex = this.list.length;
    // FIX: Use "host" ordering before gen 3
    const index = firstIndex === lastIndex
      ? firstIndex : (this.battle.gen > 3)
        ? this.battle.random(firstIndex, lastIndex + 1)
        : lastIndex;
    this.list.splice(index, 0, ...actions);
  }
}

function eachEvent(this: Battle, eventid: string, effect?: Effect | null, relayVar?: boolean) {
  const actives = this.getAllActive();
  if (!effect && this.effect) effect = this.effect;
  // FIX: Do not speed sort handlers before gen 3 = use "host" ordering
  if (this.gen >= 3) this.speedSort(actives, (a, b) => b.speed - a.speed);
  for (const pokemon of actives) {
    this.runEvent(eventid, pokemon, null, effect, relayVar);
  }
  if (eventid === 'Weather' && this.gen >= 7) {
    this.eachEvent('Update');
  }
}

function residualEvent(this: Battle, eventid: string, relayVar?: any) {
  const callbackName = `on${eventid}`;
  let handlers = this.findBattleEventHandlers(callbackName, 'duration');
  handlers = handlers.concat(
    this.findFieldEventHandlers(this.field, `onField${eventid}`, 'duration')
  );
  for (const side of this.sides) {
    if (side.n < 2 || !side.allySide) {
      handlers = handlers.concat(this.findSideEventHandlers(side, `onSide${eventid}`, 'duration'));
    }
    for (const active of side.active) {
      if (!active) continue;
      handlers = handlers.concat(
        this.findPokemonEventHandlers(active, callbackName, 'duration')
      );
      handlers = handlers.concat(
        this.findSideEventHandlers(side, callbackName, undefined, active)
      );
      handlers = handlers.concat(
        this.findFieldEventHandlers(this.field, callbackName, undefined, active)
      );
    }
  }
  // FIX: Do not speed sort handlers before gen 3 = use "host" ordering
  if (this.gen >= 3) this.speedSort(handlers);
  while (handlers.length) {
    const handler = handlers[0];
    handlers.shift();
    const effect = handler.effect;
    if ((handler.effectHolder as Pokemon).fainted) continue;
    if (handler.end && handler.state?.duration) {
      handler.state.duration--;
      if (!handler.state.duration) {
        const endCallArgs = handler.endCallArgs || [handler.effectHolder, effect.id];
        handler.end.call(...endCallArgs as [any, ...any[]]);
        if (this.ended) return;
        continue;
      }
    }

    let handlerEventid = eventid;
    if ((handler.effectHolder as Side).sideConditions) handlerEventid = `Side${eventid}`;
    if ((handler.effectHolder as Field).pseudoWeather) handlerEventid = `Field${eventid}`;
    if (handler.callback) {
      this.singleEvent(
        handlerEventid, effect, handler.state, handler.effectHolder,
        null, null, relayVar, handler.callback
      );
    }

    this.faintMessages();
    if (this.ended) return;
  }
}

// NOTE: These "patches" are not all suitable for upstreaming - each of these
// patches works around a core issue with Pokémon Showdown, but attempts to do
// so in the easiest/most minimally intrusive way as opposed to the most
// *correct* way. eg. instead of assigning "priorities" to no-op handlers, the
// handlers in question should be removed entirely (which can be accomplished by
// disabling inheritance or setting them to `null`). Similarly, in many places
// order should be used
// instead, or multiple other conditions should be changed as opposed to the ones chosen here etc.
export const patch = {
  generation: (gen: Generation) => {
    // Add priorities to mods to avoid speed ties - ordering is arbitrary
    (gen.dex.data as any).Rulesets['sleepclausemod'].onSetStatusPriority = -999;
    (gen.dex.data as any).Rulesets['freezeclausemod'].onSetStatusPriority = -998;

    const conditions = {
      // Add priority to avoid speed ties with Bide's onDisableMove handler
      1: {'disable': {onDisableMovePriority: 7}},
      2: {
        // Type-boosting items need an onBasePowerPriority... for their nop handler
        'item: Pink Bow': {onBasePowerPriority: 15},
        'item: Polkadot Bow': {onBasePowerPriority: 15},
        // Inherited from Gen 4, doesn't actually use onBasePowerPriority...
        'item: Light Ball': {onBasePowerPriority: -999},
        'attract': {
          // Confusion -> Attraction -> Disable -> Paralysis, but Paralysis has been given (2)?
          onBeforeMovePriority: 4,
          // Cure attraction before berries proc
          onUpdatePriority: 1,
        },
        // Arbitrarily make trapped higher priority than partiallytrapped
        'trapped': {onTrapPokemonPriority: 1},
        // Minimize damage increase happens after damage calc and item boosts
        'minimize': {onSourceModifyDamagePriority: -1},
        // Give Disable priority over Encore and Bide
        'disable': {onDisableMovePriority: 1, onBeforeMovePriority: 1},
        // Order doesn't matter for crit ratio since addition is commutative
        'focusenergy': {onModifyCritRatioPriority: 1},
        // Match onAfterMoveSelfPriority
        'residualdmg': {onAfterSwitchInSelfPriority: 100},
      },
    };

    for (const [name, fields] of Object.entries((conditions as any)[gen.num])) {
      const condition = gen.dex.conditions.get(name);
      for (const field in fields as any) {
        (condition as any)[field] = (fields as any)[field];
      }
    }

    return gen;
  },
  battle: (battle: Battle, prng = false, debug = false) => {
    battle.trunc = battle.dex.trunc.bind(battle.dex);
    battle.queue.insertChoice = insertChoice.bind(battle.queue);
    battle.eachEvent = eachEvent.bind(battle);
    battle.residualEvent = residualEvent.bind(battle);
    if (prng) {
      const shuffle = battle.prng.shuffle.bind(battle.prng);
      battle.prng.shuffle = (items, start = 0, end = items.length) => {
        if (location() !== tie) throw new Error('Unexpected shuffle');
        shuffle(items, start, end);
      };
    }
    if (debug) {
      const next = battle.prng.next.bind(battle.prng);
      battle.prng.next = (from?: number, to?: number) => {
        const seed = battle.prng.seed.join(',');
        const result = next(from, to);
        const roll = (battle.prng.seed[0] << 16 >>> 0) + battle.prng.seed[1];
        const original = `0x${(roll).toString(16).padStart(8, '0').toUpperCase()}`;
        battle.add('debug', location(), seed, original);
        return result;
      };
    } else {
      (battle as any).debugMode = debug;
    }
  },
};

export const Choices = new class {
  get(this: void, gen: Generation): (battle: Battle, id: SideID, struggle?: string) => string[] {
    switch (gen.num) {
      case 1: return Choices.gen1;
      case 2: return Choices.gen2;
      default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }

  gen1(this: void, battle: Battle, id: SideID, struggle = 'move 1'): string[] {
    const request = battle[id]!.activeRequest;
    if (!request || request.wait) return [];

    if (request.forceSwitch) {
      const options: string[] = [];
      const side = battle[id]!;
      for (let slot = 2; slot <= 6; slot++) {
        const pokemon = side.pokemon[slot - 1];
        if (!pokemon || pokemon.hp === 0) continue;
        options.push(`switch ${slot}`);
      }
      return options.length === 0 ? ['pass'] : options;
    } else if (request.active) {
      const options: string[] = [];

      const side = battle[id]!;
      const active = side.active[0];

      // Being "forced" on Pokémon Showdown sets "trapped"
      if (active.trapped) {
        const forced = active.trapped && request.active[0].moves.length === 1;
        if (forced) return ['move 1'];
      } else {
        for (let slot = 2; slot <= 6; slot++) {
          const pokemon = side.pokemon[slot - 1];
          if (!pokemon || pokemon.hp === 0) continue;
          options.push(`switch ${slot}`);
        }
      }

      const binding = active.volatiles['partialtrappinglock'];
      const before = options.length;
      let slot = 0;
      for (const move of active.moveSlots) {
        slot++;
        // Pokémon Showdown expect us to select 0 PP moves when binding as it disables
        // everything but the move we are to use (and forced trapping moves underflow)
        if ((move.pp === 0 && !binding) || move.disabled) continue;
        options.push(`move ${slot}`);
      }
      if (options.length === before) {
        options.push(struggle);
      }

      return options;
    } else {
      throw new Error(`Unsupported request: ${JSON.stringify(request)}`);
    }
  }

  gen2(this: void, battle: Battle, id: SideID, struggle = 'move 1'): string[] {
    const request = battle[id]!.activeRequest;
    if (!request || request.wait) return [];

    if (request.forceSwitch) {
      const options: string[] = [];
      const side = battle[id]!;
      for (let slot = 2; slot <= 6; slot++) {
        const pokemon = side.pokemon[slot - 1];
        if (!pokemon || pokemon.hp === 0) continue;
        options.push(`switch ${slot}`);
      }
      return options.length === 0 ? ['pass'] : options;
    } else if (request.active) {
      const options: string[] = [];

      const side = battle[id]!;
      const active = side.active[0];

      // Being "forced" on Pokémon Showdown sets "trapped"
      if (active.trapped) {
        const forced = active.trapped && request.active[0].moves.length === 1;
        if (forced) return ['move 1'];
      } else {
        for (let slot = 2; slot <= 6; slot++) {
          const pokemon = side.pokemon[slot - 1];
          if (!pokemon || pokemon.hp === 0) continue;
          options.push(`switch ${slot}`);
        }
      }

      const before = options.length;
      let slot = 0;
      for (const move of active.moveSlots) {
        slot++;
        if (move.pp === 0 || move.disabled) continue;
        options.push(`move ${slot}`);
      }
      if (options.length === before) {
        options.push(struggle);
      }

      return options;
    } else {
      throw new Error(`Unsupported request: ${JSON.stringify(request)}`);
    }
  }
};

export const ranged = (n: number, d: number) => n * Math.floor(0x100000000 / d);

const MODS: {[gen: number]: string[]} = {
  1: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
  2: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
};

export function formatFor(gen: Generation) {
  return `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}` as ID; // o_O "ID"
}

function fixSet(gen: Generation, set: Partial<PokemonSet>) {
  if (gen.num >= 2) set.gender = set.gender || gen.species.get(set.species!)!.gender || 'M';
  return set as PokemonSet;
}

export function createStartBattle(gen: Generation) {
  patch.generation(gen);
  const formatid = formatFor(gen);
  return (
    rolls: Roll[],
    p1: Partial<PokemonSet>[],
    p2: Partial<PokemonSet>[],
    fn?: (b: Battle) => void,
  ) => {
    const battle = new Battle({formatid, strictChoices: true});
    patch.battle(battle);
    (battle as any).debugMode = false;
    (battle as any).prng = new FixedRNG(rolls);
    if (fn) battle.started = true;
    battle.setPlayer('p1', {team: p1.map(p => fixSet(gen, p))});
    battle.setPlayer('p2', {team: p2.map(p => fixSet(gen, p))});
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

  override next(from?: number, to?: number): number {
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

  override get startingSeed(): PRNGSeed {
    throw new Error('Unsupported operation');
  }

  override clone(): PRNG {
    throw new Error('Unsupported operation');
  }

  override nextFrame(): PRNGSeed {
    throw new Error('Unsupported operation');
  }

  exhausted(): boolean {
    return this.index === this.rolls.length;
  }
}

export const FILTER = new Set([
  '', 't:', 'gametype', 'player', 'teamsize', 'gen', 'message', 'done', 'error',
  'bigerror', 'tier', 'rule', 'start', 'upkeep', '-message', '-hint', 'debug',
]);

function filter(raw: string[]) {
  const log = extractChannelMessages(raw.join('\n'), [-1])[-1];
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
  'location', 'PRNG.randomChance', 'PRNG.sample',
  'FixedRNG.next', 'FixedRNG.randomChance', 'FixedRNG.sample', 'FixedRNG.shuffle',
  'Battle.random', 'Battle.randomChance', 'Battle.sample', 'Battle.speedSort', 'Battle.runEvent',
  'PRNG.battle.prng.next', 'PRNG.battle.prng.shuffle',
]);

function location() {
  for (const line of new Error().stack!.split('\n').slice(1)) {
    const match = METHOD.exec(line);
    if (!match) continue;
    if (!NON_TERMINAL.has(match[1])) {
      return match[2].replaceAll(path.sep, '/').replace(/.*@pkmn\/sim\//, '');
    }
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
