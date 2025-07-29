import * as engine from '../../pkg';
import * as gen1 from '../../pkg/gen1';

// import {Select} from './select';
import {Battle, Gen, Generation, adapt} from './ui';
import {imports} from './util';

function toBinding(gen: number, w: WebAssembly.Exports) {
  const prefix = `GEN${gen}`;
  const buf = (w.memory as WebAssembly.Memory).buffer;

  const transitions = w[`${prefix}_transitions`] as CallableFunction;
  const deinit = w[`${prefix}_transitions_deinit`] as CallableFunction;
  const memory = new Uint8Array(buf);

  return {
    transitions(
      this: void,
      battle: ArrayBuffer,
      c1: number,
      c2: number,
      durations: bigint,
      cap: boolean,
    ): bigint {
      const bytes = new Uint8Array(battle);
      memory.set(bytes, 0);

      return transitions(0, c1, c2, durations, cap);
    },

    deinit(this: void, ref: bigint) {
      deinit(ref);
    },
  };
}

const App = ({gen, data, showdown, instance}: {
  gen: Generation;
  data: DataView;
  showdown: boolean;
  instance: WebAssembly.Instance;
}) => {
  const lookup = engine.Lookup.get(gen);
  const deserialize = (d: DataView): engine.Battle => {
    switch (gen.num) {
      case 1: return new gen1.Battle(lookup, d, {showdown});
      default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };
  const battle = deserialize(data);
  const {transitions, deinit} = toBinding(gen.num, instance.exports);

  const durations = 0n; // TODO
  const move = engine.Choice.encode(engine.Choice.move(1));
  const results =
    transitions(battle.bytes().buffer as ArrayBuffer, move, move, durations, true);
  console.debug(results);
  deinit(results);

  return <Battle battle={battle} gen={gen} showdown={showdown} hide={true} />;
};

const json = (window as any).DATA;
const wasm = (window as any).WASM;
const GEN = adapt(new Gen(json.gen));

const lookup = engine.Lookup.get(GEN);
const order: {species: string[]; moves: {[id: string]: string[]}} = {species: [], moves: {}};

let offset = 0;
const species = atob(json.order.species);
const moves = atob(json.order.moves);
for (let i = 0; i < species.length; i++) {
  const id = lookup.speciesByNum(species.charCodeAt(i));
  const specie = GEN.species.get(id)!;
  order.species.push(specie.name);

  const ids = [];
  for (; offset < moves.length && moves.charCodeAt(offset) !== 0; offset++) {
    ids.push(lookup.moveByNum(moves.charCodeAt(offset)));
  }
  offset++;
  order.moves[specie.id] = ids;
}

console.debug(order);

const bytes = Uint8Array.from(atob(wasm), c => c.charCodeAt(0));
const mod = new WebAssembly.Module(bytes);

const memory: [WebAssembly.Memory] = [null!];
const decoder = new TextDecoder();
WebAssembly.instantiate(mod, imports(memory, decoder)).then(instance => {
  memory[0] = instance.exports.memory as WebAssembly.Memory;
  return engine.initialize(json.showdown, instance).then(() => {
    const buf = Uint8Array.from(atob(json.buf), c => c.charCodeAt(0));
    document.getElementById('content')!.appendChild(<App
      gen={GEN}
      data={new DataView(buf.buffer, buf.byteOffset, buf.byteLength)}
      showdown={json.showdown}
      instance={instance}
    />);
  });
}).catch(console.error);

// const select = <Select options={order.species} placeholder='Tauros' />;

// document.getElementById('content')!.appendChild(select);
