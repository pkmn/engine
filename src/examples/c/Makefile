# On the GitHub CI where this example runs we install everything locally instead of using something
# like `--prefix /usr/local` which complicates things as we can't rely on default search semantics.
#
# `suffix` (to opt into libpkmn-showdown) or `dynamic` may be set to opt into different linking
# semantics. `options` is a bit of a hack to simplify the GitHub CI as its easier than passing
# the correct suffix in the YAML.
#
# The OS won't know where to look for our dynamic libraries unless we configure the rpath to bake it
# into the executable (or set `LD_LIBRARY_PATH`, use `install_name_tool`, etc). Sadly, the flag
# requires a different syntax ($ORIGIN vs. @executable_path) for relative paths based on OS.
#
# On macOS we also need to set `-mmacosx-version-min` on our executable as Zig will set the precise
# version on the library it builds which will result in warnings as the default for the C executable
# would otherwise just be the major version.
#
# TODO: Add examples demonstrating Windows support...

ROOT=../../../build
CFLAGS = -Wall -Wextra -pedantic -std=c99 -I$(ROOT)/include

suffix ?= $(if $(findstring showdown,$(options)),-showdown,)

ifneq ($(OS),Windows_NT)
	RPATH := -Wl,-rpath
	UNAME := $(shell uname -s)
	ifeq ($(UNAME),Linux)
			RPATH := "$(RPATH),\$$ORIGIN/$(ROOT)/lib"
			CFLAGS += -no-pie
	endif
	ifeq ($(UNAME),Darwin)
			RPATH := "$(RPATH),@executable_path/$(ROOT)/lib"
			CFLAGS += -mmacosx-version-min=$(shell sw_vers -productVersion)
	endif
endif

ifeq ($(dynamic),true)
	LDFLAGS = $(RPATH) -L$(ROOT)/lib -lpkmn$(suffix)
else
	ifeq ($(OS),Windows_NT)
		LDFLAGS = $(ROOT)/lib/pkmn$(suffix).lib
	else
		LDFLAGS = $(ROOT)/lib/libpkmn$(suffix).a
	endif
endif

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

ifeq ($(OS),Windows_NT)
example:
	@echo "TODO"
else
example: example.o
	$(CC) -o $@ $^ $(CFLAGS) $(LDFLAGS)
endif

.PHONY: clean
clean:
	rm -f *.o example

.DEFAULT: example
