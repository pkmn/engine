const {Generations} = require('./data');
const {Dex, PRNG, BattleStreams} = require('./sim');
const {ExhaustiveRunner} = require('./sim/build/cjs/sim/tools');
const {Protocol} = require('./protocol');

const gens = new Generations(Dex);

const MODS = {
  1: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
  2: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
  3: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
  4: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
};

function formatFor(gen) {
  return `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}`;
}

const FILTER = new Set([
  '', 't:', 'gametype', 'player', 'teamsize', 'gen', 'message', 'done', 'error',
  'bigerror', 'tier', 'rule', 'start', 'upkeep', '-message', '-hint', 'debug',
]);

const LINES = new Set();

class Runner {
  static AI_OPTION = {
    createAI: (s, o) => new RandomPlayerAI(s, o),
    move: 0.7,
    mega: 0.6,
  };

  constructor(options) {
    this.format = options.format;
    this.prng = (options.prng && !Array.isArray(options.prng)) ?
      options.prng : new PRNG(options.prng);
    this.p1options = {...Runner.AI_OPTIONS, ...options.p1options};
    this.p2options = {...Runner.AI_OPTIONS, ...options.p2options};
  }

  async run() {
    const battleStream = new BattleStreams.BattleStream(); 
    const streams = BattleStreams.getPlayerStreams(battleStream);
    const spec = {formatid: this.format, seed: this.prng.seed};
    const p1spec = this.getPlayerSpec("Bot 1", this.p1options);
    const p2spec = this.getPlayerSpec("Bot 2", this.p2options);

    const p1 = this.p1options.createAI(
      streams.p1, {seed: this.newSeed(), ...this.p1options}
    );
    const p2 = this.p2options.createAI(
      streams.p2, {seed: this.newSeed(), ...this.p2options}
    );
    void p1.start();
    void p2.start();

    let initMessage = `>start ${JSON.stringify(spec)}\n` +
      `>player p1 ${JSON.stringify(p1spec)}\n` +
      `>player p2 ${JSON.stringify(p2spec)}`;

    void streams.omniscient.write(initMessage);

    for await (const chunk of streams.omniscient) {
      for (const line of chunk.split('\n')) {
        const {args, kwArgs} = Protocol.parseBattleLine(line);
        if (FILTER.has(args[0])) continue;
        LINES.add(line.replaceAll(/\d+/g, 'X'));
      }
    }
    return streams.omniscient.writeEnd();
  }

  newSeed() {
    return [
      Math.floor(this.prng.next() * 0x10000),
      Math.floor(this.prng.next() * 0x10000),
      Math.floor(this.prng.next() * 0x10000),
      Math.floor(this.prng.next() * 0x10000),
    ];
  }

  getPlayerSpec(name, options) {
    const team = [];
    for (const mon of options.team) {
      mon.name = 'A';
      mon.level = 99;
      mon.shiny = false;
      team.push(mon);
    }
    return {name, team};
  }
}

(async () => {
  const gen = gens.get(process.argv[2]);
  await (new ExhaustiveRunner({
    cycles: 100, maxFailures: 1, log: false, output: true, format: formatFor(gen),
    runner: o => new Runner(o).run(),
  }).run());

  for (const line of Array.from(LINES).sort()) {
    console.log(line);
  }
})();
