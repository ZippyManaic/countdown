ERLC = erlc
ERLCFLAGS ?= +debug_info

countdown: ebin/solver.beam ebin/countdown.beam
	printf '#!/bin/sh\nexec erl -noshell +S 1 -mode minimal -pa "%s/ebin" -run countdown main\n' "$(CURDIR)" > countdown
	chmod +x countdown

ebin/%.beam: %.erl
	@mkdir -p ebin
	$(ERLC) $(ERLCFLAGS) -o ebin $<

test: ebin/solver.beam ebin/countdown.beam ebin/solver_tests.beam
	erl -noshell -pa ebin -eval 'case eunit:test(solver_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end'

clean:
	rm -rf ebin countdown

.PHONY: test clean
