# Use clang since it compiles the solver's hot loops about 10% faster than gcc
CC = clang
CFLAGS ?= -O2 -march=native -Wall -Wextra -std=gnu17

countdown: main.o solver.o
	$(CC) -o $@ main.o solver.o

test: test.o solver.o
	$(CC) -o run-tests test.o solver.o
	./run-tests

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
