import {BoostID, GenderName, Generation, ID, StatusName, TypeName} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';

import {LE, Lookup, PROTOCOL} from './data';

import {PlayerOptions} from '.';

const ArgType = PROTOCOL.ArgType;

/** A message logged by the engine parsed into Pokémon Showdown's protocol. */
export interface ParsedLine {
  /** Positional protocol arguments. */
  args: Protocol.BattleArgType;
  /** Keyword protocol arguments. */
  kwArgs: Protocol.BattleArgsKWArgType;
}

/**
 * Information related to battle required to parse the engine's binary protocol
 * into Pokémon Showdown's text protocol (e.g. Pokémon nicknames).
 */
export class Info {
  /** Information for Player 1's side. */
  p1: SideInfo;
  /** Information for Player 2's side. */
  p2: SideInfo;

  constructor(gen: Generation, sides: {p1: PlayerOptions; p2: PlayerOptions}) {
    this.p1 = new SideInfo(gen, sides.p1);
    this.p2 = new SideInfo(gen, sides.p2);
  }
}

/**
 * Information used to parse a given side's team into Pokémon Showdown's text
 * protocol from the engine's binary protocol.
 */
export class SideInfo {
  /** The side's player's name. */
  name: string;
  /** Information for the side's Pokémon. */
  team: PokemonInfo[];

  constructor(gen: Generation, player: PlayerOptions) {
    this.name = player.name;
    this.team = player.team.map(p => {
      const species = gen.species.get(p.species!)!;
      const name = p.name ?? species.name;
      const fallback = gen.num === 1 ? undefined
        : gen.num === 2 ? gen.stats.toDV(p.ivs?.atk ?? 31) >= species.genderRatio.F * 16 ? 'M' : 'F'
        : 'M';
      const gender = (p.gender ?? species.gender ?? fallback) as GenderName;
      return {species: species.name, name, gender, shiny: p.shiny};
    });
  }
}

/**
 * Information used to parse a given Pokémon into Pokémon Showdown's text
 * protocol from the engine's binary protocol.
 */
export interface PokemonInfo {
  /** The Pokémon's nickname. Either this or species must be set. */
  name?: string;
  /** The Pokémon's species. Either this or name must be set. */
  species?: string;
  /** The gender of the Pokémon. */
  gender?: string;
  /** Whether or not the Pokémon is shiny. */
  shiny?: boolean;
}

/**
 * Parses the engine's binary protocol into Pokémon Showdown's text protocol.
 */
export class Log {
  /** The generation this Log is able to parse. */
  readonly gen: Generation;
  /** The lookup table used by the Log. */
  readonly lookup: Lookup;
  /** The battle information required to parse the engine's binary protocol. */
  readonly info: Info;

  constructor(gen: Generation, lookup: Lookup, info: Info) {
    this.gen = gen;
    this.lookup = lookup;
    this.info = info;
  }

  /**
   * Decode engine's binary protocol `data` and convert it to lines of Pokémon
   * Showdown's text protocol.
   */
  *parse(data: DataView): Iterable<ParsedLine> {
    let lines: ParsedLine[] = [];
    let i = 0;
    for (; i < data.byteLength;) {
      const byte = data.getUint8(i++);
      if (!byte) {
        for (const line of lines) yield line;
        return i;
      }
      if (byte === ArgType.LastMiss) {
        (lines[0].kwArgs as Writeable<Protocol.BattleArgsKWArgs['|move|']>).miss = true;
      } else if (byte === ArgType.LastStill) {
        (lines[0].kwArgs as Writeable<Protocol.BattleArgsKWArgs['|move|']>).still = true;
      } else {
        const decoded = DECODERS[byte]?.apply(this, [i, data]);
        if (!decoded) throw new Error(`Expected arg at offset ${i} but found ${byte}`);
        i = decoded.offset;
        if (byte === ArgType.Move) {
          for (const line of lines) yield line;
          lines = [];
        } else if (!lines.length) {
          yield decoded.line;
          continue;
        }
        lines.push(decoded.line);
      }
    }
    for (const line of lines) yield line;
    return i;
  }
}

type Writeable<T> = {-readonly [P in keyof T]: T[P]};
type Decoder = (this: Log, offset: number, data: DataView) => {offset: number; line: ParsedLine};

const GENDERS: GenderName[] = ['M', 'F', 'N'];

const CANT = new Array<Protocol.Reason>(PROTOCOL.Cant.length);
CANT[PROTOCOL.Cant.Sleep] = 'slp';
CANT[PROTOCOL.Cant.Freeze] = 'frz';
CANT[PROTOCOL.Cant.Paralysis] = 'par';
CANT[PROTOCOL.Cant.Bound] = 'partiallytrapped';
CANT[PROTOCOL.Cant.Flinch] = 'flinch';
CANT[PROTOCOL.Cant.Recharge] = 'recharge';
CANT[PROTOCOL.Cant.PP] = 'nopp';

const DAMAGE = new Array(PROTOCOL.Damage.length);
DAMAGE[PROTOCOL.Damage.Poison] = 'psn' as Protocol.EffectName;
DAMAGE[PROTOCOL.Damage.Burn] = 'brn' as Protocol.EffectName;
DAMAGE[PROTOCOL.Damage.Confusion] = 'confusion' as Protocol.EffectName;
DAMAGE[PROTOCOL.Damage.LeechSeed] = 'Leech Seed' as Protocol.MoveName;
DAMAGE[PROTOCOL.Damage.RecoilOf] = 'Recoil' as Protocol.EffectName;

const BOOSTS = new Array<BoostID>(PROTOCOL.Boost.length);
BOOSTS[PROTOCOL.Boost.Rage] = 'atk';
BOOSTS[PROTOCOL.Boost.Attack] = 'atk';
BOOSTS[PROTOCOL.Boost.Defense] = 'def';
BOOSTS[PROTOCOL.Boost.Speed] = 'spe';
BOOSTS[PROTOCOL.Boost.SpecialAttack] = 'spa';
BOOSTS[PROTOCOL.Boost.SpecialDefense] = 'spd';
BOOSTS[PROTOCOL.Boost.Accuracy] = 'accuracy';
BOOSTS[PROTOCOL.Boost.Evasion] = 'evasion';

const FAIL = new Array<StatusName>(PROTOCOL.Fail.length);
FAIL[PROTOCOL.Fail.Sleep] = 'slp';
FAIL[PROTOCOL.Fail.Poison] = 'psn';
FAIL[PROTOCOL.Fail.Burn] = 'brn';
FAIL[PROTOCOL.Fail.Freeze] = 'frz';
FAIL[PROTOCOL.Fail.Paralysis] = 'par';
FAIL[PROTOCOL.Fail.Toxic] = 'tox';

const ACTIVATE = [new Array(PROTOCOL.Activate.length)];
ACTIVATE[0][PROTOCOL.Activate.Bide] = 'Bide' as Protocol.MoveName;
ACTIVATE[0][PROTOCOL.Activate.Confusion] = 'confusion' as Protocol.EffectName;
ACTIVATE[0][PROTOCOL.Activate.Haze] = 'move: Haze' as Protocol.EffectName;
ACTIVATE[0][PROTOCOL.Activate.Mist] = 'move: Mist' as Protocol.EffectName;
ACTIVATE[0][PROTOCOL.Activate.Struggle] = 'move: Struggle' as Protocol.EffectName;
ACTIVATE[0][PROTOCOL.Activate.Substitute] = 'Substitute' as Protocol.MoveName;
ACTIVATE[0][PROTOCOL.Activate.Splash] = 'move: Splash' as Protocol.EffectName;

ACTIVATE[1] = ACTIVATE[0].slice(0);
ACTIVATE[1][PROTOCOL.Activate.Bide] = 'move: Bide' as Protocol.EffectName;

const START = [new Array(PROTOCOL.Start.length)];
START[0][PROTOCOL.Start.Bide] = 'Bide' as Protocol.MoveName;
START[0][PROTOCOL.Start.Confusion] = 'confusion' as Protocol.EffectName;
START[0][PROTOCOL.Start.ConfusionSilent] = 'confusion' as Protocol.EffectName;
START[0][PROTOCOL.Start.FocusEnergy] = 'move: Focus Energy' as Protocol.EffectName;
START[0][PROTOCOL.Start.LeechSeed] = 'move: Leech Seed' as Protocol.EffectName;
START[0][PROTOCOL.Start.LightScreen] = 'Light Screen' as Protocol.MoveName;
START[0][PROTOCOL.Start.Mist] = 'Mist' as Protocol.MoveName;
START[0][PROTOCOL.Start.Reflect] = 'Reflect' as Protocol.MoveName;
START[0][PROTOCOL.Start.Substitute] = 'Substitute' as Protocol.MoveName;

START[1] = START[0].slice(0);
START[1][PROTOCOL.Start.Bide] = 'move: Bide' as Protocol.EffectName;

const END = [new Array(PROTOCOL.End.length)];
END[0][PROTOCOL.End.Disable] = 'Disable' as Protocol.MoveName;
END[0][PROTOCOL.End.Confusion] = 'confusion' as Protocol.EffectName;
END[0][PROTOCOL.End.Bide] = 'Bide' as Protocol.MoveName;
END[0][PROTOCOL.End.Substitute] = 'Substitute' as Protocol.MoveName;
END[0][PROTOCOL.End.DisableSilent] = 'Disable' as Protocol.MoveName;
END[0][PROTOCOL.End.ConfusionSilent] = 'confusion' as Protocol.EffectName;
END[0][PROTOCOL.End.MistSilent] = 'Mist' as ID;
END[0][PROTOCOL.End.FocusEnergySilent] = 'move: Focus Energy' as ID;
END[0][PROTOCOL.End.LeechSeedSilent] = 'move: Leech Seed' as ID;
END[0][PROTOCOL.End.ToxicSilent] = 'Toxic counter' as Protocol.EffectName;
END[0][PROTOCOL.End.LightScreenSilent] = 'Light Screen' as ID;
END[0][PROTOCOL.End.ReflectSilent] = 'Reflect' as ID;
END[0][PROTOCOL.End.BideSilent] = 'move: Bide' as ID;

END[1] = END[0].slice(0);
END[1][PROTOCOL.End.Disable] = 'move: Disable' as Protocol.EffectName;
END[1][PROTOCOL.End.Bide] = 'move: Bide' as Protocol.EffectName;
END[1][PROTOCOL.End.LeechSeed] = 'Leech Seed' as Protocol.MoveName;

const SIDE = new Array(PROTOCOL.Side.length);
SIDE[PROTOCOL.Side.Safeguard] = 'Safeguard' as Protocol.MoveName;
SIDE[PROTOCOL.Side.Reflect] = 'Reflect' as Protocol.MoveName;
SIDE[PROTOCOL.Side.LightScreen] = 'move: Light Screen' as Protocol.MoveName;
SIDE[PROTOCOL.Side.Spikes] = 'Spikes' as Protocol.MoveName;

const DECODERS = new Array<Decoder>(ArgType.length);
DECODERS[ArgType.Move] = function (offset, data) {
  const source = decodeIdent(this.info, data.getUint8(offset++));
  const m = data.getUint8(offset++);
  const {player, id} = decodeIdentRaw(data.getUint8(offset++));
  const set = this.info[player].team[id - 1];
  const target = id === 0
    ? '' : `${player}a: ${(set.name || set.species)!}` as Protocol.PokemonIdent;
  const reason = data.getUint8(offset++);
  const move = reason === PROTOCOL.Move.Recharge
    ? 'recharge' : this.gen.moves.get(this.lookup.moveByNum(m))!.name;
  const args = ['move', source, move, target] as Protocol.Args['|move|'];
  const kwArgs = reason === PROTOCOL.Move.From
    ? {from: this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name} : {};
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.Switch] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const details = decodeDetails(offset, data, this.gen, this.lookup);
  offset += this.gen.num > 1 ? 3 : 2;
  const hpStatus = decodeHPStatus(offset, data);
  offset += 5;
  const args = ['switch', ident, details, hpStatus] as Protocol.Args['|switch|'];
  return {offset, line: {args, kwArgs: {}}};
};
DECODERS[ArgType.Cant] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  let args: Protocol.Args['|cant|'];
  if (reason === PROTOCOL.Cant.Disable) {
    const move = this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name;
    args = ['cant', ident, 'Disable' as Protocol.MoveName, move];
  } else {
    args = ['cant', ident, CANT[reason]];
  }
  return {offset, line: {args, kwArgs: {}}};
};
DECODERS[ArgType.Faint] = function (offset, data) {
  return decodeProtocol('faint', offset, data, this.info);
};
DECODERS[ArgType.Turn] = function (offset, data) {
  const turn = data.getUint16(offset, LE).toString() as Protocol.Num;
  offset += 2;
  return {offset, line: {args: ['turn', turn] as Protocol.Args['|turn|'], kwArgs: {}}};
};
DECODERS[ArgType.Win] = function (offset, data) {
  const player = data.getUint8(offset++) ? 'p2' : 'p1';
  const args =
    ['win', this.info[player].name as Protocol.Username] as Protocol.Args['|win|'];
  return {offset, line: {args, kwArgs: {}}};
};
DECODERS[ArgType.Tie] = function (offset) {
  const line = {args: ['tie'] as Protocol.Args['|tie|'], kwArgs: {}};
  return {offset, line};
};
DECODERS[ArgType.Damage] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const hpStatus = decodeHPStatus(offset, data);
  offset += 5;
  const reason = data.getUint8(offset++);
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-damage|']>;
  if (reason > PROTOCOL.Damage.None) kwArgs.from = DAMAGE[reason];
  if (reason === PROTOCOL.Damage.RecoilOf) {
    kwArgs.of = decodeIdent(this.info, data.getUint8(offset++));
  }
  const args = ['-damage', ident, hpStatus] as Protocol.Args['|-damage|'];
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.Heal] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const hpStatus = decodeHPStatus(offset, data);
  offset += 5;
  const reason = data.getUint8(offset++);
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-heal|']>;
  if (reason === PROTOCOL.Heal.Drain) {
    kwArgs.from = 'drain' as Protocol.EffectName;
    kwArgs.of = decodeIdent(this.info, data.getUint8(offset++));
  } else if (reason === PROTOCOL.Heal.Silent) {
    kwArgs.silent = true;
  }
  const args = ['-heal', ident, hpStatus] as Protocol.Args['|-heal|'];
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.Status] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const status = decodeStatus(data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-status|']>;
  if (reason === PROTOCOL.Status.Silent) {
    kwArgs.silent = true;
  } else if (reason === PROTOCOL.Status.From) {
    const move = this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name;
    kwArgs.from = `move: ${move}` as Protocol.EffectName;
  }
  const args = ['-status', ident, status] as Protocol.Args['|-status|'];
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.CureStatus] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const status = decodeStatus(data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-curestatus|']>;
  if (reason === PROTOCOL.CureStatus.Message) {
    kwArgs.msg = true;
  } else if (reason === PROTOCOL.CureStatus.Silent) {
    kwArgs.silent = true;
  }
  const args = ['-curestatus', ident, status] as Protocol.Args['|-curestatus|'];
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.Boost] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  const boost = BOOSTS[reason];
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-boost|' | '|-unboost|']>;
  if (reason === PROTOCOL.Boost.Rage) {
    kwArgs.from = 'Rage' as Protocol.MoveName;
  }
  const n = data.getUint8(offset++) - 6;
  const type = n > 0 ? '-boost' : '-unboost';
  const num = Math.abs(n).toString() as Protocol.Num;
  const args = [type, ident, boost, num] as Protocol.Args['|-boost|' | '|-unboost|'];
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.ClearAllBoost] = function (offset) {
  const args = ['-clearallboost'] as Protocol.Args['|-clearallboost|'];
  const kwArgs = this.gen.num === 1 ? {silent: true} as const : {};
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.Fail] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  let args: Protocol.Args['|-fail|'];
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-fail|']>;
  const weak = reason === PROTOCOL.Fail.Weak;
  if (weak || reason === PROTOCOL.Fail.Substitute) {
    args = ['-fail', ident, 'move: Substitute' as Protocol.EffectName];
    if (weak) kwArgs.weak = true;
  } else if (reason !== PROTOCOL.Fail.None) {
    args = ['-fail', ident, FAIL[reason]];
  } else {
    args = ['-fail', ident];
  }
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.Miss] = function (offset, data) {
  return decodeProtocol('-miss', offset, data, this.info);
};
DECODERS[ArgType.HitCount] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const num = data.getUint8(offset++).toString() as Protocol.Num;
  const args = ['-hitcount', ident, num] as Protocol.Args['|-hitcount|'];
  return {offset, line: {args, kwArgs: {}}};
};
DECODERS[ArgType.Prepare] = function (offset, data) {
  const source = decodeIdent(this.info, data.getUint8(offset++));
  const move = this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name;
  const args = ['-prepare', source, move] as Protocol.Args['|-prepare|'];
  return {offset, line: {args, kwArgs: {}}};
};
DECODERS[ArgType.MustRecharge] = function (offset, data) {
  return decodeProtocol('-mustrecharge', offset, data, this.info);
};
DECODERS[ArgType.Activate] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  const type = reason === PROTOCOL.Activate.Mist ? '-block' : '-activate';
  const activate = ACTIVATE[this.gen.num - 1];
  const args = reason === PROTOCOL.Activate.Splash
    ? [type, '', activate[reason]] as Protocol.Args['|-activate|']
    : [type, ident, activate[reason], ''] as Protocol.Args['|-activate|' | '|-block|'];
  const kwArgs = reason === PROTOCOL.Activate.Substitute ? {damage: true} as const : {};
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.FieldActivate] = function (offset) {
  const effect = 'move: Pay Day' as Protocol.EffectName;
  const args = ['-fieldactivate', effect] as Protocol.Args['|-fieldactivate|'];
  return {offset, line: {args, kwArgs: {}}};
};
DECODERS[ArgType.Start] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  let args: Protocol.Args['|-start|'];
  const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-start|']>;
  if (reason < PROTOCOL.Start.TypeChange) {
    args = ['-start', ident, START[this.gen.num - 1][reason]];
    if (reason === PROTOCOL.Start.ConfusionSilent) kwArgs.silent = true;
  } else if (reason === PROTOCOL.Start.TypeChange) {
    const types = decodeTypes(this.lookup, data.getUint8(offset++));
    const t = types[0] === types[1] ? types[0] : types.join('/');
    args = ['-start', ident, 'typechange', t as Protocol.Types];
    kwArgs.from = 'move: Conversion' as Protocol.EffectName;
    kwArgs.of = decodeIdent(this.info, data.getUint8(offset++));
  } else {
    const move = this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name;
    const effect = reason === PROTOCOL.Start.Disable ? 'Disable' : 'Mimic';
    args = ['-start', ident, effect as Protocol.EffectName, move];
  }
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.End] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  const args = ['-end', ident, END[this.gen.num - 1][reason]] as Protocol.Args['|-end|'];
  const kwArgs = reason >= PROTOCOL.End.DisableSilent ? {silent: true} as const : {};
  return {offset, line: {args, kwArgs}};
};
DECODERS[ArgType.OHKO] = function (offset) {
  return {offset, line: {args: ['-ohko'] as Protocol.Args['|-ohko|'], kwArgs: {}}};
};
DECODERS[ArgType.Crit] = function (offset, data) {
  return decodeProtocol('-crit', offset, data, this.info);
};
DECODERS[ArgType.SuperEffective] = function (offset, data) {
  return decodeProtocol('-supereffective', offset, data, this.info);
};
DECODERS[ArgType.Resisted] = function (offset, data) {
  return decodeProtocol('-resisted', offset, data, this.info);
};
DECODERS[ArgType.Immune] = function (offset, data) {
  const ident = decodeIdent(this.info, data.getUint8(offset++));
  const reason = data.getUint8(offset++);
  const kwArgs = reason === PROTOCOL.Immune.OHKO ? {ohko: true} as const : {};
  return {offset, line: {args: ['-immune', ident] as Protocol.Args['|-immune|'], kwArgs}};
};
DECODERS[ArgType.Transform] = function (offset, data) {
  const source = decodeIdent(this.info, data.getUint8(offset++));
  const target = decodeIdent(this.info, data.getUint8(offset++));
  const args = ['-transform', source, target] as Protocol.Args['|-transform|'];
  return {offset, line: {args, kwArgs: {}}};
};

function decodeProtocol(type: string, offset: number, data: DataView, info: Info) {
  const ident = decodeIdent(info, data.getUint8(offset++));
  return {offset, line: {args: [type, ident] as Protocol.BattleArgType, kwArgs: {}}};
}

function decodeIdent(info: Info, byte: number): Protocol.PokemonIdent {
  const {player, id} = decodeIdentRaw(byte);
  const set = info[player].team[id - 1];
  return `${player}a: ${(set.name || set.species)!}` as Protocol.PokemonIdent;
}

function decodeDetails(
  offset: number,
  data: DataView,
  gen: Generation,
  lookup: Lookup,
): Protocol.PokemonDetails {
  const species = gen.species.get(lookup.speciesByNum(data.getUint8(offset++)))!.name;
  const gender = gen.num > 1 ? GENDERS[data.getUint8(offset++)] : 'N';
  const level = data.getUint8(offset);

  const mf = gender === 'N' ? '' : `, ${gender}`;
  const lvl = level === 100 ? '' : `, L${level}`;
  return `${species}${mf}${lvl}` as Protocol.PokemonDetails;
}

function decodeHPStatus(offset: number, data: DataView): Protocol.PokemonHPStatus {
  const hp = data.getUint16(offset, LE);
  offset += 2;
  const maxhp = data.getUint16(offset, LE);
  offset += 2;
  if (hp === 0) return '0 fnt' as Protocol.PokemonHPStatus;
  const status = decodeStatus(data.getUint8(offset));
  return (status ? `${hp}/${maxhp} ${status}` : `${hp}/${maxhp}`) as Protocol.PokemonHPStatus;
}

export function decodeIdentRaw(byte: number): {player: 'p1' | 'p2'; id: number} {
  return {
    player: (byte >> 3) === 0 ? 'p1' : 'p2',
    id: byte & 0b111,
  };
}

export function decodeStatus(val: number): StatusName | undefined {
  if (val & 0b111) return 'slp';
  if ((val >> 7) & 1) return 'tox';
  if ((val >> 6) & 1) return 'par';
  if ((val >> 5) & 1) return 'frz';
  if ((val >> 4) & 1) return 'brn';
  if ((val >> 3) & 1) return 'psn';
  return undefined;
}

export function decodeTypes(lookup: Lookup, val: number): readonly [TypeName, TypeName] {
  return [lookup.typeByNum(val & 0x0F), lookup.typeByNum(val >> 4)];
}
