
import type {Argument} from '../addon';

import {toBindings} from './wasm';

export async function load(showdown: boolean, addon?: Argument) {
  if (typeof addon === 'string' && addon !== 'wasm') {
    throw new Error('Unable to load native addons in the browser!');
  }

  let wasm: WebAssembly.Instance;
  if (addon instanceof WebAssembly.Instance) {
    wasm = addon;
  } else if (addon instanceof WebAssembly.Module) {
    try {
      wasm = (await WebAssembly.instantiate(addon));
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`Could not instantiate WASM module!\n${err.message}`, {cause: err});
    }
  } else {
    const name = `pkmn${showdown ? '-showdown' : ''}.wasm`;
    try {
      const response = !addon || addon === 'wasm' ? fetch(name)
        : (addon as Promise<Response> | URL) instanceof URL ? fetch(addon) : addon;
      wasm = (await WebAssembly.instantiateStreaming(response)).instance;
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      const message = !addon || addon === 'wasm'
        ? `Could not find ${name} - did you run \`npx install-pkmn-engine\`?`
        : (addon as Promise<Response> | URL) instanceof URL
          ? `Could not fetch WASM module from '${(addon as URL).href}'!`
          : 'Could not instantiate WASM module!';
      throw new Error(`${message}\n${err.message}`, {cause: err});
    }
  }

  return toBindings(wasm.exports);
}

export function loadSync() {
  throw new Error('You must `initialize` the WASM addon before using the engine!');
}
