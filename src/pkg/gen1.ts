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

import {Gen1, Names, ParsedLine} from './index';
import {LAYOUT, LE, Lookup, PROTOCOL} from './data';
import {Protocol} from '@pkmn/protocol';

const ArgType = PROTOCOL.ArgType;

const SIZES = LAYOUT[0].sizes;
const OFFSETS = LAYOUT[0].offsets;

OFFSETS.Stats.spa = OFFSETS.Stats.spd = OFFSETS.Stats.spc;
OFFSETS.Boosts.spa = OFFSETS.Boosts.spd = OFFSETS.Boosts.spc;

export class Battle implements Gen1.Battle {
  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly showdown: boolean;

  private readonly cache: [Side?, Side?];

  constructor(lookup: Lookup, data: DataView, showdown: boolean) {
    this.lookup = lookup;
    this.data = data;
    this.showdown = showdown;

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
    const offset = OFFSETS.Battle.last_damage + 2 + (this.showdown ? 4 : 1);
    const seed: number[] = [0, 0, 0, 0];
    if (this.showdown) {
      seed[LE ? 3 : 0] = this.data.getUint16(offset, LE);
      seed[LE ? 2 : 1] = this.data.getUint16(offset + 2, LE);
      seed[LE ? 1 : 2] = this.data.getUint16(offset + 4, LE);
      seed[LE ? 0 : 3] = this.data.getUint16(offset + 6, LE);
    } else {
      // Gen12RNG seed requires an index, but if we always rotate the seed based on the index when
      // reading we can avoid tracking the index as it will always be zero. NB: the exact bits of
      // the Battle will not roundtrip, but the *logical* Battle state will.
      const index = this.data.getUint8(offset + 11);
      for (let i = 0; i < 10; i++) {
        const j = i - index;
        seed[j < 0 ? j + 10 : j] = this.data.getUint8(offset + i);
      }
    }
    return seed;
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
    encodePRNG(data, seed);
    return buf;
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    battle: Gen1.Battle,
  ) {
    const buf = new ArrayBuffer(SIZES.Battle);
    const data = new DataView(buf);
    let offset = OFFSETS.Battle.p1;
    for (const side of battle.sides) {
      Side.encode(gen, lookup, side, data, offset);
      offset += SIZES.Side;
    }
    data.setUint16(OFFSETS.Battle.turn, battle.turn, LE);
    data.setUint16(OFFSETS.Battle.last_damage, battle.lastDamage, LE);
    encodePRNG(data, battle.prng);
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
    return (this.cache[id] = new Pokemon(this.lookup, this.data, this.offset, id - 1));
  }

  get active(): Pokemon {
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
      // Pokemon.init(gen, lookup, poke, data, offset, i);
      data.setUint8(offset + OFFSETS.Side.order + i, i + 1);
    }
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    side: Gen1.Side,
    data: DataView,
    offset: number
  ) {
    let i = 0;
    for (const pokemon of side.pokemon) {
      Pokemon.encode(gen, lookup, pokemon, data, offset, i);
      data.setUint8(offset + OFFSETS.Side.order + i, i + 1);
      i++;
    }
    data.setUint8(offset + OFFSETS.Side.last_selected_move,
      lookup.moveByID(side.lastSelectedMove));
    data.setUint8(offset + OFFSETS.Side.last_used_move,
      lookup.moveByID(side.lastUsedMove));
  }
}

const BOOSTS = {atk: 0, def: 0, spe: 0, spa: 0, spd: 0, accuracy: 0, evasion: 0};

export class Pokemon implements Gen1.Pokemon {
  static Volatiles = OFFSETS.Volatiles;

  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly offset: {order: number; active: number; stored: number};
  private readonly index: number;

  readonly stored: StoredPokemon;

  constructor(lookup: Lookup, data: DataView, offset: number, index: number) {
    this.lookup = lookup;
    this.data = data;
    this.offset = {
      order: offset + OFFSETS.Side.order,
      active: offset + OFFSETS.Pokemon.active,
      stored: offset + OFFSETS.Pokemon.stored + SIZES.Pokemon * index,
    };
    this.index = index;
    this.stored = new StoredPokemon(this.lookup, this.data, this.offset.stored);
  }

  active(): boolean {
    return this.index === this.data.getUint8(this.offset.order);
  }

  stat(stat: StatID): number {
    if (!this.active) return this.stored.stat(stat);

    const off = this.offset.active + OFFSETS.ActivePokemon.stats + OFFSETS.Stats[stat];
    return this.data.getUint16(off, LE);
  }

  get stats(): StatsTable {
    if (!this.active) return this.stored.stats;

    const stats: Partial<StatsTable> = {};
    for (const s in OFFSETS.Stats) {
      if (s === 'spc') continue;
      const stat = s as StatID;
      stats[stat] = this.stat(stat);
    }
    return stats as StatsTable;
  }

  volatile(bit: number): boolean {
    if (!this.active) return false;

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles + (bit >> 3);
    const byte = this.data.getUint8(off);
    return !!(byte & (1 << (bit & 7)));
  }

  get volatiles(): {[name: string]: Gen1.Volatile} {
    if (!this.active) return {};

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles + OFFSETS.Volatiles.data;
    const volatiles: {[name: string]: Gen1.Volatile} = {};
    for (const volatile in Pokemon.Volatiles) {
      if (this.volatile(Pokemon.Volatiles[volatile])) {
        const data: Gen1.Volatile = {};
        if (volatile === 'Bide') {
          data.damage = this.data.getUint16(off + OFFSETS.VolatilesData.state, LE);
        } else if (volatile === 'Trapping') {
          data.duration = this.data.getUint8(off + OFFSETS.VolatilesData.attacks >> 3);
        } else if (volatile === 'Thrashing' || volatile === 'Rage') {
          data.duration = this.data.getUint8(off + OFFSETS.VolatilesData.attacks >> 3);
          data.accuracy = this.data.getUint16(off + OFFSETS.VolatilesData.state, LE);
        } else if (volatile === 'Confusion') {
          data.duration = this.data.getUint8(off + OFFSETS.VolatilesData.confusion >> 3) & 0x0F;
        } else if (volatile === 'Substitute') {
          data.damage = this.data.getUint8(off + OFFSETS.VolatilesData.substitute >> 3);
        }
        volatiles[volatile] = data;
      }
    }
    return volatiles;
  }

  move(slot: 1 | 2 | 3 | 4): Gen1.MoveSlot | undefined {
    if (!this.active) return this.stored.move(slot);

    const off = this.offset.active + OFFSETS.ActivePokemon.moves;
    const m = this.data.getUint8(off + (slot - 1) << 1);
    if (m === 0) return undefined;
    const move = this.lookup.moveByNum(m);
    const pp = this.data.getUint8(off + (slot << 1) - 1);
    const byte = this.data.getUint8(this.offset.active +
      OFFSETS.ActivePokemon.volatiles +
      OFFSETS.Volatiles.data +
      OFFSETS.VolatilesData.disabled >> 3);
    const disabled = ((byte & 0x0F) === slot) ? byte >> 4 : undefined;
    return {move, pp, disabled};
  }

  get moves() {
    if (!this.active) return this.stored.moves;

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
    if (!this.active) return 0;

    const b = OFFSETS.Boosts[boost];
    const byte = this.data.getUint8(this.offset.active + OFFSETS.ActivePokemon.boosts + (b >> 3));
    const val = byte & ((b & 7) ? 0xF0 : 0x0F);
    return (val > 7) ? -(val & 7) : val;
  }

  get boosts(): BoostsTable {
    if (!this.active) return BOOSTS;

    const boosts: Partial<BoostsTable> = {};
    for (const b in OFFSETS.Stats) {
      if (b === 'spc') continue;
      const boost = b as BoostID;
      boosts[boost] = this.boost(boost);
    }
    return boosts as BoostsTable;
  }

  get species(): ID {
    if (!this.active) return this.stored.species;

    const off = this.offset.active + OFFSETS.ActivePokemon.species;
    return this.lookup.specieByNum(this.data.getUint8(off));
  }

  get types(): readonly [TypeName, TypeName] {
    if (!this.active) return this.types;

    const off = this.offset.active + OFFSETS.ActivePokemon.types;
    return decodeTypes(this.lookup, this.data.getUint8(off));
  }

  get level(): number {
    return this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.level);
  }

  get hp(): number {
    return this.data.getUint16(this.offset.stored + OFFSETS.Pokemon.hp, LE);
  }

  get status(): StatusName| undefined {
    const val = this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.status);
    if ((val >> 3) & 1) return this.toxic ? 'tox' : 'psn';
    if ((val >> 4) & 1) return 'brn';
    if ((val >> 5) & 1) return 'frz';
    if ((val >> 6) & 1) return 'par';
    return val > 0 ? 'slp' : undefined;
  }

  get statusData(): { sleep: number; toxic: number } {
    return {sleep: this.sleep, toxic: this.toxic};
  }

  private get sleep(): number {
    const val = this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.status);
    return val <= 7 ? val : 0;
  }

  private get toxic(): number {
    if (!this.active) return 0;

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles + OFFSETS.Volatiles.data;
    return this.data.getUint8(off + OFFSETS.VolatilesData.toxic >> 3) >> 4;
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    active: Gen1.Pokemon,
    data: DataView,
    offset: number,
    index: number,
  ) {
    let off = offset + OFFSETS.ActivePokemon.stats;
    const stats = active.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      data.setUint16(off, stats[stat], LE);
      off += 2;
    }

    off = offset + OFFSETS.ActivePokemon.volatiles;
    const volatiles = active.volatiles;
    const state = volatiles.Bide?.damage ??
      volatiles.Thrashing?.accuracy ??
      volatiles.Rage?.accuracy ?? 0;
    data.setUint16(off + OFFSETS.VolatilesData.state, state, LE);
    data.setUint8(off + OFFSETS.VolatilesData.substitute >> 3, volatiles.Substitute.hp ?? 0);
    const confusion = volatiles.Confusion?.duration ?? 0;
    // XXX data.setUint8(off + OFFSETS.VolatilesData.confusion >> 3, confusion << 4 | active.toxic);
    const attacks = volatiles.Trapping?.duration ??
      volatiles.Thrashing?.duration ??
      volatiles.Rage?.duration ?? 0;
    data.setUint8(off + OFFSETS.VolatilesData.attacks >> 3, attacks);


    off = offset + OFFSETS.ActivePokemon.moves;
    let slot = 1;
    for (const ms of active.moves) {
      data.setUint8(off++, lookup.moveByID(ms.move));
      data.setUint8(off++, ms.pp);
      if (ms.disabled !== undefined) {
        data.setUint8(offset +
          OFFSETS.ActivePokemon.volatiles +
          OFFSETS.Volatiles.data +
          OFFSETS.VolatilesData.disabled >> 3, slot << 3 | ms.disabled);
      }
      slot++;
    }

    off = offset + OFFSETS.ActivePokemon.boosts;
    const boosts = active.boosts;
    data.setUint8(off++, boosts.atk << 4 | boosts.def);
    data.setUint8(off++, boosts.spe << 4 | boosts.spa);
    data.setUint8(off++, boosts.accuracy << 4 | boosts.evasion);

    data.setUint8(offset + OFFSETS.Pokemon.species, lookup.specieByID(active.species));
    data.setUint8(offset + OFFSETS.Pokemon.types, encodeTypes(lookup, active.types));
  }
}

export class StoredPokemon {
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

  get species(): ID {
    return this.lookup.specieByNum(this.data.getUint8(this.offset + OFFSETS.Pokemon.species));
  }

  get types(): readonly [TypeName, TypeName] {
    return decodeTypes(this.lookup, this.data.getUint8(this.offset + OFFSETS.Pokemon.types));
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    set: PokemonSet,
    data: DataView,
    offset: number
  ) {
    const species = gen.species.get(set.species)!;

    // let hp = 0;
    let off = offset + OFFSETS.Pokemon.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      const val =
        gen.stats.calc(stat, species.baseStats[stat], set.ivs[stat], set.evs[stat], set.level);
      data.setUint16(off, val, LE);
      // if (stat === 'hp') hp = val;
      off += 2;
    }

    off = offset + OFFSETS.Pokemon.moves;
    for (const m of set.moves) {
      const move = gen.moves.get(m)!;
      data.setUint8(off++, move.num);
      data.setUint8(off++, move.pp);
    }

    // data.setUint16(offset + OFFSETS.Pokemon.hp, hp, LE);

    data.setUint8(offset + OFFSETS.Pokemon.species, species.num);
    data.setUint8(offset + OFFSETS.Pokemon.types, encodeTypes(lookup, species.types));
    // data.setUint8(offset + OFFSETS.Pokemon.level, set.level);
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    stored: Gen1.Pokemon['stored'],
    data: DataView,
    offset: number
  ) {
    let off = offset + OFFSETS.Pokemon.stats;
    const stats = stored.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      data.setUint16(off, stats[stat], LE);
      off += 2;
    }

    off = offset + OFFSETS.Pokemon.moves;
    for (const ms of stored.moves) {
      data.setUint8(off++, lookup.moveByID(ms.move));
      data.setUint8(off++, ms.pp);
    }

    // data.setUint16(offset + OFFSETS.Pokemon.hp, pokemon.hp, LE);

    const species = gen.species.get(stored.species)!;

    data.setUint8(offset + OFFSETS.Pokemon.species, species.num);
    data.setUint8(offset + OFFSETS.Pokemon.types, encodeTypes(lookup, species.types));
    // data.setUint8(offset + OFFSETS.Pokemon.level, pokemon.level);
  }
}

function encodePRNG(data: DataView, seed: readonly number[]) {
  const offset = OFFSETS.Battle.last_damage + 2 + (seed.length === 4 ? 4 : 1);
  if (seed.length === 4) {
    data.setUint16(offset, seed[LE ? 3 : 0], LE);
    data.setUint16(offset + 2, seed[LE ? 2 : 1], LE);
    data.setUint16(offset + 4, seed[LE ? 1 : 2], LE);
    data.setUint16(offset + 6, seed[LE ? 0 : 3], LE);
  } else {
    for (let o = offset; o < offset + 10; o++) {
      data.setUint8(o, seed[o]);
    }
    // NB: ArrayBuffer is zero initialized already so we don't need to set the index to zero
  }
}

function encodeTypes(lookup: Lookup, types: Readonly<[TypeName] | [TypeName, TypeName]>): number {
  return lookup.typeByName(types[0]) << 3 | lookup.typeByName(types[1] ?? types[0]);
}

function decodeTypes(lookup: Lookup, val: number): readonly [TypeName, TypeName] {
  return [lookup.typeByNum(val & 0x0F), lookup.typeByNum(val >> 4)];
}

export const Log = new class {
  *parse(data: DataView, names: Names): Iterable<ParsedLine> {
    const lines: ParsedLine[] = [];
    for (let i = 0; i < data.byteLength;) {
      const byte = data.getUint8(i++);
      if (!byte) {
        for (const line of lines) yield line;
        return;
      }
      if (byte === ArgType.LastMiss) {
        (lines[0].kwargs as Writeable<Protocol.BattleArgsKWArgs['|move|']>).miss = true;
      } else if (byte === ArgType.LastStill) {
        (lines[0].kwargs as Writeable<Protocol.BattleArgsKWArgs['|move|']>).still = true;
      } else {
        const decoded = DECODERS[byte]?.(i, data, names);
        if (!decoded) throw new Error(`Expected arg at offset ${i} but found ${byte}`);
        i += decoded.offset;
        if (byte === ArgType.Move) {
          for (const line of lines) yield line;
        } else if (!lines.length) {
          yield decoded.line;
          continue;
        }
        lines.push(decoded.line);
      }
    }
  }
};

type Writeable<T> = { -readonly [P in keyof T]: T[P] };
type Decoder = (offset: number, data: DataView, names: Names) => {offset: number; line: ParsedLine};

const TODO: ParsedLine = {args: ['-ohko'], kwargs: {}};

export const DECODERS: {[key: number]: Decoder} = {
  [ArgType.Move]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Switch]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Cant]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Faint]: (offset, data, names) => decodeType('fainted', offset, data, names),
  [ArgType.Turn]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Win]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Tie]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Damage]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Heal]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Status]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.CureStatus]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Boost]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Unboost]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.ClearAllBoost]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Fail]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Miss]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.HitCount]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Prepare]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.MustRecharge]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Activate]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.FieldActivate]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.Start]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.End]: (offset, data, names) => ({offset, line: TODO}),
  [ArgType.OHKO]: (offset) => {
    const line = {args: ['-ohko'] as Protocol.Args['|-ohko|'], kwargs: {}};
    return {offset, line};
  },
  [ArgType.Crit]: (offset, data, names) => decodeType('-crit', offset, data, names),
  [ArgType.SuperEffective]: (offset, data, names) =>
    decodeType('-supereffective', offset, data, names),
  [ArgType.Resisted]: (offset, data, names) => decodeType('-resisted', offset, data, names),
  [ArgType.Immune]: (offset, data, names) => decodeType('-immune', offset, data, names),
  [ArgType.Transform]: (offset, data, names) => {
    const source = ident(names, data.getUint8(offset++));
    const target = ident(names, data.getUint8(offset++));
    const line = {
      args: ['-transform', source, target] as Protocol.Args['|-transform|'],
      kwargs: {},
    };
    return {offset, line};
  },
};

function decodeType(type: string, offset: number, data: DataView, names: Names) {
  const foo = ident(names, data.getUint8(offset++));
  const line = {
    args: [type, foo] as Protocol.BattleArgType,
    kwargs: {},
  };
  return {offset, line};
}

function ident(names: Names, byte: number): Protocol.PokemonIdent {
  const player = (byte >> 4) === 0 ? 'p1' : 'p2';
  const slot = byte & 0x0F;
  return `${player}a: ${names[player].team[slot - 1]}` as Protocol.PokemonIdent;
}
