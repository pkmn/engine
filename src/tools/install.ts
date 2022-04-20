import 'source-map-support/register';

import * as https from 'https';
import * as path from 'path';
import * as fs from 'fs';
import {execFileSync} from 'child_process';
import {pipeline} from 'stream/promises';

if (+process.version.match(/^v(\d+)/)![1] < 16) {
  console.error('The pkmn engine requires Node v16+');
  process.exit(1);
}

try {
  require.resolve('7zip-min');
} catch (err: any) {
  if (err.code !== 'MODULE_NOT_FOUND') throw err;
  execFileSync('npm', ['install', '7zip-min', '--no-audit', '--no-save'], {
    cwd: path.resolve(__dirname, '../..'),
  });
}

const zip = require('7zip-min');

const ZIG_VERSION = {major: 0, minor: 9, patch: 1};
const VERSION = `${ZIG_VERSION.major}.${ZIG_VERSION.minor}.${ZIG_VERSION.patch}`;
const INDEX = 'https://ziglang.org/download/index.json';

const sh = (cmd: string, args: string[]) => execFileSync(cmd, args, {encoding: 'utf8'});
const fetch = (url: string) => new Promise<string>((resolve, reject) => {
  let buf = '';
  const req = https.request(url, res => {
    if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode!}`));
    res.on('data', d => {
      buf += d;
    });
    res.on('end', () => resolve(buf));
  });
  req.on('error', reject);
  req.end();
});
const download = (url: string, dest: string) => new Promise<void>((resolve, reject) => {
  const req = https.request(url, res => {
    if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode!}`));
    resolve(pipeline(res, fs.createWriteStream(dest)));
  });
  req.on('error', reject);
  req.end();
});
const unpack = (input: string, output: string) => new Promise<void>((resolve, reject) => {
  zip.unpack(input, output, (err: any) => {
    err ? reject(err) : resolve();
  });
});

// https://github.com/coilhq/tigerbeetle/blob/main/scripts/install_zig.sh
const install = async () => {
  try {
    const {zig_exe, version} = JSON.parse(sh('zig', ['env'])) as {zig_exe: string; version: string};
    const [major, minor, patch] = version.split('.').map((n: string) => parseInt(n));
    if (major > ZIG_VERSION.major ||
      (major >= ZIG_VERSION.major && minor > ZIG_VERSION.minor) ||
      (major >= ZIG_VERSION.major && minor >= ZIG_VERSION.minor && patch >= ZIG_VERSION.patch)) {
      console.log('Found existing compatible Zig executable:', zig_exe);
      return zig_exe;
    } else {
      console.log(`Existing Zig executable is not compatible (${version} < ${VERSION}): `, zig_exe);
    }
  } catch (err: any) {
    if (err.code !== 'ENOENT') throw err;
  }

  const arch = process.arch === 'x64'
    ? 'x86_64' : process.arch === 'arm64'
      ? 'aarch64' : process.arch;
  const platform = process.platform === 'darwin'
    ? 'macos' : process.platform === 'win32'
      ? 'windows' : process.platform;

  const dir = path.join(__dirname, '..', 'bin');
  try {
    fs.mkdirSync(dir);
  } catch (err: any) {
    if (err.code !== 'EEXIST') throw err;
  }

  const url: string = JSON.parse(await fetch(INDEX))[VERSION][`${arch}-${platform}`].tarball;

  let base = path.basename(url);
  const archive = `${dir}/${path.basename(url)}`;

  console.log(`Downloading Zig tarball from ${url} to ${archive}`);
  await download(url, archive);

  console.log(`Extracting tarball and installing to ${dir}`);
  if (archive.endsWith('.zip')) {
    await unpack(archive, dir);
    base = base.slice(0, -4);
  } else {
    const tar = archive.slice(0, -3);
    await unpack(archive, tar);
    await unpack(tar, dir);
    base = base.slice(0, -7);
  }

  fs.renameSync(`${dir}/${base}`, `${dir}/zig`);

  const zig = `${dir}/zig/zig`;
  fs.chmodSync(zig, 0o755);
  console.log(`Zig v${VERSION} executable:`, zig);

  return zig;
};

// https://github.com/coilhq/tigerbeetle-node/blob/main/scripts/download_node_headers.sh
const headers = async () => {
  const dir = path.join(__dirname, '..', 'include');
  try {
    fs.mkdirSync(dir);
  } catch (err: any) {
    if (err.code !== 'EEXIST') throw err;
  }

  const url = process.release.headersUrl!;
  const targz = `${dir}/${path.basename(url)}`;

  console.log(`Downloading Node headers from ${url} to ${targz}`);
  await download(url, targz);
  const tar = targz.slice(0, -3);
  await unpack(targz, tar);
  await unpack(tar, dir);

  const dest = `${dir}/node-${process.version}/include/node`;
  console.log('Node headers:', dest);

  return dest;
};

(async () => {
  const zig = await install();
  const include = await headers();

  console.log('Building build/lib/pkmn.node');
  sh(zig, ['build', '-Dshowdown', '-Drelease-fast', `-Dnode-headers=${include}`, '-Dstrip']);
})();

