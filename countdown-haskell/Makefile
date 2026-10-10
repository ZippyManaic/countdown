GHC = ghc
GHCFLAGS ?= -O2 -msse4.2

countdown: Countdown.hs Round.hs Solver.hs
	$(GHC) $(GHCFLAGS) -outputdir build -o countdown Countdown.hs

test: Tests.hs Round.hs Solver.hs
	$(GHC) $(GHCFLAGS) -outputdir build -o tests Tests.hs
	./tests

clean:
	rm -rf countdown tests build

.PHONY: test clean
