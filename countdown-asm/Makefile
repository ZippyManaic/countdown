CC = clang

countdown: main.o round.o solver.o
	ld -o $@ main.o round.o solver.o

%.o: %.s
	as -o $@ $<

# Link the C test driver against the dealer and solver since they follow the System V calling convention
run-tests: test.c round.h round.o solver.o
	$(CC) -O2 -Wall -Wextra -std=gnu17 -no-pie -o $@ test.c round.o solver.o

test: run-tests countdown
	./run-tests
	./test-exit-codes.sh

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
