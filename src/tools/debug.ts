import * as fs from 'fs';

import {Generation, Generations} from '@pkmn/data';

import {Battle, Choice, Info, Log, ParsedLine, Result, SideInfo} from '../pkg';
import * as addon from '../pkg/addon';
import {Data, LAYOUT, Lookup} from '../pkg/data';
import * as gen1 from '../pkg/gen1';
import {Frame, render} from '../test/display';

class SpeciesNames implements Info {
  gen: Generation;
  battle!: Battle;

  constructor(gen: Generation) {
    this.gen = gen;
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

export function display(gens: Generations, data: number[], error?: string, seed?: bigint) {
  if (!data.length) throw new Error('Invalid input');

  const view = Data.view(data);

  const showdown = !!view.getUint8(0);
  const gen = gens.get(view.getUint8(1));

  const lookup = Lookup.get(gen);
  const size = LAYOUT[gen.num - 1].sizes.Battle;
  const names = new SpeciesNames(gen);
  const log = new Log(gen, lookup, names);
  const deserialize = (buf: number[]): Battle => {
    // We don't care about the native addon, we just need to load it so other checks don't fail
    void addon.supports(true);
    switch (gen.num) {
    case 1: return new gen1.Battle(lookup, Data.view(buf), {showdown});
    default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };

  const end = view.getUint8(2);
  const head = 2 /* showdown + gen */ + 1;

  const frames: Frame[] = [];
  for (let offset = head + end; offset < data.length; offset += (3 + size)) {
    const result = Result.decode(data[offset]);
    const c1 = Choice.decode(data[offset + 1]);
    const c2 = Choice.decode(data[offset + 2]);
    const battle = deserialize(data.slice(offset + 3, offset + size + 3));
    names.battle = battle;

    const parsed: ParsedLine[] = [];
    const it = log.parse(Data.view(data.slice(offset + size + 3)))[Symbol.iterator]();
    let r = it.next();
    while (!r.done) {
      parsed.push(r.value);
      r = it.next();
    }
    offset += r.value;
    frames.push({result, c1, c2, battle, parsed});
  }

  return render(gen, showdown, error, seed, frames, {
    parsed: end > 0
      ? Array.from(log.parse(Data.view(data.slice(head, head + end))))
      : undefined,
  });
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
  process.stdout.write(display(gens, Array.from(input)));
}

if (require.main === module) {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  run(new Generations(require('@pkmn/sim').Dex)).catch(err => {
    console.error(err.message);
    process.exit(1);
  });
}
