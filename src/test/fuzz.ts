import 'source-map-support/register';

import {execFile} from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import {LE} from '../pkg/data';
import * as debug from '../tools/debug';

const ROOT = path.resolve(__dirname, '..', '..');

const usage = (msg?: string): void => {
  if (msg) console.error(msg);
  console.error('Usage: fuzz <pkmn|showdown> <GEN> <DURATION> <SEED?>');
  process.exit(1);
};

export async function run(
  gens: Generations,
  gen: number | string,
  showdown: boolean,
  testing?: boolean,
  duration?: string,
  seed?: bigint
) {
  const args = ['build', '--summary', 'failures', 'fuzz', '-Dlog', '-Dchance', '-Dcalc'];
  if (showdown) args.push('-Dshowdown');

  let input = undefined;
  if (typeof duration !== 'undefined') {
    args.push('--', gen.toString(), duration);
    if (seed) args.push(seed.toString());
  } else {
    input = fs.readFileSync(gen);
  }

  try {
    await new Promise<void>((resolve, reject) => {
      const child = execFile('zig', args, {encoding: 'buffer'}, (error, stdout, stderr) => {
        if (error) return reject({error, stdout, stderr});
        resolve();
      });
      if (child.stdin && input) {
        child.stdin.write(input);
        child.stdin.end();
      }
    });
    return true;
  } catch (err: any) {
    const {stdout, stderr} = err as {stdout: Buffer; stderr: Buffer};
    const raw = stderr.toString('utf8');
    const panic = raw.indexOf('panic: ');
    if (testing || !stdout.length) throw new Error(raw, {cause: err});

    console.error(raw);

    const dir = path.join(ROOT, 'logs');
    try {
      fs.mkdirSync(dir, {recursive: true});
    } catch (e: any) {
      if (e.code !== 'EEXIST') throw e;
    }

    seed = LE ? stdout.readBigUInt64LE(0) : stdout.readBigUInt64BE(0);
    const hex = `0x${seed.toString(16).toUpperCase()}`;
    let file = path.join(dir, `${hex}.fuzz.html`);
    let link = path.join(dir, 'fuzz.html');

    fs.writeFileSync(file, debug.render(gens, stdout.subarray(8), raw.slice(panic), seed));
    fs.rmSync(link, {force: true});
    fs.symlinkSync(file, link);

    file = path.join(dir, `${hex}.fuzz.json`);
    link = path.join(dir, 'fuzz.json');

    fs.writeFileSync(file, debug.render(gens, stdout.subarray(8), raw.slice(panic), seed, true));
    fs.rmSync(link, {force: true});
    fs.symlinkSync(file, link);

    return false;
  }
}

if (require.main === module) {
  (async () => {
    if (process.argv.length < 4 || process.argv.length > 6) usage(process.argv.length.toString());
    const mode = process.argv[2];
    if (mode !== 'pkmn' && mode !== 'showdown') {
      usage(`Mode must be either 'pkmn' or 'showdown', received '${mode}'`);
    }
    const gens = new Generations(Dex as any);
    const seed = process.argv.length > 5 ? BigInt(process.argv[5]) : undefined;
    await run(gens, process.argv[3], mode === 'showdown', false, process.argv[4], seed);
  })().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
