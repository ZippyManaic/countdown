# Join each program with the solver since bwBASIC has no way to include one file in another
countdown.bas: main.bas solver.bas
	cat main.bas solver.bas > countdown.bas

test: tests.bas solver.bas
	cat tests.bas solver.bas > tests-run.bas
	bwbasic tests-run.bas < /dev/null | tail -n +5 | tee tests-run.out
	@grep -q "all tests passed" tests-run.out

clean:
	rm -f countdown.bas tests-run.bas tests-run.out

.PHONY: test clean
