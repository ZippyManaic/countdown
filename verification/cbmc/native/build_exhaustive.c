// Compare build on every pair of small sorted lists and on random larger ones with a plain reference implementation
#include "../../../countdown-c/solver.c"

static entry ref[4096];
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

static long cases, failures, ranked;

// Build subset 3 from lists a and b as solve would and check it against the reference
static void check(const uint32_t *a, uint32_t na, const uint32_t *b, uint32_t nb)
{
    state *s = calloc(1, sizeof *s);
    s->full = 3;
    s->arena = grow(NULL, &s->cap, 4096, sizeof *s->arena);
    for (uint32_t i = 0; i < na; i++)
        s->arena[i] = (entry){.value = a[i]};
    for (uint32_t j = 0; j < nb; j++)
        s->arena[na + j] = (entry){.value = b[j]};
    s->off[1] = 0, s->len[1] = na, s->off[2] = na, s->len[2] = nb, s->top = na + nb;
    uint64_t x = a[na - 1], y = b[nb - 1];
    s->max[1] = (uint32_t)x, s->max[2] = (uint32_t)y;
    s->max[3] = (uint32_t)(x * y > x + y ? x * y : x + y);
    reserve_rights(s);
    reserve_seen(s, s->max[3]);
    build(s, 3);

    nref = 0;
    for (uint32_t i = 0; i < na; i++) {
        for (uint32_t j = 0; j < nb; j++) {
            uint32_t p = a[i], q = b[j];
            bool left_larger = p >= q;
            uint32_t hi = left_larger ? p : q, lo = left_larger ? q : p;
            unsigned lm = left_larger ? 1 : 2, sm = left_larger ? 2 : 1;
            ref_add(hi + lo, OP_ADD, lm, sm, hi, lo);
            if (hi != lo)
                ref_add(hi - lo, OP_SUB, lm, sm, hi, lo);
            if (lo != 1) {
                ref_add(hi * lo, OP_MUL, lm, sm, hi, lo);
                if (hi % lo == 0)
                    ref_add(hi / lo, OP_DIV, lm, sm, hi, lo);
            }
        }
    }
    for (size_t i = 1; i < nref; i++) {
        entry e = ref[i];
        size_t k = i;
        for (; k > 0 && ref[k - 1].value > e.value; k--)
            ref[k] = ref[k - 1];
        ref[k] = e;
    }
    bool ok = s->len[3] == nref && s->off[3] == na + nb;
    const entry *got = s->arena + s->off[3];
    for (size_t k = 0; ok && k < nref; k++)
        ok = !memcmp(&got[k], &ref[k], sizeof(entry));
    for (size_t w = 0; ok && w < s->seen_words; w++)
        ok = s->seen[w] == 0;
    cases++;
    ranked += nref >= RANK_MIN;
    if (!ok && failures++ < 5)
        printf("mismatch for lists of %u and %u values starting %u and %u\n", na, nb, a[0], b[0]);
    free(s->arena), free(s->tmp), free(s->seen), free(s->rank), free(s->right_values), free(s->right_inv), free(s);
}

// Enumerate every strictly ascending list of up to three values from 1 to v
static int lists(uint32_t v, uint32_t out[][3], uint32_t *len)
{
    int n = 0;
    for (uint32_t i = 1; i <= v; i++) {
        out[n][0] = i, len[n++] = 1;
        for (uint32_t j = i + 1; j <= v; j++) {
            out[n][0] = i, out[n][1] = j, len[n++] = 2;
            for (uint32_t k = j + 1; k <= v; k++)
                out[n][0] = i, out[n][1] = j, out[n][2] = k, len[n++] = 3;
        }
    }
    return n;
}

int main(void)
{
    static uint32_t all[3000][3], len[3000];
    int n = lists(24, all, len);
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            check(all[i], len[i], all[j], len[j]);
    printf("exhaustive: %ld cases over lists of up to 3 values from 1 to 24, %ld used the rank sort\n", cases, ranked);

    // Try random longer lists with values up to 60000 so products stay below 2^32 and larger bitsets and longer outputs are covered
    long before = cases;
    uint64_t r = 88172645463325252ull;
    for (int t = 0; t < 20000; t++) {
        uint32_t a[12], b[12], na, nb;
        for (int side = 0; side < 2; side++) {
            uint32_t *l = side ? b : a, *nl = side ? &nb : &na;
            r ^= r << 13, r ^= r >> 7, r ^= r << 17;
            *nl = 1 + (uint32_t)(r % 12);
            uint32_t top = (uint32_t)(r >> 20) % 3 == 0 ? 60000 : (uint32_t)(r >> 20) % 3 == 1 ? 1000 : 30;
            uint32_t v = 0;
            for (uint32_t k = 0; k < *nl; k++) {
                r ^= r << 13, r ^= r >> 7, r ^= r << 17;
                v += 1 + (uint32_t)(r % (top / 12 + 1));
                l[k] = v;
            }
        }
        check(a, na, b, nb);
    }
    printf("random: %ld cases with up to 12 values per side up to 60000, %ld failures in total\n", cases - before, failures);
    return failures != 0;
}
