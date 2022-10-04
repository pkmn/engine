import 'source-map-support/register';

import {execFile} from 'child_process';
import {promisify} from 'util';

import {minify} from 'html-minifier';

import {Dex} from '@pkmn/sim';
import {Generation, Generations, GenerationNum} from '@pkmn/data';


import {Battle, Result, Choice, Log, ParsedLine, Names} from '../pkg';
import {Lookup, Data, LAYOUT, LE} from '../pkg/data';
import {STYLES, displayBattle, escapeHTML, SCRIPTS} from '../test/display';
import * as gen1 from '../pkg/gen1';

const run = promisify(execFile);

const usage = (msg?: string): void => {
  if (msg) console.error(msg);
  console.error('Usage: fuzz <pkmn|showdown> <GEN> <DURATION> <SEED?>');
  process.exit(1);
};

const pretty = (choice: Choice) =>
  choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`;

const format = (kwVal: any) => typeof kwVal === 'boolean' ? '' : ` ${kwVal as string}`;

const compact = (line: ParsedLine) =>
  [...line.args, ...Object.keys(line.kwArgs)
    .map(k => `[${k}]${format((line.kwArgs as any)[k])}`)].join('|');

const display = (
  gen: Generation,
  showdown: boolean,
  result: Result,
  c1: Choice,
  c2: Choice,
  battle: Battle,
  log: ParsedLine[],
  seed: bigint | Battle,
) => {
  const buf = [];
  if (typeof seed === 'bigint') buf.push(`<h1>0x${seed.toString(16).toUpperCase()}</h1>`);
  buf.push('<div class="log">');
  buf.push(`<pre><code>|${log.map(compact).join('\n|')}</code></pre>`);
  buf.push('</div>');
  buf.push(displayBattle(gen, showdown, battle, typeof seed === 'bigint' ? undefined : seed));
  buf.push('<div class="sides" style="text-align: center;">');
  buf.push(`<pre class="side"><code>${result.p1} -&gt; ${pretty(c1)}</code></pre>`);
  buf.push(`<pre class="side"><code>${result.p2} -&gt; ${pretty(c2)}</code></pre>`);
  buf.push('</div>');
  return buf.join('');
};

class SpeciesNames implements Names {
  gen: Generation;
  battle!: Battle;

  constructor(gen: Generation) {
    this.gen = gen;
  }

  get p1() {
    const [p1] = Array.from(this.battle.sides);
    const team = Array.from(p1.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => this.gen.species.get(p.stored.species)!.name);
    return {name: 'Player 1', team};
  }

  get p2() {
    const [, p2] = Array.from(this.battle.sides);
    const team = Array.from(p2.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => this.gen.species.get(p.stored.species)!.name);
    return {name: 'Player 2', team};
  }
}

(async () => {
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
  const names = new SpeciesNames(gen);
  const log = new Log(gen, lookup, names);
  const deserialize = (buf: number[]): Battle => {
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
    const raw = stderr.toString('utf8');
    const panic = raw.indexOf('panic: ');
    const error = raw.slice(panic);

    console.error(raw);

    const data = Array.from(stdout);
    if (!data.length) process.exit(1);

    const buf = [];

    buf.push(
      '<!doctype html><html lang=en><head>' +
        '<meta charset="utf-8">' +
        '<meta name="viewport" content="width=device-width, initial-scale=1">' +
        '<link rel="icon" href="https://pkmn.cc/favicon.ico">' +
        '<title>@pkmn/engine</title>' +
        `<style>${STYLES}
        h1 {
          text-align: center;
        }
        .error {
          overflow: auto;
          scrollbar-width: none;
        }
        .error::-webkit-scrollbar {
          display: none;
        }
        </style>` +
      '</head><body><div id="content">'
    );


    const view = Data.view(data);

    const head = 8 + 1;
    const seed = view.getBigUint64(0, LE);
    const end = view.getUint8(8);

    let last: Battle | undefined = undefined;
    for (let offset = head + end; offset < data.length; offset += (3 + size)) {
      const result = Result.parse(data[offset]);
      const c1 = Choice.parse(data[offset + 1]);
      const c2 = Choice.parse(data[offset + 2]);
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

      buf.push(display(gen, showdown, result, c1, c2, battle, parsed, last ?? seed));
      last = battle;
    }

    if (end > 0) {
      const logs = Array.from(log.parse(Data.view(data.slice(head, head + end))));
      buf.push('<div class="log">');
      buf.push(`<pre><code>|${logs.map(compact).join('\n|')}</code></pre>`);
      buf.push('</div>');
    }

    buf.push('<hr />');
    buf.push(`<pre class="error"><code>${escapeHTML(error)}</pre></code>`);
    buf.push(`</div><script>${SCRIPTS}</script></body></html>`);

    console.log(minify(buf.join(''), {minifyCSS: true, minifyJS: true}));
    process.exit(1);
  }
})().catch(err => {
  console.error(err);
  process.exit(1);
});
