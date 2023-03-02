import * as fs from 'fs';
import * as path from 'path';

import {Generations} from '@pkmn/data';
import {Dex} from '@pkmn/dex';
// import {Battle} from '@pkmn/engine';
import {Team} from '@pkmn/sets';

const gens = new Generations(Dex);

const team = (p: string) =>
  Team.import(fs.readFileSync(path.join(__dirname, '..', 'teams', `${p}.txt`), 'utf8'), Dex)!.team;
const TEAMS = {p1: team('p1'), p2: team('p2')};

// let result, c1, c2;
// const options = {p1: {team: TEAMS.p1}, p2: {team: TEAMS.p2}, seed: [1, 2, 3, 4], showdown};
// const battle = Battle.create(gens.get(1), options);
// while (!(result = battle.update(c1, c2))) {
//   c1 = random.next(battle.choices('p1', result));
//   c2 = random.next(battle.choices('p2', result));
// }

// console.log(result);

console.log(gens.get(1).species.get('Gengar')!.baseStats.hp);
console.log(TEAMS);
