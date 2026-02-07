## Adding a new Generation

1. **[Research](./RESEARCH.md)** the data structures and code flow
2. Add a `data.zig` file with **basic data types** (`Battle`, `Side`, `Pokemon`, ...) and fields
   - un-optimized - exact layout tweaked in step 11
3. **[Generate](../src/tools/generate.ts) data** files
   - reorder enums for performance
   - update [`Lookup`](../src/pkg/data.ts) if necessary
4. **[Generate](../src/tools/generate.ts) test** files
   - reorganize logically and to match previous generations
   - add in cases for known Pokémon Showdown bugs and cartridge glitches
5. **Copy over shared code/files**
   - copy over `README.md` for new generation
   - copy over imports and public function skeletons in `mechanics.zig`
   - copy `Test` infrastructure and rolls into `test.zig`
   - copy over `helpers.zig`
6. Implement **unit [tests](../src/test/showdown/) against Pokémon Showdown** behavior
   - update Bugs section of generation documentation as bugs are discovered
7. Implement **mechanics** in `mechanics.zig` based on cartridge research
   - update [protocol](../src/lib/common/protocol.zig) as necessary, also updating
     [documentation](PROTOCOL.md), [driver](../src/pkg/protocol.ts), and tests
   - [generate](../src/tools/dump.zig) updated [`protocol.json`](../src/data/protocol.json)
8. Adjust **mechanics for Pokémon Showdown** compatibility
   - track RNG differences and update generation documentation (group all RNG is in `Rolls`)
   - ensure all bugs are tracked in documentation
   - add logic to tests to block any unimplementable effects
9. **Unit test the engine** in both cartridge and Pokémon Showdown compatibility mode
   - see [below](#converting-unit-tests) on how to convert the unit tests from JS
10. Implement a **`MAX_LOGS` unit test**
    - document in [`PROTOCOL.md`](PROTOCOL.md)
    - validate with Z3
11. **Optimize data structures**
    - [generate](../src/tools/dump.zig) updated [`layout.json`](../src/data/layout.json) and
     [`data.json`](../src/data/data.json)
12. Implement **driver serialization/deserialization** and writes tests
13. **Expose API** for new generation
    - update [`pkmn.zig`](../src/lib/pkmn.zig) and bindings in
      [`c.zig`](..src/lib/c.zig)/[`node.zig`](..src/lib/node.zig)/[`wasm.zig`](..src/lib/wasm.zig)
    - update [`pkmn.h`](../src/include/pkmn.h)
    - update [`index.ts`](../src/pkg/index.ts)
14. Write **`helper.zig`** and implement **`choices`** method
    - matching `Choices` code required in [showdown](../src/test/showdown/index.ts)
15. Ensure **[fuzz tests](../src/test/benchmark.zig)** pass
    - update [`fuzz.ts`](../src/test/fuzz.ts) and [`debug.ts`](../src/tools/debug.ts)
16. Ensure **[integration tests](../src/test/integration.ts)** pass
17. Add **`chance.zig`** and **`calc.zig`** files with data types
18. **Instrument code with `Chance` and `Calc` calls**
19. Update **unit tests with `expectProbability`** and ensure chance/calc overrides roundtrip
20. Implement **`transitions` function**
   - add `Rolls` helpers for new generation
   - include `transitions` function call in fuzz tests
   - determine `MAX_FRONTIER_SIZE` and add constants to API
21. **Add support to the JS driver for `calc` and `chance`**
   - update [`layout.json`](../src/data/layout.json) to include offsets required
22. **[Benchmark](../src/test/benchmark.zig)** new generation
23. Finalize **documentation** for generation

## Updating `@pkmn/sim` dependency

1. **Bump** pinned `@pkmn/sim` version in [`package.json`](../package.json) and run `npm install`
2. Run `npm run test:integration`, **update rolls and behavior of Pokémon Showdown tests** in
   [`src/test/showdown`](src/test/showdown)
3. **Update Zig mechanics tests to match** the updates applied to the integration tests
4. **Update Zig engine code** to cause the updated mechanics tests to pass
5. **Update documentation** to match new behavior/bugs
6. **Remove effects from blocklists** and helpers if necessary

## Debugging Tests

### Regression Tests

When debugging a specific regression test, remove the logic from the final `catch` block of the
`play` function in [`integration.ts`](../src/test/integration.ts) preventing replays from generating
the [`logs/pkmn.html`](../logs/pkmn.html) and [`logs/showdown.html`](../logs/showdown.html) UIs:

 ```diff
-if (!replay) {
 const num = toBigInt(seed);
 const stack = err.stack.replace(ANSI, '');
 errors?.seeds.push(num);
 errors?.stacks.push(stack);
 try {
   console.error('');
   dump(
     gen,
     stack,
     num,
     rawInputLog,
     frames,
     partial,
   );
 } catch (e) {
   console.error(e);
 }
-}
```

### Specific errors

#### Unexpected shuffle

Modify `patch.battle` within [`showdown.ts`](../src/test/showdown.ts):

 ```diff
 battle: (battle: Battle, prng = false, debug = false) => {
 +   const run = battle.runEvent.bind(battle);
 +   battle.runEvent = (...args) => {
 +     console.debug(args[0]);
 +     return run(...args);
 +   };
 battle.trunc = battle.dex.trunc.bind(battle.dex);
```
After you have determined the problematic effects which speed tie you can assign them a priority in
`patch.generation`.

#### Mismatched seeds

You can determine RNG advances in the engine by modifying the `Gen56` RNG within
[`rng.zig`](src/lib/common/rng.zig) to log:

```patch
pub fn advance(self: *Gen56) void {
+    DEBUG(self.seed);
    self.seed = 0x5D588B656C078965 *% self.seed +% 0x0000000000269EC3;
}
```

Note that **the numbers printed here will not match the seeds from Pokémon Showdown** as they are in
little-endian instead of Pokémon Showdown's big-endian convention. Alternatively, if you wish to see
where the advances are occurring you can add debug prints to each of the `Rolls` at the bottom of
the appropriate `mechanics.zig`:

```diff
pub const Rolls = struct {
    fn speedTie(battle: anytype, options: anytype) !bool {
+      DEBUG(@src());
 ```


## Testing `pkmn-debug`

The `pkmn-debug` script requires some additional work to test properly because of how it is
packaged. First you must apply a patch to force a fuzz test failure (and to remove the embedded
seed) in order to get some input to feed into it:

```diff
diff --git a/src/test/fuzz.ts b/src/test/fuzz.ts
index 462f9bce..d0c02636 100644
--- a/src/test/fuzz.ts
+++ b/src/test/fuzz.ts
@@ -39,7 +39,6 @@ export async function run(
   } catch (err: any) {
     const {stdout, stderr} = err as {stdout: Buffer; stderr: Buffer};
     const raw = stderr.toString('utf8');
-    const panic = raw.indexOf('panic: ');
     if (testing || !stdout.length) throw new Error(raw);

     console.error(raw);
@@ -56,7 +55,7 @@ export async function run(
     const file = path.join(dir, `${hex}.fuzz.html`);
     const link = path.join(dir, 'fuzz.html');

-    fs.writeFileSync(file, display.render(gens, stdout.subarray(8), raw.slice(panic), seed));
+    fs.writeFileSync(file, stdout.subarray(8));
     fs.rmSync(link, {force: true});
     fs.symlinkSync(file, link);

diff --git a/src/test/fuzz.zig b/src/test/fuzz.zig
index ff67b3e1..edf88aa3 100644
--- a/src/test/fuzz.zig
+++ b/src/test/fuzz.zig
@@ -163,6 +163,8 @@ fn run(
                 .log = try buf.?.toOwnedSlice(),
             });
         }
+
+        std.debug.assert(battle.turn < 64);
     }

     std.debug.assert(!showdown or result.type != .Error);
```

You then must compile and pack the script before running it in isolation with `npm` to prove that
it will work correctly when installed by an end user:

```sh
$ npm run fuzz pkmn 1 1s 0x12345678 && mv logs/fuzz.html /tmp/log.pkmn
$ npm run compile && npm pack && mv *.tgz /tmp
$ cd /tmp && npm i *.tgz && npx pkmn-debug < log.pkmn > debug.html
$ open debug.html
```

## Converting Unit Tests

The following template can be used within JS Pokémon Showdown behavior test cases for a new effect:

<details><summary><b>JS</b></summary>

```ts
test('TODO', () => {
  const battle = startBattle([], [
    {species: 'TODO', evs, moves: ['TODO']},
  ], [
    {species: 'TODO', evs, moves: ['TODO']},
  ]);

  let p1hp = battle.p1.pokemon[0].hp;
  let p2hp = battle.p2.pokemon[0].hp;

  battle.makeChoices('move 1', 'move 1');
  // expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
  // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

  verify(battle, [
  ]);
});
```

</details>

The corresponding Zig template is as follows, with additional snippets that can be copied depending
on the scenario:

<details><summary><b>Zig</b></summary>

### Setup

```zig
var t = Test((if (showdown)
    .{ }
else
    .{ })).init(
var t = Test(
// zig fmt: off
    if (showdown) .{
       // TODO
    } else .{
       // TODO
    }
// zig fmt: on
).init(
    &.{
        .{ .species = .TODO, .moves = &.{ .TODO } },
        .{ .species = .TODO, .moves = &.{.TODO} },
    },
    &.{.{ .species = .TODO, .moves = &.{.TODO} }},
);
defer t.deinit();
try t.log.expected.turn(2);
try expectEqual(Result.Default, try t.update(move(1), move(1)));
try t.verify();
```

### P1 Switch

```zig
try t.log.expected.switched(P1.ident(2), t.expected.p1.get(2));
```

### P2 Switch

```zig
try t.log.expected.switched(P2.ident(2), t.expected.p2.get(2));
```

### P1 Splash

```zig
try t.log.expected.move(P1.ident(1), Move.Splash, P1.ident(1), null);
try t.log.expected.activate(P1.ident(1), .Splash);
```

```zig
try t.log.expected.move(P1.ident(1), Move.Splash, P1.ident(1), null);
try t.log.expected.activate(P1.ident(1), .Splash);
if (showdown) try t.log.expected.fail(P1.ident(1), .None);
```

### P2 Splash

 ```zig
try t.log.expected.move(P2.ident(1), Move.Splash, P2.ident(1), null);
try t.log.expected.activate(P2.ident(1), .Splash);
 ```

```zig
try t.log.expected.move(P2.ident(1), Move.Splash, P2.ident(1), null);
try t.log.expected.activate(P2.ident(1), .Splash);
if (showdown) try t.log.expected.fail(P2.ident(1), .None);
 ```

### P1 Substitute

```zig
try t.log.expected.move(P1.ident(1), Move.Substitute, P1.ident(1), null);
try t.log.expected.start(P1.ident(1), .Substitute);
t.expected.p1.get(1).hp -= 0;
try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
try t.log.expected.activate(P1.ident(1), .Substitute);
try t.log.expected.end(P1.ident(1), .Substitute);
```

### P2 Substitute

```zig
try t.log.expected.move(P2.ident(1), Move.Substitute, P2.ident(1), null);
try t.log.expected.start(P2.ident(1), .Substitute);
t.expected.p2.get(1).hp -= 0;
try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
try t.log.expected.activate(P2.ident(1), .Substitute);
try t.log.expected.end(P2.ident(1), .Substitute);
```

### P1 Damage

```zig
try t.log.expected.move(P1.ident(1), Move.TODO, P2.ident(1), null);
t.expected.p2.get(1).hp -= 0;
try t.log.expected.damage(P2.ident(1), t.expected.p2.get(1), .None);
```

### P2 Damage

```zig
try t.log.expected.move(P2.ident(1), Move.TODO, P1.ident(1), null);
t.expected.p1.get(1).hp -= 0;
try t.log.expected.damage(P1.ident(1), t.expected.p1.get(1), .None);
```

</details>

The following script can be used sloppily convert Pokémon Showdown text logs into logs suitable for
Zig behavior testing:

<details><summary><b>parse.js</b></summary>

```js
const readline = require('readline');

//const prefix = {log: 't.log', ident: 't.expected.'};
const prefix = {log: '', ident: ''};
const ID = /^(P\d)(\(\d\))$/;

const buf = [];
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});
rl.on('line', raw => {
  const line = raw.trim();
  if (!line || line === '-') return;

  const [tag, ...parts] = line.split(' ');
  const method = `try ${prefix.log}expected.${tag.replaceAll(/[|-]/g, '')}`;
  for (let i = 0; i < parts.length; i++) {
    let m;
    if (m = ID.exec(parts[i])) {
      parts[i] = `${m[1]}.ident${m[2]}`;
    } else if (/^[A-Z]/.test(parts[i])) {
      parts[i] = `.${parts[i]}`;
    }
  }
  const ident = () => `${prefix.ident}${parts[0].toLowerCase().replace('ident', 'get')}`;
  if (tag === '|move|') {
    parts[1] = `Move${parts[1]}`;
    if (parts[4]) parts[4] = `Move${parts[4]}`;
    parts.splice(3, 1);
  } else if (tag === '|-start' && parts[1] === '.Disable') {
    parts[2] = `Move${parts[1]}`;
  } else if (tag === '|-damage|') {
    const id = ident();
    buf.push(`${id}.hp -= 0; // TODO ${parts[1]}`);
    parts.splice(1, 2, id);
  } if (tag === '|-boost|') {
    parts[2] = +parts[2] - 6;
  } else if (tag === '|-status|') {
    const id = ident();
    buf.push(`${id}.status = Status.init(${parts[1]});`);
    parts.splice(1, 1, `${id}.status`);
  }
  buf.push(`${method}(.{ ${parts.join(', ')} });`);
  if (tag === '|-curestatus|') {
    buf.push(`${ident()}.status = 0;`);
  }
});
rl.on('close', () => {
  console.log(`\n---\n\n${buf.join('\n')}`);
});
```

</details>
