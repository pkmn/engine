# This Makefile exists to orchestrate Zig's `build.zig` and JavaScript's
# `package.json`. In many cases you will still want to invoke `zig build` or
# `npm run` directly for more targeted execution, but to have one set of
# commands that covers everything, see below.

.PHONY: default
default: check

.PHONY: zig-build
zig-build:
	zig build --summary all -Dlog -Dchance -Dcalc -p build
	zig build --summary all -Dshowdown -Dlog -Dchance -Dcalc -p build

.PHONY: js-build
js-build: export DEBUG_PKMN_ENGINE=true
js-build: node_modules
	node src/bin/install-pkmn-engine --options='-Dshowdown -Dlog -Dchance -Dcalc'
	npm run compile

.PHONY: build
build: zig-build js-build

node_modules:
	npm install

.PHONY: install
install: node_modules

.PHONY: uninstall
uninstall:
	rm -rf node_modules

.PHONY: generate
generate:
	npm run generate

.PHONY: zig-lint
zig-lint:
	ziglint --exclude src/examples/zig/example.zig,src/lib/gen1/calc.zig

.PHONY: js-lint
js-lint: node_modules
	npm run lint

.PHONY: lint
lint: zig-lint js-lint

.PHONY: zig-fix
zig-fix:
	zig fmt . --exclude build

.PHONY: js-fix
js-fix: node_modules
	npm run fix

.PHONY: fix
fix: zig-fix js-fix

.PHONY: zig-test
zig-test:
	zig build --summary all -Dlog -Dchance -Dcalc test
	zig build --summary all -Dshowdown -Dlog -Dchance -Dcalc test

.PHONY: js-test
js-test: js-build
	npm run test

.PHONY: test
test: zig-test js-test

.PHONY: zig-coverage
zig-coverage:
	rm -rf coverage/zig
	mkdir -p coverage/zig
	zig build --summary all test -Dtest-coverage=coverage/zig/pkmn
	zig build --summary all -Dshowdown -Dlog -Dchance -Dcalc test -Dtest-coverage=coverage/zig/pkmn-showdown
	kcov --merge coverage/zig/merged coverage/zig/pkmn coverage/zig/pkmn-showdown

.PHONY: js-coverage
js-coverage: js-build
	npm run test -- --coverage

.PHONY: coverage
coverage: zig-coverage js-coverage

.PHONY: check
check: test lint

.PHONY: c-example
c-example:
	$(MAKE) -C src/examples/c
	./src/examples/c/example 1234

src/examples/js/node_modules:
	npm -C src/examples/js install --install-links=false

.PHONY: js-example
js-example: src/examples/js/node_modules
	npm -C src/examples/js start

.PHONY: zig-example
zig-example:
	cd src/examples/zig; zig build --summary all run -- 1234

.PHONY: example
example: c-example js-example zig-example

.PHONY: addon
addon: export DEBUG_PKMN_ENGINE=true
addon:
	node src/bin/install-pkmn-engine --options='-Dshowdown -Dlog -Dchance -Dcalc'

.PHONY: integration
integration: build test example lint addon
	npm run test:integration

.PHONY: benchmark
benchmark: export DEBUG_PKMN_ENGINE=
benchmark:
	node src/bin/install-pkmn-engine --options='-Dshowdown'
	npm run benchmark

.PHONY: clean-example
clean-example:
	$(MAKE) clean -C src/examples/c
	rm -rf src/examples/js/.parcel* src/examples/js/{build,dist}
	rm -rf src/examples/zig/zig-*

.PHONY: clean
clean: clean-example
	rm -rf zig-* build .tsbuildinfo .eslintcache

.PHONY: release
release:
	npm run release -- --prod

, := ,
gen := $(or $(gen),1)
seed := $(or $(seed),1$(,)2$(,)3$(,)4)
opt := $(if $(filter true,$(showdown)),-Dshowdown,)

.PHONY: patch
patch:
	sed -i '' 's|"@pkmn/sim":.*",|"@pkmn/sim": "file:../ps/sim",|g' package.json
	sed -i '' 's|sim/battle-queue.ts:405:15|sim/battle-queue.ts:408:15|g' src/test/showdown.ts
	sed -i '' 's|/.*@pkmn\/sim\//|/.*ps\/sim\//|g' src/test/showdown.ts
	npm install --install=links=false

.PHONY: t
t:
	zig build --summary all test -Dlog -Dchance -Dcalc -Dtest-file=src/lib/gen$(gen)/test.zig -Dtest-filter="$(filter)" $(opt)

.PHONY: it
it:
	npm run integration -- --cycles=1 --maxFailures=1 --gen=$(gen) --seed=$(seed)

