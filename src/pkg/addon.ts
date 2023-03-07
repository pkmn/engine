import * as path from 'path';

import {Choice, Player, Result} from '.';

const ROOT = path.join(__dirname, '..', '..');

let ADDON: [Bindings<false>?, Bindings<true>?] | undefined = undefined;

interface Bindings<T extends boolean> {
  options: { showdown: T; trace: boolean };
  bindings: Binding[];
}

interface Binding {
  OPTIONS_SIZE: number;
  LOGS_SIZE: number;
  update(battle: ArrayBuffer, c1: number, c2: number, log: ArrayBuffer | undefined): number;
  choices(battle: ArrayBuffer, player: number, request: number, options: ArrayBuffer): number;
}

function load() {
  if (ADDON) return ADDON;
  let pkmn: Bindings<false> | undefined = undefined;
  let showdown: Bindings<true> | undefined = undefined;
  try {
    pkmn = require(path.join(ROOT, 'build', 'lib', 'pkmn.node')) as Bindings<false>;
  } catch { }
  try {
    showdown = require(path.join(ROOT, 'build', 'lib', 'pkmn-showdown.node')) as Bindings<true>;
  } catch { }
  if (!pkmn && !showdown) {
    throw new Error('Could not find native addons - did you run `npx install-pkmn-engine`?');
  }
  return (ADDON = [pkmn, showdown]);
}

export function check(showdown: boolean) {
  if (!load()[+showdown]) {
    const opts = ADDON![+!showdown]!.options.trace ? ['-Dtrace'] : [];
    if (showdown) opts.push('-Dshowdown');
    throw new Error(
      `@pkmn/engine has ${showdown ? 'not' : 'only'} been configured to support Pokémon Showdown.` +
      `\n(running \`npx install-pkmn-engine --options='${opts.join(' ')}'\` can fix this issue).`
    );
  }
}

export function supports(showdown: boolean, trace?: boolean) {
  if (!load()[+showdown]) return false;
  if (trace === undefined) return true;
  return ADDON![+showdown]!.options.trace === trace;
}

export function update(
  index: number,
  showdown: boolean,
  battle: ArrayBuffer,
  c1?: Choice,
  c2?: Choice,
  log?: ArrayBuffer,
) {
  return Result.parse(ADDON![+showdown]!.bindings[index]
    .update(battle, Choice.encode(c1), Choice.encode(c2), log));
}

export function choices(
  index: number,
  showdown: boolean,
  battle: ArrayBuffer,
  player: Player,
  choice: Choice['type'],
  buf: ArrayBuffer,
) {
  const request = choice[0] === 'p' ? 0 : choice[0] === 'm' ? 1 : 2;
  const n = ADDON![+showdown]!.bindings[index].choices(battle, +(player !== 'p1'), request, buf);
  const options = new Array<Choice>(n);
  const data = new Uint8Array(buf);
  for (let i = 0; i < n; i++) options[i] = Choice.parse(data[i]);
  return options;
}

export function size(index: number, type: 'options' | 'log') {
  const bindings = (ADDON![1] ?? ADDON![0])!.bindings[index]!;
  return type[0] === 'o' ? bindings.OPTIONS_SIZE : bindings.LOGS_SIZE;
}

