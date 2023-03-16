import {
  BoostsTable, Generation, ID, PokemonSet, StatsTable, StatusName, TypeName,
} from '@pkmn/data';

import * as addon from './addon';
import {Lookup} from './data';
import * as gen1 from './gen1';

/** Representation of one of the battle's participants. */
export type Player = 'p1' | 'p2';
/** The one-indexed location of a player's Pokémon in battle. */
export type Slot = 1 | 2 | 3 | 4 | 5 | 6;

/** Root object representing the entire state of a Pokémon battle. */
export type Battle = Gen1.Battle;
export type Side = Gen1.Side;
export type Pokemon = Gen1.Pokemon;
export type MoveSlot = Gen1.MoveSlot;

export interface API {
  update(c1: Choice, c2: Choice): Result;
  choices(id: Player, result: Result): Choice[];
  choose(id: Player, result: Result, fn: (n: number) => number): Choice;
}

export type Data<T extends API> = Omit<T, keyof API>;

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

/** Options for creating a battle via Battle.create. */
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

/** Options for restoring a battle via Battle.restore. */
export type RestoreOptions = {
  p1: PlayerOptions;
  p2: PlayerOptions;
  showdown?: boolean;
  log: true;
} | {
  showdown?: boolean;
  log?: false;
};

/** Options about a particular player. */
export interface PlayerOptions {
  name: string;
  team: Partial<PokemonSet>[];
}

/** A choice made by a player during battle. */
export interface Choice {
  type: 'pass' | 'move' | 'switch';
  data: number;
}

/** The result of the battle - all defined results should be considered terminal. */
export interface Result {
  type: undefined | 'win' | 'lose' | 'tie' | 'error';
  p1: Choice['type'];
  p2: Choice['type'];
}

/** Factory for creating Battle objects. */
export const Battle = new class {
  /** Create a Battle in the given generation with the provided options. */
  create(gen: Generation, options: CreateOptions) {
    addon.check(!!options.showdown);
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.create(gen, lookup, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }

  /** Restore a (possibly in-progress) Battle in the given generation with the provided options. */
  restore(gen: Generation, battle: Battle, options: RestoreOptions) {
    addon.check(!!options.showdown);
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.restore(gen, lookup, battle, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }
};

/** Utilities for working with Choice objects. */
export class Choice {
  static Types = ['pass', 'move', 'switch'] as const;
  static PASS = {type: 'pass', data: 0} as const;
  static MATCH = /^(?:(pass)|((move) ([0-4]))|((switch) ([2-6])))$/;

  private constructor() {}

  /** Decode a Choice from its binary representation. */
  static decode(byte: number): Choice {
    return {type: Choice.Types[byte & 0b11], data: byte >> 4};
  }

  /** Encode a Choice to its binary representation. */
  static encode(choice?: Choice): number {
    return (choice
      ? (choice.data << 4 | (choice.type === 'pass' ? 0 : choice.type === 'move' ? 1 : 2))
      : 0);
  }

  /**
   * Parse a Pokémon Showdown choice string into a Choice.
   * Only numeric choice data is supported.
   */
  static parse(choice: string): Choice {
    const m = Choice.MATCH.exec(choice);
    if (!m) throw new Error(`Invalid choice: '${choice}'`);
    const type = (m[1] ?? m[3] ?? m[6]) as Choice['type'];
    const data = +(m[4] ?? m[7] ?? 0);
    return {type, data};
  }

  /** Formats a Choice ino a Pokémon Showdown compatible choice string. */
  static format(choice: Choice): string {
    return choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`;
  }

  /** Returns the "pass" Choice. */
  static pass(): Choice {
    return Choice.PASS;
  }

  /** Returns a "move" Choice with the provided data. */
  static move(data: 0 | 1 | 2 | 3 | 4): Choice {
    return {type: 'move', data};
  }

  /** Returns a "switch" Choice with the provided data. */
  static switch(data: 2 | 3 | 4 | 5 | 6): Choice {
    return {type: 'switch', data};
  }
}

/** Utilities for working with Result objects */
export class Result {
  static Types = [undefined, 'win', 'lose', 'tie', 'error'] as const;

  private constructor() {}

  /** Decode a Result from its binary representation. */
  static decode(byte: number): Result {
    return {
      type: Result.Types[byte & 0b1111],
      p1: Choice.Types[(byte >> 4) & 0b11],
      p2: Choice.Types[byte >> 6],
    };
  }
}

export * from './protocol';
export {Lookup} from './data';
