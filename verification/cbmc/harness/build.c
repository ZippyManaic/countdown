// Prove build turns every pair of two symbolic sorted lists into the same sorted first-derivation list as a plain reference
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Bound the list lengths and the values in them
#ifndef LMAX
#define LMAX 3
#endif
#ifndef RMAX
#define RMAX 3
#endif
#ifndef VMAX
#define VMAX 12u
#endif

uint32_t nondet_u32(void);

// Hold the reference result as plain entries
static entry ref[4 * LMAX * RMAX];
static size_t nref;

// Keep a result only if no earlier derivation made the same value
static void ref_add(uint32_t v, uint8_t op, unsigned lm, unsigned sm, uint32_t big, uint32_t small)
{
    if (v == 0)
        return;
    for (size_t k = 0; k < nref; k++)
        if (ref[k].value == v)
            return;
    ref[nref++] = (entry){.value = v, .op = op, .larger_mask = (uint8_t)lm, .smaller_mask = (uint8_t)sm, .larger = big, .smaller = small};
}

int main(void)
{
    // Keep the state in a global so CBMC tracks where each of its pointers points
    static state st;
    state *s = &st;
    uint32_t nl = nondet_u32(), nr = nondet_u32();
    __CPROVER_assume(1 <= nl && nl <= LMAX && 1 <= nr && nr <= RMAX);
    s->full = 3;
    // Point the buffers at typed static arrays big enough that grow never reallocates since CBMC runs out of memory on grow's untyped blocks
    static entry arena[LMAX + RMAX + 4 * LMAX * RMAX], tmp[4 * LMAX * RMAX + 1];
    static uint32_t right_values[LMAX > RMAX ? LMAX : RMAX];
    static double right_inv[LMAX > RMAX ? LMAX : RMAX];
    s->arena = arena, s->cap = sizeof arena / sizeof *arena;
    s->tmp = tmp, s->tmp_cap = sizeof tmp / sizeof *tmp;
    s->right_values = right_values, s->right_inv = right_inv;
    s->right_cap = sizeof right_values / sizeof *right_values;
    // Fill subset 1 and subset 2 with strictly ascending positive values
    uint32_t prev = 0;
    for (uint32_t i = 0; i < nl; i++) {
        uint32_t v = nondet_u32();
        __CPROVER_assume(prev < v && v <= VMAX);
        s->arena[i] = (entry){.value = v};
        prev = v;
    }
    prev = 0;
    for (uint32_t j = 0; j < nr; j++) {
        uint32_t v = nondet_u32();
        __CPROVER_assume(prev < v && v <= VMAX);
        s->arena[nl + j] = (entry){.value = v};
        prev = v;
    }
    s->off[1] = 0, s->len[1] = nl;
    s->off[2] = nl, s->len[2] = nr;
    s->top = nl + nr;
    // Bound the pair's values the way solve does from each side's largest value
    uint64_t a = s->arena[nl - 1].value, b = s->arena[nl + nr - 1].value;
    s->max[1] = (uint32_t)a, s->max[2] = (uint32_t)b;
#ifdef FIXED_MAX
    // Use the largest bound any lists in range could give so the bitset size is concrete
    s->max[3] = VMAX * VMAX;
#else
    s->max[3] = (uint32_t)(a * b > a + b ? a * b : a + b);
#endif
    reserve_rights(s);
    reserve_seen(s, s->max[3]);
    build(s, 3);

    // Enumerate every pair in the reference order of left ascending then right ascending with the larger operand first
    for (uint32_t i = 0; i < nl; i++) {
        for (uint32_t j = 0; j < nr; j++) {
            uint32_t p = s->arena[i].value, q = s->arena[nl + j].value;
            bool left_larger = p >= q;
            uint32_t x = left_larger ? p : q, y = left_larger ? q : p;
            unsigned lm = left_larger ? 1 : 2, sm = left_larger ? 2 : 1;
            ref_add(x + y, OP_ADD, lm, sm, x, y);
            if (x != y)
                ref_add(x - y, OP_SUB, lm, sm, x, y);
            if (y != 1) {
                ref_add(x * y, OP_MUL, lm, sm, x, y);
                if (x % y == 0)
                    ref_add(x / y, OP_DIV, lm, sm, x, y);
            }
        }
    }
    // Sort the reference by value with a plain insertion sort
    for (size_t i = 1; i < nref; i++) {
        entry e = ref[i];
        size_t k = i;
        for (; k > 0 && ref[k - 1].value > e.value; k--)
            ref[k] = ref[k - 1];
        ref[k] = e;
    }

    assert(s->len[3] == nref);
    assert(s->off[3] == nl + nr);
    const entry *got = s->arena + s->off[3];
    for (size_t k = 0; k < nref; k++) {
        assert(got[k].value == ref[k].value);
        assert(got[k].op == ref[k].op);
        assert(got[k].larger_mask == ref[k].larger_mask);
        assert(got[k].smaller_mask == ref[k].smaller_mask);
        assert(got[k].larger == ref[k].larger);
        assert(got[k].smaller == ref[k].smaller);
    }
    // Expect the bitset to be left clear for the next subset
    for (size_t w = 0; w < s->seen_words; w++)
        assert(s->seen[w] == 0);
    return 0;
}
