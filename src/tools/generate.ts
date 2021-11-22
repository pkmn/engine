import 'source-map-support/register';

import * as fs from 'fs';
import * as path from 'path';
import {fileURLToPath} from 'url';

import fetch from 'node-fetch';
import Mustache from 'mustache';

import {Generations, Generation, GenerationNum, TypeName} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const TEMPLATES = path.join(ROOT, 'src', 'lib', 'common', 'data');
const CACHE = path.join(ROOT, '.cache');

const NAMES: {[constant: string]: string} = {
  // Items
  BLACKBELT_I: 'BlackBelt',
  BLACKGLASSES: 'BlackGlasses',
  BLK_APRICORN: 'BlackApricorn',
  BLU_APRICORN: 'BlueApricorn',
  BLUESKY_MAIL: 'BlueSkyMail',
  BRIGHTPOWDER: 'BrightPowder',
  ELIXER: 'Elixir',
  ENERGYPOWDER: 'EnergyPowder',
  GRN_APRICORN: 'GreenApricorn',
  HP_UP: 'HPUp',
  LITEBLUEMAIL: 'LightBlueMail',
  MAX_ELIXER: 'MaxElixir',
  MIRACLEBERRY: 'MiracleBerry',
  MYSTERYBERRY: 'MysteryBerry',
  NEVERMELTICE: 'NeverMeltIce',
  PARLYZ_HEAL: 'ParylzeHeal',
  PNK_APRICORN: 'PinkApricorn',
  PORTRAITMAIL: 'PortrailMail',
  PP_UP: 'PPUp',
  PRZCUREBERRY: 'PRZCureBerry',
  PSNCUREBERRY: 'PSNCureBerry',
  RAGECANDYBAR: 'RageCandyBar',
  SILVERPOWDER: 'SilverPowder',
  SLOWPOKETAIL: 'SlowpokeTail',
  THUNDERSTONE: 'ThunderStone',
  TINYMUSHROOM: 'TinyMushroom',
  TWISTEDSPOON: 'TwistedSpoon',
  WHT_APRICORN: 'WhiteApricorn',
  YLW_APRICORN: 'YellowApricorn',
  // Moves
  SMELLING_SALT: 'SmellingSalts',
};

const nameToEnum = (s: string) => s.replace(/[^A-Za-z0-9]+/g, '');
const constToEnum = (s: string) =>
  s.split('_').map(w => `${w[0]}${w.slice(1).toLowerCase()}`).join('');

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
  file: string, dir: string, url: string, update: boolean,
  fn: (line: string, last: string) => string | undefined
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
    let last = '';
    for (const line of text.split('\n')) {
      const val = fn(line, last);
      if (val !== undefined) result.push(val);
      last = line;
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
      return nameToEnum(gen.moves.get(token)!.name);
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
      return match ? nameToEnum(gen.species.get(match[1])!.name) : undefined;
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

    // Items
    let url = `${pret}/data/items/attributes.asm`;
    const items = await getOrUpdate('items', dirs.cache, url, update, (line, last) => {
      const match = /^; ([A-Z]\w+)/.exec(last);
      if (!match || match[1].startsWith('HM') || match[1].startsWith('ITEM_')) return undefined;
      if (line.includes('KEY_ITEM')) return undefined;

      const held = /HELD_(\w+),/.exec(line)![1];
      const name = match[1].startsWith('TM')
        ? `${match[1]}`
        : (NAMES[match[1]] || constToEnum(match[1]));
      return `${name} ${held}`;
    });
    const values: string[] = [];
    const berries: string[] = [];
    const boosts: [string, TypeName][] = [];
    for (const item of items) {
      const [name, held] = item.split(' ');
      if (held === 'NONE') {
        values.push(`${name},`);
        continue;
      }
      const s = `${name}, // ${held}`;
      if (name.endsWith('Berry')) {
        berries.push(s);
      } else if (held.endsWith('_BOOST')) {
        boosts.push([name, gen.types.get(held.slice(0, held.indexOf('_')))!.name]);
      } else {
        values.push(s);
      }
    }
    for (const type of types.reverse()) {
      if (type === '???') {
        values.unshift('PolkadotBow, // ??? (Normal)');
      } else {
        for (const [n, t] of boosts) {
          if (t === type) {
            values.unshift(`${n}, // ${t}`);
            break;
          }
        }
      }
    }
    const berry = values.length;
    for (const s of berries) {
      values.push(s);
    }
    template('items', dirs.out, {
      gen: gen.num,
      Items: {
        type: 'u8',
        values: values.join('\n    '),
        size: 1,
        boosts: boosts.length,
        berry,
      },
    });

    // Moves
    url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, line => {
      const match = /move (\w+),/.exec(line);
      if (!match) return undefined;
      const token = match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1];
      return nameToEnum(gen.moves.get(token)!.name);
    });
    const MOVES: string[] = [];
    for (const name of moves) {
      const move = gen.moves.get(name)!;
      const pp = move.pp === 1 ? '0, // = 1' : `${move.pp / 5}, // * 5 = ${move.pp}`;
      const chance = move.secondary?.chance
        ? `${move.secondary.chance / 10}, // * 10 = ${move.secondary.chance}`
        : '0,';
      MOVES.push('Move{\n' +
        `        // ${name}\n` +
        `        .bp = ${move.basePower},\n` +
        `        .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `        .accuracy = ${move.accuracy === true ? '100' : move.accuracy},\n` +
        `        .pp = ${pp}\n` +
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
      return nameToEnum(gen.species.get(match[1])!.name);
    });
    template('species', dirs.out, {
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        size: 1,
      },
    });
  },
  3: async (gen, dirs, update) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokeemerald/master/';

    // Moves
    let url = `${pret}/include/constants/moves.h`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, line => {
      const match = /#define MOVE_(\w+)/.exec(line);
      if (!match || match[1] === 'NONE') return undefined;
      console.debug(match[1]);
      return NAMES[match[1]] || nameToEnum(gen.moves.get(match[1])!.name);
    });
    // const MOVES: string[] = [];
    // for (const name of moves) {
    //   const move = gen.moves.get(name)!;
    //   MOVES.push('Move{\n' +
    //     `        // ${name}\n` +
    //     `        .bp = ${move.basePower},\n` +
    //     `        .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
    //     `        .accuracy = ${move.accuracy === true ? '100' : move.accuracy},\n` +
    //     `        .pp = ${move.pp / 5}, // * 5 = ${move.pp}\n` +
    //     '    }');
    // }
    template('moves', dirs.out, {
      gen: gen.num,
      Moves: {
        type: 'u16',
        values: moves.join(',\n    '),
        size: 2,
      },
      MOVES: '//', // MOVES.join(',\n    '),
    });


    // Species
    url = `${pret}/include/constants/species.h`;
    const species = await getOrUpdate('species', dirs.cache, url, update, line => {
      const match = /#define NATIONAL_DEX_(\w+)\s+\d+/.exec(line);
      if (!match || match[1] === 'NONE' || match[1].startsWith('OLD_UNOWN')) return undefined;
      return nameToEnum(gen.species.get(match[1])!.name);
    });
    template('species', dirs.out, {
      Species: {
        type: 'u16',
        values: species.join(',\n    '),
        size: 2,
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

    await GEN[gen.num]!(gen, {out, cache}, update);
  }
})().catch((err: any) => {
  console.error(err);
  process.exit(1);
});
