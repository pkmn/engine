import {Generation, ID, TypeName} from '@pkmn/data';

import idsJSON from './data/ids.json';
import offsetsJSON from './data/layout.json';
import protocolJSON from './data/protocol.json';

export const LE = (() => {
  const u8 = new Uint8Array(4);
  const u16 = new Uint16Array(u8.buffer);
  return !!((u16[0] = 1) & u16[0]);
})();

export type IDs = [
  {types: Exclude<TypeName, 'Dark' | 'Steel' | 'Fairy' | 'Stellar'>[]},
  {items: ID[]; types: Exclude<TypeName, 'Fairy' | 'Stellar'>[]},
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

export const Data = new class {
  view(buf: number[] | Buffer): DataView {
    buf = Array.isArray(buf) ? Buffer.from(buf) : buf;
    return new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  }
};

const LOOKUPS: Lookup[] = [];

/**
 * Translation table for encoding/decoding Pokémon Showdown string identifiers
 * to the identifiers used internally by the pkmn engine.
 */
export class Lookup {
  private readonly gen: Generation;
  private readonly typesByNum: TypeName[];
  private readonly typesByName: {[key in TypeName]: number};
  private readonly species: ID[];
  private readonly moves: ID[];
  private readonly itemsByNum: ID[];
  private readonly itemsByID: {[id: string]: number};

  /** Returns a `Lookup` table for a given generation. */
  static get(gen: Generation) {
    if (gen.num > 2) throw new Error(`Unsupported gen ${gen.num}`);
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
      this.itemsByNum = [];
      this.itemsByID = {};
    } else {
      this.itemsByNum = IDS[gen.num - 1 as 1].items;
      this.itemsByID = {} as {[id: string]: number};
      for (let i = 0; i < this.itemsByNum.length; i++) {
        if (this.itemsByNum[i] === 'flowermail') {
          this.itemsByNum[i] = 'mail' as ID;
        }
        this.itemsByID[this.itemsByNum[i]] = i;
      }
    }
  }

  /**
   * Returns the respective sizes of the various data types in the lookup table.
   */
  get sizes() {
    return {
      types: this.typesByNum.length,
      species: this.species.length,
      moves: this.moves.length,
      items: this.itemsByNum.length,
    };
  }

  /**
   * Decodes the Pokémon Showdown `TypeName` for a type corresponding to the
   * identifying `num` returned by the engine.
   */
  typeByNum(num: number): TypeName {
    return this.typesByNum[num];
  }

  /**
   * Encodes a `TypeName` to the number used as an identifier by the engine.
   */
  typeByName(name: TypeName): number {
    return this.typesByName[name];
  }

  /**
   * Decodes the Pokémon Showdown `ID` for a species corresponding to the
   * identifying `num` returned by the engine.
   */
  speciesByNum(num: number): ID {
    return this.species[num - 1];
  }

  /**
   * Encodes a species `ID` to the number used as an identifier by the engine.
   */
  speciesByID(id: ID | undefined): number {
    return id ? this.gen.species.get(id)!.num : 0;
  }

  /**
   * Decodes the Pokémon Showdown `ID` for a move corresponding to the
   * identifying `num` returned by the engine.
   */
  moveByNum(num: number): ID {
    return this.moves[num - 1];
  }

  /**
   * Encodes a move `ID` to the number used as an identifier by the engine.
   */
  moveByID(id: ID | undefined): number {
    return id ? this.gen.moves.get(id)!.num : 0;
  }

  /**
   * Decodes the Pokémon Showdown `ID` for an item corresponding to the
   * identifying `num` returned by the engine.
   */
  itemByNum(num: number): ID {
    return this.itemsByNum[num - 1];
  }

  /**
   * Encodes an item `ID` to the number used as an identifier by the engine.
   */
  itemByID(id: ID | undefined): number {
    return id ? this.itemsByID[id] + 1 : 0;
  }
}
