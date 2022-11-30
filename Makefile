# This Makefile exists to orchestrate Zig's `build.zig` and JavaScript's `package.json`. In many
# cases you will still want to invoke `zig build` or `npm run` directly for more targeted
# execution, but to have one set of commands that covers everything, see below.

.PHONY: default
default: check

.PHONY: zig-build
zig-build:
	zig build -Dtrace -p build
	zig build -Dshowdown -Dtrace -p build

.PHONY: js-build
js-build: node_modules
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
	zig build lint

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
	zig build -Dtrace test
	zig build -Dshowdown -Dtrace test

.PHONY: js-test
js-test: js-build
	npm run test

.PHONY: test
test: zig-test js-test

.PHONY: zig-coverage
zig-coverage:
	rm -rf coverage/zig
	mkdir -p coverage/zig
	zig build test -Dtest-coverage=coverage/zig/pkmn
	zig build -Dshowdown -Dtrace test -Dtest-coverage=coverage/zig/pkmn-showdown
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
	./src/examples/c/example

src/examples/js/node_modules:
	npm -C src/examples/js install

.PHONY: js-example
js-example: src/examples/js/node_modules
	npm -C src/examples/js start

.PHONY: zig-example
zig-example:
	cd src/examples/zig; zig build run -- 1234

.PHONY: example
example: c-example js-example zig-example

.PHONY: integration
# TODO: integration: check example
integration: check zig-example
	npm run test:integration

.PHONY: benchmark
benchmark:
	npm run benchmark

.PHONY: clean
clean:
	rm -rf zig-* build .tsbuildinfo .eslintcache
	$(MAKE) clean -C src/examples/c
	rm -rf src/examples/js/.parcel* src/examples/js/dist
	rm -rf src/examples/zig/zig-*

.PHONY: release
release:
	@echo "release TODO"

