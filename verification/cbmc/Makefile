# Run every CBMC proof and native check on the C solver under a memory cap and timeout
#
# make all        run the SAT (CaDiCaL) proofs and the native checks
# make z3         rerun the proofs that reach a verdict with Z3 as the decision procedure
# make slow       run the full-range reciprocal proofs that time out on this machine
# Each run writes logs/<name>.log ending with its wall time and peak memory

CAP ?= 6G
TIMEOUT ?= 1800
CPUS ?= 20-23
RUN = /usr/bin/time -f "%e s %M KB" ./cap.sh $(CAP) $(TIMEOUT) $(CPUS)
SAT = --external-sat-solver cadical
CHECKS = --pointer-check --bounds-check --unsigned-overflow-check --signed-overflow-check --conversion-check
RECIP = --property main.assertion.1 --property main.assertion.2 --property main.assertion.3
# Bound each build loop by what two lists of at most LMAX and RMAX values can need
BUILD_1X1 = -DLMAX=1 -DRMAX=1 -DVMAX=12u --object-bits 12 --unwind 2 \
	--unwindset main.0:2,main.1:2,main.2:2,main.3:2,main.4:5,main.5:5,main.6:5,main.7:4,ref_add.0:5,build.16:5,build.17:5,build.18:4,build.19:5,grow.0:0,reserve_rights.0:4 \
	--no-built-in-assertions --no-unwinding-assertions

PROOFS = reciprocal_x1000 reciprocal_y30 reciprocal_y15x20 lookup_16 lookup_order_1024 emit_24 rank_20 build_1x1 cats_ops
Z3 = $(addprefix z3_,reciprocal_x1000 lookup_16 emit_24 cats_ops build_1x1)
NATIVE = shim_check recip_exhaustive build_exhaustive cats_bounds cats_sweep

all: $(addprefix logs/,$(addsuffix .log,$(PROOFS) $(NATIVE)))
z3: $(addprefix logs/,$(addsuffix .log,$(Z3)))
slow: logs/reciprocal_full.log logs/reciprocal_y1.log logs/cats_bounds_std.log logs/build_2x2.log

logs:
	mkdir -p logs

native/build/%: FORCE
	$(MAKE) -C native build/$*

# Prove the reciprocal test on cells of dividends and divisors
logs/reciprocal_x1000.log: | logs
	$(RUN) cbmc -I shim harness/reciprocal.c -DX_MAX=1000u $(SAT) $(RECIP) > $@ 2>&1
logs/reciprocal_y30.log: | logs
	$(RUN) cbmc -I shim harness/reciprocal.c -DY_MIN=1073741824u -DY_MAX=2147483647u $(SAT) $(RECIP) > $@ 2>&1
logs/reciprocal_y15x20.log: | logs
	$(RUN) cbmc -I shim harness/reciprocal.c -DY_MIN=32768u -DY_MAX=65535u -DX_MIN=1048576u -DX_MAX=2097151u $(SAT) $(RECIP) > $@ 2>&1
logs/reciprocal_full.log: | logs
	$(RUN) cbmc -I shim harness/reciprocal.c $(SAT) $(RECIP) > $@ 2>&1
logs/reciprocal_y1.log: | logs
	$(RUN) cbmc -I shim harness/reciprocal.c -DY_MAX=3u $(SAT) $(RECIP) > $@ 2>&1

# Prove the branchless binary search against a plain scan
logs/lookup_16.log: | logs
	$(RUN) cbmc -I shim harness/lookup.c -DN=16 $(SAT) --unwindset main.0:17,main.1:17,lookup.0:6 $(CHECKS) > $@ 2>&1
logs/lookup_order_1024.log: | logs
	$(RUN) cbmc -I shim harness/lookup_order.c -DN=1024 $(SAT) --unwindset main.0:1025,lookup.0:11 $(CHECKS) > $@ 2>&1

# Prove the append and sort kernels
logs/emit_24.log: | logs
	$(RUN) cbmc -I shim harness/emit.c $(SAT) --unwind 26 $(CHECKS) > $@ 2>&1
logs/rank_20.log: | logs
	$(RUN) cbmc -I shim harness/rank.c $(SAT) --unwind 22 $(CHECKS) > $@ 2>&1
logs/build_1x1.log: | logs
	$(RUN) cbmc -I shim harness/build.c $(SAT) $(BUILD_1X1) $(CHECKS) > $@ 2>&1
logs/build_2x2.log: | logs
	$(RUN) cbmc -I shim harness/build.c $(SAT) -DLMAX=2 -DRMAX=2 -DVMAX=12u --object-bits 12 --unwind 3 --unwindset main.0:3,main.1:3,main.2:3,main.3:3,main.4:17,main.5:17,main.6:17,main.7:4,ref_add.0:17,build.16:17,build.17:17,build.18:4,build.19:17,grow.0:0,reserve_rights.0:4 --no-built-in-assertions --no-unwinding-assertions $(CHECKS) > $@ 2>&1

# Prove cats-mode arithmetic and indexing
logs/cats_ops.log: | logs
	$(RUN) cbmc -I shim harness/cats_ops.c $(SAT) --unwind 2 $(CHECKS) > $@ 2>&1
logs/cats_bounds_std.log: | logs
	$(RUN) cbmc -I shim harness/cats_bounds.c $(SAT) --unwind 70 --object-bits 12 $(CHECKS) > $@ 2>&1

# Rerun the proofs that reach a verdict with Z3 using its floating-point theory where floats appear
logs/z3_reciprocal_x1000.log: | logs
	$(RUN) cbmc -I shim harness/reciprocal.c -DX_MAX=1000u --z3 --fpa $(RECIP) > $@ 2>&1
logs/z3_lookup_16.log: | logs
	$(RUN) cbmc -I shim harness/lookup.c -DN=16 --z3 --unwindset main.0:17,main.1:17,lookup.0:6 $(CHECKS) > $@ 2>&1
logs/z3_emit_24.log: | logs
	$(RUN) cbmc -I shim harness/emit.c --z3 --unwind 26 $(CHECKS) > $@ 2>&1
logs/z3_cats_ops.log: | logs
	$(RUN) cbmc -I shim harness/cats_ops.c --z3 --unwind 2 $(CHECKS) > $@ 2>&1
logs/z3_build_1x1.log: | logs
	$(RUN) cbmc -I shim harness/build.c --z3 --fpa $(BUILD_1X1) $(CHECKS) > $@ 2>&1

# Run the native checks on the real hardware
logs/shim_check.log: native/build/shim-check | logs
	$(RUN) native/build/shim-check > $@ 2>&1
logs/recip_exhaustive.log: native/build/recip-exhaustive | logs
	$(RUN) native/build/recip-exhaustive > $@ 2>&1
logs/build_exhaustive.log: native/build/build-exhaustive | logs
	$(RUN) native/build/build-exhaustive > $@ 2>&1
logs/cats_bounds.log: native/build/bounds | logs
	$(RUN) native/build/bounds > $@ 2>&1
logs/cats_sweep.log: native/build/driver-san native/build/driver | logs
	$(RUN) python3 native/sweep.py > $@ 2>&1

clean:
	rm -rf logs native/build

.PHONY: all z3 slow clean FORCE
