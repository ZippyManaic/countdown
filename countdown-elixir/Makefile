ELIXIRC = elixirc
# Run the virtual machine with one scheduler since a single round gains nothing from more
ELIXIR = elixir --erl "+S 1"

ebin/Elixir.Countdown.beam: solver.ex countdown.ex
	mkdir -p ebin
	$(ELIXIRC) --warnings-as-errors -o ebin solver.ex countdown.ex

run: ebin/Elixir.Countdown.beam
	./countdown

test: ebin/Elixir.Countdown.beam
	$(ELIXIR) -pa ebin tests.exs

clean:
	rm -rf ebin

.PHONY: run test clean
