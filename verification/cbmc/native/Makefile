# Build the real solver unchanged with sanitisers and plainly for the cats-mode sweep
SOLVER = ../../../countdown-c
CC = clang
OUT ?= build

all: $(OUT)/driver-san $(OUT)/driver $(OUT)/bounds $(OUT)/shim-check $(OUT)/recip-exhaustive $(OUT)/build-exhaustive

$(OUT):
	mkdir -p $(OUT)

$(OUT)/driver-san: driver.c $(SOLVER)/solver.c | $(OUT)
	$(CC) -O1 -g -march=native -std=gnu17 -I$(SOLVER) -fsanitize=address,undefined,integer -fno-sanitize-recover=all -o $@ driver.c $(SOLVER)/solver.c

$(OUT)/driver: driver.c $(SOLVER)/solver.c | $(OUT)
	$(CC) -O2 -march=native -std=gnu17 -I$(SOLVER) -o $@ driver.c $(SOLVER)/solver.c

$(OUT)/bounds: bounds.c | $(OUT)
	$(CC) -O2 -o $@ bounds.c

clean:
	rm -rf $(OUT)

.PHONY: all clean

# Check the CBMC intrinsic models against the real instructions
$(OUT)/shim-check: shim_check.c shim_tu.c ../shim/immintrin.h | $(OUT)
	$(CC) -O2 -march=native -I../shim -c -o $(OUT)/shim_tu.o shim_tu.c
	$(CC) -O2 -march=native -o $@ shim_check.c $(OUT)/shim_tu.o -lm

# Check the reciprocal test at every exact quotient across the whole 32-bit range
$(OUT)/recip-exhaustive: recip_exhaustive.c $(SOLVER)/solver.c | $(OUT)
	$(CC) -O2 -march=native -std=gnu17 -I$(SOLVER) -pthread -o $@ recip_exhaustive.c

# Compare build with a reference on every small pair of lists and on random larger ones
$(OUT)/build-exhaustive: build_exhaustive.c $(SOLVER)/solver.c | $(OUT)
	$(CC) -O2 -march=native -std=gnu17 -I$(SOLVER) -o $@ build_exhaustive.c
