import * as path from 'path';

import {Choice, Player, Result} from '.';

const ROOT = path.join(__dirname, '..', '..');

let ADDON: [Bindings<false>?, Bindings<true>?] | undefined = undefined;

interface Bindings<T extends boolean> {
  options: { showdown: T; log: boolean };
  bindings: Binding[];
}

interface Binding {
  CHOICES_SIZE: number;
  LOGS_SIZE: number;
  update(battle: ArrayBuffer, c1: number, c2: number, log: ArrayBuffer | undefined): number;
  choices(battle: ArrayBuffer, player: number, request: number, options: ArrayBuffer): number;
}

function load() {
  if (ADDON) return ADDON;
  let pkmn: Bindings<false> | undefined = undefined;
  let showdown: Bindings<true> | undefined = undefined;
  try {
    pkmn = require(path.join(ROOT, 'build', 'lib', 'pkmn.node')).engine as Bindings<false>;
  } catch { }
  try {
    showdown =
      require(path.join(ROOT, 'build', 'lib', 'pkmn-showdown.node')).engine as Bindings<true>;
  } catch { }
  if (!pkmn && !showdown) {
    throw new Error('Could not find native addons - did you run `npx install-pkmn-engine`?');
  }
  return (ADDON = [pkmn, showdown]);
}

export function check(showdown: boolean) {
  if (!load()[+showdown]) {
    const opts = ADDON![+!showdown]!.options.log ? ['-log'] : [];
    if (showdown) opts.push('-Dshowdown');
    throw new Error(
      `@pkmn/engine has ${showdown ? 'not' : 'only'} been configured to support Pokémon Showdown.` +
      `\n(running \`npx install-pkmn-engine --options='${opts.join(' ')}'\` can fix this issue).`
    );
  }
}

export function supports(showdown: boolean, log?: boolean) {
  if (!load()[+showdown]) return false;
  if (log === undefined) return true;
  return ADDON![+showdown]!.options.log === log;
}

export function update(
  index: number,
  showdown: boolean,
  battle: ArrayBuffer,
  c1?: Choice,
  c2?: Choice,
  log?: ArrayBuffer,
) {
  return Result.decode(ADDON![+showdown]!.bindings[index]
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
  // The top-level API signature means our hands our tied with respect to
  // writing really fast bindings here. The simplest approach would be to return
  // the ArrayBuffer the bindings populate as well as its size and only decode a
  // Choice after the selection. However, given that we need to return
  // `Choices[]` we need to decode all of them even if they're not all being
  // used which is wasteful. This shouldn't be *that* bad as its a very small
  // list, but its still wasted work. Switching the top-level API to return an
  // Iterable<Choice> doesn't help as we need both the length and the ability to
  // randomly access it, so the best way to make the current API fast would be
  // to have the Zig bindings create Choice objects directly, only that won't
  // scale well as it would require us to basically rewrite the low-level
  // choices function for each generation within node.zig. We could do something
  // really galaxy-brained and return some sort of frankenstein subclass of
  // Array backed by ArrayBuffer which would lazily decode the Choice on access,
  // but thats ultimately not worth the effort. You can't have both a high-level
  // idiomatic API and performance here, hence why the choose function below
  // exists.
  const options = new Array<Choice>(n);
  const data = new Uint8Array(buf);
  for (let i = 0; i < n; i++) options[i] = Choice.decode(data[i]);
  return options;
}

export function choose(
  index: number,
  showdown: boolean,
  battle: ArrayBuffer,
  player: Player,
  choice: Choice['type'],
  buf: ArrayBuffer,
  fn: (n: number) => number,
) {
  const request = choice[0] === 'p' ? 0 : choice[0] === 'm' ? 1 : 2;
  const n = ADDON![+showdown]!.bindings[index].choices(battle, +(player !== 'p1'), request, buf);
  const data = new Uint8Array(buf);
  return Choice.decode(data[fn(n)]);
}

export function size(index: number, type: 'choices' | 'log') {
  const bindings = (ADDON![1] ?? ADDON![0])!.bindings[index];
  return type[0] === 'c' ? bindings.CHOICES_SIZE : bindings.LOGS_SIZE;
}

