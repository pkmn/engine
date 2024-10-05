# On the GitHub CI where this example runs we install everything locally instead
# of using something like `--prefix /usr/local` which complicates things as we
# can't rely on default search semantics.
#
# `suffix` (to opt into libpkmn-showdown) or `dynamic` may be set to opt into
# different linking semantics. `options` is a bit of a hack to simplify the
# GitHub CI as its easier than passing the correct suffix in the YAML.
#
# The OS won't know where to look for our dynamic libraries unless we configure
# the rpath to bake it into the executable (or set `LD_LIBRARY_PATH`, use
# `install_name_tool`, etc). Sadly, the flag requires a different syntax
# ($ORIGIN vs. @executable_path) for relative paths based on OS. Of course,
# Windows doesn't support any of this
# (https://ibob.bg/blog/2018/12/16/windows-rpath/) so we just give up and copy
# the files into the current directory directly. This isn't required for static
# linking on Windows, but for simplicity we copy the artifacts anyway (though
# the location of said exact artifacts changed from lib -> bin in
# ziglang/zig#19743).
#
# On macOS we also need to set `-mmacosx-version-min` on our executable as Zig
# will set the precise version on the library it builds which will result in
# warnings as the default for the C executable would otherwise just be the major
# version.
#
# Possibly due to some Zig or MinGW issue we need to also need to link against
# 'C:/Windows/System32/ntdll.dll' (which can't be statically linked to?) - when
# compiling the C code with the Zig toolchain this will get automatically
# linked. Some documentation suggests that GCC requires the static library to be
# named libpkmn.a instead of pkmn.lib, but the latter seems to work fine.

ROOT=../../build
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
else
	CC = gcc
endif

ifeq ($(dynamic),true)
	ifeq ($(OS),Windows_NT)
		LDFLAGS = -L. -lpkmn$(suffix)
	else
		LDFLAGS = $(RPATH) -L$(ROOT)/lib -lpkmn$(suffix)
	endif
else
	ifeq ($(OS),Windows_NT)
		LDFLAGS = pkmn$(suffix).lib C:/Windows/System32/ntdll.dll
	else
		LDFLAGS = $(ROOT)/lib/libpkmn$(suffix).a
	endif
endif

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

example: example.o
ifeq ($(OS),Windows_NT)
ifeq (,$(wildcard $(ROOT)/lib/pkmn$(suffix).lib))
	cp $(ROOT)/bin/pkmn$(suffix).lib .
else
	cp $(ROOT)/lib/pkmn$(suffix).lib .
endif
ifeq ($(dynamic),true)
ifeq (,$(wildcard $(ROOT)/lib/pkmn$(suffix).dll))
	cp $(ROOT)/bin/pkmn$(suffix).dll .
else
	cp $(ROOT)/lib/pkmn$(suffix).dll .
endif
endif
endif
	$(CC) -o $@ $^ $(CFLAGS) $(LDFLAGS)

.PHONY: clean
clean:
	rm -f *.o *.dll *.lib example

.DEFAULT: example
