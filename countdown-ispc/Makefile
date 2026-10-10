# Build the solver for AVX2 with four 64-bit lanes since that gang width measured fastest
CC = clang
CFLAGS ?= -O2 -march=native -Wall -Wextra -std=gnu17
ISPC = ispc
# Leave out the generic performance warnings since the one varying shift they flag is a single instruction here
ISPCFLAGS ?= -O2 --target=avx2-i64x4 --pic --wno-perf

countdown: main.o solver.o
	$(CC) -o $@ main.o solver.o

solver.o: solver.ispc
	$(ISPC) $(ISPCFLAGS) -o $@ $<

test: test.o solver.o
	$(CC) -o run-tests test.o solver.o
	./run-tests

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
