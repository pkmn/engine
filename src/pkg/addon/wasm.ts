import type {Binding, Bindings} from '../addon';
import {LAYOUT} from '../data';

export function toBindings<T extends boolean>(w: WebAssembly.Exports): Bindings<T> {
  const memory = new Uint8Array((w.memory as WebAssembly.Memory).buffer);
  return {
    options: {
      showdown: !!memory[w.SHOWDOWN.valueOf()] as T,
      log: !!memory[w.LOG.valueOf()],
      chance: !!memory[w.CHANCE.valueOf()],
      calc: !!memory[w.CALC.valueOf()],
    },
    bindings: [toBinding(1, w)],
  };
}

function toBinding(gen: number, w: WebAssembly.Exports): Binding {
  const prefix = `GEN${gen}`;
  const buf = (w.memory as WebAssembly.Memory).buffer;

  const constants = new Uint32Array(buf);
  const CHOICES_SIZE = constants[w[`${prefix}_CHOICES_SIZE`].valueOf() / 4];
  const LOGS_SIZE = constants[w[`${prefix}_LOGS_SIZE`].valueOf() / 4];

  const size = LAYOUT[gen - 1].sizes.Battle;
  const update = w[`${prefix}_update`] as CallableFunction;
  const choices = w[`${prefix}_choices`] as CallableFunction;
  const memory = new Uint8Array(buf);

  return {
    CHOICES_SIZE,
    LOGS_SIZE,
    update(
      battle: ArrayBufferLike,
      c1: number,
      c2: number,
      log: ArrayBufferLike | undefined,
    ): number {
      const bytes = new Uint8Array(battle);
      memory.set(bytes, 0);

      let result: number;
      if (log) {
        result = update(0, c1, c2, size);
        new Uint8Array(log).set(memory.subarray(size, size + LOGS_SIZE));
      } else {
        result = update(0, c1, c2, 0);
      }

      bytes.set(memory.subarray(0, size));
      return result;
    },
    choices(
      battle: ArrayBufferLike,
      player: number,
      request: number,
      options: ArrayBufferLike,
    ): number {
      const opts = new Uint8Array(options);
      memory.set(new Uint8Array(battle));
      const n = choices(0, player, request, size);
      opts.set(memory.subarray(size, size + n));
      return n;
    },
  };
}
