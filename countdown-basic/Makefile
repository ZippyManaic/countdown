# Join each program with the solver since bwBASIC has no way to include one file in another
countdown.bas: main.bas solver.bas deal.bas
	cat main.bas solver.bas deal.bas > countdown.bas

test: tests.bas solver.bas deal.bas
	cat tests.bas solver.bas deal.bas > tests-run.bas
	bwbasic tests-run.bas < /dev/null | tail -n +5 | tee tests-run.out
	@grep -q "all tests passed" tests-run.out
	@# Check the script rejects three arguments since bwBASIC never sees them
	@./countdown cats 1 2 2>/dev/null; test $$? -eq 2

clean:
	rm -f countdown.bas tests-run.bas tests-run.out

.PHONY: test clean
