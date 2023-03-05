import * as path from 'path';

import {GenerationNum} from '@pkmn/data';

import {Choice, Result} from '.';

const ROOT = path.join(__dirname, '..', '..');

let ADDON: AddOn | undefined = undefined;

interface AddOn {
  showdown?: Bindings<true>;
  pkmn?: Bindings<false>;
}

interface Bindings<T extends boolean> {
  options: { showdown: T; trace: boolean };
  bindings: Binding[];
}

interface Binding {
  OPTIONS_SIZE: number;
  LOGS_SIZE: number;
  update(battle: ArrayBuffer, c1: number, c2: number, log: ArrayBuffer | undefined): number;
  // TODO: choices(battle: ArrayBuffer, p: number, c: number): Choice[];
}

function load() {
  if (ADDON) return ADDON;
  let pkmn: Bindings<false> | undefined = undefined;
  let showdown: Bindings<true> | undefined = undefined;
  try {
    pkmn = require(path.join(ROOT, 'build', 'lib', 'pkmn.node')) as Bindings<false>;
    if (pkmn.options.showdown) throw new Error();
  } catch { }
  try {
    showdown = require(path.join(ROOT, 'build', 'lib', 'pkmn-showdown.node')) as Bindings<true>;
    if (!showdown.options.showdown) throw new Error();
  } catch { }
  if (!pkmn && !showdown) {
    throw new Error('Could not find native addons - did you run `npx install-pkmn-engine`?');
  }
  return (ADDON = {pkmn, showdown});
}

export function check(showdown?: boolean) {
  if (!load()[showdown ? 'showdown' : 'pkmn']) {
    const opts = ADDON![showdown ? 'pkmn' : 'showdown']!.options.trace ? ['-Dtrace'] : [];
    if (showdown) opts.push('-Dshowdown');
    throw new Error(`@pkmn/engine has ${showdown ? 'not ' : ''}been configured ` +
      `to ${showdown ? 'only ' : ''}support Pokémon Showdown compatibility mode.\n` +
      `(running \`npx install-pkmn-engine -- --options='${opts.join(' ')}'\` can fix this issue).`);
  }
}

export function supports(mode: 'showdown' | 'pkmn', trace?: boolean) {
  if (!load()[mode]) return false;
  if (trace === undefined) return true;
  return ADDON![mode]!.options.trace === trace;
}

// TODO: compare performance of skipping the load check and simply asserting `ADDON!`
export function update(
  gen: GenerationNum,
  showdown: boolean,
  battle: ArrayBuffer,
  c1?: Choice,
  c2?: Choice,
  log?: ArrayBuffer,
) {
  return Result.parse(load()[showdown ? 'showdown' : 'pkmn']!.bindings[gen - 1]
    .update(battle, Choice.encode(c1), Choice.encode(c2), log));
}

export function size(gen: GenerationNum, type: 'options' | 'log') {
  const addon = load();
  const bindings = (addon.showdown ?? addon.pkmn)!.bindings[gen - 1]!;
  return type === 'options' ? bindings.OPTIONS_SIZE : bindings.LOGS_SIZE;
}

