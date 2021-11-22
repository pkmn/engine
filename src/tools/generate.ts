import 'source-map-support/register';

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

import fetch from 'node-fetch';
import Mustache from 'mustache';

import { Generations, Generation, GenerationNum, TypeName } from '@pkmn/data';
import { Dex } from '@pkmn/sim';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const TEMPLATES = path.join(ROOT, 'src', 'lib', 'common', 'data');
const CACHE = path.join(ROOT, '.cache');

const toEnum = (s: string) => s.replace(/[^A-Za-z0-9]+/g, '');
const mkdir = (dir: string) => {
  try {
    fs.mkdirSync(dir);
    return true;
  } catch (err: any) {
    if (err.code !== 'EEXIST') throw err;
    return false;
  }
};
const template = (file: string, dir: string, data: any, tmpl?: string) => {
  fs.writeFileSync(
    path.join(dir, `${file}.zig`),
    Mustache.render(
      fs.readFileSync(path.join(TEMPLATES, `${tmpl || file}.zig.tmpl`), 'utf8'),
      data
    )
  );
};

const getTypeChart = (gen: Generation, types: TypeName[]) => {
  const chart = [];
  for (const t1 of types) {
    const type1 = gen.types.get(t1)!;
    const effectiveness = [];
    for (const t2 of types) {
      const e = type1.effectiveness[t2];
      if (e === 2) {
        effectiveness.push('S');
      } else if (e === 1) {
        effectiveness.push('N');
      } else if (e === 0.5) {
        effectiveness.push('R');
      } else {
        effectiveness.push('I');
      }
    }
    chart.push(`[_]Effectiveness{ ${effectiveness.join(', ')} }, // ${t1}`);
  }
  return chart;
};
const getOrUpdate = async (
  file: string, dir: string, url: string, update: boolean, fn: (line: string) => string | undefined
) => {
  const cache = path.resolve(dir, `${file}.txt`);
  const cached = (() => {
    try {
      return fs.readFileSync(cache, 'utf8');
    } catch (err: any) {
      if (err.code !== 'ENOENT') throw err;
      return undefined;
    }
  })();

  if (!cached || update) {
    const result: string[] = [];
    const text = await (await fetch(url)).text();
    for (const line of text.split('\n')) {
      const val = fn(line);
      if (val !== undefined) result.push(val);
    }
    fs.writeFileSync(cache, result.join('\n') + '\n');
    return result;
  }

  const result: string[] = [];
  for (const line of cached.split('\n')) {
    if (line) result.push(line.trim());
  }
  return result;
};

type GenerateFn =
  (gen: Generation, dirs: { out: string; cache: string }, update: boolean) => Promise<void>;
const GEN: { [gen in GenerationNum]?: GenerateFn } = {
  1: async (gen, dirs, update) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokered/master/';
    // Moves
    let url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, line => {
      const match = /move (\w+),/.exec(line);
      if (!match) return undefined;
      const token = match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1];
      return toEnum(gen.moves.get(token)!.name);
    });
    const MOVES: string[] = [];
    for (const name of moves) {
      const move = gen.moves.get(name)!;
      MOVES.push('Move{\n' +
        `        // ${name}\n` +
        `        .bp = ${move.basePower},\n` +
        `        .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `        .accuracy = ${move.accuracy === true ? '100' : move.accuracy},\n` +
        `        .pp = ${move.pp / 5}, // * 5 = ${move.pp}\n` +
        '    }');
    }
    template('moves', dirs.out, {
      gen: gen.num,
      Moves: {
        type: 'u8',
        values: moves.join(',\n    '),
        size: 1,
      },
      MOVES: MOVES.join(',\n    '),
    });

    // Species
    url = `${pret}/constants/pokedex_constants.asm`;
    const species = await getOrUpdate('species', dirs.cache, url, update, line => {
      const match = /const DEX_(\w+)/.exec(line);
      return match ? toEnum(gen.species.get(match[1])!.name) : undefined;
    });
    template('species', dirs.out, {
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        size: 1,
      },
    });

    // Types
    const types = [
      'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost',
      'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon',
    ] as TypeName[];

    template('types', dirs.out, {
      Type: {
        type: 'u4',
        values: types.join(',\n    '),
        bitSize: 4,
      },
      Types: {
        num: types.length,
        chart: getTypeChart(gen, types).join('\n    '),
        bitSize: 8,
      },
    });
  },
  2: async (gen, dirs, update) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokecrystal/master/';
    // Moves
    let url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, line => {
      const match = /move (\w+),/.exec(line);
      if (!match) return undefined;
      const token = match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1];
      return toEnum(gen.moves.get(token)!.name);
    });
    const MOVES: string[] = [];
    for (const name of moves) {
      const move = gen.moves.get(name)!;
      const chance = move.secondary?.chance
        ? `${move.secondary.chance / 10}, // * 10 = ${move.secondary.chance}`
        : '0,';
      MOVES.push('Move{\n' +
        `        // ${name}\n` +
        `        .bp = ${move.basePower},\n` +
        `        .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `        .accuracy = ${move.accuracy === true ? '100' : move.accuracy},\n` +
        `        .pp = ${move.pp / 5}, // * 5 = ${move.pp}\n` +
        `        .chance = ${chance}\n` +
        '    }');
    }
    template('moves', dirs.out, {
      gen: gen.num,
      Moves: {
        type: 'u8',
        values: moves.join(',\n    '),
        size: 1,
      },
      MOVES: MOVES.join(',\n    '),
    });

    // Species
    url = `${pret}/constants/pokemon_constants.asm`;
    const species = await getOrUpdate('species', dirs.cache, url, update, line => {
      const match = /const (\w+)/.exec(line);
      if (!match || match[1] === 'EGG' || match[1].startsWith('UNOWN_')) return undefined;
      return toEnum(gen.species.get(match[1])!.name);
    });
    template('species', dirs.out, {
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        size: 1,
      },
    });

    // Types
    const types = [
      'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost', 'Steel',
      '???', 'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon', 'Dark',
    ] as TypeName[];

    template('types', dirs.out, {
      Type: {
        type: 'u8',
        values: types.map(t => t === '???' ? '@"???"' : t).join(',\n    '),
        bitSize: 8,
      },
      Types: {
        num: types.length,
        chart: getTypeChart(gen, types).join('\n    '),
        bitSize: 16,
      },
    });
  },
};

(async () => {
  const gens = new Generations(Dex as any);

  let UPDATE = process.argv[2] === '--force';
  if (mkdir(CACHE)) UPDATE = true;

  for (const n in GEN) {
    const gen = gens.get(+n as GenerationNum);

    const out = path.join(ROOT, 'src', 'lib', `gen${gen.num}`, 'data');
    const cache = path.join(CACHE, `gen${gen.num}`);

    let update = UPDATE;
    if (mkdir(out)) update = true;
    if (mkdir(cache)) update = true;

    await GEN[gen.num]!(gen, { out, cache }, update);
  }
})().catch((err: any) => {
  console.error(err);
  process.exit(1);
});
