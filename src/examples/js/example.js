const fs = require('fs');

const {Generations} = require("@pkmn/data");
const {Dex} = require("@pkmn/dex");
const {Team} = require("@pkmn/sets");
// const {Battle} = require("@pkmn/engine");

// TODO determine if showdown!!!
// const showdown = true;

const gens = new Generations(Dex);

const TEAMS = {
  p1: Team.import(fs.readFileSync(__dirname + '/teams/p1.txt', 'utf8'), Dex).team,
  p2: Team.import(fs.readFileSync(__dirname + '/teams/p2.txt', 'utf8'), Dex).team,
};

class Random {
  constructor(seed = 0x27d4eb2d) {
    this.seed = seed;
  }

  next(max) {
    let z = (this.seed += 0x6d2b79f5 | 0);
    z = Math.imul(z ^ (z >>> 15), z | 1);
    z = z ^ (z + Math.imul(z ^ (z >>> 7), z | 61));
    z = (z ^ (z >>> 14)) >>> 0;
    const n = z / 2 ** 32;
    return Math.floor(n * max);
  }
}

// let result, c1, c2;
// const options = {p1: {team: TEAMS.p1}, p2: {team: TEAMS.p2}, seed: [1, 2, 3, 4], showdown};
// const battle = Battle.create(gens.get(1), options);
// while (!(result = battle.update(c1, c2))) {
//   c1 = random.next(battle.choices('p1', result));
//   c2 = random.nexy(battle.choices('p2', result));
// }

// console.log(result);

console.log(gens.get(1).species.get('Gengar').baseStats.hp);
console.log(TEAMS);
console.log(new Random().next());
