import {
  BoostsTable,
  Generation,
  ID,
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
    move: ID;
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

export class Battle {
  static create(gen: Generation, buf: ArrayBuffer, showdown = true) {
    switch (gen.num) {
    case 1: return new gen1.Battle(Lookup.get(gen), new DataView(buf), showdown);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }
}
