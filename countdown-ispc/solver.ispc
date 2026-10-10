// Solve a Countdown numbers round with the pair arithmetic spread across the gang's lanes

extern "C" void *uniform calloc(uniform uint64 count, uniform uint64 size);
extern "C" void *uniform realloc(void *uniform p, uniform uint64 size);
extern "C" void free(void *uniform p);
extern "C" void exit(uniform int status);

// Spell characters as codes since ISPC has no character literals
#define OP_ADD 43
#define OP_SUB 45
#define OP_MUL 42
#define OP_DIV 47
#define CH_OPEN 40
#define CH_CLOSE 41
#define CH_SPACE 32
#define CH_ZERO 48

// Mark a subset whose values are held only in its bitset
#define UNLISTED 0xffffffffu

// Give every bitset room past its end for the spare words that illegal results are sent to
#define SPARE_WORDS (4 * programCount)

// Radix sort a subset when its bitset has more than this many words per value
#define SPARSE 64

// Hold the working memory of one solve with every listed subset's sorted values back to back in one arena
struct State {
    uint32 target;
    uint32 full;
    // Keep each value's reciprocal beside it so division tests need no divide
    uniform uint32 *uniform values;
    uniform double *uniform inverses;
    uint64 top, cap;
    uint32 off[256], len[256];
    // Hold the largest value each subset can make which bounds the words of its bitset
    uint32 max[256];
    // Keep every subset's bitset so a search tests one bit instead of binary searching
    uniform uint64 *uniform bits[256];
    uniform uint64 *uniform blocks[10];
    // Hold where an unlisted sparse subset left its unsorted values and how many including spares or zero for none
    uint64 pend_off[256];
    uint32 pend_len[256];
    // Hold scratch space for radix sorting sparse subsets
    uniform uint32 *uniform scratch;
    uint64 scratch_cap;
};

// Pass a bitset through memory so the compiler cannot treat it as separate from the staging buffer and extract lanes one by one
struct Bitset {
    uniform uint64 *uniform words;
    uint32 count;
    // Append each new value here when the subset is sparse or leave it null to only mark bits
    uniform uint32 *uniform out;
    uint32 emitted;
};

// Describe the first way a subset makes a value as its split and the two operands taken from each half
struct Way {
    uint32 left;
    uint32 a;
    uint32 b;
    uint32 op;
};

// Stop the program when memory runs out since a solve cannot continue without it
static void fail()
{
    print("out of memory\n");
    exit(2);
}

// Make the arena hold need values plus a gang's worth of padding that vector loads may read past the end
static void reserve(uniform State *uniform s, uniform uint64 need)
{
    need += programCount;
    if (need <= s->cap)
        return;
    while (s->cap < need)
        s->cap = s->cap ? s->cap * 2 : 16384;
    s->values = (uniform uint32 * uniform) realloc(s->values, s->cap * sizeof(uniform uint32));
    s->inverses = (uniform double *uniform)realloc(s->inverses, s->cap * sizeof(uniform double));
    if (s->values == NULL || s->inverses == NULL)
        fail();
}

// Return how many words a subset's bitset needs to hold every value it can make
static inline uniform uint32 words_of(const uniform State *uniform s, uniform uint32 mask)
{
    return s->max[mask] / 64 + 1;
}

// Mark every legal value from each value of the shorter half with every value of the longer half
static void pairs(const uniform State *uniform s, uniform uint32 left, uniform uint32 right, const uniform Bitset *uniform set,
                  uniform uint32 buf[])
{
    uniform uint64 *uniform seen = set->words;
    // Loop over the shorter half one value at a time and spread the longer half across the lanes
    uniform uint32 short_mask = s->len[left] <= s->len[right] ? left : right;
    uniform uint32 long_mask = left ^ right ^ short_mask;
    const uniform uint32 *uniform shorts = s->values + s->off[short_mask];
    const uniform double *uniform short_inv = s->inverses + s->off[short_mask];
    const uniform uint32 *uniform longs = s->values + s->off[long_mask];
    const uniform double *uniform long_inv = s->inverses + s->off[long_mask];
    uniform uint32 ns = s->len[short_mask], nl = s->len[long_mask];
    // Send each illegal result to its own spare word past the end so they form no chain of updates to one word
    uint32 spare = (set->count + programIndex) * 64;
    for (uniform uint32 i = 0; i < ns; i++) {
        uniform uint32 a = shorts[i];
        uniform double ia = short_inv[i];
        for (uniform uint32 j0 = 0; j0 < nl; j0 += programCount) {
            uint32 j = j0 + programIndex;
            // Read past the end into the padding and send those lanes to spare words too
            bool live = j < nl;
            uint32 b = longs[j];
            double ib = long_inv[j];
            bool b_smaller = b <= a;
            uint32 x = b_smaller ? a : b, y = b_smaller ? b : a;
            double iy = b_smaller ? ib : ia;
            uint32 q = (uint32)(int32)round((double)(int32)x * iy);
            buf[programIndex] = live ? x + y : spare;
            // Skip a zero result since every intermediate value must be a positive integer
            buf[programCount + programIndex] = live && x != y ? x - y : spare + programCount * 64;
            // Skip multiplying and dividing by one as they never produce a new value
            buf[2 * programCount + programIndex] = live && y != 1 ? x * y : spare + 2 * programCount * 64;
            buf[3 * programCount + programIndex] = live && y != 1 && q * y == x ? q : spare + 3 * programCount * 64;
            // Set the bits one lane at a time since lanes can share a word
            for (uniform int k = 0; k < 4 * programCount; k++) {
                uniform uint32 v = buf[k];
                seen[v >> 6] |= (uniform uint64)1 << (v & 63);
            }
        }
    }
}

// Mark every legal value as pairs does and also append each new one to the subset's output
static void pairs_emit(const uniform State *uniform s, uniform uint32 left, uniform uint32 right, uniform Bitset *uniform set,
                       uniform uint32 buf[])
{
    uniform uint64 *uniform seen = set->words;
    uniform uint32 short_mask = s->len[left] <= s->len[right] ? left : right;
    uniform uint32 long_mask = left ^ right ^ short_mask;
    const uniform uint32 *uniform shorts = s->values + s->off[short_mask];
    const uniform double *uniform short_inv = s->inverses + s->off[short_mask];
    const uniform uint32 *uniform longs = s->values + s->off[long_mask];
    const uniform double *uniform long_inv = s->inverses + s->off[long_mask];
    uniform uint32 ns = s->len[short_mask], nl = s->len[long_mask];
    uint32 spare = (set->count + programIndex) * 64;
    uniform uint32 *uniform out = set->out;
    uniform uint32 emitted = set->emitted;
    for (uniform uint32 i = 0; i < ns; i++) {
        uniform uint32 a = shorts[i];
        uniform double ia = short_inv[i];
        for (uniform uint32 j0 = 0; j0 < nl; j0 += programCount) {
            uint32 j = j0 + programIndex;
            bool live = j < nl;
            uint32 b = longs[j];
            double ib = long_inv[j];
            bool b_smaller = b <= a;
            uint32 x = b_smaller ? a : b, y = b_smaller ? b : a;
            double iy = b_smaller ? ib : ia;
            uint32 q = (uint32)(int32)round((double)(int32)x * iy);
            buf[programIndex] = live ? x + y : spare;
            buf[programCount + programIndex] = live && x != y ? x - y : spare + programCount * 64;
            buf[2 * programCount + programIndex] = live && y != 1 ? x * y : spare + 2 * programCount * 64;
            buf[3 * programCount + programIndex] = live && y != 1 && q * y == x ? q : spare + 3 * programCount * 64;
            // Append each value advancing past it only if its bit was clear so duplicates cost no branch
            for (uniform int k = 0; k < 4 * programCount; k++) {
                uniform uint32 v = buf[k];
                uniform uint64 word = seen[v >> 6];
                seen[v >> 6] = word | (uniform uint64)1 << (v & 63);
                out[emitted] = v;
                emitted += (uniform uint32)(~word >> (v & 63) & 1);
            }
        }
    }
    set->emitted = emitted;
}

// Return how many pairs of values a subset's splits combine
static uniform uint64 pairs_of(const uniform State *uniform s, uniform uint32 mask)
{
    // Visit each split once by keeping the lowest number on the left since the order of halves does not change the count
    uniform uint32 low = mask & -mask;
    uniform uint32 rest = mask ^ low;
    uniform uint64 pair_count = 0;
    for (uniform uint32 sub = (rest - 1) & rest; sub != rest; sub = (sub - 1) & rest)
        pair_count += (uniform uint64)s->len[sub | low] * s->len[rest ^ sub];
    return pair_count;
}

// Mark every value a subset can make in its bitset appending each new one to out unless it is null and return how many were appended
static uniform uint32 mark(const uniform State *uniform s, uniform uint32 mask, uniform uint32 *uniform out)
{
    uniform Bitset set = {s->bits[mask], words_of(s, mask), out, 0};
    // Stage results in memory owned by the caller since staging them in registers makes the compiler extract lanes one by one
    uniform uint32 buf[4 * programCount];
    for (uniform uint32 left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        uniform uint32 right = mask ^ left;
        // Visit each split once rather than once per ordering
        if (left >= right)
            continue;
        if (out == NULL)
            pairs(s, left, right, &set, buf);
        else
            pairs_emit(s, left, right, &set, buf);
    }
    return set.emitted;
}

// Sort a sparse subset's n appended values at off in place by radix dropping the spare values past its largest and list them
static void list_sparse(uniform State *uniform s, uniform uint32 mask, uniform uint64 off, uniform uint32 n)
{
    if (n > s->scratch_cap) {
        free(s->scratch);
        s->scratch_cap = n;
        s->scratch = (uniform uint32 * uniform) calloc(n, sizeof(uniform uint32));
        if (s->scratch == NULL)
            fail();
    }
    uniform uint32 *uniform values = s->values + off;
    uniform uint32 *uniform scratch = s->scratch;
    uniform uint32 bound = s->max[mask];
    // Count the three 11-bit digits of every real value while moving them to the scratch space
    uniform uint32 counts[3][2048];
    foreach (d = 0 ... 2048) {
        counts[0][d] = 0;
        counts[1][d] = 0;
        counts[2][d] = 0;
    }
    uniform uint32 count = 0;
    for (uniform uint32 i = 0; i < n; i++) {
        uniform uint32 v = values[i];
        if (v > bound)
            continue;
        scratch[count++] = v;
        counts[0][v & 2047]++;
        counts[1][v >> 11 & 2047]++;
        counts[2][v >> 22]++;
    }
    // Scatter by each digit in turn ping-ponging so the third pass lands back in the arena
    uniform uint32 *uniform from = scratch, *uniform to = values;
    for (uniform int pass = 0; pass < 3; pass++) {
        uniform uint32 sum = 0;
        for (uniform int d = 0; d < 2048; d++) {
            uniform uint32 c = counts[pass][d];
            counts[pass][d] = sum;
            sum += c;
        }
        for (uniform uint32 i = 0; i < count; i++) {
            uniform uint32 v = from[i];
            to[counts[pass][v >> (11 * pass) & 2047]++] = v;
        }
        uniform uint32 *uniform t = from;
        from = to;
        to = t;
    }
    uniform double *uniform inv = s->inverses + off;
    foreach (i = 0 ... count)
        inv[i] = 1.0d / (double)(int32)values[i];
    s->off[mask] = (uniform uint32)off;
    s->len[mask] = count;
}

// Pack the positions of the set bits of each four-bit mask into bytes lowest first
static const uniform uint32 NIBBLE_LANES[16] = {0x0,     0x0,     0x1,     0x100,   0x2,     0x200,
                                                0x201,   0x20100, 0x3,     0x300,   0x301,   0x30100,
                                                0x302,   0x30200, 0x30201, 0x3020100};

// List a subset's values in order into the arena straight out of its bitset
static void list(uniform State *uniform s, uniform uint32 mask, uniform uint64 pair_count)
{
    const uniform uint64 *uniform seen = s->bits[mask];
    uniform uint32 words = words_of(s, mask);
    uniform uint64 bound = s->max[mask];
    uniform uint64 most = 4 * pair_count < bound ? 4 * pair_count : bound;
    // Reserve room for the busy word list after the values plus slack for the values written ahead of the count
    reserve(s, s->top + most + 8 + words + programCount);
    uniform uint32 *uniform out = s->values + s->top;
    uniform uint32 *uniform busy = out + most + 8;
    uniform uint32 nbusy = 0;
    // List the words holding values without branching and with every lane on so each gang goes out as one plain store
    unmasked {
        for (uniform uint32 w0 = 0; w0 < words; w0 += programCount) {
            uint32 w = w0 + programIndex;
            uniform uint32 m = packmask(seen[w] != 0 && w < words);
#if TARGET_WIDTH <= 8
            // Pack the busy lanes' positions into bytes and write a gang of word indices of which the first are real
            uniform uint64 lanes = NIBBLE_LANES[m & 15];
#if TARGET_WIDTH > 4
            lanes |= (uniform uint64)(NIBBLE_LANES[m >> 4] + 0x04040404) << (8 * popcnt((uniform int32)(m & 15)));
#endif
            busy[nbusy + programIndex] = w0 + (uint32)((lanes >> (8 * programIndex)) & 255);
#else
            // Write each nibble's busy word indices in turn since a wide gang's positions do not fit one word
            uniform uint32 at = nbusy;
            for (uniform int c = 0; c < programCount; c += 4) {
                uniform uint32 nib = (m >> c) & 15;
                uniform uint32 lanes = NIBBLE_LANES[nib];
                busy[at] = w0 + c + (lanes & 255);
                busy[at + 1] = w0 + c + (lanes >> 8 & 255);
                busy[at + 2] = w0 + c + (lanes >> 16 & 255);
                busy[at + 3] = w0 + c + (lanes >> 24);
                at += popcnt((uniform int32)nib);
            }
#endif
            nbusy += popcnt((uniform int32)m);
        }
    }
    uniform uint32 count = 0;
    for (uniform uint32 k = 0; k < nbusy; k++) {
        uniform uint32 word = busy[k];
        uniform uint64 bits = seen[word];
        uniform uint32 base = word * 64;
        uniform uint32 n = popcnt((uniform int64)bits);
        // Write four values whether or not they exist since most words hold fewer and the count moves on by the real number
        uniform uint32 *uniform at = out + count;
        at[0] = base + count_trailing_zeros(bits);
        bits &= bits - 1;
        at[1] = base + count_trailing_zeros(bits);
        bits &= bits - 1;
        at[2] = base + count_trailing_zeros(bits);
        bits &= bits - 1;
        at[3] = base + count_trailing_zeros(bits);
        bits &= bits - 1;
        if (n > 4) {
            at += 4;
            do {
                *at++ = base + count_trailing_zeros(bits);
                bits &= bits - 1;
            } while (bits);
        }
        count += n;
    }
    uniform double *uniform inv = s->inverses + s->top;
    foreach (i = 0 ... count)
        inv[i] = 1.0d / (double)(int32)out[i];
    s->off[mask] = (uniform uint32)s->top;
    s->len[mask] = count;
    s->top += count;
}

// List a subset left unlisted so its values can be scanned
static void list_unlisted(uniform State *uniform s, uniform uint32 mask)
{
    if (s->len[mask] != UNLISTED)
        return;
    if (s->pend_len[mask] != 0)
        list_sparse(s, mask, s->pend_off[mask], s->pend_len[mask]);
    else
        list(s, mask, pairs_of(s, mask));
}

// Return whether a subset makes value by testing its bit
static inline uniform bool contains(const uniform State *uniform s, uniform uint32 mask, uniform uint32 value)
{
    return value <= s->max[mask] && (s->bits[mask][value >> 6] >> (value & 63) & 1) != 0;
}

// Fill m and op with every number that combines with n under Countdown rules to make the target in operator order
static inline uniform int partners(uniform uint32 n, uniform uint32 target, uniform uint32 m[6], uniform uint32 op[6])
{
    uniform int count = 0;
    if (target > n) {
        m[count] = target - n;
        op[count++] = OP_ADD;
    }
    if (n > target) {
        m[count] = n - target;
        op[count++] = OP_SUB;
    }
    m[count] = n + target;
    op[count++] = OP_SUB;
    // Divide only when the quotient could be at least two since neither operand may be one
    if (n != 1 && 2 * n <= target && target % n == 0) {
        m[count] = target / n;
        op[count++] = OP_MUL;
    }
    if (n >= 2 * target && n % target == 0) {
        m[count] = n / target;
        op[count++] = OP_DIV;
    }
    // Skip a product too large for any subset to make
    if (n != 1 && (uniform uint64)n * target <= 0xffffffffu) {
        m[count] = n * target;
        op[count++] = OP_DIV;
    }
    return count;
}

// Find the first way building would make value from a subset by scanning one half and testing partners in the other
static uniform bool find(const uniform State *uniform s, uniform uint32 mask, uniform uint32 value, uniform Way &way)
{
    for (uniform uint32 left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        uniform uint32 right = mask ^ left;
        // Visit splits in the same order as building so the same origin wins
        if (left >= right)
            continue;
        // Scan the shorter half which is always the listed one since an unlisted half counts as longest
        uniform uint32 nl = s->len[left], nr = s->len[right];
        // Keep the lowest pair as building would since partners come in operator order
        uniform uint32 best_a = 0xffffffffu, best_b = 0xffffffffu, best_op = 0;
        uniform uint32 m[6], op[6];
        if (nl <= nr) {
            const uniform uint32 *uniform lefts = s->values + s->off[left];
            // Take the first left value with any partner on the right since left values ascend
            for (uniform uint32 i = 0; i < nl && best_op == 0; i++) {
                uniform int count = partners(lefts[i], value, m, op);
                for (uniform int k = 0; k < count; k++) {
                    if (m[k] < best_b && contains(s, right, m[k])) {
                        best_a = lefts[i];
                        best_b = m[k];
                        best_op = op[k];
                    }
                }
            }
        } else {
            const uniform uint32 *uniform rights = s->values + s->off[right];
            for (uniform uint32 j = 0; j < nr; j++) {
                uniform int count = partners(rights[j], value, m, op);
                for (uniform int k = 0; k < count; k++) {
                    if (m[k] < best_a && contains(s, left, m[k])) {
                        best_a = m[k];
                        best_b = rights[j];
                        best_op = op[k];
                    }
                }
            }
        }
        if (best_op) {
            way.left = left;
            way.a = best_a;
            way.b = best_b;
            way.op = best_op;
            return true;
        }
    }
    return false;
}

// Write n in decimal and return the new end
static uniform int8 *uniform put_uint(uniform int8 *uniform out, uniform uint32 n)
{
    uniform int8 digits[10];
    uniform int k = 0;
    do {
        digits[k++] = CH_ZERO + n % 10;
        n /= 10;
    } while (n);
    while (k)
        *out++ = digits[--k];
    return out;
}

// Write the expression for a subset's first way of making a value and return the new end
static uniform int8 *uniform render(const uniform State *uniform s, uniform uint32 mask, const uniform Way &way,
                                    uniform int8 *uniform out, uniform bool bracket);

// Write the expression making value from a subset by finding its first way and return the new end
static uniform int8 *uniform render_value(const uniform State *uniform s, uniform uint32 mask, uniform uint32 value,
                                          uniform int8 *uniform out)
{
    if ((mask & (mask - 1)) == 0)
        return put_uint(out, value);
    uniform Way way;
    find(s, mask, value, way);
    return render(s, mask, way, out, true);
}

static uniform int8 *uniform render(const uniform State *uniform s, uniform uint32 mask, const uniform Way &way,
                                    uniform int8 *uniform out, uniform bool bracket)
{
    uniform uint32 right = mask ^ way.left;
    // Write the larger operand first and the left half first when they are equal
    uniform bool a_larger = way.a >= way.b;
    if (bracket)
        *out++ = CH_OPEN;
    out = render_value(s, a_larger ? way.left : right, a_larger ? way.a : way.b, out);
    *out++ = CH_SPACE;
    *out++ = way.op;
    *out++ = CH_SPACE;
    out = render_value(s, a_larger ? right : way.left, a_larger ? way.b : way.a, out);
    if (bracket)
        *out++ = CH_CLOSE;
    return out;
}

static inline uniform uint32 distance(uniform uint32 value, uniform uint32 target)
{
    return value > target ? value - target : target - value;
}

// Return the distance from the target above the value for ordering candidates by both at once
static inline uint64 nearness(uint32 v, uniform uint32 target)
{
    return ((uint64)(v > target ? v - target : target - v) << 32) | v;
}

// Return the nearest value the whole pool makes packed as distance above value without storing any of them
static uniform uint64 whole_nearest(const uniform State *uniform s)
{
    uniform uint32 full = s->full, target = s->target;
    // Keep each lane's minimum since the closest and lowest value wins whatever order it is found in
    uint64 best = 0xffffffffffffffffull;
    for (uniform uint32 left = (full - 1) & full; left; left = (left - 1) & full) {
        uniform uint32 right = full ^ left;
        if (left >= right)
            continue;
        uniform uint32 short_mask = s->len[left] <= s->len[right] ? left : right;
        uniform uint32 long_mask = left ^ right ^ short_mask;
        const uniform uint32 *uniform shorts = s->values + s->off[short_mask];
        const uniform double *uniform short_inv = s->inverses + s->off[short_mask];
        const uniform uint32 *uniform longs = s->values + s->off[long_mask];
        const uniform double *uniform long_inv = s->inverses + s->off[long_mask];
        uniform uint32 ns = s->len[short_mask], nl = s->len[long_mask];
        for (uniform uint32 i = 0; i < ns; i++) {
            uniform uint32 a = shorts[i];
            uniform double ia = short_inv[i];
            for (uniform uint32 j0 = 0; j0 < nl; j0 += programCount) {
                uint32 j = j0 + programIndex;
                uint32 b = longs[j];
                double ib = long_inv[j];
                bool b_smaller = b <= a;
                uint32 x = b_smaller ? a : b, y = b_smaller ? b : a;
                double iy = b_smaller ? ib : ia;
                uint32 q = (uint32)(int32)round((double)(int32)x * iy);
                uint64 key = nearness(x + y, target);
                uint64 k = nearness(x - y, target);
                key = x != y && k < key ? k : key;
                k = nearness(x * y, target);
                key = y != 1 && k < key ? k : key;
                k = nearness(q, target);
                key = y != 1 && q * y == x && k < key ? k : key;
                best = j < nl && key < best ? key : best;
            }
        }
    }
    return reduce_min(best);
}

export uniform uint32 solve(uniform uint32 target, const uniform uint32 pool[], uniform uint32 n,
                            uniform int8 out[])
{
    uniform State *uniform s = (uniform State * uniform) calloc(1, sizeof(uniform State));
    if (s == NULL)
        fail();
    s->target = target;
    s->full = (1u << n) - 1;

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    for (uniform uint32 mask = 1; mask <= s->full; mask++) {
        if ((mask & (mask - 1)) == 0) {
            s->max[mask] = pool[count_trailing_zeros((uniform int32)mask)];
        } else {
            // Visit each split once by keeping the lowest number on the left
            uniform uint32 low = mask & -mask;
            uniform uint32 rest = mask ^ low;
            uniform uint32 sub = rest;
            do {
                sub = (sub - 1) & rest;
                uniform uint64 a = s->max[sub | low], b = s->max[rest ^ sub];
                uniform uint64 m = a * b > a + b ? a * b : a + b;
                s->max[mask] = m > s->max[mask] ? (uniform uint32)m : s->max[mask];
            } while (sub != 0);
        }
    }

    // Store each pool number as a one-number subset with a bitset of its own
    reserve(s, 0);
    uniform uint64 single_words = 0;
    for (uniform uint32 i = 0; i < n; i++)
        single_words += words_of(s, 1u << i);
    uniform uint64 *uniform singles = (uniform uint64 * uniform) calloc(single_words, sizeof(uniform uint64));
    if (singles == NULL)
        fail();
    s->blocks[1] = singles;
    uniform int hit_mask = -1;
    for (uniform uint32 i = 0; i < n; i++) {
        s->values[i] = pool[i];
        s->inverses[i] = 1.0d / (double)(int32)pool[i];
        s->off[1u << i] = i;
        s->len[1u << i] = 1;
        s->bits[1u << i] = singles;
        singles[pool[i] >> 6] |= (uniform uint64)1 << (pool[i] & 63);
        singles += words_of(s, 1u << i);
        if (hit_mask < 0 && pool[i] == target)
            hit_mask = 1u << i;
    }
    s->top = n;

    // List subsets by size then mask so the loops below need no unpredictable size test
    uniform uint8 order[256];
    uniform uint32 first[10] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    for (uniform uint32 mask = 1; mask <= s->full; mask++)
        first[popcnt((uniform int32)mask) + 1]++;
    for (uniform uint32 size = 1; size <= n + 1; size++)
        first[size] += first[size - 1];
    uniform uint32 fill[10];
    for (uniform uint32 size = 0; size < 10; size++)
        fill[size] = first[size];
    for (uniform uint32 mask = 1; mask <= s->full; mask++)
        order[fill[popcnt((uniform int32)mask)]++] = mask;

    // Work through subsets smallest first stopping at the first size that hits the target
    uniform Way hit;
    for (uniform uint32 size = 2; size <= n && hit_mask < 0; size++) {
        // Keep the lowest matching subset of this size to break ties the same way every run
        for (uniform uint32 k = first[size]; k < first[size + 1] && hit_mask < 0; k++) {
            if (find(s, order[k], target, hit))
                hit_mask = order[k];
        }
        // Skip building the whole pool's values since no larger subset is made from them
        if (hit_mask >= 0 || size == n)
            break;
        // List the size below first if it was left unlisted since building this size scans its values
        if (size == n - 1 && n >= 5) {
            for (uniform uint32 k = first[size - 1]; k < first[size]; k++)
                list_unlisted(s, order[k]);
        }
        // Give each subset of this size its own bitset in one block for the size
        uniform uint64 total = 0;
        for (uniform uint32 k = first[size]; k < first[size + 1]; k++)
            total += words_of(s, order[k]) + SPARE_WORDS;
        uniform uint64 *uniform block = (uniform uint64 * uniform) calloc(total, sizeof(uniform uint64));
        if (block == NULL)
            fail();
        s->blocks[size] = block;
        // Leave the two largest sizes unlisted when every split that searches them scans a smaller listed half
        uniform bool unlisted = size == n - 1 || (size == n - 2 && n >= 5);
        for (uniform uint32 k = first[size]; k < first[size + 1]; k++) {
            uniform uint32 mask = order[k];
            s->bits[mask] = block;
            block += words_of(s, mask) + SPARE_WORDS;
            uniform uint64 pair_count = pairs_of(s, mask);
            uniform uint64 most = 4 * pair_count < s->max[mask] ? 4 * pair_count : s->max[mask];
            if (words_of(s, mask) > SPARSE * most) {
                // Append the values of a subset sure to be sparse so listing it costs its values rather than its range
                reserve(s, s->top + most + SPARE_WORDS + 1);
                uniform uint32 emitted = mark(s, mask, s->values + s->top);
                if (unlisted) {
                    s->pend_off[mask] = s->top;
                    s->pend_len[mask] = emitted;
                    s->len[mask] = UNLISTED;
                } else {
                    list_sparse(s, mask, s->top, emitted);
                }
                s->top += emitted;
            } else {
                mark(s, mask, NULL);
                if (unlisted)
                    s->len[mask] = UNLISTED;
                else
                    list(s, mask, pair_count);
            }
        }
    }

    uniform uint32 best_mask = 1, best_value = pool[0];
    if (hit_mask >= 0) {
        best_mask = hit_mask;
        best_value = target;
    } else if (n > 1) {
        // List the unlisted subsets now since the closest value may be any of their values
        for (uniform uint32 mask = 1; mask < s->full; mask++)
            list_unlisted(s, mask);
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        uniform uint32 best_distance = 0xffffffffu;
        uniform int best_used = 99;
        for (uniform uint32 mask = 1; mask < s->full; mask++) {
            uniform int used = popcnt((uniform int32)mask);
            const uniform uint32 *uniform values = s->values + s->off[mask];
            for (uniform uint32 i = 0; i < s->len[mask]; i++) {
                uniform uint32 d = distance(values[i], target);
                if (d < best_distance || (d == best_distance && used < best_used)) {
                    best_mask = mask;
                    best_value = values[i];
                    best_distance = d;
                    best_used = used;
                }
            }
        }
        // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        uniform uint64 whole = whole_nearest(s);
        if ((whole >> 32) < best_distance) {
            best_mask = s->full;
            best_value = (uniform uint32)whole;
        }
    }

    // Render without outer brackets which matches stripping them from the bracketed form
    uniform int8 *uniform end;
    if ((best_mask & (best_mask - 1)) == 0) {
        end = put_uint(out, best_value);
    } else {
        // Reuse the search's way for an exact hit and search again for the closest value otherwise
        if (best_mask != hit_mask)
            find(s, best_mask, best_value, hit);
        end = render(s, best_mask, hit, out, false);
    }
    *end = 0;
    free(s->values);
    free(s->inverses);
    free(s->scratch);
    for (uniform int size = 0; size < 10; size++)
        free(s->blocks[size]);
    free(s);
    return best_value;
}
