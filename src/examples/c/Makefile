CC=gcc
#CC=clang
CFLAGS=-Wall -Wextra -pedantic -std=c99

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

example: example.o
	$(CC) -o $@ $^ $(CFLAGS)

.PHONY: clean
clean:
	rm -f *.o example

.DEFAULT: example

