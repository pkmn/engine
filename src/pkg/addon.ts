import {load, loadSync} from './addon/node';
import {Choice, Player, Result} from './common';

export type Argument = string | URL | WebAssembly.Module | WebAssembly.Instance | Promise<Response>;

export interface Bindings<T extends boolean> {
  /**
   * The compile-time options the bindings were built with. showdown is special
   * cased because it changes the name of addon.
   */
  options: {showdown: T; log: boolean; chance: boolean; calc: boolean};
  /** Bindings are per-generation, Generation I is index 0. */
  bindings: Binding[];
}

export interface Binding {
  CHOICES_SIZE: number;
  LOGS_SIZE: number;
  update(battle: ArrayBufferLike, c1: number, c2: number, log: ArrayBufferLike | undefined): number;
  choices(battle: ArrayBufferLike, player: number, request: number, out: ArrayBufferLike): number;
}

const ADDONS: [Bindings<false>?, Bindings<true>?] = [];
const loading: [Promise<Bindings<false>>?, Promise<Bindings<true>>?] = [];

/** TODO */
export async function initialize(showdown: boolean, addon?: Argument) {
  if (loading[+showdown]) {
    throw new Error(`Cannot call initialize more than once with showdown=${showdown}`);
  }
  loading[+showdown] = load(showdown, addon);
  loading[+showdown]!.then(a => {
    ADDONS[+showdown] = a;
  }).catch(() => {
    loading[+showdown] = undefined;
  });
  return loading[+showdown]?.then(() => {});
}

export function check(showdown: boolean) {
  if (!addons(showdown)[+showdown]) {
    const opts = ADDONS[+!showdown]!.options.log ? ['-log'] : [];
    if (showdown) opts.push('-Dshowdown');
    throw new Error(
      `@pkmn/engine has ${showdown ? 'not' : 'only'} been configured to support Pokémon Showdown.` +
      `\n(running \`npx install-pkmn-engine --options='${opts.join(' ')}'\` can fix this issue).`
    );
  }
}

export function supports(showdown: boolean, log?: boolean) {
  if (!addons(showdown)[+showdown]) return false;
  if (log === undefined) return true;
  return ADDONS[+showdown]!.options.log === log;
}

function addons(showdown: boolean) {
  if (ADDONS[+showdown]) return ADDONS;
  // If we havem't been initialized attempt to autoload if we're on Node
  ADDONS[+showdown] = loadSync(showdown);
  return ADDONS;
}

export function update(
  index: number,
  showdown: boolean,
  battle: ArrayBufferLike,
  c1?: Choice,
  c2?: Choice,
  log?: ArrayBufferLike,
) {
  return Result.decode(ADDONS[+showdown]!.bindings[index]
    .update(battle, Choice.encode(c1), Choice.encode(c2), log));
}

export function choices(
  index: number,
  showdown: boolean,
  battle: ArrayBufferLike,
  player: Player,
  choice: Choice['type'],
  out: Uint8Array,
) {
  const request = choice[0] === 'p' ? 0 : choice[0] === 'm' ? 1 : 2;
  const n =
    ADDONS[+showdown]!.bindings[index].choices(battle, +(player !== 'p1'), request, out.buffer);
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
  // but thats ultimately not worth the effort.
  const options = new Array<Choice>(n);
  for (let i = 0; i < n; i++) options[i] = Choice.decode(out[i]);
  return options;
}

export function size(index: number, type: 'choices' | 'log') {
  const bindings = (ADDONS[1] ?? ADDONS[0])!.bindings[index];
  return type[0] === 'c' ? bindings.CHOICES_SIZE : bindings.LOGS_SIZE;
}

