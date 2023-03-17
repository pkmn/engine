import 'source-map-support/register';

import {execFile} from 'child_process';

const run = async (cmd: string, args: string[]): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    execFile(cmd, args, {encoding: 'buffer'}, (error, stdout) =>
      error ? reject(error) : resolve(stdout));
  });

const partition = (array: string[], n: number): string[][] =>
  array.length ? [array.splice(0, n)].concat(partition(array, n)) : [];

(async () => {
  const buf = await run('zig', ['build', 'serde', '--', process.argv[2].toString()]);
  const arr = Array.from(buf);
  const lines = partition(arr.map(x => `0x${x.toString(16).padStart(2, '0')}`), 16);
  console.log(lines.map(line => line.join(', ')).join(',\n'));
})().catch(err => {
  console.error(err);
  process.exit(1);
})
