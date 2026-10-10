# Suppress runtime checks and inline across units since the solver guarantees its own bounds
ADAFLAGS ?= -O3 -gnatn -gnatp -march=native

countdown: countdown.adb solver.adb solver.ads
	gnatmake -q $(ADAFLAGS) countdown

test: tests.adb solver.adb solver.ads
	gnatmake -q $(ADAFLAGS) tests
	./tests

clean:
	rm -f countdown tests *.o *.ali

.PHONY: test clean
