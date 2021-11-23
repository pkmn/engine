import {Dex, BattleStreams, RandomPlayerAI, Teams} from '@pkmn/sim';
import {TeamGenerators} from '@pkmn/randoms';

import * as trakr from 'trakr';

import {Gen12PRNG} from './prng';

Teams.setGeneratorFactory(TeamGenerators);

const FORMATS = [
  'gen1randombattle',
  // 'gen2randombattle',
  // 'gen3randombattle',
  // 'gen4randombattle',
  // 'gen5randombattle',
  // 'gen6randombattle',
  // 'gen7randombattle', 'gen7randomdoublesbattle',
  // 'gen8randombattle', 'gen8randomdoublesbattle',
];