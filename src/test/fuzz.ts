import 'source-map-support/register';

import {execFile} from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import {promisify} from 'util';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import {LE} from '../pkg/data';
import {display} from '../tools/debug';

const ROOT = path.resolve(__dirname, '..', '..');
const sh = promisify(execFile);

const usage = (msg?: string): void => {
  if (msg) console.error(msg);
  console.error('Usage: fuzz <pkmn|showdown> <GEN> <DURATION> <SEED?>');
  process.exit(1);
};

export async function run(
  gens: Generations,
  gen: number | string,
  showdown: boolean,
  duration: string,
  seed?: bigint,
  testing?: boolean,
) {
  const args = ['build', '-j1', '-fno-summary', 'fuzz', '-Dlog'];
  if (showdown) args.push('-Dshowdown');
  args.push('--', gen.toString(), duration);
  if (seed) args.push(seed.toString());

  try {
    await sh('zig', args, {encoding: 'buffer'});
    return true;
  } catch (err: any) {
    const {stdout, stderr} = err as {stdout: Buffer; stderr: Buffer};
    const raw = stderr.toString('utf8');
    const panic = raw.indexOf('panic: ');
    if (testing || !stdout.length) throw new Error(raw);

    console.error(raw);

    seed = LE ? stdout.readBigUInt64LE(0) : stdout.readBigUInt64BE(0);
    const output = display(gens, stdout.subarray(8), raw.slice(panic), seed);

    const dir = path.join(ROOT, 'logs');
    try {
      fs.mkdirSync(dir, {recursive: true});
    } catch (e: any) {
      if (e.code !== 'EEXIST') throw e;
    }

    const hex = `0x${seed.toString(16).toUpperCase()}`;
    const file = path.join(dir, `${hex}.fuzz.html`);
    const link = path.join(dir, 'fuzz.html');

    fs.writeFileSync(file, output);
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
    await run(gens, process.argv[3], mode === 'showdown', process.argv[4], seed);
  })().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
