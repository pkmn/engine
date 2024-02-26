import {
  BoostID, BoostsTable, Generation, ID, PokemonSet,
  StatID, StatsTable, StatusName, TypeName, toID,
} from '@pkmn/data';

import * as addon from './addon';
import {LAYOUT, LE, Lookup} from './data';
import {decodeIdentRaw, decodeStatus, decodeTypes} from './protocol';

import {Choice, CreateOptions, Data, Gen1, Player, RestoreOptions, Result, Slot} from '.';

const SIZES = LAYOUT[0].sizes;
const OFFSETS = LAYOUT[0].offsets;

OFFSETS.Stats.spa = OFFSETS.Stats.spd = OFFSETS.Stats.spc;
OFFSETS.Boosts.spa = OFFSETS.Boosts.spd = OFFSETS.Boosts.spc;

const VOLATILES: {[volatile: string]: number} = {};
for (const v in OFFSETS.Volatiles) {
  if (v.charCodeAt(0) >= 65 && v.charCodeAt(0) <= 90) {
    VOLATILES[v] = OFFSETS.Volatiles[v];
  }
}

export class Battle implements Gen1.Battle {
  readonly config: CreateOptions | RestoreOptions;
  readonly log?: DataView;

  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly options: ArrayBuffer;
  private readonly buf: ArrayBuffer | undefined;

  private readonly cache: [Side?, Side?];

  constructor(lookup: Lookup, data: DataView, config: CreateOptions | RestoreOptions) {
    this.config = config;

    this.lookup = lookup;
    this.data = data;
    this.options = new ArrayBuffer(addon.size(0, 'choices'));
    this.buf = config.log ? new ArrayBuffer(addon.size(0, 'log')) : undefined;
    this.log = config.log ? new DataView(this.buf!) : undefined;

    this.cache = [undefined, undefined];
  }

  update(c1?: Choice, c2?: Choice): Result {
    return addon.update(0, !!this.config.showdown, this.data.buffer, c1, c2, this.buf);
  }

  choices(id: Player, result: Result): Choice[] {
    return addon.choices(0, !!this.config.showdown, this.data.buffer, id, result[id], this.options);
  }

  choose(id: Player, result: Result, fn: (n: number) => number): Choice {
    return addon.choose(
      0, !!this.config.showdown, this.data.buffer, id, result[id], this.options, fn
    );
  }

  get sides() {
    return this._sides();
  }

  *_sides() {
    yield this.side('p1');
    yield this.side('p2');
  }

  side(id: Player): Side {
    const i = id === 'p1' ? 0 : 1;
    const side = this.cache[i];
    return side ?? (this.cache[i] = new Side(this, this.lookup, this.data, id as 'p1' | 'p2'));
  }

  foe(side: Player): Side {
    return this.side(side === 'p1' ? 'p2' : 'p1');
  }

  get turn(): number {
    return this.data.getUint16(OFFSETS.Battle.turn, LE);
  }

  get lastDamage(): number {
    return this.data.getUint16(OFFSETS.Battle.last_damage, LE);
  }

  get prng(): readonly number[] {
    const offset = OFFSETS.Battle.last_moves + (this.config.showdown ? 4 : 2);
    // Pokémon Showdown's PRNGSeed is always big-endian
    const seed: number[] = [0, 0, 0, 0];
    if (this.config.showdown) {
      seed[LE ? 3 : 0] = this.data.getUint16(offset, LE);
      seed[LE ? 2 : 1] = this.data.getUint16(offset + 2, LE);
      seed[LE ? 1 : 2] = this.data.getUint16(offset + 4, LE);
      seed[LE ? 0 : 3] = this.data.getUint16(offset + 6, LE);
    } else {
      // Gen12RNG seed requires an index, but if we always rotate the seed based on the index when
      // reading we can avoid tracking the index as it will always be zero. NB: the exact bits of
      // the Battle will not roundtrip, but the *logical* Battle state will.
      const index = this.data.getUint8(offset + 9);
      for (let i = 0; i < 9; i++) {
        const j = i - index;
        seed[j < 0 ? j + 9 : j] = this.data.getUint8(offset + i);
      }
    }
    return seed;
  }

  toJSON(): Data<Gen1.Battle> {
    return {
      sides: Array.from(this.sides).map(s => s.toJSON()),
      turn: this.turn,
      lastDamage: this.lastDamage,
      prng: this.prng,
    };
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
    return new Battle(lookup, data, options);
  }

  static restore(
    gen: Generation,
    lookup: Lookup,
    battle: Data<Gen1.Battle>,
    options: RestoreOptions,
  ) {
    const buf = new ArrayBuffer(SIZES.Battle);
    const data = new DataView(buf);
    let offset = OFFSETS.Battle.p1;
    const lastMoves: number[] = [];
    for (const side of battle.sides) {
      Side.encode(gen, !!options.showdown, lookup, battle, side, data, offset);
      offset += SIZES.Side;
      if (options.showdown) {
        lastMoves.push(+!!side.lastMoveCounterable);
        lastMoves.push((side.lastMoveIndex ?? 0));
      } else {
        lastMoves.push((+!!side.lastMoveCounterable << 4) | (side.lastMoveIndex ?? 0));
      }
    }
    data.setUint16(OFFSETS.Battle.turn, battle.turn, LE);
    data.setUint16(OFFSETS.Battle.last_damage, battle.lastDamage, LE);
    data.setUint8(OFFSETS.Battle.last_moves, lastMoves[0]);
    data.setUint8(OFFSETS.Battle.last_moves + 1, lastMoves[1]);
    if (options.showdown) {
      data.setUint8(OFFSETS.Battle.last_moves + 2, lastMoves[2]);
      data.setUint8(OFFSETS.Battle.last_moves + 3, lastMoves[3]);
    }
    encodePRNG(data, battle.prng);
    return new Battle(lookup, data, options);
  }
}

export class Side implements Gen1.Side {
  readonly id: 'p1' | 'p2';

  private readonly battle: Battle;
  private readonly lookup: Lookup;
  private readonly data: DataView;

  private readonly offset: number;
  private readonly cache: [Pokemon?, Pokemon?, Pokemon?, Pokemon?, Pokemon?, Pokemon?];

  constructor(battle: Battle, lookup: Lookup, data: DataView, id: 'p1' | 'p2') {
    this.id = id;

    this.battle = battle;
    this.lookup = lookup;
    this.data = data;

    this.offset = OFFSETS.Battle[id];
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
      const poke = this.get(i as Slot);
      if (!poke) break;
      yield poke;
    }
  }

  slot(id: number): Slot | undefined {
    for (let slot = 1; slot <= 6; slot++) {
      const i = this.data.getUint8(this.offset + OFFSETS.Side.order + slot - 1);
      if (i === id) return slot as Slot;
    }
    return undefined;
  }

  get(slot: Slot): Pokemon | undefined {
    const id = this.data.getUint8(this.offset + OFFSETS.Side.order + slot - 1) - 1;
    if (id < 0) return undefined;
    const poke = this.cache[id];
    if (poke) return poke;
    return (this.cache[id] = new Pokemon(this.battle, this.lookup, this.data, this.offset, id));
  }

  get lastUsedMove(): ID | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Side.last_used_move);
    return m === 0 ? undefined : this.lookup.moveByNum(m);
  }

  get lastSelectedMove(): ID | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Side.last_selected_move);
    return m === 0 ? undefined : this.lookup.moveByNum(m);
  }

  get lastMoveIndex(): 1 | 2 | 3 | 4 | undefined {
    let m: number;
    if (this.battle.config.showdown) {
      const off = this.id === 'p1' ? 0 : 2;
      m = this.data.getUint8(OFFSETS.Battle.last_moves + off);
    } else {
      const off = this.id === 'p1' ? 0 : 1;
      m = this.data.getUint8(OFFSETS.Battle.last_moves + off) & 0x0F;
    }
    return m === 0 ? undefined : m as 1 | 2 | 3 | 4;
  }

  get lastMoveCounterable(): boolean {
    let m: number;
    if (this.battle.config.showdown) {
      const off = this.id === 'p1' ? 1 : 3;
      m = this.data.getUint8(OFFSETS.Battle.last_moves + off);
    } else {
      const off = this.id === 'p1' ? 0 : 1;
      m = this.data.getUint8(OFFSETS.Battle.last_moves + off) & 0xF0;
    }
    return m !== 0;
  }

  toJSON(): Gen1.Side {
    return {
      active: this.active?.toJSON(),
      pokemon: Array.from(this.pokemon).map(p => p.toJSON()),
      lastSelectedMove: this.lastSelectedMove,
      lastUsedMove: this.lastUsedMove,
      lastMoveIndex: this.lastMoveIndex,
      lastMoveCounterable: this.lastMoveCounterable,
    };
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    team: Partial<PokemonSet>[],
    data: DataView,
    offset: number
  ) {
    const n = Math.min(6, team.length);
    for (let i = 0; i < n; i++) {
      const poke = team[i];
      Pokemon.init(gen, lookup, poke, data, offset, i);
      data.setUint8(offset + OFFSETS.Side.order + i, i + 1);
    }
  }

  static encode(
    gen: Generation,
    showdown: boolean,
    lookup: Lookup,
    battle: Data<Gen1.Battle>,
    side: Gen1.Side,
    data: DataView,
    offset: number,
  ) {
    let i = 0;
    for (const pokemon of side.pokemon) {
      const off = offset + OFFSETS.Side.pokemon + SIZES.Pokemon * (pokemon.position - 1);
      Pokemon.encodeStored(gen, showdown, lookup, pokemon, data, off);
      data.setUint8(offset + OFFSETS.Side.order + (pokemon.position - 1), i + 1);
      i++;
    }
    Pokemon.encodeActive(gen, lookup, battle, side.active, data, offset + OFFSETS.Side.active);
    data.setUint8(offset + OFFSETS.Side.last_selected_move,
      lookup.moveByID(side.lastSelectedMove));
    data.setUint8(offset + OFFSETS.Side.last_used_move,
      lookup.moveByID(side.lastUsedMove));
  }
}

export class Pokemon implements Gen1.Pokemon {
  static Volatiles = VOLATILES;

  private readonly battle: Battle;
  private readonly lookup: Lookup;
  private readonly data: DataView;
  private readonly offset: {order: number; active: number; stored: number};
  private readonly index: number;

  readonly stored: StoredPokemon;

  constructor(battle: Battle, lookup: Lookup, data: DataView, offset: number, index: number) {
    this.battle = battle;
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
    return started(this.data) && this.position === this.data.getUint8(this.offset.order);
  }

  stat(stat: StatID | 'spc'): number {
    if (!this.active) return this.stored.stat(stat);

    const off = this.offset.active + OFFSETS.ActivePokemon.stats + OFFSETS.Stats[stat];
    return this.data.getUint16(off, LE);
  }

  get stats(): StatsTable {
    if (!this.active) return this.stored.stats;
    const spc = this.stat('spc');
    return {
      hp: this.stat('hp'),
      atk: this.stat('atk'),
      def: this.stat('def'),
      spe: this.stat('spe'),
      spa: spc,
      spd: spc,
    };
  }

  volatile(bit: number): boolean {
    if (!this.active) return false;

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles + (bit >> 3);
    const byte = this.data.getUint8(off);
    return !!(byte & (1 << (bit & 7)));
  }

  get volatiles(): Gen1.Volatiles {
    if (!this.active) return {};

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles;
    const volatiles: Gen1.Volatiles = {};
    for (const v in Pokemon.Volatiles) {
      if (v === 'Toxic' || v === 'MultiHit') continue;
      const volatile = toID(v) as keyof Gen1.Volatiles;

      if (this.volatile(Pokemon.Volatiles[v])) {
        if (volatile === 'bide') {
          volatiles[volatile] = {
            duration: (this.data.getUint8(off + (OFFSETS.Volatiles.attacks >> 3)) >> 5) & 0b111,
            damage: this.data.getUint16(off + (OFFSETS.Volatiles.state >> 3), LE),
          };
        } else if (volatile === 'binding') {
          volatiles[volatile] = {
            duration: (this.data.getUint8(off + (OFFSETS.Volatiles.attacks >> 3)) >> 5) & 0b111,
          };
        } else if (volatile === 'thrashing') {
          volatiles[volatile] = {
            duration: (this.data.getUint8(off + (OFFSETS.Volatiles.attacks >> 3)) >> 5) & 0b111,
            accuracy: this.data.getUint16(off + (OFFSETS.Volatiles.state >> 3), LE),
          };
        } else if (volatile === 'rage') {
          volatiles[volatile] = {
            accuracy: this.data.getUint16(off + (OFFSETS.Volatiles.state >> 3), LE),
          };
        } else if (volatile === 'confusion') {
          volatiles[volatile] = {
            duration: (this.data.getUint8(off + (OFFSETS.Volatiles.confusion >> 3)) >> 2) & 0b111,
          };
        } else if (volatile === 'substitute') {
          volatiles[volatile] = {
            hp: this.data.getUint8(off + (OFFSETS.Volatiles.substitute >> 3)),
          };
        } else if (volatile === 'transform') {
          const {player, id} =
            decodeIdentRaw((this.data.getUint8(off + (OFFSETS.Volatiles.transform >> 3))) & 0x0F);
          volatiles[volatile] = {player, slot: this.battle.side(player).slot(id)!};
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
    const m = this.data.getUint8(off + ((slot - 1) << 1));
    if (m === 0) return undefined;
    const id = this.lookup.moveByNum(m);
    const pp = this.data.getUint8(off + ((slot << 1) - 1));
    const byte = this.data.getUint8(this.offset.active +
      OFFSETS.ActivePokemon.volatiles +
      (OFFSETS.Volatiles.disable_move >> 3));
    const disabled = ((byte & 0b111) === slot)
      ? this.data.getUint8(this.offset.active +
      OFFSETS.ActivePokemon.volatiles +
      (OFFSETS.Volatiles.disable_duration >> 3)) >> 4
      : undefined;
    return {id, pp, disabled};
  }

  get moves(): Iterable<Gen1.MoveSlot> {
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
    const val = (b & 7) ? byte >> 4 : byte & 0x0F;
    return decodeSigned(val);
  }

  get boosts(): BoostsTable {
    const boosts = {atk: 0, def: 0, spe: 0, spa: 0, spd: 0, accuracy: 0, evasion: 0};
    if (!this.active) return boosts;

    for (const b in OFFSETS.Boosts) {
      if (b === 'spc') continue;
      const boost = b as BoostID;
      boosts[boost] = this.boost(boost);
    }
    return boosts as BoostsTable;
  }

  get species(): ID {
    if (!this.active) return this.stored.species;

    const off = this.offset.active + OFFSETS.ActivePokemon.species;
    return this.lookup.speciesByNum(this.data.getUint8(off));
  }

  get types(): readonly [TypeName, TypeName] {
    if (!this.active) return this.stored.types;

    const off = this.offset.active + OFFSETS.ActivePokemon.types;
    return decodeTypes(this.lookup, this.data.getUint8(off));
  }

  get level(): number {
    return this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.level);
  }

  get hp(): number {
    return this.data.getUint16(this.offset.stored + OFFSETS.Pokemon.hp, LE);
  }

  get status(): StatusName | undefined {
    const status = decodeStatus(this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.status));
    return status === 'psn' && this.toxic ? 'tox' : status;
  }

  get statusData(): {sleep: number; self: boolean; toxic: number} {
    const sleep = this.sleep;
    return {sleep, self: !!sleep && this.ext, toxic: this.toxic};
  }

  private get sleep(): number {
    const val = this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.status);
    return val & 0b111;
  }

  private get ext(): boolean {
    return (this.data.getUint8(this.offset.stored + OFFSETS.Pokemon.status) >> 7) === 1;
  }

  private get toxic(): number {
    if (!this.active) return 0;

    const off = this.offset.active + OFFSETS.ActivePokemon.volatiles;
    return this.data.getUint8(off + (OFFSETS.Volatiles.toxic >> 3)) >> 3;
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
    };
  }

  static init(
    gen: Generation,
    lookup: Lookup,
    set: Partial<PokemonSet>,
    data: DataView,
    offset: number,
    index: number,
  ) {
    const stored = offset + OFFSETS.Side.pokemon + SIZES.Pokemon * index;
    const species = gen.species.get(set.species!)!;

    let hp = 0;
    let off = stored + OFFSETS.Pokemon.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      const val = gen.stats.calc(
        stat,
        species.baseStats[stat],
        set.ivs?.[stat] ?? 31,
        set.evs?.[stat] ?? 252,
        set.level ?? 100
      );
      data.setUint16(off, val, LE);
      if (stat === 'hp') hp = val;
      off += 2;
    }

    off = stored + OFFSETS.Pokemon.moves;
    for (const m of set.moves!) {
      const move = gen.moves.get(m)!;
      data.setUint8(off++, move.num);
      data.setUint8(off++, Math.min(move.pp / 5 * 8, gen.num === 1 ? 61 : 64));
    }

    data.setUint16(stored + OFFSETS.Pokemon.hp, hp, LE);

    data.setUint8(stored + OFFSETS.Pokemon.species, species.num);
    data.setUint8(stored + OFFSETS.Pokemon.types, encodeTypes(lookup, species.types));
    data.setUint8(stored + OFFSETS.Pokemon.level, set.level ?? 100);
  }

  static encodeStored(
    gen: Generation,
    showdown: boolean,
    lookup: Lookup,
    pokemon: Gen1.Pokemon,
    data: DataView,
    offset: number,
  ) {
    let off = 0;
    const stats = pokemon.stored.stats;
    for (const stat of gen.stats) {
      if (stat === 'spd') break;
      data.setUint16(offset + OFFSETS.Pokemon.stats + off, stats[stat], LE);
      off += 2;
    }

    off = offset + OFFSETS.Pokemon.moves;
    for (const ms of pokemon.stored.moves) {
      data.setUint8(off++, lookup.moveByID(ms.id));
      data.setUint8(off++, ms.pp);
    }

    data.setUint16(offset + OFFSETS.Pokemon.hp, pokemon.hp, LE);

    const species = gen.species.get(pokemon.stored.species)!;
    data.setUint8(offset + OFFSETS.Pokemon.species, species.num);
    data.setUint8(offset + OFFSETS.Pokemon.types, encodeTypes(lookup, species.types));
    data.setUint8(offset + OFFSETS.Pokemon.level, pokemon.level);
    data.setUint8(offset + OFFSETS.Pokemon.status, encodeStatus(pokemon, showdown));
  }

  static encodeActive(
    gen: Generation,
    lookup: Lookup,
    battle: Data<Gen1.Battle>,
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
    const disabled = {duration: 0, move: 0};
    for (const ms of pokemon.moves) {
      data.setUint8(off++, lookup.moveByID(ms.id));
      data.setUint8(off++, ms.pp);
      if (ms.disabled !== undefined) {
        disabled.duration = ms.disabled;
        disabled.move = slot;
      }
      slot++;
    }

    off = offset + OFFSETS.ActivePokemon.volatiles;
    const volatiles = pokemon.volatiles;

    data.setUint8(off + (Pokemon.Volatiles.Bide >> 3),
      +!!volatiles.bide | (+!!volatiles.thrashing << 1) | (+!!volatiles.flinch << 3) |
       (+!!volatiles.charging << 4) | (+!!volatiles.binding << 5) |
       (+!!volatiles.invulnerable << 6) | (+!!volatiles.confusion << 7));

    data.setUint8(off + (Pokemon.Volatiles.Mist >> 3),
      +!!volatiles.mist | (+!!volatiles.focusenergy << 1) |
       (+!!volatiles.substitute << 2) | (+!!volatiles.recharging << 3) |
       (+!!volatiles.rage << 4) | (+!!volatiles.leechseed << 5) |
       (+!!pokemon.statusData.toxic << 6) | (+!!volatiles.lightscreen << 7));

    const confusion = volatiles.confusion?.duration ?? 0;
    const attacks = volatiles.binding?.duration ??
      volatiles.thrashing?.duration ?? 0;
    data.setUint8(off + (Pokemon.Volatiles.Reflect >> 3),
      +!!volatiles.reflect | (+!!volatiles.transform << 1) |
      (confusion << 2) | (attacks << 5));

    const state = volatiles.bide?.damage ??
      volatiles.thrashing?.accuracy ??
      volatiles.rage?.accuracy ?? 0;
    data.setUint16(off + (OFFSETS.Volatiles.state >> 3), state, LE);
    data.setUint8(off + (OFFSETS.Volatiles.substitute >> 3), volatiles.substitute?.hp ?? 0);

    let transform = 0;
    if (volatiles.transform) {
      const side = Array.from(battle.sides)[volatiles.transform.player === 'p1' ? 0 : 1];
      const id = Array.from(side.pokemon)[volatiles.transform.slot - 1].position;
      transform = (+!!(volatiles.transform.player === 'p2') << 3) | id;
    }
    data.setUint8(off + (OFFSETS.Volatiles.transform >> 3),
      (transform | (disabled.duration << 4)));
    data.setUint8(off + (OFFSETS.Volatiles.toxic >> 3),
      (disabled.move | ((pokemon.statusData.toxic ?? 0) << 3)));

    off = offset + OFFSETS.ActivePokemon.boosts;
    const boosts = pokemon.boosts;
    data.setUint8(off++, encodeSigned(boosts.atk) | (encodeSigned(boosts.def) << 4));
    data.setUint8(off++, encodeSigned(boosts.spe) | (encodeSigned(boosts.spa) << 4));
    data.setUint8(off++, encodeSigned(boosts.accuracy) | (encodeSigned(boosts.evasion) << 4));

    data.setUint8(offset + OFFSETS.ActivePokemon.species, lookup.speciesByID(pokemon.species));
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

  stat(stat: StatID | 'spc'): number {
    return this.data.getUint16(this.offset + OFFSETS.Pokemon.stats + OFFSETS.Stats[stat], LE);
  }

  get stats(): StatsTable {
    const spc = this.stat('spc');
    return {
      hp: this.stat('hp'),
      atk: this.stat('atk'),
      def: this.stat('def'),
      spe: this.stat('spe'),
      spa: spc,
      spd: spc,
    };
  }

  move(slot: 1 | 2 | 3 | 4): {id: ID; pp: number} | undefined {
    const m = this.data.getUint8(this.offset + OFFSETS.Pokemon.moves + ((slot - 1) << 1));
    if (m === 0) return undefined;
    const id = this.lookup.moveByNum(m);
    const pp = this.data.getUint8(this.offset + OFFSETS.Pokemon.moves + ((slot << 1) - 1));
    return {id, pp};
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
    return this.lookup.speciesByNum(this.data.getUint8(this.offset + OFFSETS.Pokemon.species));
  }

  get types(): readonly [TypeName, TypeName] {
    return decodeTypes(this.lookup, this.data.getUint8(this.offset + OFFSETS.Pokemon.types));
  }

  toJSON(): Gen1.Pokemon['stored'] {
    return {
      species: this.species,
      types: this.types,
      stats: this.stats,
      moves: Array.from(this.moves),
    };
  }
}

function encodePRNG(data: DataView, seed: readonly number[]) {
  const offset = OFFSETS.Battle.last_damage + 2 + (seed.length === 4 ? 4 : 2);
  if (seed.length === 4) {
    data.setUint16(offset, seed[LE ? 3 : 0], LE);
    data.setUint16(offset + 2, seed[LE ? 2 : 1], LE);
    data.setUint16(offset + 4, seed[LE ? 1 : 2], LE);
    data.setUint16(offset + 6, seed[LE ? 0 : 3], LE);
  } else {
    for (let i = 0; i < 9; i++) {
      data.setUint8(offset + i, seed[i]);
    }
    // NB: ArrayBuffer is zero initialized already so we don't need to set the index to zero
  }
}

function started(data: DataView) {
  return data.getUint16(OFFSETS.Battle.turn, LE) !== 0;
}

function encodeTypes(lookup: Lookup, types: Readonly<[TypeName] | [TypeName, TypeName]>): number {
  return (lookup.typeByName(types[1] ?? types[0]) << 4) | lookup.typeByName(types[0]);
}

function decodeSigned(n: number) {
  return (n > 7) ? -(0b10000 - n) : n;
}

function encodeSigned(n: number) {
  return (n < 0) ? 0b10000 + n : n;
}

function encodeStatus(pokemon: Gen1.Pokemon, showdown: boolean): number {
  if (pokemon.statusData.sleep) {
    if (pokemon.status !== 'slp') {
      throw new Error('Pokemon is not asleep but has non-zero sleep turns');
    }
    return (pokemon.statusData.self ? 0x80 : 0) | pokemon.statusData.sleep;
  }
  switch (pokemon.status) {
    case 'tox': return showdown ? 0b10001000 : 1 << 3;
    case 'psn': return 1 << 3;
    case 'brn': return 1 << 4;
    case 'frz': return 1 << 5;
    case 'par': return 1 << 6;
  }
  return 0;
}
