import {Generation, StatusName, TypeName, BoostID, ID, GenderName} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';

import {PlayerOptions} from './index';
import {LE, Lookup, PROTOCOL} from './data';

const ArgType = PROTOCOL.ArgType;

export interface ParsedLine {
  args: Protocol.BattleArgType;
  kwArgs: Protocol.BattleArgsKWArgType;
}

export class Info {
  p1: SideInfo;
  p2: SideInfo;

  constructor(gen: Generation, sides: {p1: PlayerOptions; p2: PlayerOptions}) {
    this.p1 = new SideInfo(gen, sides.p1);
    this.p2 = new SideInfo(gen, sides.p2);
  }
}

export class SideInfo {
  name: string;
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

export interface PokemonInfo {
  name: string;
  gender?: GenderName;
  shiny?: boolean;
}

export class Log {
  readonly gen: Generation;
  readonly lookup: Lookup;
  readonly info: Info;

  constructor(gen: Generation, lookup: Lookup, info: Info) {
    this.gen = gen;
    this.lookup = lookup;
    this.info = info;
  }

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

type Writeable<T> = { -readonly [P in keyof T]: T[P] };
type Decoder = (this: Log, offset: number, data: DataView) => {offset: number; line: ParsedLine};

const CANT: {[reason: number]: Protocol.Reason} = {
  [PROTOCOL.Cant.Sleep]: 'slp',
  [PROTOCOL.Cant.Freeze]: 'frz',
  [PROTOCOL.Cant.Paralysis]: 'par',
  [PROTOCOL.Cant.Trapped]: 'partiallytrapped',
  [PROTOCOL.Cant.Flinch]: 'flinch',
  [PROTOCOL.Cant.Recharge]: 'recharge',
  [PROTOCOL.Cant.PP]: 'nopp',
};

const DAMAGE = {
  [PROTOCOL.Damage.Poison]: 'psn' as Protocol.EffectName,
  [PROTOCOL.Damage.Burn]: 'psn' as Protocol.EffectName,
  [PROTOCOL.Damage.Confusion]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.Damage.LeechSeed]: 'Leech Seed' as Protocol.MoveName,
  [PROTOCOL.Damage.RecoilOf]: 'Recoil' as Protocol.EffectName,
};

const BOOSTS: {[reason: number]: BoostID} = {
  [PROTOCOL.Boost.Rage]: 'atk',
  [PROTOCOL.Boost.Attack]: 'atk',
  [PROTOCOL.Boost.Defense]: 'def',
  [PROTOCOL.Boost.Speed]: 'spe',
  [PROTOCOL.Boost.SpecialAttack]: 'spa',
  [PROTOCOL.Boost.SpecialDefense]: 'spd',
  [PROTOCOL.Boost.Accuracy]: 'accuracy',
  [PROTOCOL.Boost.Evasion]: 'evasion',
};

const FAIL: {[reason: number]: StatusName} = {
  [PROTOCOL.Fail.Sleep]: 'slp',
  [PROTOCOL.Fail.Poison]: 'psn',
  [PROTOCOL.Fail.Burn]: 'brn',
  [PROTOCOL.Fail.Freeze]: 'frz',
  [PROTOCOL.Fail.Paralysis]: 'par',
  [PROTOCOL.Fail.Toxic]: 'tox',
};

const ACTIVATE = {
  [PROTOCOL.Activate.Bide]: 'Bide' as Protocol.MoveName,
  [PROTOCOL.Activate.Confusion]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.Activate.Haze]: 'move: Haze' as Protocol.EffectName,
  [PROTOCOL.Activate.Mist]: 'move: Mist' as Protocol.EffectName,
  [PROTOCOL.Activate.Struggle]: 'move: Struggle' as Protocol.EffectName,
  [PROTOCOL.Activate.Substitute]: 'Substitute' as Protocol.MoveName,
  [PROTOCOL.Activate.Splash]: 'move: Splash' as Protocol.EffectName,
};

const START = {
  [PROTOCOL.Start.Bide]: 'Bide' as Protocol.MoveName,
  [PROTOCOL.Start.Confusion]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.Start.ConfusionSilent]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.Start.FocusEnergy]: 'move: Focus Energy' as Protocol.EffectName,
  [PROTOCOL.Start.LeechSeed]: 'move: Leech Seed' as Protocol.EffectName,
  [PROTOCOL.Start.LightScreen]: 'Light Screen' as Protocol.MoveName,
  [PROTOCOL.Start.Mist]: 'Mist' as Protocol.MoveName,
  [PROTOCOL.Start.Reflect]: 'Reflect' as Protocol.MoveName,
  [PROTOCOL.Start.Substitute]: 'Substitute' as Protocol.MoveName,
};

const END = {
  [PROTOCOL.End.Disable]: 'Disable' as Protocol.MoveName,
  [PROTOCOL.End.Confusion]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.End.Bide]: 'move: Bide' as Protocol.MoveName,
  [PROTOCOL.End.Substitute]: 'Substitute' as Protocol.MoveName,
  [PROTOCOL.End.DisableSilent]: 'Disable' as Protocol.MoveName,
  [PROTOCOL.End.ConfusionSilent]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.End.Mist]: 'Mist' as ID,
  [PROTOCOL.End.FocusEnergy]: 'move: Focus Energy' as ID,
  [PROTOCOL.End.LeechSeed]: 'move: Leech Seed' as ID,
  [PROTOCOL.End.LightScreen]: 'Light Screen' as ID,
  [PROTOCOL.End.Reflect]: 'Reflect' as ID,
};

export const DECODERS: {[key: number]: Decoder} = {
  [ArgType.Move](offset, data) {
    const source = decodeIdent(this.info, data.getUint8(offset++));
    const m = data.getUint8(offset++);
    const {player, id} = decodeIdentRaw(data.getUint8(offset++));
    const target = id === 0
      ? '' : `${player}a: ${this.info[player].team[id - 1].name}` as Protocol.PokemonIdent;
    const reason = data.getUint8(offset++);
    const move = reason === PROTOCOL.Move.Recharge
      ? 'recharge' : this.gen.moves.get(this.lookup.moveByNum(m))!.name;
    const args = ['move', source, move, target] as Protocol.Args['|move|'];
    const kwArgs = reason === PROTOCOL.Move.From
      ? {from: this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name} : {};
    return {offset, line: {args, kwArgs}};
  },
  [ArgType.Switch](offset, data) {
    const ident = decodeIdent(this.info, data.getUint8(offset++));
    const details = decodeDetails(offset, data, this.gen, this.lookup);
    offset += 2;
    const hpStatus = decodeHPStatus(offset, data);
    offset += 5;
    const args = ['switch', ident, details, hpStatus] as Protocol.Args['|switch|'];
    return {offset, line: {args, kwArgs: {}}};
  },
  [ArgType.Cant](offset, data) {
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
  },
  [ArgType.Faint](offset, data) {
    return decodeProtocol('faint', offset, data, this.info);
  },
  [ArgType.Turn](offset, data) {
    const turn = data.getUint16(offset, LE).toString() as Protocol.Num;
    offset += 2;
    return {offset, line: {args: ['turn', turn] as Protocol.Args['|turn|'], kwArgs: {}}};
  },
  [ArgType.Win](offset, data) {
    const player = data.getUint8(offset++) ? 'p2' : 'p1';
    const args =
      ['win', this.info[player].name as Protocol.Username] as Protocol.Args['|win|'];
    return {offset, line: {args, kwArgs: {}}};
  },
  [ArgType.Tie](offset) {
    const line = {args: ['tie'] as Protocol.Args['|tie|'], kwArgs: {}};
    return {offset, line};
  },
  [ArgType.Damage](offset, data) {
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
  },
  [ArgType.Heal](offset, data) {
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
  },
  [ArgType.Status](offset, data) {
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
  },
  [ArgType.CureStatus](offset, data) {
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
  },
  [ArgType.Boost](offset, data) {
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
  },
  [ArgType.ClearAllBoost](offset) {
    const args = ['-clearallboost'] as Protocol.Args['|-clearallboost|'];
    return {offset, line: {args, kwArgs: {}}};
  },
  [ArgType.Fail](offset, data) {
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
  },
  [ArgType.Miss](offset, data) {
    return decodeProtocol('-miss', offset, data, this.info);
  },
  [ArgType.HitCount](offset, data) {
    const ident = decodeIdent(this.info, data.getUint8(offset++));
    const num = data.getUint8(offset++).toString() as Protocol.Num;
    const args = ['-hitcount', ident, num] as Protocol.Args['|-hitcount|'];
    return {offset, line: {args, kwArgs: {}}};
  },
  [ArgType.Prepare](offset, data) {
    const source = decodeIdent(this.info, data.getUint8(offset++));
    const move = this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name;
    const args = ['-prepare', source, move] as Protocol.Args['|-prepare|'];
    return {offset, line: {args, kwArgs: {}}};
  },
  [ArgType.MustRecharge](offset, data) {
    return decodeProtocol('-mustrecharge', offset, data, this.info);
  },
  [ArgType.Activate](offset, data) {
    const ident = decodeIdent(this.info, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const args = reason === PROTOCOL.Activate.Splash
      ? ['-activate', '', ACTIVATE[reason]] as Protocol.Args['|-activate|']
      : ['-activate', ident, ACTIVATE[reason], ''] as Protocol.Args['|-activate|'];
    const kwArgs = reason === PROTOCOL.Activate.Substitute ? {damage: true} : {};
    return {offset, line: {args, kwArgs}};
  },
  [ArgType.FieldActivate](offset) {
    const effect = 'move: Pay Day' as Protocol.EffectName;
    const args = ['-fieldactivate', effect] as Protocol.Args['|-fieldactivate|'];
    return {offset, line: {args, kwArgs: {}}};
  },
  [ArgType.Start](offset, data) {
    const ident = decodeIdent(this.info, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    let args: Protocol.Args['|-start|'];
    const kwArgs = {} as Writeable<Protocol.BattleArgsKWArgs['|-start|']>;
    if (reason < PROTOCOL.Start.TypeChange) {
      args = ['-start', ident, START[reason]];
      if (reason === PROTOCOL.Start.ConfusionSilent) kwArgs.silent = true;
    } else if (reason === PROTOCOL.Start.TypeChange) {
      const types = decodeTypes(this.lookup, data.getUint8(offset++));
      const t = types[0] === types[1] ? types[0] : types.join('/');
      args = ['-start', ident, 'typechange', t as Protocol.Types];
      kwArgs.from = 'move: Conversion' as Protocol.EffectName;
      kwArgs.of = ident;
    } else {
      const move = this.gen.moves.get(this.lookup.moveByNum(data.getUint8(offset++)))!.name;
      const effect = reason === PROTOCOL.Start.Disable ? 'Disable' : 'Mimic';
      args = ['-start', ident, effect as Protocol.EffectName, move];
    }
    return {offset, line: {args, kwArgs}};
  },
  [ArgType.End](offset, data) {
    const ident = decodeIdent(this.info, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const args = ['-end', ident, END[reason]] as Protocol.Args['|-end|'];
    const kwArgs = reason >= PROTOCOL.End.DisableSilent ? {silent: true} : {};
    return {offset, line: {args, kwArgs}};
  },
  [ArgType.OHKO](offset) {
    return {offset, line: {args: ['-ohko'] as Protocol.Args['|-ohko|'], kwArgs: {}}};
  },
  [ArgType.Crit](offset, data) {
    return decodeProtocol('-crit', offset, data, this.info);
  },
  [ArgType.SuperEffective](offset, data) {
    return decodeProtocol('-supereffective', offset, data, this.info);
  },
  [ArgType.Resisted](offset, data) {
    return decodeProtocol('-resisted', offset, data, this.info);
  },
  [ArgType.Immune](offset, data) {
    const ident = decodeIdent(this.info, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const kwArgs = reason === PROTOCOL.Immune.OHKO ? {ohko: true} : {};
    return {offset, line: {args: ['-immune', ident] as Protocol.Args['|-immune|'], kwArgs}};
  },
  [ArgType.Transform](offset, data) {
    const source = decodeIdent(this.info, data.getUint8(offset++));
    const target = decodeIdent(this.info, data.getUint8(offset++));
    const args = ['-transform', source, target] as Protocol.Args['|-transform|'];
    return {offset, line: {args, kwArgs: {}}};
  },
};

function decodeProtocol(type: string, offset: number, data: DataView, info: Info) {
  const ident = decodeIdent(info, data.getUint8(offset++));
  return {offset, line: {args: [type, ident] as Protocol.BattleArgType, kwArgs: {}}};
}

function decodeIdent(info: Info, byte: number): Protocol.PokemonIdent {
  const {player, id} = decodeIdentRaw(byte);
  return `${player}a: ${info[player].team[id - 1].name}` as Protocol.PokemonIdent;
}

function decodeDetails(
  offset: number,
  data: DataView,
  gen: Generation,
  lookup: Lookup,
): Protocol.PokemonDetails {
  const species = gen.species.get(lookup.speciesByNum(data.getUint8(offset++)))!.name;
  const level = data.getUint8(offset);
  return (level === 100 ? species : `${species}, L${level}`) as Protocol.PokemonDetails;
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
  if ((val >> 3) & 1) return 'psn';
  if ((val >> 4) & 1) return 'brn';
  if ((val >> 5) & 1) return 'frz';
  if ((val >> 6) & 1) return 'par';
  // NOTE: this bit is also used in Gen I & II to indicate self-inflicted sleep,
  // but we should already have returned above with 'slp'
  if ((val >> 7) & 1) return 'tox';
  return undefined;
}

export function decodeTypes(lookup: Lookup, val: number): readonly [TypeName, TypeName] {
  return [lookup.typeByNum(val & 0x0F), lookup.typeByNum(val >> 4)];
}
