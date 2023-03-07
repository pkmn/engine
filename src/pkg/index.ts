import {
  BoostsTable, Generation, ID, PokemonSet, StatsTable, StatusName, TypeName,
} from '@pkmn/data';

import {Lookup} from './data';
import * as addon from './addon';
import * as gen1 from './gen1';

export type Player = 'p1' | 'p2';
export type Slot = 1 | 2 | 3 | 4 | 5 | 6;

export type Battle = Gen1.Battle;
export type Side = Gen1.Side;
export type Pokemon = Gen1.Pokemon;
export type MoveSlot = Gen1.MoveSlot;

export interface API {
  update(c1: Choice, c2: Choice): Result;
  choices(id: Player, result: Result): Choice[];
}

export namespace Gen1 {
  export interface Battle extends API {
    sides: Iterable<Side>;
    turn: number;
    lastDamage: number;
    prng: readonly number[];
  }

  export interface Side {
    active: Pokemon | undefined;
    pokemon: Iterable<Pokemon>;
    lastUsedMove: ID | undefined;
    lastSelectedMove: ID | undefined;
    lastSelectedIndex: 1 | 2 | 3 | 4 | undefined;
  }

  export interface Pokemon {
    species: ID;
    types: readonly [TypeName, TypeName];
    level: number;
    hp: number;
    status: StatusName | undefined;
    statusData: {sleep: number; self: boolean; toxic: number};
    stats: StatsTable;
    boosts: BoostsTable;
    moves: Iterable<MoveSlot>;
    volatiles: Volatiles;
    stored: {
      species: ID;
      types: readonly [TypeName, TypeName];
      stats: StatsTable;
      moves: Iterable<Omit<MoveSlot, 'disabled'>>;
    };
    position: Slot;
  }

  export interface MoveSlot {
    id: ID;
    pp: number;
    disabled?: number;
  }

  export interface Volatiles {
    bide?: {duration: number; damage: number};
    thrashing?: {duration: number; accuracy: number};
    multihit?: unknown;
    flinch?: unknown;
    charging?: unknown;
    binding?: {duration: number};
    invulnerable?: unknown;
    confusion?: {duration: number};
    mist?: unknown;
    focusenergy?: unknown;
    substitute?: {hp: number};
    recharging?: unknown;
    rage?: {accuracy: number};
    leechseed?: unknown;
    lightscreen?: unknown;
    reflect?: unknown;
    transform?: {player: 'p1' | 'p2'; slot: number};
  }
}

export type BattleOptions = CreateOptions | RestoreOptions;

export type CreateOptions = {
  p1: PlayerOptions;
  p2: PlayerOptions;
  seed: number[];
  showdown?: boolean;
  log: true;
} | {
  p1: Omit<PlayerOptions, 'name'>;
  p2: Omit<PlayerOptions, 'name'>;
  seed: number[];
  showdown?: boolean;
  log?: false;
};

export type RestoreOptions = {
  p1: PlayerOptions;
  p2: PlayerOptions;
  showdown?: boolean;
  log: true;
} | {
  showdown?: boolean;
  log?: false;
};

export interface PlayerOptions {
  name: string;
  team: Partial<PokemonSet>[];
}

export interface Choice {
  type: 'pass' | 'move' | 'switch';
  data: number;
}

export interface Result {
  type: undefined | 'win' | 'lose' | 'tie' | 'error';
  p1: Choice['type'];
  p2: Choice['type'];
}

export const Battle = new class {
  create(gen: Generation, options: CreateOptions) {
    addon.check(!!options.showdown);
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.create(gen, lookup, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }

  restore(gen: Generation, battle: Battle, options: RestoreOptions) {
    addon.check(!!options.showdown);
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.restore(gen, lookup, battle, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }
};

export class Choice {
  static Types = ['pass', 'move', 'switch'] as const;

  private constructor() {}

  static parse(byte: number): Choice {
    return {type: Choice.Types[byte & 0b11], data: byte >> 4};
  }

  static encode(choice?: Choice): number {
    return (choice
      ? (choice.data << 4 | (choice.type === 'pass' ? 0 : choice.type === 'move' ? 1 : 2))
      : 0);
  }

  static pass(): Choice {
    return {type: 'pass', data: 0};
  }

  static move(data: 0 | 1 | 2 | 3 | 4): Choice {
    return {type: 'move', data};
  }

  static switch(data: 2 | 3 | 4 | 5 | 6): Choice {
    return {type: 'switch', data};
  }
}

export class Result {
  static Types = [undefined, 'win', 'lose', 'tie', 'error'] as const;

  private constructor() {}

  static parse(byte: number): Result {
    return {
      type: Result.Types[byte & 0b1111],
      p1: Choice.Types[(byte >> 4) & 0b11],
      p2: Choice.Types[byte >> 6],
    };
  }
}

export * from './protocol';
export {Lookup} from './data';
