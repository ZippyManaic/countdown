# Compile the optimised C solver to WebAssembly and run it under Node
CC = clang
SOLVER = ../countdown-c/solver.c
# Shadow immintrin.h with portable stand-ins so the unchanged C source compiles for wasm
CFLAGS ?= -O2 -msimd128 -mbulk-memory -mnontrapping-fptoint -Wall -Wextra -std=gnu17
WASMFLAGS = --target=wasm32-wasi -mexec-model=reactor -Icompat -I../countdown-c
LDFLAGS = -Wl,--export=solve -Wl,--export=malloc -Wl,--export=free

solver.wasm: $(SOLVER) ../countdown-c/solver.h compat/immintrin.h
	$(CC) $(WASMFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $(SOLVER)

run: solver.wasm
	node countdown.mjs

test: solver.wasm
	node --test test.mjs

clean:
	rm -f solver.wasm

.PHONY: run test clean
