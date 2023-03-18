import 'source-map-support/register';

import {ExecFileSyncOptionsWithStringEncoding, execFileSync, execSync} from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import minimist from 'minimist';

const ROOT = path.resolve(__dirname, '..', '..');

const argv = minimist(process.argv.slice(2), {boolean: ['prod', 'dryRun']});
// const KEY = 'RWQJbSYgSRvYHXIqYwkOzpuV4eQW6roHp8PqUXcQAUk3suFmclEUZZff';

type Options = Omit<ExecFileSyncOptionsWithStringEncoding, 'encoding'> & {bypass?: boolean};
const sh = (cmd: string, args: string[], options: Options = {}) => {
  const cwd = (options.cwd ?? process.cwd()).toString();
  const env = {...process.env, ...options.env};
  const e = options.env
    ? `${Object.entries(options.env).map(([k, v]) => `${k}=${v!}`).join(' ')} ` : '';
  const run = `${e}${cmd} ${args.join(' ')}`;

  if (cwd !== process.cwd()) {
    console.log(`$(cd ${path.relative(process.cwd(), cwd)}; ${run})`);
  } else {
    console.log(run);
  }

  if (argv.dryRun && !options.bypass) return '';
  return execFileSync(cmd, args, {...options, env, cwd, encoding: 'utf8'});
};

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

if (sh('git', ['status', '--porcelain'])) {
  console.error('Cowardly refusing to cut a release with untracked changes.');
  process.exit(1);
}

sh('make', ['clean']);

const release = path.join(ROOT, 'release');
const relative = path.relative(process.cwd(), release);
try {
  console.log(`rm -rf ${relative} && mkdir -p ${relative}`);
  fs.rmSync(release, {force: true, recursive: true});
  fs.mkdirSync(release, {recursive: true});
} catch (err: any) {
  if (err.code !== 'EEXIST') throw err;
}

// eslint-disable-next-line
let version: string = require('../../package.json').version;
if (!argv.prod) {
  const HEAD = sh('git', ['rev-parse', 'HEAD'], {bypass: true}).slice(0, 8);
  version = `${version}-dev+${HEAD}`;
}

// xz vs. zip
for (const {triple, mcpu} of TARGETS) {
  for (const showdown of ['true', 'false']) {
    sh('zig', [
      'build',
      '-Doptimize=ReleaseFast',
      // FIXME '-Dstrip',
      `-Dtarget=${triple}`,
      `-Dcpu=${mcpu}`,
      `-Dshowdown=${showdown}`,
      '-Dtrace',
      '-p',
      `release/${triple}`,
    ]);
  }
  let archive: string;
  if (triple.includes('windows')) {
    archive = `libpkmn-${triple}-${version}.zip`;
    sh('7z', ['a', archive, `${triple}/`], {cwd: release});
  } else {
    archive = `libpkmn-${triple}-${version}.tar.xz`;
    const options = {cwd: release, env: {XZ_OPT: '-9'}};
    // --sort=name fails on macOS because not GNU...
    sh('tar', ['cJf', `libpkmn-${triple}-${version}.tar.xz`, `${triple}/`], options);
  }
  console.log(`rm -rf ${path.join(relative, triple)}`);
  fs.rmSync(path.join(release, triple), {force: argv.dryRun, recursive: true});
  if (argv.prod) {
    console.log(`$(cd ${relative}; echo | minisign -Sm ${archive})`);
    execSync(`echo | minisign -Sm ${archive}`, {cwd: release, stdio: 'ignore'});
  }
}

if (argv.prod) {
  sh('npm', ['build']);
  sh('npm', ['publish']);
  sh('git', ['tag', `v${version}`]);
  sh('git', ['push', '--tags', 'origin', 'main']);

  // TODO: upload release
}
