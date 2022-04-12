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

// let result, c1, c2;
// const options = {p1: {team: TEAMS.p1}, p2: {team: TEAMS.p2}, seed: [1, 2, 3, 4], showdown};
// const battle = Battle.create(gens.get(1), options);
// while (!(result = battle.update(c1, c2))) {
//   c1 = random.range(0, battle.choices('p1', result));
//   c2 = random.range(0, battle.choices('p1', result));
// }

// console.log(result);

console.log(gens.get(1).species.get('Gengar').baseStats.hp);
console.log(TEAMS);
