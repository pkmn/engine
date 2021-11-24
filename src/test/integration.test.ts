import {PRNG, PRNGSeed, BattleStreams} from '@pkmn/sim';
import {ExhaustiveRunner, ExhaustiveRunnerOptions, RunnerOptions, AIOptions} from '@pkmn/sim/tools';

import {GBRNG, GBARNG} from './rng';

class Runner {
  private readonly format: string;
  private readonly prng: PRNG;
  private readonly p1options?: AIOptions;
  private readonly p2options?: AIOptions;

  constructor(options: RunnerOptions) {
    this.format = options.format;

    this.prng = (options.prng && !Array.isArray(options.prng))
      ? options.prng : new PRNG(options.prng);
    this.p1options = options.p1options;
    this.p2options = options.p2options;
  }

  async run() {
    const rawBattleStream = new RawBattleStream(this.format);
    const streams = BattleStreams.getPlayerStreams(rawBattleStream);

    const spec = {formatid: this.format, seed: this.prng.seed};
    const p1spec = {name: 'Bot 1', ...this.p1options};
    const p2spec = {name: 'Bot 2', ...this.p2options};

    const p1 = this.p1options!.createAI(streams.p2, {
      seed: this.newSeed(), move: 0.7, mega: 0.6, ...this.p1options!,
    }).start();
    const p2 = this.p2options!.createAI(streams.p1, {
      seed: this.newSeed(), move: 0.7, mega: 0.6, ...this.p2options!,
    }).start();

    await Promise.all([streams.omniscient.write(
      `>start ${JSON.stringify(spec)}\n` +
      `>player p1 ${JSON.stringify(p1spec)}\n` +
      `>player p2 ${JSON.stringify(p2spec)}`
    ), p1, p2]);

    for (const channel in streams) {
      const buf = [];
      for await (const chunk of streams[channel as keyof typeof streams]) {
        buf.push(chunk);
      }
      // TODO: feed input from rawBattleStream.rawInputLog into @pkmn/engine
      // TODO: compare to @pkmn/engine data
      // TODO: add buf to output if doesn't compare
      // TODO: verify binary protocol round trip
    }

    // BUG: streams.p2.writeEnd ?
  }

  // Same as PRNG#generatedSeed, only deterministic.
  // NOTE: advances this.prng's seed by 4.
  newSeed(): PRNGSeed {
    return [
      Math.floor(this.prng.next() * 0x10000),
      Math.floor(this.prng.next() * 0x10000),
      Math.floor(this.prng.next() * 0x10000),
      Math.floor(this.prng.next() * 0x10000),
    ];
  }
}

class RawBattleStream extends BattleStreams.BattleStream {
  readonly format: string;
  readonly rawInputLog: string[];

  constructor(format: string) {
    super();
    this.format = format;
    this.rawInputLog = [];
  }

  _write(message: string) {
    this.rawInputLog.push(message);
    super._write(message);
  }

  _writeLine(type: string, message: string) {
    super._writeLine(type, message);
    if (type === 'start') {
      switch (this.format) {
      case 'gen1customgame':
      case 'gen2customgame':
        this.battle!.prng = new GBRNG(this.battle!.prng.seed);
        break;
      case 'gen3customgame':
      case 'gen4customgame':
        this.battle!.prng = new GBARNG(this.battle!.prng.seed);
        break;
      default:
        throw new Error(`Unsupported format: ${this.format}`);
      }
    }
  }
}

const FORMATS = [
  'gen1customgame',
  // 'gen2customgame',
  // 'gen3customgame', 'gen3doublescustomgame',
  // 'gen4customgame', 'gen4doublescustomgame',
  // 'gen5customgame', 'gen5doublescustomgame',
  // 'gen6customgame', 'gen6doublescustomgame',
  // 'gen7customgame', 'gen7doublescustomgame',
  // 'gen8customgame', 'gen8doublescustomgame',
];

describe('integration', () => {
  it('test', async () => {
    const opts: ExhaustiveRunnerOptions =
      {format: '', prng: [1, 2, 3, 4], runner: o => new Runner(o).run()};
    for (const format of FORMATS) {
      opts.format = format;
      expect(await (new ExhaustiveRunner(opts).run())).toBe(0);
    }
  });
});
