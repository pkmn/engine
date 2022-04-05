import {
  BoostID,
  BoostsTable,
  Generation,
  ID,
  toID,
  PokemonSet,
  SideID,
  StatID,
  StatsTable,
  StatusName,
  TypeName,
} from '@pkmn/data';

import {Gen1, Slot, BattleOptions, CreateOptions, RestoreOptions} from './index';
import {LAYOUT, LE, Lookup} from './data';
import {decodeStatus, decodeTypes} from './protocol';

const SIZES = LAYOUT[0].sizes;
const OFFSETS = LAYOUT[0].offsets;

OFFSETS.Stats.spa = OFFSETS.Stats.spd = OFFSETS.Stats.spc;
OFFSETS.Boosts.spa = OFFSETS.Boosts.spd = OFFSETS.Boosts.spc;

export class Battle implements Gen1.Battle {
  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly options: BattleOptions;

  private readonly cache: [Side?, Side?];

  constructor(lookup: Lookup, data: DataView, options: BattleOptions) {
    this.lookup = lookup;
    this.data = data;
    this.options = options;

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

  toJSON(): Gen1.Battle {
    return {
      sides: Array.from(this.sides).map(s => s.toJSON()),
      turn: this.turn,
      lastDamage: this.lastDamage,
      prng: this.prng,
    };
  }

  get prng(): readonly number[] {
    const offset = OFFSETS.Battle.last_damage + 2 + (this.options.showdown ? 4 : 1);
    const seed: number[] = [0, 0, 0, 0];
    if (this.options.showdown) {
      seed[LE ? 3 : 0] = this.data.getUint16(offset, LE);
      seed[LE ? 2 : 1] = this.data.getUint16(offset + 2, LE);
      seed[LE ? 1 : 2] = this.data.getUint16(offset + 4, LE);
      seed[LE ? 0 : 3] = this.data.getUint16(offset + 6, LE);
    } else {
      // Gen12RNG seed requires an index, but if we always rotate the seed based on the index when
      // reading we can avoid tracking the index as it will always be zero. NB: the exact bits of
      // the Battle will not roundtrip, but the *logical* Battle state will.
      const index = this.data.getUint8(offset + 10);
      for (let i = 0; i < 10; i++) {
        const j = i - index;
        seed[j < 0 ? j + 10 : j] = this.data.getUint8(offset + i);
      }
    }
    return seed;
  }

  static create(
    gen: Generation,
    lookup: Lookup,
    options: CreateOptions,
  ) {
    const buf = new ArrayBuffer(SIZES.Battle);
    const data = new DataView(buf);
    Side.init(gen, lookup, options.p1.team, data, OFFSETS.Battle.p1);
    Side.init(gen, lookup, options.p2.team, data, OFFSETS.Battle.p2);
    encodePRNG(data, options.seed);
    return new Battle(lookup, new DataView(buf), options);
  }

  static restore(
    gen: Generation,
    lookup: Lookup,
    battle: Gen1.Battle,
    options: RestoreOptions,
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
    return new Battle(lookup, new DataView(buf), options);
  }
}

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

  get active(): Pokemon | undefined {
    return started(this.data) ? this.get(1) : undefined;
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
    const id = this.data.getUint8(this.offset + OFFSETS.Side.order + slot - 1) - 1;
    const poke = this.cache[id];
    if (poke) return poke;
    return (this.cache[id] = new Pokemon(this.lookup, this.data, this.offset, id));
  }

  get lastSelectedMove(): ID | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Side.last_selected_move);
    return m === 0 ? undefined : this.lookup.moveByNum(m);
  }

  get lastUsedMove(): ID | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Side.last_used_move);
    return m === 0 ? undefined : this.lookup.moveByNum(m);
  }

  toJSON(): Gen1.Side {
    return {
      active: this.active,
      pokemon: Array.from(this.pokemon).map(p => p.toJSON()),
      lastSelectedMove: this.lastSelectedMove,
      lastUsedMove: this.lastUsedMove,
    };
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
      Pokemon.init(gen, lookup, poke, data, offset, i);
      data.setUint8(offset + OFFSETS.Side.order + i, i + 1);
    }
  }

  static encode(
    gen: Generation,
    lookup: Lookup,
    side: Gen1.Side,
    data: DataView,
    offset: number,
  ) {
    let i = 0;
    for (const pokemon of side.pokemon) {
      const off = offset + OFFSETS.Side.pokemon + SIZES.Pokemon * i;
      Pokemon.encodeStored(gen, lookup, pokemon, data, off);
      data.setUint8(offset + OFFSETS.Side.order + i, pokemon.position);
      i++;
    }
    Pokemon.encodeActive(gen, lookup, side.active, data, offset + OFFSETS.Side.active);
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
      active: offset + OFFSETS.Side.active,
      stored: offset + OFFSETS.Side.pokemon + SIZES.Pokemon * index,
    };
    this.index = index;
    this.stored = new StoredPokemon(this.lookup, this.data, this.offset.stored);
  }

  get position(): Slot {
    return this.index + 1 as Slot;
  }

  get active(): boolean {
    return started(this.data) && this.index === this.data.getUint8(this.offset.order);
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

  get volatiles(): Gen1.Volatiles {
    if (!this.active) return {};

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles + OFFSETS.Volatiles.data;
    const volatiles: Gen1.Volatiles = {};
    for (const v in Pokemon.Volatiles) {
      if (v === 'data') continue;
      const volatile = toID(v) as keyof Gen1.Volatiles;
      if (this.volatile(Pokemon.Volatiles[volatile])) {
        if (volatile === 'bide') {
          volatiles[volatile] = {
            damage: this.data.getUint16(off + OFFSETS.VolatilesData.state, LE),
          };
        } else if (volatile === 'trapping') {
          volatiles[volatile] = {
            duration: this.data.getUint8(off + OFFSETS.VolatilesData.attacks >> 3),
          };
        } else if (volatile === 'thrashing' || volatile === 'rage') {
          volatiles[volatile] = {
            duration: this.data.getUint8(off + OFFSETS.VolatilesData.attacks >> 3),
            accuracy: this.data.getUint16(off + OFFSETS.VolatilesData.state, LE),
          };
        } else if (volatile === 'confusion') {
          volatiles[volatile] = {
            duration: this.data.getUint8(off + OFFSETS.VolatilesData.confusion >> 3) & 0x0F,
          };
        } else if (volatile === 'substitute') {
          volatiles[volatile] = {
            hp: this.data.getUint8(off + OFFSETS.VolatilesData.substitute >> 3),
          };
        } else {
          volatiles[volatile] = {};
        }
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
    const status = decodeStatus(this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.status));
    return status === 'psn' && this.toxic ? 'tox' : status;
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
    return this.data.getUint8(off + (OFFSETS.VolatilesData.toxic >> 3)) >> 4;
  }

  toJSON(): Gen1.Pokemon {
    return {
      species: this.species,
      types: this.types,
      level: this.level,
      hp: this.hp,
      status: this.status,
      statusData: this.statusData,
      stats: this.stats,
      boosts: this.boosts,
      moves: Array.from(this.moves),
      volatiles: this.volatiles,
      stored: this.stored.toJSON(),
      position: this.position,
    }
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    set: PokemonSet,
    data: DataView,
    offset: number,
    index: number,
  ) {
    const stored = offset + OFFSETS.Pokemon.stored + SIZES.Pokemon * index;
    const species = gen.species.get(set.species)!;

    let hp = 0;
    let off = stored + OFFSETS.Pokemon.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      const val =
         gen.stats.calc(stat, species.baseStats[stat], set.ivs[stat], set.evs[stat], set.level);
      data.setUint16(off, val, LE);
      if (stat === 'hp') hp = val;
      off += 2;
    }

    off = stored + OFFSETS.Pokemon.moves;
    for (const m of set.moves) {
      const move = gen.moves.get(m)!;
      data.setUint8(off++, move.num);
      data.setUint8(off++, move.pp);
    }

    data.setUint16(stored + OFFSETS.Pokemon.hp, hp, LE);

    data.setUint8(stored + OFFSETS.Pokemon.species, species.num);
    data.setUint8(stored + OFFSETS.Pokemon.types, encodeTypes(lookup, species.types));
    data.setUint8(stored + OFFSETS.Pokemon.level, set.level);
  }

  static encodeStored(
    gen: Generation,
    lookup: Lookup,
    pokemon: Gen1.Pokemon,
    data: DataView,
    offset: number,
  ) {
    let off = 0;
    const stats = pokemon.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      data.setUint16(offset + OFFSETS.Pokemon.stats + off, stats[stat], LE);
      off += 2;
    }

    off = offset + OFFSETS.Pokemon.moves;
    for (const ms of pokemon.stored.moves) {
      data.setUint8(off++, lookup.moveByID(ms.move));
      data.setUint8(off++, ms.pp);
    }

    data.setUint16(offset + OFFSETS.Pokemon.hp, pokemon.hp, LE);

    const species = gen.species.get(pokemon.stored.species)!;
    data.setUint8(offset + OFFSETS.Pokemon.species, species.num);
    data.setUint8(offset + OFFSETS.Pokemon.types, encodeTypes(lookup, species.types));
    data.setUint8(offset + OFFSETS.Pokemon.level, pokemon.level);
    data.setUint8(offset + OFFSETS.Pokemon.status, encodeStatus(pokemon));
  }

  static encodeActive(
    gen: Generation,
    lookup: Lookup,
    pokemon: Gen1.Pokemon | undefined,
    data: DataView,
    offset: number,
  ) {
    if (!pokemon) return;

    let off = 0;
    const stats = pokemon.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      data.setUint16(offset + OFFSETS.ActivePokemon.stats + off, stats[stat], LE);
      off += 2;
    }

    off = offset + OFFSETS.ActivePokemon.moves;
    let slot = 1;
    for (const ms of pokemon.moves) {
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

    off = offset + OFFSETS.ActivePokemon.volatiles;
    const volatiles = pokemon.volatiles;
    const state = volatiles.bide?.damage ??
      volatiles.thrashing?.accuracy ??
      volatiles.rage?.accuracy ?? 0;
    data.setUint16(off + OFFSETS.VolatilesData.state, state, LE);
    data.setUint8(off + OFFSETS.VolatilesData.substitute >> 3, volatiles.substitute?.hp ?? 0);
    const confusion = volatiles.confusion?.duration ?? 0;
    data.setUint8(off + OFFSETS.VolatilesData.confusion >> 3, confusion << 4 |
      (pokemon.statusData.toxic ?? 0));
    const attacks = volatiles.trapping?.duration ??
      volatiles.thrashing?.duration ??
      volatiles.rage?.duration ?? 0;
    data.setUint8(off + OFFSETS.VolatilesData.attacks >> 3, attacks);

    data.setUint8(off + (Pokemon.Volatiles.Bide >> 3),
      +!!volatiles.bide | +!!volatiles.thrashing << 1 |
       +!!volatiles.multihit << 2 || +!!volatiles.flinch << 3 |
       +!!volatiles.charging << 4 | +!!volatiles.trapping << 5 |
       +!!volatiles.invulnerable << 6 | +!!volatiles.confusion << 7);
    data.setUint8(off + (Pokemon.Volatiles.Mist >> 3),
      +!!volatiles.mist | +!!volatiles.focusenergy << 1 |
       +!!volatiles.substitute << 2 || +!!volatiles.recharging << 3 |
       +!!volatiles.rage << 4 | +!!volatiles.leechseed << 5 |
       +!!volatiles.toxic << 6 | +!!volatiles.lightscreen << 7);
    data.setUint8(off + (Pokemon.Volatiles.Reflect >> 3),
      +!!volatiles.reflect | +!!volatiles.transform << 1);

    off = offset + OFFSETS.ActivePokemon.boosts;
    const boosts = pokemon.boosts;
    data.setUint8(off++, boosts.atk << 4 | boosts.def);
    data.setUint8(off++, boosts.spe << 4 | boosts.spa);
    data.setUint8(off++, boosts.accuracy << 4 | boosts.evasion);

    data.setUint8(offset + OFFSETS.ActivePokemon.species, lookup.specieByID(pokemon.species));
    data.setUint8(offset + OFFSETS.ActivePokemon.types, encodeTypes(lookup, pokemon.types));
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

  toJSON(): Gen1.Pokemon['stored'] {
    return {
      species: this.species,
      types: this.types,
      stats: this.stats,
      moves: this.moves,
    };
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

function started(data: DataView) {
  return data.getUint16(OFFSETS.Battle.turn, LE) !== 0;
}

function encodeTypes(lookup: Lookup, types: Readonly<[TypeName] | [TypeName, TypeName]>): number {
  return lookup.typeByName(types[0]) << 3 | lookup.typeByName(types[1] ?? types[0]);
}


function encodeStatus(pokemon: Gen1.Pokemon): number {
  if (pokemon.statusData.sleep) {
    if (pokemon.status !== 'slp') {
      throw new Error('Pokemon is not asleep but has non-zero sleep turns');
    }
    return pokemon.statusData.sleep;
  }
  switch (pokemon.status) {
  case 'tox': case 'psn': return 1 << 3;
  case 'brn': return 1 << 4;
  case 'frz': return 1 << 5;
  case 'par': return 1 << 6;
  }
  return 0;
}
