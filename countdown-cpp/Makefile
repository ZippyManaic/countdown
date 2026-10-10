CXX = clang++
CXXFLAGS ?= -O2 -march=native -Wall -Wextra -std=c++23

countdown: main.o solver.o
	$(CXX) -o $@ main.o solver.o

test: test.o solver.o
	$(CXX) -o run-tests test.o solver.o
	./run-tests

clean:
	rm -f countdown run-tests *.o

.PHONY: test clean
