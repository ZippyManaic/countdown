ERLC = erlc
ERLCFLAGS ?= +debug_info
# Keep idle schedulers spinning and spread across cores so a worker answers a job without being woken
ERLFLAGS = +sbwt very_long +swt very_low +scl false +sbt db

countdown: ebin/solver_par.beam ebin/countdown_par.beam
	printf '#!/bin/sh\nexec erl -noshell +S "$${COUNTDOWN_THREADS:-8}" $(ERLFLAGS) -mode minimal -pa "%s/ebin" -run countdown_par main -extra "$$@"\n' "$(CURDIR)" > countdown
	chmod +x countdown

ebin/%.beam: %.erl
	@mkdir -p ebin
	$(ERLC) $(ERLCFLAGS) -o ebin $<

test: ebin/solver_par.beam ebin/countdown_par.beam ebin/solver_par_tests.beam
	erl -noshell +S 4 $(ERLFLAGS) -pa ebin -eval 'case eunit:test(solver_par_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end'

clean:
	rm -rf ebin countdown

.PHONY: test clean
