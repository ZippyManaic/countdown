FBC = fbc
FBCFLAGS ?= -gen gcc -O 3 -Wc -march=native

countdown: countdown.bas deal.bas solver.bas
	$(FBC) $(FBCFLAGS) countdown.bas -x countdown

test: tests.bas deal.bas solver.bas
	$(FBC) $(FBCFLAGS) tests.bas -x tests
	./tests

clean:
	rm -f countdown tests

.PHONY: test clean
