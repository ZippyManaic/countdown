# Use clang since it compiles the solver's hot loops about 10% faster than gcc
CC = clang
CFLAGS ?= -O2 -march=native -Wall -Wextra -std=gnu17
LDLIBS = -pthread

countdown: main.o solver.o
	$(CC) -o $@ main.o solver.o $(LDLIBS)

test: test.o solver.o
	$(CC) -o run-tests test.o solver.o $(LDLIBS)
	./run-tests
	COUNTDOWN_THREADS=1 ./run-tests

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
