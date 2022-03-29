import {PokemonSet} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';

import {PROTOCOL} from './data';

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

