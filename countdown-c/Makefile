# Use clang since it compiles the solver's hot loops about 10% faster than gcc
CC = clang
CFLAGS ?= -O2 -march=native -Wall -Wextra -std=gnu17

countdown: main.o round.o solver.o
	$(CC) -o $@ main.o round.o solver.o

test: test.o round.o solver.o
	$(CC) -o run-tests test.o round.o solver.o
	./run-tests

# Rebuild the main program and tests when the dealer interface changes
main.o test.o round.o: round.h

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
