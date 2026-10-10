ELIXIRC = elixirc
THREADS ?= 8
# Run one scheduler per thread and stop dirty schedulers busy-waiting since they steal processors from the workers
ELIXIR = elixir --erl "+S $(THREADS) +sbwtdcpu none +sbwtdio none"

ebin/Elixir.CountdownPar.beam: solver.ex countdown.ex
	mkdir -p ebin
	$(ELIXIRC) --warnings-as-errors -o ebin solver.ex countdown.ex

run: ebin/Elixir.CountdownPar.beam
	./countdown

# Test with the default thread count and again with one thread
test: ebin/Elixir.CountdownPar.beam
	COUNTDOWN_THREADS=$(THREADS) $(ELIXIR) -pa ebin tests.exs
	COUNTDOWN_THREADS=1 elixir --erl "+S 1" -pa ebin tests.exs

clean:
	rm -rf ebin

.PHONY: run test clean
