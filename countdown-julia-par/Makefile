JULIA ?= julia
COUNTDOWN_THREADS ?= 8
export COUNTDOWN_THREADS
JULIAFLAGS ?= -O3 --startup-file=no -t $(COUNTDOWN_THREADS),0

run:
	$(JULIA) $(JULIAFLAGS) countdown.jl

# Run the tests sharing work across threads and again on one thread
test:
	$(JULIA) $(JULIAFLAGS) tests.jl
	COUNTDOWN_THREADS=1 $(JULIA) -O3 --startup-file=no -t 1,0 tests.jl
	COUNTDOWN_THREADS=4 COUNTDOWN_BUILD_MIN=0 COUNTDOWN_WHOLE_MIN=0 COUNTDOWN_SEARCH_SIZE=2 $(JULIA) -O3 --startup-file=no -t 4,0 tests.jl

.PHONY: run test
