import * as fs from 'fs';

import {Generation, Generations} from '@pkmn/data';

import {Battle, Choice, Info, Log, Result, SideInfo} from '../pkg';
import * as addon from '../pkg/addon';
import {Data, LAYOUT, LE, Lookup} from '../pkg/data';
import * as gen1 from '../pkg/gen1';
import {Frame, render} from '../test/display';

class SpeciesNames implements Info {
  gen: Generation;
  battle: Battle;

  constructor(gen: Generation, battle: Battle) {
    this.gen = gen;
    this.battle = battle;
  }

  get p1() {
    const [p1] = Array.from(this.battle.sides);
    const team = Array.from(p1.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => ({species: p.stored.species}));
    return new SideInfo(this.gen, {name: 'Player 1', team});
  }

  get p2() {
    const [, p2] = Array.from(this.battle.sides);
    const team = Array.from(p2.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => ({species: p.stored.species}));
    return new SideInfo(this.gen, {name: 'Player 2', team});
  }
}

export function display(gens: Generations, data: Buffer, error?: string, seed?: bigint) {
  if (!data.length) throw new Error('Invalid input');

  const view = Data.view(data);

  let offset = 0;
  const showdown = !!view.getUint8(offset++);
  const gen = gens.get(view.getUint8(offset++));
  const N = view.getUint16(offset, LE);
  offset += 2;

  const lookup = Lookup.get(gen);
  const size = LAYOUT[gen.num - 1].sizes.Battle;
  const deserialize = (buf: Buffer): Battle => {
    // We don't care about the native addon, we just need to load it so other checks don't fail
    void addon.supports(true);
    switch (gen.num) {
    case 1: return new gen1.Battle(lookup, Data.view(buf), {showdown});
    default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };

  const battle = deserialize(data.subarray(offset, offset += size));
  const names = new SpeciesNames(gen, battle);
  const log = new Log(gen, lookup, names);

  let partial: Partial<Frame> | undefined = undefined;
  const frames: Frame[] = [];
  while (offset < view.byteLength) {
    partial = {parsed: []};
    const it = log.parse(Data.view(data.subarray(offset)))[Symbol.iterator]();
    let r = it.next();
    while (!r.done) {
      partial.parsed!.push(r.value);
      r = it.next();
    }
    offset += N || r.value;
    if (offset >= view.byteLength) break;

    partial.battle = deserialize(data.subarray(offset, offset += size));
    if (offset >= view.byteLength) break;

    partial.result = Result.decode(data[offset++]);
    if (offset >= view.byteLength) break;

    partial.c1 = Choice.decode(data[offset++]);
    if (offset >= view.byteLength) break;

    partial.c2 = Choice.decode(data[offset++]);

    frames.push(partial as Frame);
    partial = undefined;
  }

  return render(gen, showdown, error, seed, frames, partial);
}

export async function run(gens: Generations) {
  let input;
  if (process.argv.length > 2) {
    if (process.argv.length > 3) {
      console.error('Invalid input');
      process.exit(1);
    }
    input = fs.readFileSync(process.argv[2]);
  } else {
    let length = 0;
    const result: Uint8Array[] = [];
    for await (const chunk of process.stdin) {
      result.push(chunk);
      length += chunk.length;
    }
    input = Buffer.concat(result, length);
  }
  process.stdout.write(display(gens, input));
}

if (require.main === module) {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  run(new Generations(require('@pkmn/sim').Dex)).catch(err => {
    console.error(err.message);
    process.exit(1);
  });
}
