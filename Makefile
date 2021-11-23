# This Makefile exists to orchestrate Zig's `build.zig` and JavaScript's `package.json`. In many
# cases you will still want to invoke `zig build` or `npm run` directly for more targeted
# execution, but to have one set of commands that covers everything, see below.

build:
	npm run compile
	zig build

install:
	npm install

uninstall:
	rm -rf node_modules

generate:
	npm run generate

lint:
	npm run lint
	zig fmt --check .

fix:
	npm run fix
	zig fmt .

test:
	npm run test
	zig build test

integration:
	npm run test:integration

clean:
	rm -rf bin lib zig-* release debug build node_modules .tsbuildinfo .eslintcache

release:
	@echo "release TODO"

.DEFAULT: build

.PHONY: build install uninstall run generate lint fix test clean