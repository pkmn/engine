import 'source-map-support/register';

import {execFileSync} from 'child_process';
import {promises as fs} from 'fs';
import * as path from 'path';

import {Generations, ID, PokemonSet, toID} from '@pkmn/data';
import {Dex} from '@pkmn/sim';
import {Smogon} from '@pkmn/smogon';

import {Battle, Choice, Lookup, initialize} from '../pkg';

import {Move, Species, pruneMove, pruneSpecies, render} from './display';
import {imports} from './display/util';

const ROOT = path.resolve(__dirname, '..', '..');

const sh = (cmd: string, args: string[]) => execFileSync(cmd, args, {encoding: 'utf8'});

const showdown = true;
const gens = new Generations(Dex as any);

// DEBUG
const URL = 'https://data.pkmn.cc/';
const fetch = async (url: string) => {
  if (!url.startsWith(URL)) throw new Error(`Invalid url: '${url}'`);
  const name = path.resolve(ROOT, '..', 'smogon', 'data', url.slice(URL.length + 1));
  const json = JSON.parse(await fs.readFile(name, 'utf8'));
  return {json: () => Promise.resolve(json)};
};

const smogon = new Smogon(fetch);

const gen = gens.get(process.argv[2]);
const lookup = Lookup.get(gen);

const SKIP = ['gen1lc'] as ID[];

(async () => {
  sh('zig', ['build', `-Dshowdown=${showdown.toString()}`, '-Ddemo', '-p', 'build']);

  const order: {
    global: {species: {[id: string]: number}; moves: {[id: string]: number}};
    local: number[];
  } = {global: await overall(), local: []};

  const data: {
    num: number;
    species: {[id: string]: Species};
    moves: {[id: string]: Move};
  } = {num: gen.num, species: {}, moves: {}};

  let p1: PokemonSet | undefined = undefined;
  let p2: PokemonSet | undefined = undefined;
  for (const id in order.global.species) {
    const s = gen.species.get(id)!;
    data.species[s.id] = pruneSpecies(gen, s);

    if (!p1) {
      p1 = (await smogon.sets(gen, s))[0] as PokemonSet;
      if (p1.moves.includes('Metronome')) throw new Error(`${s.name} set contains Metronome`);
    } else if (!p2) {
      p2 = (await smogon.sets(gen, s))[0] as PokemonSet;
      if (p2.moves.includes('Metronome')) throw new Error(`${s.name} set contains Metronome`);
    }

    let usage: ID[];
    try {
      if (SKIP.includes(Smogon.format(gen, s) as ID)) throw new Error();
      const stats = await smogon.stats(gen, s);
      usage = Object.keys(stats!.moves).filter(m => m !== 'Nothing' && m !== 'Metronome').map(toID);
    } catch {
      usage = (await smogon.sets(gen, s))[0]?.moves?.map(toID) ?? [];
      if (usage.includes('metronome' as ID)) throw new Error(`${s.name} set contains Metronome`);
    }

    const learnset: ID[] = [];
    for (const move in (await gen.learnsets.learnable(s.name))!) {
      if (!usage.includes(move as ID) && move !== 'metronome') learnset.push(move as ID);
    }
    learnset.sort((a, b) => order.global.moves[b] - order.global.moves[a]);

    order.local.push(...([...usage, ...learnset]).map(m => lookup.moveByID(toID(m))), 0);
  }
  for (const m of gen.moves) {
    if (m.id === 'metronome') continue;
    data.moves[m.id] = pruneMove(gen, m);
  }

  const file = path.join(ROOT, 'build', 'lib', `demo${showdown ? '-showdown' : ''}.wasm`);
  const bytes = await fs.readFile(file);
  const wasm = bytes.toString('base64');

  const memory: [WebAssembly.Memory] = [null!];
  const decoder = new TextDecoder();
  const instance = await WebAssembly.instantiate(
    new WebAssembly.Module(bytes.buffer as ArrayBuffer),
    imports(memory, decoder)
  );
  memory[0] = instance.exports.memory as WebAssembly.Memory;
  await initialize(showdown, instance);
  const battle = Battle.create(gen, {
    p1: {team: [p1!]}, p2: {team: [p2!]}, seed: [1, 2, 3, 4], showdown, log: false,
  });
  battle.update(Choice.pass, Choice.pass);

  process.stdout.write(render(path.join(ROOT, 'build', 'tools', 'display', 'demo.jsx'), {
    order: {
      species: Buffer.from(Object.keys(order.global.species)
        .map(s => lookup.speciesByID(s as ID))).toString('base64'),
      moves: Buffer.from(order.local).toString('base64'),
    },
    gen: data,
    buf: Buffer.from((battle as any).data.buffer).toString('base64'),
    showdown,
  }, {styles: [path.join(ROOT, 'src', 'tools', 'display', 'select.css')], wasm}));
})();

const TIERS = Object.fromEntries([
  'AG', 'Uber', '(Uber)',
  'OU', '(OU)', 'UUBL',
  'UU', 'RUBL', 'RU',
  'NUBL', 'NU', '(NU)',
  'PUBL', 'PU', '(PU)',
  'ZUBL', 'ZU', 'NFE', 'LC',
  'Unreleased', 'Illegal', 'CAP',
  'CAP NFE', 'CAP LC',
].map((t, i) => [t, i]));

function sort(
  weights: {[id: string]: number},
  cmp = (a: [string, number], b: [string, number]) => b[1] - a[1],
) {
  return Object.fromEntries(Object.entries(weights).sort(cmp).map((a, i) => [a[0], i]));
}

async function overall() {
  const species: {[id: string]: number} = {};
  const moves: {[id: string]: number} = {};

  for (const s of gen.species) {
    try {
      const stats = (await smogon.stats(gen, s, `gen${gen.num}ou` as ID))!;
      species[s.id] = stats.usage.weighted!;
      for (const m in stats.moves) {
        if (m === 'Nothing') continue;
        const id = toID(m);
        moves[id] = (moves[id] || 0) + (stats.moves[m] * stats.usage.weighted);
      }
    } catch {
      species[s.id] = 0;
    }
  }

  // Sort first by usage followed by tier
  const sorted = sort(species, (a, b) => b[1] - a[1] ||
    ((TIERS[gen.species.get(a[0])!.tier] ?? Infinity) -
      (TIERS[gen.species.get(b[0])!.tier] ?? Infinity)));
  return {species: sorted, moves: sort(moves)};
}
