import * as pkmn from '@pkmn/data';
import * as adaptable from '@pkmn/img/adaptable';

import * as engine from '../../pkg';

import {Fragment} from './dom';
import * as util from './util';

declare const Sprites: adaptable.Sprites;
declare const Icons: adaptable.Icons;

const POSITIONS = ['a', 'b', 'c', 'd', 'e', 'f'];
const STATS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'] as const;
const DISPLAY = {hp: 'HP', atk: 'Atk', def: 'Def', spa: 'SpA', spd: 'SpD', spe: 'Spe', spc: 'Spc'};
const VOLATILES: {[id in keyof engine.Pokemon['volatiles']]: [string, 'good' | 'bad' | 'neutral']} =
  {
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

export interface Generation {
  num: pkmn.GenerationNum;
  species: {
    get(id: pkmn.ID): util.Species & {id: pkmn.ID} | undefined;
    [Symbol.iterator](): Generator<util.Species & {id: pkmn.ID}, void>;
  };
  moves: {
    get(id: pkmn.ID): util.Move & {id: pkmn.ID} | undefined;
    [Symbol.iterator](): Generator<util.Move & {id: pkmn.ID}, void>;
  };
}

export class Gen implements Generation {
  num: pkmn.GenerationNum;
  species: API<util.Species>;
  moves: API<util.Move>;

  constructor(json: {
    num: pkmn.GenerationNum;
    species: {[id: string]: util.Species};
    moves: {[id: string]: util.Move};
  }) {
    this.num = json.num;
    this.species = new API(json.species);
    this.moves = new API(json.moves);
  }
}

class API<T> {
  raw: {[id: string]: T};

  constructor(raw: {[id: string]: T}) {
    this.raw = raw;
  }

  get(id: pkmn.ID) {
    return {id, ...this.raw[id]};
  }

  *[Symbol.iterator]() {
    for (const id in this.raw) {
      yield this.get(id as pkmn.ID);
    }
  }
}

export const Battle = (props: {
  battle: engine.Data<engine.Battle>;
  gen: Generation;
  showdown: boolean;
  last?: engine.Data<engine.Battle>;
  hide?: boolean;
}) => {
  const {battle, last, hide} = props;
  const [p1, p2] = Array.from(battle.sides);
  const [o1, o2] = last ? Array.from(last.sides) : [undefined, undefined];
  return <div className='battle'>
    {!hide && battle.turn && <div className='details'>
      <h2>Turn {battle.turn}</h2>
      <div className="inner">
        <div><strong>Last Damage:</strong> {battle.lastDamage}</div>
        <div><strong>Seed:</strong> {battle.prng.join(', ')}</div>
      </div>
    </div>}
    <div className='sides'>
      <Side {...props} side={p1} player={'p1'} last={o1} />
      <Side {...props} side={p2} player={'p2'} last={o2} />
    </div>
  </div>;
};

export const Side = ({side, battle, player, gen, showdown, last, hide}: {
  side: engine.Data<engine.Side>;
  battle: engine.Data<engine.Battle>;
  player: 'p1' | 'p2';
  gen: Generation;
  showdown: boolean;
  last?: engine.Data<engine.Side>;
  hide?: boolean;
}) => {
  let header = undefined;
  if (battle.turn) {
    const used = side.lastUsedMove ? gen.moves.get(side.lastUsedMove)!.name : <em>None</em>;
    const selected = side.lastSelectedMove ? gen.moves.get(side.lastSelectedMove) : undefined;
    const move = selected?.name ?? <em>None</em>;
    const counterable = !!selected && selected.basePower > 0 && selected.id !== 'counter' &&
      (selected.type === 'Normal' || selected.type === 'Fighting');
    const mismatch = counterable !== side.lastMoveCounterable ? '*' : '';
    const index = side.lastMoveIndex ? ` (${side.lastMoveIndex})` : '';
    header = <div className='details'>
      <div><strong>Last Used</strong><br />{used}</div>
      <div><strong>Last Selected</strong><br />{move}{mismatch}{index}</div>
    </div>;
  }

  let active = undefined;
  if (side.active) {
    let prev = undefined;
    if (last) {
      for (const pokemon of last.pokemon) {
        if (pokemon.position === side.active.position) {
          prev = pokemon;
          break;
        }
      }
    }
    active = <div className='active'>
      <Pokemon pokemon={side.active}
        battle={battle}
        active={true}
        gen={gen}
        showdown={showdown}
        last={prev}
      /></div>;
  }

  let i = 0;
  let icons = [];
  const teamicons = [];
  for (const pokemon of side.pokemon) {
    if (i === 3) {
      teamicons.push(<div className='teamicons'>{icons}</div>);
      icons = [];
    }
    icons.push(<PokemonIcon pokemon={pokemon} side={player}/>);
    i++;
  }
  if (icons.length) teamicons.push(<div className='teamicons'>{icons}</div>);

  const party = [];
  for (const pokemon of side.pokemon) {
    party.push(<Pokemon pokemon={pokemon}
      battle={battle}
      active={false}
      gen={gen}
      showdown={showdown}
    />);
  }

  return <div className={`side ${player}`}>
    {!hide && header}
    {active}
    {!hide && <details className='team'><summary>{teamicons}</summary>{party}</details>}
  </div>;
};

export const Pokemon = ({pokemon, battle, active, gen, showdown, last}: {
  pokemon: engine.Data<engine.Pokemon>;
  battle: engine.Data<engine.Battle>;
  active: boolean;
  gen: Generation;
  showdown: boolean;
  last?: engine.Data<engine.Pokemon>;
}) => {
  const ths = [];
  const tds = [];
  const stats = active ? pokemon.stats : pokemon.stored.stats;
  for (const stat of STATS) {
    if (gen.num === 1 && stat === 'spd') continue;
    ths.push(<th>{DISPLAY[gen.num === 1 && stat === 'spa' ? 'spc' : stat]}</th>);
    const boost = active ? pokemon.boosts[stat as pkmn.BoostID] : 0;
    tds.push(<td><Stat value={stats[stat]} boost={boost} /></td>);
  }

  const boosts = active ? <div className='boosts'>
    {!!pokemon.boosts.accuracy &&
      <div><strong>Accuracy:</strong> <Boost value={pokemon.boosts.accuracy} /></div>}
    {!!pokemon.boosts.evasion &&
      <div><strong>Evasion:</strong> <Boost value={pokemon.boosts.evasion} /></div>}
  </div> : '';

  const lis = [];
  const moves = active ? pokemon.moves : pokemon.stored.moves;
  for (const move of moves) {
    const {name, maxpp} = gen.moves.get(move.id)!;
    const disabled = !move.pp || (move as any).disabled ? 'disabled' : '';
    const title = (move as any).disabled ? `Disabled: ${(move as any).disabled as number}` : '';
    lis.push(<li className={disabled} title={title}>{name} <small>({move.pp}/{maxpp})</small></li>);
  }

  const volatiles = [];
  for (const v in pokemon.volatiles) {
    const volatile = v as keyof engine.Pokemon['volatiles'];
    const [name, type] = VOLATILES[volatile]!;
    let text = '';
    if (['binding', 'confusion', 'substitute'].includes(volatile)) {
      const narrowed = volatile as 'binding' | 'confusion' | 'substitute';
      text = (Object.values(pokemon.volatiles[narrowed]!)[0]).toString();
    } else if (volatile === 'bide') {
      const val = pokemon.volatiles[volatile]!;
      text = `${val.duration} (${val.damage})`;
    } else if (volatile === 'rage') {
      const val = pokemon.volatiles[volatile]!;
      text = val.accuracy ? val.accuracy.toString() : '';
    } else if (volatile === 'thrashing') {
      const val = pokemon.volatiles[volatile]!;
      text = `${val.duration}${val.accuracy ? ` (${val.accuracy})` : ''}`;
    } else if (volatile === 'transform') {
      const {player, slot} = pokemon.volatiles[volatile]!;
      const p = +player.charAt(1) - 1;
      let i = 0;
      for (const side of battle.sides) {
        if (i++ === p) {
          i = 1;
          for (const poke of side.pokemon) {
            if (i++ === slot) {
              text = `${player}${POSITIONS[poke.position - 1]}`;
              break;
            }
          }
          break;
        }
      }
    }
    text = (text ? `${name}: ${text}` : name).replace(' ', '\u00A0');
    volatiles.push(<span className={`volatile ${type}`}>{text}</span>);
  }

  const position = active ? '' : <div className='position'>{POSITIONS[pokemon.position - 1]}</div>;
  return <div className='pokemon'>
    <div className='left' title={`${pokemon.hp}/${pokemon.stats.hp}`}>
      {position}
      <div className='statbar rstatbar' style={{display: 'block', opacity: 1}}>
        <PokemonNameStatus pokemon={pokemon} active={active} gen={gen} />
        <HPBar pokemon={pokemon} last={last} />
      </div>
      <PokemonSprite pokemon={pokemon} active={active} showdown={showdown} />
      <TypeIcons pokemon={pokemon} active={active} />
    </div>
    <div className='right'>
      {position}
      <div className='stats'><table><tr>{ths}</tr><tr>{tds}</tr></table>
        {boosts}
      </div>
      <div className='moves'><ul>{lis}</ul> </div>
      {active && <div className='volatiles'>{volatiles}</div>}
    </div>
  </div>;
};

export const PokemonNameStatus = ({pokemon, active, gen}: {
  pokemon: engine.Data<engine.Pokemon>;
  active: boolean;
  gen: Generation;
}) => {
  const species = active ? pokemon.species : pokemon.stored.species;
  const n = gen.species.get(species)!.name;
  const name = <strong>{n}&nbsp;<small>L{pokemon.level}</small></strong>;
  return <span className='name'>
    <Status pokemon={pokemon} />
    {(active && pokemon.species !== pokemon.stored.species) ? <em>{name}</em> : name}
  </span>;
};

const HPBar = ({pokemon, last}: {
  pokemon: engine.Data<engine.Pokemon>;
  last?: engine.Data<engine.Pokemon>;
}) => {
  const {percent, color, style} = getHP(pokemon);
  let bar = <div className={`hp ${color}`} style={style}></div>;
  if (last?.position === pokemon.position && pokemon.hp < last.hp) {
    const prev = getHP(last);
    bar = <div className={`prevhp ${prev.color ? 'prev' + prev.color : ''}`} style={prev.style}>
      {bar}
    </div>;
  }
  return <div className='hpbar'>{bar}<div className='hptext'>{percent}%</div></div>;
};

export const Status = ({pokemon}: {pokemon: engine.Data<engine.Pokemon>}) => {
  if (!pokemon.status) return <></>;
  const classes = `status ${pokemon.status === 'tox' ? 'psn' : pokemon.status}`;
  let title = '';
  if (pokemon.statusData.sleep) title += `Sleep: ${pokemon.statusData.sleep}`;
  if (pokemon.status === 'tox' || pokemon.statusData.toxic) {
    title += `${title ? ' ' : ''}Toxic: ${pokemon.statusData.toxic}`;
  }
  return <span className={classes} title={title}>
    {pokemon.statusData.self ? 'slf' : pokemon.status}
  </span>;
};

export const Stat = ({value, boost}: {value: number; boost: number}) => {
  if (!boost) return <span className='stat'>{value}</span>;
  if (boost > 0) return <span className='stat good'>{value}&nbsp;(+{boost})</span>;
  return <span className='stat bad'>{value}&nbsp;({boost})</span>;
};

export const Boost = ({value}: {value: number}) => {
  if (value > 0) return <span className='boost good'>+{value}</span>;
  return <span className='boost bad'>{value}</span>;
};

export const PokemonIcon = ({pokemon, side}: {
  pokemon: engine.Data<engine.Pokemon>;
  side: 'p1' | 'p2';
}) => {
  const fainted = pokemon.hp === 0;
  const i = Icons.getPokemon(pokemon.stored.species, {side, fainted, domain: 'pkmn.cc'});
  return <span style={i.css}></span>;
};

export const PokemonSprite = ({pokemon, active, showdown}: {
  pokemon: engine.Data<engine.Pokemon>;
  active: boolean;
  showdown: boolean;
}) => {
  const species = active ? pokemon.species : pokemon.stored.species;
  const s = Sprites.getPokemon(species, {gen: showdown ? 'gen1' : 'gen1rb'});
  const fainted = pokemon.hp === 0;
  return <img className='sprite' src={s.url} width={s.w} height={s.h} style={{
    imageRendering: s.pixelated ? 'pixelated' : undefined,
    opacity: fainted ? 0.3 : undefined,
    filter: fainted ? 'grayscale(100%) brightness(.5)' : undefined,
  }} />;
};

export const TypeIcons = ({pokemon, active}: {
  pokemon: engine.Data<engine.Pokemon>;
  active: boolean;
}) => {
  const types = active ? pokemon.types : pokemon.stored.types;
  const type1 = <TypeIcon type={types[0]} />;
  const type2 = types[0] !== types[1] ? <TypeIcon type={types[1]} /> : '';
  return <div className='types'>{type1}{type2}</div>;
};

export const TypeIcon = ({type}: {type: pkmn.TypeName}) => {
  const i = Icons.getType(type);
  const style = {imageRendering: 'pixelated' as const};
  return <img className='icon' src={i.url} width={i.w} height={i.h} style={style} />;
};

export function getHP(pokemon: engine.Data<engine.Pokemon>) {
  const ratio = pokemon.hp / pokemon.stats.hp;
  let percent = Math.ceil(ratio * 100);
  if ((percent === 100) && (ratio < 1.0)) {
    percent = 99;
  }
  const width = (pokemon.hp === 1 && pokemon.stats.hp > 45)
    ? '1px' : ratio === 1.0
      ? 'var(--hp-bar)' : `calc(${ratio} * var(--hp-bar))`;
  const color = ratio > 0.5 ? '' : ratio > 0.2 ? 'hp-yellow' : 'hp-red';
  const style = {width: width, borderRightWidth: `${percent === 100 ? 1 : 0}px;`};
  return {percent, color, style};
}

// @pkmn/img/adaptable means we can use our pruned data to provide sprite
// info for just the SpriteGen's that we're going to use
export function adapt(gen: Generation) {
  const Data = new class {
    getPokemon(name: string) {
      const s = gen.species.get(pkmn.toID(name))!;
      return {spriteid: s.id, gen: gen.num, ...s};
    }
    getItem() {
      return undefined;
    }
    getAvatar() {
      return undefined;
    }
  };
  (globalThis as any).Sprites = new adaptable.Sprites(Data);
  (globalThis as any).Icons = new adaptable.Icons(Data);
  return gen;
}
