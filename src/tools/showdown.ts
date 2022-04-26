import 'source-map-support/register';

import {Streams, BattleStreams} from '@pkmn/sim';

if (process.argv[2] !== 'simulate-battle') {
  throw new Error(`Unsupported command: ${process.argv[2]}`);
}

const stdin = Streams.stdin();
const stdout = Streams.stdout();

const battleStream = new BattleStreams.BattleTextStream({noCatch: true} as any);
stdin.pipeTo(battleStream).catch(console.error);
battleStream.pipeTo(stdout).catch(console.error);
