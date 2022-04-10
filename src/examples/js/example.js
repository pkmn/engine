const fs = require('fs');

const {Generations} = require("@pkmn/data");
const {Dex} = require("@pkmn/dex");
const {Team} = require("@pkmn/sets");

const TEAMS = {
  p1: Team.import(fs.readFileSync(__dirname + '/teams/p1.txt', 'utf-8'), Dex).team,
  p2: Team.import(fs.readFileSync(__dirname + '/teams/p2.txt', 'utf-8'), Dex).team,
};

const gens = new Generations(Dex);
console.log(gens.get(1).species.get('Gengar').baseStats.hp);
console.log(TEAMS);
