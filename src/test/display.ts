import * as fs from 'fs';
import * as path from 'path';

import {BoostID, Generation, ID, StatID, TypeName} from '@pkmn/data';
import {Icons, Sprites} from '@pkmn/img';
import {minify} from 'html-minifier';
import * as mustache from 'mustache';

import {Battle, Choice, Data, ParsedLine, Pokemon, Result, Side} from '../pkg';

const ROOT = path.resolve(__dirname, '..', '..');
const template = (s: 'pkmn' | 'showdown') =>
  path.join(ROOT, 'src', 'test', 'display', `${s}.html.tmpl`);

const POSITIONS = ['a', 'b', 'c', 'd', 'e', 'f'];
const VOLATILES: {[id in keyof Pokemon['volatiles']]: [string, 'good' | 'bad' | 'neutral']} = {
  bide: ['Bide', 'good'],
  thrashing: ['Thrashing', 'neutral'],
  flinch: ['Flinch', 'bad'],
  charging: ['Charging', 'good'],
  binding: ['Binding', 'bad'],
  invulnerable: ['Invulnerable', 'good'],
  confusion: ['Confusion', 'bad'],
  mist: ['Mist', 'good'],
  focusenergy: ['Focus Energy', 'good'],
  substitute: ['Substitute', 'good'],
  recharging: ['Recharging', 'bad'],
  rage: ['Rage', 'neutral'],
  leechseed: ['Leech Seed', 'bad'],
  lightscreen: ['Light Screen', 'good'],
  reflect: ['Reflect', 'good'],
  transform: ['Transformed', 'neutral'],
};

const pretty = (choice?: Choice) => choice
  ? choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`
  : '???';

const format = (kwVal: any) => typeof kwVal === 'boolean' ? '' : ` ${kwVal as string}`;
const trim = (args: string[]) => {
  while (args.length && !args[args.length - 1]) args.pop();
  return args;
};

const compact = (line: ParsedLine) =>
  [...trim(line.args.slice(0) as string[]), ...Object.keys(line.kwArgs)
    .map(k => `[${k}]${format((line.kwArgs as any)[k])}`)].join('|');

const debug = (s: string) => s.startsWith('|debug')
  ? /^\|debug\|[^|]*:\d/.test(s) ? 'class="debug rng"'
  : 'class="debug"' : '';

export const toText = (parsed: ParsedLine[]) => `|${parsed.map(compact).join('\n|')}`;

export type Frame = {
  result: Result;
  c1: Choice;
  c2: Choice;
} & ({
  battle: Data<Battle>;
  parsed: ParsedLine[];
} | {
  seed: number[];
  chunk: string;
});

export function render(
  gen: Generation,
  showdown: boolean,
  error: string | undefined,
  seed: bigint | undefined,
  frames: Iterable<Frame>,
  partial: Partial<Frame> = {},
) {
  const output: string[] = [];
  const buf = [];
  if (seed) buf.push(`<h1>0x${seed.toString(16).toUpperCase()}</h1>`);

  let last: Data<Battle> | number[] | undefined = undefined;
  for (const frame of frames) {
    buf.push(displayFrame(gen, showdown, frame, last));
    if ('battle' in frame) {
      last = frame.battle;
    } else {
      last = frame.seed;
      output.push(frame.chunk);
    }
  }
  buf.push(displayFrame(gen, true, partial, last));

  if (error) {
    const err = error.replaceAll(ROOT + path.sep, '');
    buf.push(`<pre class="error"><code>${escapeHTML(err)}</pre></code>`);
  }

  const type = Array.isArray(last) ? 'showdown' : 'pkmn';
  return minify(
    mustache.render(fs.readFileSync(template(type), 'utf8'), type === 'pkmn'
      ? {content: buf.join('')}
      : {
        seed: buf.shift(),
        content: buf.join(''),
        output: output.join('\n'),
      }),
    {minifyCSS: true, minifyJS: true}
  );
}

function displayFrame(
  gen: Generation,
  showdown: boolean,
  partial: Partial<Frame>,
  last?: Data<Battle> | number[],
) {
  const buf = [];
  if ('parsed' in partial && partial.parsed) {
    buf.push('<div class="log">');
    buf.push(`<pre><code>${toText(partial.parsed)}</code></pre>`);
    buf.push('</div>');
  } else if ('chunk' in partial && partial.chunk) {
    buf.push('<div class="log"><pre>');
    for (const line of partial.chunk.split('\n')) {
      buf.push(`<code ${debug(line)}>${line}</code><br />`);
    }
    buf.push('</pre></div>');
  }
  if ('battle' in partial && partial.battle) {
    buf.push(displayBattle(gen, showdown, partial.battle, last as Data<Battle>));
  } else if ('seed' in partial && partial.seed) {
    buf.push(`<div class="seed">${partial.seed.join(', ')}</div>`);
  }
  if (partial.result) {
    const {result, c1, c2} = partial;
    buf.push('<div class="sides" style="text-align: center;">');
    buf.push(`<pre class="side"><code>${result.p1} -&gt; ${pretty(c1)}</code></pre>`);
    buf.push(`<pre class="side"><code>${result.p2} -&gt; ${pretty(c2)}</code></pre>`);
    buf.push('</div>');
  }
  return buf.join('');
}

function displayBattle(
  gen: Generation,
  showdown: boolean,
  battle: Data<Battle>,
  last?: Data<Battle>,
) {
  const buf = [];
  buf.push('<div class="battle">');
  if (battle.turn) {
    buf.push('<div class="details">');
    buf.push(`<h2>Turn ${battle.turn}</h2>`);
    buf.push('<div class="inner">');
    buf.push(`<div><strong>Last Damage:</strong> ${battle.lastDamage}</div>`);
    buf.push(`<div><strong>Seed:</strong> ${battle.prng.join(', ')}</div>`);
    buf.push('</div>');
    buf.push('</div>');
  }
  buf.push('<div class="sides">');
  const [p1, p2] = Array.from(battle.sides);
  const [o1, o2] = last ? Array.from(last.sides) : [undefined, undefined];
  buf.push(displaySide(gen, showdown, !!battle.turn, 'p1', p1, o1));
  buf.push(displaySide(gen, showdown, !!battle.turn, 'p2', p2, o2));
  buf.push('</div>');
  buf.push('</div>');
  return buf.join('');
}

function displaySide(
  gen: Generation,
  showdown: boolean,
  started: boolean,
  player: 'p1' | 'p2',
  side: Side,
  last?: Side,
) {
  const buf = [];
  buf.push(`<div class="side ${player}">`);
  if (started) {
    buf.push('<div class="details">');
    const used = side.lastUsedMove ? gen.moves.get(side.lastUsedMove)!.name : '<em>None</em>';
    buf.push(`<div><strong>Last Used</strong><br />${used}</div>`);
    const selected =
      side.lastSelectedMove ? gen.moves.get(side.lastSelectedMove)!.name : '<em>None</em>';
    const index =
      side.lastSelectedIndex ? ` (${side.lastSelectedIndex})` : '';
    buf.push(`<div><strong>Last Selected</strong><br />${selected}${index}</div>`);
    buf.push('</div>');
  }
  if (side.active) {
    buf.push('<div class="active">');
    let prev = undefined;
    if (last) {
      for (const pokemon of last.pokemon) {
        if (pokemon.position === side.active.position) {
          prev = pokemon;
          break;
        }
      }
    }
    buf.push(displayPokemon(gen, showdown, side.active, true, prev));
    buf.push('</div>');
  }
  buf.push('<details class="team">');
  buf.push('<summary><div class="teamicons">');
  let i = 0;
  const b = [];
  for (const pokemon of side.pokemon) {
    if (i === 3) b.push('</div><div class="teamicons">');
    b.push(icon(player, pokemon));
    i++;
  }
  buf.push(b.join(''));
  buf.push('</div></summary>');
  for (const pokemon of side.pokemon) {
    buf.push(displayPokemon(gen, showdown, pokemon, false));
  }
  buf.push('</details>');
  buf.push('</div>');
  return buf.join('');
}

const STATS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'] as const;

function displayPokemon(
  gen: Generation,
  showdown: boolean,
  pokemon: Pokemon,
  active: boolean,
  last?: Pokemon,
) {
  const buf = [];
  buf.push('<div class="pokemon">');
  const species = active ? pokemon.species : pokemon.stored.species;

  // HP Bar
  const {title, percent, width, color} = getHP(pokemon);
  buf.push(`<div class="left" title="${title}">`);
  if (!active) buf.push(`<div class="position">${POSITIONS[pokemon.position - 1]}</div>`);
  buf.push('<div class="statbar rstatbar" style="display: block; opacity: 1;">');
  buf.push('<span class="name">');
  if (pokemon.status) buf.push(displayStatus(pokemon));
  let name: string = gen.species.get(species)!.name;
  if (active && pokemon.species !== pokemon.stored.species) name = `<em>${name}</em>`;
  buf.push(`<strong>${name}&nbsp;<small>L${pokemon.level}</small></strong>`);
  if (active && pokemon.species !== pokemon.stored.species) buf.push('</em>');
  buf.push('</span>');
  buf.push('<div class="hpbar">');
  const style = `width: ${width}; border-right-width: ${percent === 100 ? 1 : 0}px;`;
  const hp = `<div class="hp ${color}" style="${style}"></div>`;
  if (last && last.position === pokemon.position && pokemon.hp < last.hp) {
    const prev = getHP(last);
    const style = `width: ${prev.width}; border-right-width: ${prev.percent === 100 ? 1 : 0}px;`;
    buf.push(`<div class="prevhp ${prev.color ? 'prev' + prev.color : ''}" style="${style}">`);
    buf.push(hp);
    buf.push('</div>');
  } else {
    buf.push(hp);
  }
  buf.push(`<div class="hptext">${percent}%</div>`);
  buf.push('</div></div>');

  // Sprite & Types
  buf.push(sprite(showdown, species, pokemon.hp === 0));
  const types = active ? pokemon.types : pokemon.stored.types;
  buf.push('<div class="types">');
  buf.push(typicon(types[0]));
  if (types[0] !== types[1]) buf.push(typicon(types[1]));
  buf.push('</div>');
  buf.push('</div>');

  buf.push('<div class="right">');
  if (!active) buf.push(`<div class="position">${POSITIONS[pokemon.position - 1]}</div>`);

  // Stats & Boosts
  buf.push('<div class="stats"><table><tr>');
  const stats = active ? pokemon.stats : pokemon.stored.stats;
  for (const stat of STATS) {
    if (gen.num === 1 && stat === 'spd') continue;
    buf.push(`<th>${gen.stats.display(stat)}</th>`);
  }
  buf.push('</tr><tr>');
  for (const stat of STATS) {
    if (gen.num === 1 && stat === 'spd') continue;
    const boost = active ? pokemon.boosts[stat as BoostID] : 0;
    buf.push(`<td>${displayStat(stats[stat as StatID], boost)}</td>`);
  }
  buf.push('</tr></table>');
  if (active) {
    buf.push('<div class="boosts">');
    if (pokemon.boosts.accuracy) {
      buf.push(`<div><strong>Accuracy:</strong> ${displayBoost(pokemon.boosts.accuracy)}</div>`);
    }
    if (pokemon.boosts.evasion) {
      buf.push(`<div><strong>Evasion:</strong> ${displayBoost(pokemon.boosts.evasion)}</div>`);
    }
    buf.push('</div>');
  }
  buf.push('</div>');

  // Moves
  buf.push('<div class="moves"><ul>');
  const moves = active ? pokemon.moves : pokemon.stored.moves;
  for (const move of moves) {
    const name = gen.moves.get(move.id)!.name;
    const maxpp = Math.min(gen.moves.get(move.id)!.pp / 5 * 8, gen.num === 1 ? 61 : 64);
    const disabled = !move.pp || (move as any).disabled ? 'disabled' : '';
    const title =
      (move as any).disabled ? `title="Disabled: ${(move as any).disabled as number}"` : '';
    const pp = `<small>(${move.pp}/${maxpp})</small>`;
    buf.push(`<li class="${disabled}" ${title}>${name} ${pp}</li>`);
  }
  buf.push('</ul></div>');

  // Volatiles
  if (active) {
    buf.push('<div class="volatiles">');
    for (const v in pokemon.volatiles) {
      const volatile = v as keyof Pokemon['volatiles'];
      const [name, type] = VOLATILES[volatile]!;
      let data = '';
      if (['binding', 'confusion', 'substitute'].includes(volatile)) {
        data = Object.values(pokemon.volatiles[volatile]!)[0].toString();
      } else if (volatile === 'bide') {
        const val = pokemon.volatiles[volatile]!;
        data = `${val.duration} (${val.damage})`;
      } else if (volatile === 'rage') {
        const val = pokemon.volatiles[volatile]!;
        data = val.accuracy ? val.accuracy.toString() : '';
      } else if (volatile === 'thrashing') {
        const val = pokemon.volatiles[volatile]!;
        data = `${val.duration}${val.accuracy ? ` (${val.accuracy})` : ''}`;
      } else if (volatile === 'transform') {
        const slot = POSITIONS[pokemon.volatiles[volatile]!.slot];
        data = `${pokemon.volatiles[volatile]!.player}${slot}`;
      }
      data = (data ? `${name}: ${data}` : name).replace(' ', '&nbsp;');
      buf.push(`<span class="volatile ${type}">${data}</span>`);
    }
    buf.push('</div>');
  }

  buf.push('</div>');
  buf.push('</div>');
  return buf.join('');
}

function escapeHTML(str: string) {
  return (str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
    .replace(/\//g, '&#x2f;')
    .replace(/\n/g, '<br />'));
}

function getHP(pokemon: Pokemon) {
  const title = `${pokemon.hp}/${pokemon.stats.hp}`;
  const ratio = pokemon.hp / pokemon.stats.hp;
  let percent = Math.ceil(ratio * 100);
  if ((percent === 100) && (ratio < 1.0)) {
    percent = 99;
  }
  const width = (pokemon.hp === 1 && pokemon.stats.hp > 45)
    ? '1px' : ratio === 1.0
      ? 'var(--hp-bar)' : `calc(${ratio} * var(--hp-bar))`;
  const color = ratio > 0.5 ? '' : ratio > 0.2 ? 'hp-yellow' : 'hp-red';
  return {title, percent, width, color};
}

function displayStatus(pokemon: Pokemon) {
  const c = pokemon.status === 'tox' ? 'psn' : pokemon.status!;
  let t = '';
  if (pokemon.statusData.sleep) t += `Sleep: ${pokemon.statusData.sleep}`;
  if (pokemon.status === 'tox' || pokemon.statusData.toxic) {
    t += `Toxic: ${pokemon.statusData.toxic}`;
  }
  if (t) t = `title="${t}"`;
  const s = pokemon.statusData.self ? 'slf' : pokemon.status!;
  return `<span class="status ${c}" ${t}>${s}</span>`;
}

function displayStat(stat: number, boost: number) {
  if (!boost) return `${stat}`;
  if (boost > 0) return `<span class="good">${stat} (+${boost})</span>`;
  return `<span class="bad">${stat} (${boost})</span>`;
}

function displayBoost(boost: number) {
  if (boost > 0) return `<span class="good">+${boost}</span>`;
  return `<span class="bad">${boost}</span>`;
}

function icon(side: 'p1' | 'p2', pokemon: Pokemon) {
  const fainted = pokemon.hp === 0;
  const icon = Icons.getPokemon(pokemon.stored.species, {side, fainted, domain: 'pkmn.cc'});
  return `<span style="${icon.style}"></span>`;
}

function sprite(showdown: boolean, species: ID, fainted: boolean) {
  const s = Sprites.getPokemon(species, {gen: showdown ? 'gen1' : 'gen1rb'});
  let style = s.pixelated ? 'image-rendering: pixelated;' : '';
  if (fainted) style += 'opacity: 0.3; filter: grayscale(100%) brightness(.5);';
  return `<img class="sprite" src="${s.url}" width="${s.w}" height="${s.h}" style="${style}" />`;
}

function typicon(type: TypeName) {
  const i = Icons.getType(type);
  const style = 'image-rendering: pixelated;';
  return `<img class="icon" src="${i.url}" width="${i.w}" height="${i.h}" style="${style}" />`;
}
