COBC = cobc
COBFLAGS ?= -O2 -free

countdown: countdown.cob solver.cob
	$(COBC) $(COBFLAGS) -x -o $@ countdown.cob solver.cob

test: tests.cob solver.cob
	$(COBC) $(COBFLAGS) -x -o run-tests tests.cob solver.cob
	./run-tests

clean:
	rm -f countdown run-tests

.PHONY: test clean
