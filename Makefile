# This Makefile exists to orchestrate Zig's `build.zig` and JavaScript's `package.json`. In many
# cases you will still want to invoke `zig build` or `npm run` directly for more targeted
# execution, but to have one set of commands that covers everything, see below.

.PHONY: zig-build
zig-build:
	zig build -p build
	zig build -Dshowdown -Dtrace -p build

.PHONY: js-build
js-build:
	npm run compile

.PHONY: build
build: zig-build js-build

.PHONY: install
install:
	npm install

.PHONY: uninstall
uninstall:
	rm -rf node_modules

.PHONY: generate
generate:
	npm run generate

.PHONY: zig-lint
zig-lint:
	zig fmt --check .

.PHONY: js-lint
js-lint:
	npm run lint

.PHONY: lint
lint: zig-lint js-lint

.PHONY: zig-fix
zig-fix:
	zig fmt .

.PHONY: js-fix
js-fix:
	npm run fix

.PHONY: fix
fix: zig-fix js-fix

.PHONY: zig-test
zig-test:
	zig build test
	zig build -Dshowdown -Dtrace test

.PHONY: js-test
js-test: zig-build js-build
	npm run test

.PHONY: test
test: zig-test js-test

.PHONY: zig-coverage
zig-coverage:
	rm -f coverage/zig
	mkdir -p coverage/zig
	zig build test -Dtest-coverage=coverage/zig/pkmn
	zig build -Dshowdown -Dtrace test -Dtest-coverage=coverage/zig/pkmn-showdown
	kcov --merge coverage/zig/merged coverage/zig/pkmn coverage/zig/pkmn-showdown

.PHONY: js-coverage
js-coverage: js-test

.PHONY: coverage
coverage: zig-coverage js-coverage

.PHONY: check
check: test lint

.PHONY: integration
integration: check
	npm run test:integration

.PHONY: clean
clean:
	rm -rf bin lib zig-* build node_modules .tsbuildinfo .eslintcache

.PHONY: release
release:
	@echo "release TODO"

.DEFAULT: build