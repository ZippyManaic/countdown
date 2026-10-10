CXX = clang++
CXXFLAGS ?= -O2 -march=native -Wall -Wextra -std=c++23

countdown: main.o round.o solver.o
	$(CXX) -o $@ main.o round.o solver.o

test: test.o round.o solver.o
	$(CXX) -o run-tests test.o round.o solver.o
	./run-tests

# Rebuild the main program and tests when the dealer interface changes
main.o test.o round.o: round.hpp

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
