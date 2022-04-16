import {
  BoostsTable,
  Generation,
  ID,
  PokemonSet,
  StatsTable,
  StatusName,
  TypeName,
} from '@pkmn/data';

import {Lookup} from './data';
import * as gen1 from './gen1';

export type Slot = 1 | 2 | 3 | 4 | 5 | 6;
export interface Battle extends Gen1.Battle {}
export interface Side extends Gen1.Side {}
export interface Pokemon extends Gen1.Pokemon {}
export interface MoveSlot extends Gen1.MoveSlot {}

export namespace Gen1 {
  export interface Battle {
    sides: Iterable<Side>;
    turn: number;
    lastDamage: number;
    prng: readonly number[];
  }

  // TODO: rename to active/team/pokemon?
  export interface Side {
    active: Pokemon | undefined;
    pokemon: Iterable<Pokemon>;
    lastUsedMove: ID | undefined;
    lastSelectedMove: ID | undefined;
  }

  export interface Pokemon {
    species: ID;
    types: readonly [TypeName, TypeName];
    level: number;
    hp: number;
    status: StatusName | undefined;
    statusData: {sleep: number; toxic: number};
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
    bide?: {damage: number};
    thrashing?: {duration: number; accuracy: number};
    multihit?: unknown;
    flinch?: unknown;
    charging?: unknown;
    trapping?: {duration: number};
    invulnerable?: unknown;
    confusion?: {duration: number};
    mist?: unknown;
    focusenergy?: unknown;
    substitute?: {hp: number};
    recharging?: unknown;
    rage?: {duration: number; accuracy: number};
    leechseed?: unknown;
    toxic?: unknown;
    lightscreen?: unknown;
    reflect?: unknown;
    transform?: unknown;
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
  type: 'move' | 'switch' | 'pass';
  data: number;
}

export interface Result {
  type: 'none' | 'win' | 'lose' | 'tie' | 'error';
  p1: Choice['type'];
  p2: Choice['type'];
}

export class Battle {
  private constructor() {}

  static create(gen: Generation, options: CreateOptions) {
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.create(gen, lookup, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }

  static restore(gen: Generation, battle: Battle, options: RestoreOptions) {
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.restore(gen, lookup, battle, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }
}
