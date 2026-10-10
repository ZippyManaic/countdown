JULIA ?= julia
JULIAFLAGS ?= -O3 --startup-file=no

run:
	$(JULIA) $(JULIAFLAGS) countdown.jl

test:
	$(JULIA) $(JULIAFLAGS) tests.jl

.PHONY: run test
