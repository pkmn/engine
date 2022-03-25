import {
  BoostID,
  BoostsTable,
  Generation,
  ID,
  PokemonSet,
  SideID,
  StatID,
  StatsTable,
  StatusName,
  TypeName,
} from '@pkmn/data';

import {Gen1} from './index';
import {LAYOUT, LE, Lookup} from './data';

const SIZES = LAYOUT[0].sizes;
const OFFSETS = LAYOUT[0].offsets;

OFFSETS.Stats.spa = OFFSETS.Stats.spd = OFFSETS.Stats.spc;
OFFSETS.Boosts.spa = OFFSETS.Boosts.spd = OFFSETS.Boosts.spc;

export class Battle implements Gen1.Battle {
  private readonly lookup: Lookup;
  private readonly data: DataView;

  private readonly cache: [Side?, Side?];

  constructor(lookup: Lookup, data: DataView) {
    this.lookup = lookup;
    this.data = data;

    this.cache = [undefined, undefined];
  }

  get sides() {
    return this._sides();
  }

  *_sides() {
    yield this.side('p1');
    yield this.side('p2');
  }

  side(id: SideID): Side {
    const i = id === 'p1' ? 0 : 1;
    const side = this.cache[i];
    return side ?? (this.cache[i] =
        new Side(this.lookup, this.data, OFFSETS.Battle[id as 'p1' | 'p2']));
  }

  foe(side: SideID): Side {
    return this.side(side === 'p1' ? 'p2' : 'p1');
  }

  get turn(): number {
    return this.data.getUint16(OFFSETS.Battle.turn, LE);
  }

  get lastDamage(): number {
    return this.data.getUint16(OFFSETS.Battle.last_damage, LE);
  }

  get prng(): readonly number[] {
    return [0, 0, 0, 0]; // TODO
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    seed: number[],
    p1: PokemonSet[],
    p2: PokemonSet[]
  ) {
    const buf = new ArrayBuffer(SIZES.Battle);
    const data = new DataView(buf);
    Side.init(gen, lookup, p1, data, OFFSETS.Battle.p1);
    Side.init(gen, lookup, p2, data, OFFSETS.Battle.p2);
    const offset = OFFSETS.Battle.last_damage + 2;
    if (seed.length === 4) {
      data.setUint16(offset + 4, seed[LE ? 3 : 0], LE);
      data.setUint16(offset + 6, seed[LE ? 2 : 1], LE);
      data.setUint16(offset + 8, seed[LE ? 1 : 2], LE);
      data.setUint16(offset + 10, seed[LE ? 0 : 3], LE);
    } else {
      for (let o = offset; o < offset + 10; o++) {
        data.setUint8(o, seed[o]);
      }
    }
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    battle: Gen1.Battle,
  ) {
    // TODO
  }
}

export type Slot = 1 | 2 | 3 | 4 | 5 | 6;

export class Side implements Gen1.Side {
  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly offset: number;

  readonly cache: [Pokemon?, Pokemon?, Pokemon?, Pokemon?, Pokemon?, Pokemon?];

  constructor(lookup: Lookup, data: DataView, offset: number) {
    this.lookup = lookup;
    this.data = data;
    this.offset = offset;

    this.cache = [undefined, undefined, undefined, undefined, undefined, undefined];
  }

  get pokemon() {
    return this._pokemon();
  }

  *_pokemon() {
    for (let i = 1; i <= 6; i++) {
      yield this.get(i as Slot);
    }
  }

  get(slot: Slot): Pokemon {
    const id = this.data.getUint8(this.offset + OFFSETS.Side.order + slot - 1);
    const poke = this.cache[id];
    if (poke) return poke;
    const offset = this.offset + OFFSETS.Side.pokemon + OFFSETS.Side.pokemon * (id - 1);
    return (this.cache[id] = new Pokemon(this.lookup, this.data, offset));
  }

  get active(): ActivePokemon {
    const offset = this.offset + OFFSETS.Side.active;
    return new ActivePokemon(this.lookup, this.data, offset);
  }

  get stored(): Pokemon {
    return this.get(1);
  }

  get lastSelectedMove(): ID | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Side.last_selected_move);
    return m === 0 ? undefined : this.lookup.moveByNum(m);
  }

  get lastUsedMove(): ID | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Side.last_used_move);
    return m === 0 ? undefined : this.lookup.moveByNum(m);
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    team: PokemonSet[],
    data: DataView,
    offset: number
  ) {
    for (let i = 0; i < 6; i++) {
      const poke = team[i];
      const off = offset + OFFSETS.Side.pokemon * i;
      Pokemon.init(gen, lookup, poke, data, off);
      data.setUint8(offset + OFFSETS.Side.order + i, i + 1);
    }
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    battle: Gen1.Side,
    data: DataView,
    offset: number
  ) {
    // TODO
  }
}

export class ActivePokemon implements Gen1.ActivePokemon {
  static Volatiles = OFFSETS.Volatiles;

  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly offset: number;

  constructor(lookup: Lookup, data: DataView, offset: number) {
    this.lookup = lookup;
    this.data = data;
    this.offset = offset;
  }

  stat(stat: StatID): number {
    const off = this.offset + OFFSETS.ActivePokemon.stats + OFFSETS.Stats[stat];
    return this.data.getUint16(off, LE);
  }

  get stats(): StatsTable {
    const stats: Partial<StatsTable> = {};
    for (const s in OFFSETS.Stats) {
      if (s === 'spc') continue;
      const stat = s as StatID;
      stats[stat] = this.stat(stat);
    }
    return stats as StatsTable;
  }

  volatile(bit: number): boolean {
    const byte = this.data.getUint8(this.offset + OFFSETS.ActivePokemon.volatiles + (bit >> 3));
    return !!(byte & (1 << (bit & 7)));
  }

  get volatiles(): {[name: string]: number} {
    const volatiles: {[name: string]: number} = {};
    for (const volatile in ActivePokemon.Volatiles) {
      if (this.volatile(ActivePokemon.Volatiles[volatile])) {
        volatiles[volatile] = 0;
      }
    }
    // TODO disabled + data
    return volatiles;
  }

  move(slot: 1 | 2 | 3 | 4): {move: ID; pp: number; disabled: boolean} | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.ActivePokemon.moves + (slot - 1) << 1);
    if (m === 0) return undefined;
    const move = this.lookup.moveByNum(m);
    const pp = this.data.getUint8(this.offset + OFFSETS.ActivePokemon.moves + (slot << 1) - 1);
    const byte = this.data.getUint8(this.offset + OFFSETS.ActivePokemon.volatiles + 4);
    const disabled = (byte & 0x0F) === slot;
    return {move, pp, disabled};
  }

  get moves() {
    return this._moves();
  }

  *_moves() {
    for (let i = 1; i <= 4; i++) {
      const move = this.move(i as 1 | 2 | 3 | 4);
      if (!move) break;
      yield move;
    }
  }

  boost(boost: BoostID): number {
    const b = OFFSETS.Boosts[boost];
    const byte = this.data.getUint8(this.offset + OFFSETS.ActivePokemon.boosts + (b >> 3));
    const val = byte & ((b & 7) ? 0xF0 : 0x0F);
    return (val > 7) ? -(val & 7) : val;
  }

  get boosts(): BoostsTable {
    const boosts: Partial<BoostsTable> = {};
    for (const b in OFFSETS.Stats) {
      if (b === 'spc') continue;
      const boost = b as BoostID;
      boosts[boost] = this.boost(boost);
    }
    return boosts as BoostsTable;
  }

  get species(): ID {
    return this.lookup.specieByNum(
      this.data.getUint8(this.offset + OFFSETS.ActivePokemon.species)
    );
  }

  get types(): readonly [TypeName, TypeName] {
    return decodeTypes(this.lookup, this.data.getUint8(this.offset + OFFSETS.ActivePokemon.types));
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    battle: Gen1.ActivePokemon,
    data: DataView,
    offset: number
  ) {
    // TODO
  }
}

export class Pokemon implements Gen1.Pokemon {
  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly offset: number;

  constructor(lookup: Lookup, data: DataView, offset: number) {
    this.lookup = lookup;
    this.data = data;
    this.offset = offset;
  }

  stat(stat: StatID): number {
    return this.data.getUint16(this.offset + OFFSETS.Pokemon.stats + OFFSETS.Stats[stat], LE);
  }

  get stats(): StatsTable {
    const stats: Partial<StatsTable> = {};
    for (const s in OFFSETS.Stats) {
      if (s === 'spc') continue;
      const stat = s as StatID;
      stats[stat] = this.stat(stat);
    }
    return stats as StatsTable;
  }

  move(slot: 1 | 2 | 3 | 4): {move: ID; pp: number} | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Pokemon.moves + (slot - 1) << 1);
    if (m === 0) return undefined;
    const move = this.lookup.moveByNum(m);
    const pp = this.data.getUint8(this.offset + OFFSETS.Pokemon.moves + (slot << 1) - 1);
    return {move, pp};
  }

  get moves() {
    return this._moves();
  }

  *_moves() {
    for (let i = 1; i <= 4; i++) {
      const move = this.move(i as 1 | 2 | 3 | 4);
      if (!move) break;
      yield move;
    }
  }

  get hp(): number {
    return this.data.getUint16(this.offset + OFFSETS.Pokemon.hp, LE);
  }

  get status(): StatusName | undefined {
    const val = this.data.getUint8(this.offset + OFFSETS.Pokemon.status);
    if ((val >> 3) & 1) return 'psn';
    if ((val >> 4) & 1) return 'brn';
    if ((val >> 5) & 1) return 'frz';
    if ((val >> 6) & 1) return 'par';
    return val > 0 ? 'slp' : undefined;
  }

  get species(): ID {
    return this.lookup.specieByNum(this.data.getUint8(this.offset + OFFSETS.Pokemon.species));
  }

  get types(): readonly [TypeName, TypeName] {
    return decodeTypes(this.lookup, this.data.getUint8(this.offset + OFFSETS.Pokemon.types));
  }

  get level(): number {
    return this.data.getUint8(this.offset + OFFSETS.Pokemon.level);
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    set: PokemonSet,
    data: DataView,
    offset: number
  ) {
    const species = gen.species.get(set.species)!;

    let hp = 0;
    let off = offset + OFFSETS.Pokemon.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      const val =
        gen.stats.calc(stat, species.baseStats[stat], set.ivs[stat], set.evs[stat], set.level);
      data.setUint16(off, val, LE);
      if (stat === 'hp') hp = val;
      off += 2;
    }

    off = offset + OFFSETS.Pokemon.moves;
    for (const m of set.moves) {
      const move = gen.moves.get(m)!;
      data.setUint8(off++, move.num);
      data.setUint8(off++, move.pp);
    }

    data.setUint16(offset + OFFSETS.Pokemon.hp, hp, LE);
    data.setUint8(offset + OFFSETS.Pokemon.species, species.num);

    const type1 = species.types[0];
    const type2 = species.types[1] ?? type1;
    const types = lookup.typeByName(type1) << 3 | lookup.typeByName(type2);
    data.setUint8(offset + OFFSETS.Pokemon.types, types);

    data.setUint8(offset + OFFSETS.Pokemon.level, set.level);
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    battle: Gen1.Pokemon,
    data: DataView,
    offset: number
  ) {
    // TODO
  }
}

function decodeTypes(lookup: Lookup, val: number): readonly [TypeName, TypeName] {
  return [lookup.typeByNum(val & 0x0F), lookup.typeByNum(val >> 4)];
}
