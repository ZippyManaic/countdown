FC = gfortran
# Use -O3 since gfortran only inlines the hot store routine at that level
FFLAGS ?= -O3 -march=native -Wall -Wextra -std=f2018

countdown: solver.o main.o
	$(FC) -o $@ solver.o main.o

test: solver.o test.o
	$(FC) -o run-tests solver.o test.o
	./run-tests

main.o test.o: solver.o

%.o: %.f90
	$(FC) $(FFLAGS) -c $<

clean:
	rm -f countdown run-tests *.o *.mod

.PHONY: test clean
