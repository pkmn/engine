import 'source-map-support/register';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/dex';
import {Battle, Choice, Log, Lookup, Result} from '@pkmn/engine';
import {Team} from '@pkmn/sets';

// @pkmn/engine does not export the PSRNG - PRNG from @pkmn/sim can be used if
// absolutely necessary, but instead an RNG optimized for JS should be used -
// here we're using a Mulberry32 RNG variant
// See also: https://github.com/bryc/code/blob/master/jshash/PRNGs.md
class Random {
  seed: number;

  // Slightly more sophisticated than https://xkcd.com/221/ because its output
  // from a FNV-1a hash, but in production one should really be seeding with
  // crypto.getRandomBytes() or similar
  constructor(seed = 0x27d4eb2d) {
    this.seed = seed;
  }

  // https://gist.github.com/tommyettinger/46a874533244883189143505d203312c
  next(max: number) {
    let z = (this.seed += 0x6d2b79f5 | 0);
    z = Math.imul(z ^ (z >>> 15), z | 1);
    z = z ^ (z + Math.imul(z ^ (z >>> 7), z | 61));
    z = (z ^ (z >>> 14)) >>> 0;
    const n = z / 0x100000000;
    // A more general next implementation would return n, but since we need it
    // only for making choices we can instead specialize the function to return
    // a number between [0, max)
    return Math.floor(n * max);
  }
}

// By adding a dependency on @pkmn/sets we can define our two example teams with
// Pokémon Showdown's packed format which can then be parsed into PokemonSet[].
// We could read this data in from a file (which even works with Parcel due to
// magic!), but for the sake of having an example that works without too much
// hairiness in both Node and the browser we inline these teams instead
const P1 = Team.unpack(
  'Fushigidane|Bulbasaur||-|SleepPowder,SwordsDance,RazorLeaf,BodySlam|||||||]' +
  'Hitokage|Charmander||-|FireBlast,FireSpin,Slash,Counter|||||||]' +
  'Zenigame|Squirtle||-|Surf,Blizzard,BodySlam,Rest|||||||]' +
  'Pikachuu|Pikachu||-|Thunderbolt,ThunderWave,Surf,SeismicToss|||||||]' +
  'Koratta|Rattata||-|SuperFang,BodySlam,Blizzard,Thunderbolt|||||||]' +
  'Poppo|Pidgey||-|DoubleEdge,QuickAttack,WingAttack,MirrorMove|||||||', Dex
)!.team;

const P2 = Team.unpack(
  'Kentarosu|Tauros||-|BodySlam,HyperBeam,Blizzard,Earthquake|||||||]' +
  'Rakkii|Chansey||-|Reflect,SeismicToss,SoftBoiled,ThunderWave|||||||]' +
  'Kabigon|Snorlax||-|BodySlam,Reflect,Rest,IceBeam|||||||]' +
  'Nasshii|Exeggutor||-|SleepPowder,Psychic,Explosion,DoubleEdge|||||||]' +
  'Sutaamii|Starmie||-|Recover,ThunderWave,Blizzard,Thunderbolt|||||||]' +
  'Fuudin|Alakazam||-|Psychic,SeismicToss,ThunderWave,Recover|||||||', Dex
)!.team;

// Enabling logging means we are required to pass names for our players. NB:
// Logging still will not actually take place unless we also build with -Dlog!
// If we don't run:
//
//   npx install-pkmn-engine -- --options='-Dshowdown -Dlog'
//
// beforehand then we will simply run this example with the default
// configuration (-Dshowdown) and not receive any protocol log messages.
// Similarly, `showdown: true` here only works because the default configuration
// opts into Pokémon Showdown compatibility mode - if we change around our
// configuration we will need to change this initialization option as well.
const gens = new Generations(Dex);
const gen = gens.get(1);
const options = {
  p1: {name: 'Player A', team: P1},
  p2: {name: 'Player B', team: P2},
  seed: [1, 2, 3, 4],
  showdown: true,
  log: true,
};
const battle = Battle.create(gen, options);
const log = new Log(gen, Lookup.get(gen), options);
const display = () => {
  for (const line of log.parse(battle.log!)) {
    console.log(line);
  }
};

const random = new Random();
const choose = random.next.bind(random);

// For convenience the engine actually is written so that passing in undefined
// is equivalent to Choice.pass() but to appease the TypeScript compiler we're
// going to be explicit here
let result: Result, c1 = Choice.pass(), c2 = Choice.pass();
while (!(result = battle.update(c1, c2)).type) {
  // If -Dlog is enabled we can parse and output the resulting logs since we
  // initialized the battle to support logging (both `-Dlog` *and* `log: true`
  // are required for logging)
  display();
  // Technically due to Generation I's Transform + Mirror Move/Metronome PP
  // error if the battle contains Pokémon with a combination of Transform,
  // Mirror Move/Metronome, and Disable its possible that there are no available
  // choices (softlock), though this is impossible here given that our example
  // battle involves none of these moves
  //
  // Battles expose a choices method if we wish to see all the available
  // choices, but if we don't care about which one is chosen because we're doing
  // so randomly (e.g. during a MCTS simulation) we can opt for the faster
  // special-cased choose method instead
  c1 = battle.choose('p1', result, choose);
  c2 = battle.choose('p2', result, choose);
}
// Remember to display any logs that were produced during the last update
display();

// The result is from the perspective of P1
const msg = {
  win: 'won by Player A',
  lose: 'won by Player B',
  tie: 'ended in a tie',
  error: 'encountered an error',
}[result.type];

console.log(`Battle ${msg} after ${battle.turn} turns`);
