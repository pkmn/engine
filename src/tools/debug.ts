import {execFileSync} from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import {Generation, Generations} from '@pkmn/data';

import * as data from '../pkg/data';
import * as gen1 from '../pkg/gen1';

import * as display from './display';

const ROOT = path.resolve(__dirname, '..', '..');
const ZIG = path.dirname(parse(execFileSync('zig', ['env'], {encoding: 'utf8'})).lib_dir);

function parse(s: string) {
  try {
    return JSON.parse(s);
  } catch (e) {
    if (!(e instanceof SyntaxError)) throw e;
    const json = s
      // "key": -> "key": (ensures keys are quoted)
      .replace(/\.([a-zA-Z_][a-zA-Z0-9_]*)\s*=/g, '"$1":')
      // .{ -> { (converts ZON struct to JSON object)
      .replace(/\.\{/g, '{')
      // Remove trailing commas, which are invalid in JSON
      .replace(/,\s*([}\]])/g, '$1');
    return JSON.parse(json);
  }
};

export function error(err: string) {
  return (err
    .replaceAll(ROOT + path.sep, '')
    .replaceAll(ZIG, '$ZIG')
    .split('\n').slice(0, -3).join('\n'));
}

export function render(
  gens: Generation | Generations,
  buffer: Buffer,
  err?: string,
  seed?: bigint
) {
  if (!buffer.length) throw new Error('Invalid input');

  // Peek at the start of the data buffer just to figure out whether showdown is enabled, what
  // generation it is, and the intial state of the Battle
  const view = data.Data.view(buffer);

  let offset = 0;
  const showdown = !!view.getUint8(offset++);
  const num = view.getUint8(offset++);
  const gen = 'get' in gens ? gens.get(num) : gens;
  if (gen.num !== num) {
    throw new Error(`Require generation ${num} but was passed generation ${gen.num}`);
  }
  offset += 6;

  const lookup = data.Lookup.get(gen);
  const size = data.LAYOUT[gen.num - 1].sizes.Battle;

  const deserialize = (buf: Buffer) => {
    switch (gen.num) {
      case 1: return new gen1.Battle(lookup, data.Data.view(buf), {inert: true, showdown});
      default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };
  const battle = deserialize(buffer.subarray(offset, offset += size));

  return display.render(path.join(ROOT, 'build', 'tools', 'display', 'debug.jsx'), {
    gen: display.prune(gen, battle),
    buf: buffer.toString('base64'),
    error: err && error(err),
    seed: seed?.toString(),
  }, {styles: [path.join(ROOT, 'src', 'tools', 'display', 'debug.css')]});
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
  process.stdout.write(render(gens, input));
}

if (require.main === module) {
  run(new Generations(require('@pkmn/sim').Dex)).catch(err => {
    console.error(err.message);
    process.exit(1);
  });
}
