import {ID, TypeName, Generation} from '@pkmn/data';

import idsJSON from './data/ids.json';
import protocolJSON from './data/protocol.json';
import offsetsJSON from './data/layout.json';

export const LE = (() => {
  const u8 = new Uint8Array(4);
  const u16 = new Uint16Array(u8.buffer);
  return !!((u16[0] = 1) & u16[0]);
})();

export type IDs = [
  { types: TypeName[] },
  { items: ID[]; types: TypeName[] },
  { items: ID[] },
];

export const IDS = idsJSON as IDs;

export const PROTOCOL: {[decl: string]: {[name: string]: number}} = {};
for (const decl in protocolJSON) {
  PROTOCOL[decl] = {};
  let i = 0;
  for (const name of protocolJSON[decl as keyof typeof protocolJSON]) {
    PROTOCOL[decl][name] = i++;
  }
}

export const LAYOUT = offsetsJSON as Array<{
  sizes: {[decl: string]: number};
  offsets: {[decl: string]: {[field: string]: number}};
}>;
for (const gen of LAYOUT) {
  gen.offsets.Battle.p1 = gen.offsets.Battle.sides;
  gen.offsets.Battle.p2 = gen.offsets.Battle.sides + gen.sizes.Side;
}

const LOOKUPS: Lookup[] = [];

export class Lookup {
  private readonly gen: Generation;
  private readonly typesByNum: TypeName[];
  private readonly typesByName: {[key in TypeName]: number};
  private readonly species: ID[];
  private readonly moves: ID[];
  private readonly items: ID[];
  private readonly abilities: ID[];

  static get(gen: Generation) {
    const lookup = LOOKUPS[gen.num - 1];
    return lookup || (LOOKUPS[gen.num - 1] = new Lookup(gen));
  }

  private constructor(gen: Generation) {
    this.gen = gen;
    this.typesByNum = IDS[Math.min(gen.num, 2) - 1 as 0 | 1].types;
    this.typesByName = {} as {[key in TypeName]: number};
    for (let i = 0; i < this.typesByNum.length; i++) {
      this.typesByName[this.typesByNum[i]] = i;
    }
    this.species = [];
    for (const specie of gen.species) {
      this.species[specie.num - 1] = specie.id;
    }
    this.moves = [];
    for (const move of gen.moves) {
      this.moves[move.num - 1] = move.id;
    }
    if (gen.num === 1) {
      this.items = [];
    } else {
      this.items = IDS[gen.num - 1 as 1 | 2].items;
    }
    this.abilities = []; // TODO
  }

  typeByNum(num: number): TypeName {
    return this.typesByNum[num];
  }

  typeByName(name: TypeName): number {
    return this.typesByName[name];
  }

  specieByNum(num: number): ID {
    return this.species[num - 1];
  }

  specieByID(id: ID | undefined): number {
    return id ? this.gen.species.get(id)!.num : 0;
  }

  moveByNum(num: number): ID {
    return this.moves[num - 1];
  }

  moveByID(id: ID | undefined): number {
    return id ? this.gen.moves.get(id)!.num : 0;
  }

  itemByNum(num: number): ID {
    return this.items[num - 1];
  }

  itemByID(id: ID | undefined): number {
    return id ? this.gen.items.get(id)!.num : 0;
  }

  abilityByNum(num: number): ID {
    return this.abilities[num - 1];
  }

  abilityByID(id: ID | undefined): number {
    return id ? this.gen.abilities.get(id)!.num : 0;
  }
}
