import 'source-map-support/register';

import {execFile} from 'child_process';
import {promisify} from 'util';

import {Dex} from '@pkmn/sim';
import {Generation, Generations, GenerationNum} from '@pkmn/data';

import {Battle, Result, Choice} from '../pkg';
import {Lookup, Data, LAYOUT} from '../pkg/data';
import * as gen1 from '../pkg/gen1';

import stringify from 'json-stringify-pretty-compact';

const run = promisify(execFile);

const usage = (msg?: string): void => {
  if (msg) console.error(msg);
  console.error('Usage: fuzz <pkmn|showdown> <GEN> <DURATION> <SEED?>');
  process.exit(1);
};

const pretty = (choice: Choice) =>
  choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`;

const display = (
  gen: Generation,
  result: Result | undefined,
  c1: Choice,
  c2: Choice,
  battle: Battle
) => {
  const [p1, p2] = Array.from(battle.sides);
  const header = {turn: battle.turn, lastDamage: battle.lastDamage, prng: battle.prng};
  console.log(`<div><pre><code>${stringify(header)}</code></pre><table>`);
  if (result) {
    console.log(`<tr><th><pre><code>(${result.p1})&gt; p1 ${pretty(c2)}</code></pre></th>`);
    console.log(`<th><pre><code>(${result.p2})&gt; p2 ${pretty(c2)}</code></pre></th></tr>`);
  }
  console.log(`<tr><td><pre><code>${stringify(p1)}</code></pre></td>`);
  console.log(`<td><pre><code>${stringify(p2)}</code></pre><td></tr>`);
  console.log('</table></div>');
};

(async () => {
  console.debug(Result.parse(0b0101_0000), Result.parse(0b1000_0000));
  if (process.argv.length < 4 || process.argv.length > 6) usage(process.argv.length.toString());
  const mode = process.argv[2];
  if (mode !== 'pkmn' && mode !== 'showdown') {
    usage(`Mode must be either 'pkmn' or 'showdown', received '${mode}'`);
  }
  const showdown = mode === 'showdown';

  const gens = new Generations(Dex as any);
  const gen = gens.get(+process.argv[3] as GenerationNum);
  const lookup = Lookup.get(gen);
  const size = LAYOUT[gen.num - 1].sizes.Battle;
  const create = (buf: number[]): Battle => {
    switch (gen.num) {
    case 1: return new gen1.Battle(lookup, Data.view(buf), {showdown});
    default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };

  const args = ['build', 'fuzz', '-Dtrace'];
  if (showdown) args.push('-Dshowdown');
  args.push('--', gen.num.toString(), process.argv[4]);
  if (process.argv.length > 5) args.push(process.argv[5].toString());

  try {
    await run('zig', args, {encoding: 'buffer'});
  } catch (err: any) {
    const {stdout, stderr} = err as {stdout: Buffer; stderr: Buffer};
    console.error(stderr.toString('utf8'));

    console.log(
      '<!doctype html><html lang=en><head>' +
        '<meta charset="utf-8">' +
        '<meta name="viewport" content="width=device-width, initial-scale=1">' +
        '<link rel="icon" href="pkmn.cc/favicon.ico">' +
        '<title>@pkmn/engine</title>' +
        '<style>td { vertical-align: top; }</style>' +
      '</head><body><div id="content">'
    );

    const data = Array.from(stdout);
    for (let i = 0; ; i++) {
      const offset = i * (3 + size);
      if (offset >= data.length) break;

      const result = i === 0 ? undefined : Result.parse(data[offset]);
      const c1 = Choice.parse(data[offset + 1]);
      const c2 = Choice.parse(data[offset + 2]);
      const battle = create(data.slice(offset + 3, offset + size + 3));

      display(gen, result, c1, c2, battle);
    }

    console.log('</div></body></html>');
  }
})().catch(console.error);
