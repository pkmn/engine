import {Generation, PokemonSet, StatusName, TypeName, BoostID, ID} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';

import {LE, Lookup, PROTOCOL} from './data';

const ArgType = PROTOCOL.ArgType;

export interface ParsedLine {
  args: Protocol.BattleArgType;
  kwargs: Protocol.BattleArgsKWArgType;
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

export const Log = new class {
  // TODO: what should go into instance variables?
  *parse(gen: Generation, data: DataView, names: Names, lookup: Lookup): Iterable<ParsedLine> {
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
        const decoded = DECODERS[byte]?.(i, data, names, gen, lookup);
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
type Decoder = (offset: number, data: DataView, names: Names, gen: Generation, lookup: Lookup)
=> {offset: number; line: ParsedLine};

const CANT: {[reason: number]: Protocol.Reason} = {
  [PROTOCOL.Cant.Sleep]: 'slp',
  [PROTOCOL.Cant.Freeze]: 'frz',
  [PROTOCOL.Cant.Paralysis]: 'par',
  [PROTOCOL.Cant.Trapped]: 'partiallytrapped',
  [PROTOCOL.Cant.Flinch]: 'flinch',
  [PROTOCOL.Cant.Recharging]: 'recharge',
  [PROTOCOL.Cant.PP]: 'nopp',
};

const DAMAGE = {
  [PROTOCOL.Damage.Poison]: 'psn' as Protocol.EffectName,
  [PROTOCOL.Damage.Burn]: 'psn' as Protocol.EffectName,
  [PROTOCOL.Damage.Confusion]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.Damage.PoisonOf]: 'psn' as Protocol.EffectName,
  [PROTOCOL.Damage.BurnOf]: 'brn' as Protocol.EffectName,
  [PROTOCOL.Damage.RecoilOf]: 'Recoil' as Protocol.EffectName,
  [PROTOCOL.Damage.LeechSeedOf]: 'Leech Seed' as Protocol.MoveName,
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
  [PROTOCOL.Activate.Confusion]: 'confusion' as Protocol.EffectName,
  [PROTOCOL.Activate.Bide]: 'Bide' as Protocol.MoveName,
  [PROTOCOL.Activate.Haze]: 'move: Haze' as Protocol.EffectName,
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
  [PROTOCOL.End.Mist]: 'mist' as ID,
  [PROTOCOL.End.FocusEnergy]: 'focusenergy' as ID,
  [PROTOCOL.End.LeechSeed]: 'leechseed' as ID,
  [PROTOCOL.End.Toxic]: 'toxic' as ID,
  [PROTOCOL.End.LightScreen]: 'lightscreen' as ID,
  [PROTOCOL.End.Reflect]: 'reflect' as ID,
};

export const DECODERS: {[key: number]: Decoder} = {
  [ArgType.Move]: (offset, data, names, gen, lookup) => {
    const source = decodeIdent(names, data.getUint8(offset++));
    const m = data.getUint8(offset++);
    const target = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const move = reason === PROTOCOL.Move.Recharge
      ? 'recharge' : gen.moves.get(lookup.moveByNum(m))!.name;
    const args = ['move', source, move, target] as Protocol.Args['|move|'];
    const kwargs = reason === PROTOCOL.Move.From
      ? {from: gen.moves.get(lookup.moveByNum(data.getUint8(offset++)))!.name} : {};
    return {offset, line: {args, kwargs}};
  },
  [ArgType.Switch]: (offset, data, names, gen, lookup) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const details = decodeDetails(offset, data, gen, lookup);
    offset += 2;
    const hpStatus = decodeHPStatus(offset, data);
    offset += 5;
    const args = ['switch', ident, details, hpStatus] as Protocol.Args['|switch|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.Cant]: (offset, data, names, gen, lookup) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    let args: Protocol.Args['|cant|'];
    if (reason === PROTOCOL.Cant.Disable) {
      const move = gen.moves.get(lookup.moveByNum(data.getUint8(offset++)))!.name;
      args = ['cant', ident, 'Disable' as Protocol.MoveName, move];
    } else {
      args = ['cant', ident, CANT[reason]];
    }
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.Faint]: (offset, data, names) => decodeProtocol('fainted', offset, data, names),
  [ArgType.Turn]: (offset, data) => {
    const turn = data.getUint16(offset, LE).toString() as Protocol.Num;
    offset += 2;
    return {offset, line: {args: ['turn', turn] as Protocol.Args['|turn|'], kwargs: {}}};
  },
  [ArgType.Win]: (offset, data, names) => {
    const player = data.getUint8(offset++) ? 'p2' : 'p1';
    const args = ['win', names[player].player] as Protocol.Args['|win|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.Tie]: (offset) => {
    const line = {args: ['tie'] as Protocol.Args['|tie|'], kwargs: {}};
    return {offset, line};
  },
  [ArgType.Damage]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const hpStatus = decodeHPStatus(offset, data);
    offset += 5;
    const reason = data.getUint8(offset++);
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-damage|']>;
    if (reason >= PROTOCOL.Damage.None) kwargs.from = DAMAGE[reason];
    if (reason >= PROTOCOL.Damage.PoisonOf) {
      kwargs.of = decodeIdent(names, data.getUint8(offset++));
    }
    const args = ['-damage', ident, hpStatus] as Protocol.Args['|-damage|'];
    return {offset, line: {args, kwargs}};
  },
  [ArgType.Heal]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const hpStatus = decodeHPStatus(offset, data);
    offset += 5;
    const reason = data.getUint8(offset++);
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-heal|']>;
    if (reason === PROTOCOL.Heal.Drain) {
      kwargs.from = 'drain' as Protocol.EffectName;
      kwargs.of = decodeIdent(names, data.getUint8(offset++));
    } else if (reason === PROTOCOL.Heal.Silent) {
      kwargs.silent = true;
    }
    const args = ['-heal', ident, hpStatus] as Protocol.Args['|-heal|'];
    return {offset, line: {args, kwargs}};
  },
  [ArgType.Status]: (offset, data, names, gen, lookup) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const status = decodeStatus(data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-status|']>;
    if (reason === PROTOCOL.Status.Silent) {
      kwargs.silent = true;
    } else if (reason === PROTOCOL.Status.From) {
      kwargs.from = gen.moves.get(lookup.moveByNum(data.getUint8(offset++)))!.name;
    }
    const args = ['-status', ident, status] as Protocol.Args['|-status|'];
    return {offset, line: {args, kwargs}};
  },
  [ArgType.CureStatus]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const status = decodeStatus(data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-status|']>;
    if (reason === PROTOCOL.Status.Silent) kwargs.silent = true;
    const args = ['-status', ident, status] as Protocol.Args['|-status|'];
    return {offset, line: {args, kwargs}};
  },
  [ArgType.Boost]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const boost = BOOSTS[reason];
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-boost|']>;
    if (reason === PROTOCOL.Boost.Rage) {
      kwargs.from = 'Rage' as Protocol.MoveName;
    }
    const num = data.getUint8(offset++).toString() as Protocol.Num;
    const args = ['-boost', ident, boost, num] as Protocol.Args['|-boost|'];
    return {offset, line: {args, kwargs}};
  },
  [ArgType.Unboost]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const boost = BOOSTS[reason];
    const num = data.getUint8(offset++).toString() as Protocol.Num;
    const args = ['-unboost', ident, boost, num] as Protocol.Args['|-unboost|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.ClearAllBoost]: (offset) => {
    const args = ['-clearallboost'] as Protocol.Args['|-clearallboost|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.Fail]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    let args: Protocol.Args['|-fail|'];
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-fail|']>;
    const weak = reason === PROTOCOL.Fail.Weak;
    if (weak || reason === PROTOCOL.Fail.Substitute) {
      args = ['-fail', ident, 'move: Substitute' as Protocol.EffectName];
      if (weak) kwargs.weak = true;
    } else if (reason !== PROTOCOL.Fail.None) {
      args = ['-fail', ident, FAIL[reason]];
    } else {
      args = ['-fail', ident];
    }
    return {offset, line: {args, kwargs}};
  },
  [ArgType.Miss]: (offset, data, names) => {
    const source = decodeIdent(names, data.getUint8(offset++));
    const target = decodeIdent(names, data.getUint8(offset++));
    const args = ['-miss', source, target] as Protocol.Args['|-miss|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.HitCount]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const num = data.getUint8(offset++).toString() as Protocol.Num;
    const args = ['-hitcount', ident, num] as Protocol.Args['|-hitcount|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.Prepare]: (offset, data, names, gen, lookup) => {
    const source = decodeIdent(names, data.getUint8(offset++));
    const move = gen.moves.get(lookup.moveByNum(data.getUint8(offset++)))!.name;
    const args = ['-prepare', source, move] as Protocol.Args['|-prepare|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.MustRecharge]: (offset, data, names) =>
    decodeProtocol('-mustrecharge', offset, data, names),
  [ArgType.Activate]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const args = ['-activate', ident, ACTIVATE[reason]] as Protocol.Args['|-activate|'];
    const kwargs = reason === PROTOCOL.Activate.Substitute ? {damage: true} : {};
    return {offset, line: {args, kwargs}};
  },
  [ArgType.FieldActivate]: (offset) => {
    const effect = 'move: Pay Day' as Protocol.EffectName;
    const args = ['-fieldactivate', effect] as Protocol.Args['|-fieldactivate|'];
    return {offset, line: {args, kwargs: {}}};
  },
  [ArgType.Start]: (offset, data, names, gen, lookup) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    let args: Protocol.Args['|-start|'];
    const kwargs = {} as Writeable<Protocol.BattleArgsKWArgs['|-start|']>;
    if (reason < PROTOCOL.Start.TypeChange) {
      args = ['-start', ident, START[reason]];
      if (reason === PROTOCOL.Start.ConfusionSilent) kwargs.silent = true;
    } else if (reason === PROTOCOL.Start.TypeChange) {
      const types = decodeTypes(lookup, data.getUint8(offset++));
      const t = types[0] === types[1] ? types[0] : types.join(', ');
      args = ['-start', ident, 'typechange' as Protocol.EffectName, t as Protocol.Types];
      kwargs.from = 'move: Conversion' as Protocol.EffectName;
      kwargs.of = ident;
    } else {
      const move = gen.moves.get(lookup.moveByNum(data.getUint8(offset++)))!.name;
      const effect = reason === PROTOCOL.Start.Disable ? 'Disable' : 'Mimic';
      args = ['-start', ident, effect as Protocol.EffectName, move];
    }
    return {offset, line: {args, kwargs}};
  },
  [ArgType.End]: (offset, data, names) => {
    const ident = decodeIdent(names, data.getUint8(offset++));
    const reason = data.getUint8(offset++);
    const args = ['-end', ident, END[reason]] as Protocol.Args['|-end|'];
    const kwargs = reason >= PROTOCOL.End.DisableSilent ? {silent: true} : {};
    return {offset, line: {args, kwargs}};
  },
  [ArgType.OHKO]: (offset) =>
    ({offset, line: {args: ['-ohko'] as Protocol.Args['|-ohko|'], kwargs: {}}}),
  [ArgType.Crit]: (offset, data, names) => decodeProtocol('-crit', offset, data, names),
  [ArgType.SuperEffective]: (offset, data, names) =>
    decodeProtocol('-supereffective', offset, data, names),
  [ArgType.Resisted]: (offset, data, names) => decodeProtocol('-resisted', offset, data, names),
  [ArgType.Immune]: (offset, data, names) => decodeProtocol('-immune', offset, data, names),
  [ArgType.Transform]: (offset, data, names) => {
    const source = decodeIdent(names, data.getUint8(offset++));
    const target = decodeIdent(names, data.getUint8(offset++));
    const args = ['-transform', source, target] as Protocol.Args['|-transform|'];
    return {offset, line: {args, kwargs: {}}};
  },
};

function decodeProtocol(type: string, offset: number, data: DataView, names: Names) {
  const ident = decodeIdent(names, data.getUint8(offset++));
  return {offset, line: {args: [type, ident] as Protocol.BattleArgType, kwargs: {}}};
}

function decodeIdent(names: Names, byte: number): Protocol.PokemonIdent {
  const player = (byte >> 4) === 0 ? 'p1' : 'p2';
  const slot = byte & 0x0F;
  return `${player}a: ${names[player].team[slot - 1]}` as Protocol.PokemonIdent;
}

function decodeDetails(
  offset: number,
  data: DataView,
  gen: Generation,
  lookup: Lookup,
): Protocol.PokemonDetails {
  const species = gen.species.get(lookup.specieByNum(data.getUint8(offset++)))!.name;
  const level = data.getUint8(offset);
  return (level === 100 ? species : `${species}, L${level}`) as Protocol.PokemonDetails;
}

function decodeHPStatus(offset: number, data: DataView): Protocol.PokemonHPStatus {
  const hp = data.getUint16(offset, LE);
  offset += 2;
  const maxhp = data.getUint16(offset, LE);
  offset += 2;
  const status = hp === 0 ? 'fnt' : decodeStatus(data.getUint8(offset));
  return (status ? `${hp}/${maxhp} ${status}` : `${hp}/${maxhp}`) as Protocol.PokemonHPStatus;
}

export function decodeStatus(val: number): StatusName | undefined {
  if ((val >> 3) & 1) return 'psn';
  if ((val >> 4) & 1) return 'brn';
  if ((val >> 5) & 1) return 'frz';
  if ((val >> 6) & 1) return 'par';
  if ((val >> 7) & 1) return 'tox';
  return val > 0 ? 'slp' : undefined;
}

export function decodeTypes(lookup: Lookup, val: number): readonly [TypeName, TypeName] {
  return [lookup.typeByNum(val & 0x0F), lookup.typeByNum(val >> 4)];
}
