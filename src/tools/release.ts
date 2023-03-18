import 'source-map-support/register';

import {execFileSync} from 'child_process';

const sh = (cmd: string, args: string[]) => execFileSync(cmd, args, {encoding: 'utf8', env: {}});


const TARGETS = [
  // Windows
  {triple: 'x86_64-windows-gnu', mcpu: 'baseline'},
  {triple: 'aarch64-windows-gnu', mcpu: 'baseline'},
  // macOS
  {triple: 'x86_64-macos-none', mcpu: 'baseline'},
  {triple: 'aarch64-macos-none', mcpu: 'apple_a14'},
  // Linux
  {triple: 'x86_64-linux-musl', mcpu: 'baseline'},
  {triple: 'aarch64-linux-musl', mcpu: 'baseline'},
];

const HEAD = sh('git', ['rev-parse', 'HEAD']).slice(0, 8);
const dirty = !!sh('git', ['status',  '--porcelain']);
console.log(HEAD, dirty);

// (async () => {

// })().catch(err => {
//   console.error(err);
//   process.exit(1);
// })


