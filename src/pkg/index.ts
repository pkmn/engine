import {
  BoostsTable,
  Generation,
  ID,
  PokemonSet,
  StatsTable,
  StatusName,
  TypeName,
} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';

import {Lookup} from './data';
import * as gen1 from './gen1';

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

  export interface Side {
    active: Pokemon;
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
    volatiles: {[name: string]: Volatile};
    stored: {
      species: ID;
      types: readonly [TypeName, TypeName];
      stats: StatsTable;
      moves: Iterable<Omit<MoveSlot, 'disabled'>>;
    };
  }

  export interface MoveSlot {
    move: ID;
    pp: number;
    disabled?: number;
  }

  export interface Volatile {
    duration?: number;
    damage?: number;
    hp?: number;
    accuracy?: number;
  }
}

export interface ParsedLine {
  args: Protocol.BattleArgType;
  kwargs: Protocol.BattleArgsKWArgType;
}

export class Battle {
  static create(gen: Generation, buf: ArrayBuffer, showdown = true) {
    switch (gen.num) {
    case 1: return new gen1.Battle(Lookup.get(gen), new DataView(buf), showdown);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }
}

export interface Names {
  p1: SideNames;
  p2: SideNames;
}

export class SideNames {
  player: Protocol.Username;
  team: string[];

  constructor(name: string, team: PokemonSet[]) {
    this.player = name as Protocol.Username;
    this.team = team.map(p => p.name ?? p.species);
  }
}
