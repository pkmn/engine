import 'source-map-support/register';

import * as fs from 'fs';
import * as path from 'path';
import * as https from 'https';

import * as mustache from 'mustache';

import { Generations, Generation, GenerationNum, TypeName, Specie } from '@pkmn/data';
import { Dex, toID } from '@pkmn/sim';

import type { IDs } from '..';

const ROOT = path.resolve(__dirname, '..', '..');
const TEMPLATES = path.join(ROOT, 'src', 'lib', 'common', 'data');
const CACHE = path.join(ROOT, '.cache');

const IDS: IDs = {
  1: {
    types: [
      'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost',
      'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon',
    ] as TypeName[],
  },
  2: {
    types: [
      'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost', 'Steel',
      '???', 'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon', 'Dark',
    ] as TypeName[],
    items: [],
  },
  3: {
    items: [],
  },
};

const NAMES: { [constant: string]: string } = {
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
    mustache.render(
      fs.readFileSync(path.join(TEMPLATES, `${tmpl || file}.zig.tmpl`), 'utf8'),
      data
    )
  );
};

const fetch = (url: string): Promise<string> => new Promise((resolve, reject) => {
  let buf = '';
  const req = https.request(url, res => {
    if (res.statusCode === 301 || res.statusCode === 302) {
      return resolve(fetch(res.headers.location!));
    } else if (res.statusCode !== 200) {
      return reject(new Error(`HTTP ${res.statusCode!}`));
    }
    res.on('data', d => {
      buf += d;
    });
    res.on('end', () => resolve(buf));
  });
  req.on('error', reject);
  req.end();
});

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

const convertGenderRatio = (species: Specie) => {
  if (species.gender === 'N') return '0xFF, // N';
  switch (species.genderRatio.F) {
    case 0: return '0x00, // 0.00% F';
    case 0.125: return '0x1F, // 12.5% F';
    case 0.25: return '0x3F, // 25.0% F';
    case 0.5: return '0x7F, // 50.0% F';
    case 0.75: return '0xBF, // 75.0% F';
    case 1: return '0xFE, // 100% F';
    default:
      throw new Error(`Invalid gender ratio for ${species.name}`);
  }
};

const getOrUpdate = async (
  file: string, dir: string, url: string, update: boolean,
  fn: (line: string, last: string, i: number) => string | undefined
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
    const text = await fetch(url);
    let last = '';
    for (const line of text.split('\n')) {
      const val = fn(line, last, result.length);
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
    const pret = 'https://raw.githubusercontent.com/pret/pokered/master';
    // Moves
    let url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, (line, _, i) => {
      const match = /move (\w+),/.exec(line);
      if (!match) return undefined;
      const move = gen.moves.get(match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1])!;
      if (move.num !== i + 1) {
        throw new Error(`Expected ${move.num} for ${move.name} and received ${i + 1}`);
      }
      return nameToEnum(move.name);
    });
    const MOVES: string[] = [];
    const PP: string[] = [];
    for (const name of moves) {
      const move = gen.moves.get(name)!;
      MOVES.push(`// ${name}\n` +
        '        .{\n' +
        `            .bp = ${move.basePower},\n` +
        `            .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `            .acc = ${move.accuracy === true ? '14' : move.accuracy / 5 - 6},\n` +
        '        }');
      PP.push(`${move.pp}, // ${name}`);
    }
    template('moves', dirs.out, {
      gen: gen.num,
      Moves: {
        type: 'u8',
        values: moves.join(',\n    '),
        size: 1,
        data: MOVES.join(',\n        '),
        dataSize: MOVES.length * 2,
        ppData: PP.join('\n        '),
      },
    });

    // Species
    url = `${pret}/constants/pokedex_constants.asm`;
    const species = await getOrUpdate('species', dirs.cache, url, update, (line, _, i) => {
      const match = /const DEX_(\w+)/.exec(line);
      if (!match) return undefined;
      const specie = gen.species.get(match[1])!;
      if (specie.num !== i + 1) {
        throw new Error(`Expected ${specie.num} for ${specie.name} and received ${i + 1}`);
      }
      return nameToEnum(specie.name);
    });
    const SPECIES = [];
    for (const name of species) {
      const s = gen.species.get(name)!;
      const types = s.types.length === 1
        ? [s.types[0], s.types[0]] : s.types;
      SPECIES.push(`// ${name}\n` +
        '        .{\n' +
        '            .stats = .{\n' +
        `                .hp = ${s.baseStats.hp},\n` +
        `                .atk = ${s.baseStats.atk},\n` +
        `                .def = ${s.baseStats.def},\n` +
        `                .spe = ${s.baseStats.spe},\n` +
        `                .spc = ${s.baseStats.spa},\n` +
        '            },\n' +
        `            .types = .{ .type1 = .${types[0]}, .type2 = .${types[1]} },\n` +
        '        }');
    }
    template('species', dirs.out, {
      gen: gen.num,
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        size: 1,
        data: SPECIES.join(',\n        '),
      },
    });

    // Types
    const types = IDS[1].types;
    template('types', dirs.out, {
      Type: {
        type: 'u4',
        values: types.join(',\n    '),
        bitSize: 4,
        num: types.length,
        chart: getTypeChart(gen, types).join('\n        '),
        chartSize: types.length * types.length,
      },
      Types: {
        bitSize: 8,
      },
    });
  },
  2: async (gen, dirs, update) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokecrystal/master';

    // Types
    const types = IDS[2].types;
    template('types', dirs.out, {
      Type: {
        type: 'u8',
        values: types.map(t => t === '???' ? '@"???"' : t).join(',\n    '),
        bitSize: 8,
        num: types.length,
        chart: getTypeChart(gen, types).join('\n        '),
        chartSize: types.length * types.length,
      },
      Types: {
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
    const mail: string[] = [];
    const berries: string[] = [];
    const boosts: [string, TypeName][] = [];
    for (const item of items) {
      const [name, held] = item.split(' ');
      if (held === 'NONE') {
        if (name.endsWith('Mail')) {
          mail.push(`${name},`);
        } else {
          values.push(`${name},`);
        }
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
    const offset = { mail: 0, berries: 0 };
    offset.mail = values.length;
    for (const s of mail) {
      values.push(s);
    }
    offset.berries = values.length;
    for (const s of berries) {
      values.push(s);
    }
    for (const value of values) {
      IDS[2].items.push(toID(value.split(' ')[0]));
    }
    template('items', dirs.out, {
      gen: gen.num,
      Items: {
        type: 'u8',
        values: values.join('\n    '),
        size: 1,
        boosts: boosts.length,
        mail: offset.mail,
        berry: offset.berries,
      },
    });

    // Moves
    url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, (line, _, i) => {
      const match = /move (\w+),/.exec(line);
      if (!match) return undefined;
      const move = gen.moves.get(match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1])!;
      if (move.num !== i + 1) {
        throw new Error(`Expected ${move.num} for ${move.name} and received ${i + 1}`);
      }
      return nameToEnum(move.name);
    });
    const MOVES: string[] = [];
    const PP: string[] = [];
    for (const name of moves) {
      const move = gen.moves.get(name)!;
      const pp = move.pp === 1 ? '0, // = 1' : `${move.pp / 5}, // * 5 = ${move.pp}`;
      const chance = move.secondary?.chance
        ? `${move.secondary.chance / 10}, // * 10 = ${move.secondary.chance}`
        : '';
      MOVES.push(`// ${name}\n` +
        '        .{\n' +
        `            .bp = ${move.basePower},\n` +
        `            .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `            .accuracy = ${move.accuracy === true ? '100' : move.accuracy},\n` +
        `            .pp = ${pp}\n` +
        (chance ? `            .chance = ${chance}\n` : '') +
        '        }');
      PP.push(`${move.pp}, // ${name}`);
    }
    template('moves', dirs.out, {
      gen: gen.num,
      Moves: {
        type: 'u8',
        values: moves.join(',\n    '),
        size: 1,
        data: MOVES.join(',\n        '),
        dataSize: MOVES.length * 4,
        ppData: PP.join('\n        '),
      },
    });

    // Species
    url = `${pret}/constants/pokemon_constants.asm`;
    const species = await getOrUpdate('species', dirs.cache, url, update, (line, _, i) => {
      const match = /const (\w+)/.exec(line);
      if (!match || match[1] === 'EGG' || match[1].startsWith('UNOWN_')) return undefined;
      const specie = gen.species.get(match[1])!;
      if (specie.num !== i + 1) {
        throw new Error(`Expected ${specie.num} for ${specie.name} and received ${i + 1}`);
      }
      return nameToEnum(specie.name);
    });
    const SPECIES = [];
    for (const name of species) {
      const s = gen.species.get(name)!;
      const t = s.types.length === 1
        ? [s.types[0], s.types[0]] : s.types;
      SPECIES.push(`// ${name}\n` +
        '        .{\n' +
        '            .stats = .{\n' +
        `                .hp = ${s.baseStats.hp},\n` +
        `                .atk = ${s.baseStats.atk},\n` +
        `                .def = ${s.baseStats.def},\n` +
        `                .spe = ${s.baseStats.spe},\n` +
        `                .spa = ${s.baseStats.spa},\n` +
        `                .spd = ${s.baseStats.spd},\n` +
        '            },\n' +
        `            .types = .{ .type1 = .${t[0]}, .type2 = .${t[1]} },\n` +
        `            .ratio = ${convertGenderRatio(s)}\n` +
        '        }');
    }
    template('species', dirs.out, {
      gen: gen.num,
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        size: 1,
        data: SPECIES.join(',\n        '),
      },
    });
  },
  3: async (gen, dirs, update) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokeemerald/master';

    // Moves
    let url = `${pret}/include/constants/moves.h`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, (line, _, i) => {
      const match = /#define MOVE_(\w+)/.exec(line);
      if (!match || match[1] === 'NONE') return undefined;
      const move = gen.moves.get(NAMES[match[1]] || match[1])!;
      if (move.num !== i + 1) {
        throw new Error(`Expected ${move.num} for ${move.name} and received ${i + 1}`);
      }
      return nameToEnum(move.name);
    });
    // const MOVES: string[] = [];
    // const PP: string[] = [];
    // for (const name of moves) {
    //   const move = gen.moves.get(name)!;
    //   MOVES.push(`// ${name}\n` +
    //     '        .{\n' +
    //     `            .bp = ${move.basePower},\n` +
    //     `            .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
    //     `            .accuracy = ${move.accuracy === true ? '100' : move.accuracy},\n` +
    //     `            .pp = ${move.pp / 5}, // * 5 = ${move.pp}\n` +
    //     '        }');
    //   PP.push(`${move.pp}, // ${name}`);
    // }
    template('moves', dirs.out, {
      gen: gen.num,
      Moves: {
        type: 'u16',
        values: moves.join(',\n    '),
        size: 2,
        data: '//', // MOVES.join(',\n        '),
        dataSize: 0,
        ppData: '//', // PP.join('\n        '),
      },
    });

    // Species
    url = `${pret}/include/constants/species.h`;
    const species = await getOrUpdate('species', dirs.cache, url, update, (line, _, i) => {
      const match = /#define NATIONAL_DEX_(\w+)\s+\d+/.exec(line);
      if (!match || match[1] === 'NONE' || match[1].startsWith('OLD_UNOWN')) return undefined;
      if (!match || match[1] === 'EGG' || match[1].startsWith('UNOWN_')) return undefined;
      const specie = gen.species.get(match[1])!;
      if (specie.num !== i + 1) {
        throw new Error(`Expected ${specie.num} for ${specie.name} and received ${i + 1}`);
      }
      return nameToEnum(specie.name);
    });
    const SPECIES = [];
    for (const name of species) {
      const s = gen.species.get(name)!;
      const types = s.types.length === 1
        ? [s.types[0], s.types[0]] : s.types;
      // FIXME abilities
      SPECIES.push(`// ${name}\n` +
        '        .{\n' +
        '            .stats = .{\n' +
        `                .hp = ${s.baseStats.hp},\n` +
        `                .atk = ${s.baseStats.atk},\n` +
        `                .def = ${s.baseStats.def},\n` +
        `                .spe = ${s.baseStats.spe},\n` +
        `                .spa = ${s.baseStats.spa},\n` +
        `                .spd = ${s.baseStats.spd},\n` +
        '            },\n' +
        `            .types = .{ .type1 = .${types[0]}, .type2 = .${types[1]} },\n` +
        `            .ratio = ${convertGenderRatio(s)}\n` +
        '        }');
    }
    template('species', dirs.out, {
      gen: gen.num,
      Species: {
        type: 'u16',
        values: species.join(',\n    '),
        size: 2,
        data: SPECIES.join(',\n        '),
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

  fs.writeFileSync(path.join(ROOT, 'src', 'ids.json'), JSON.stringify(IDS));
})().catch((err: any) => {
  console.error(err);
  process.exit(1);
});
