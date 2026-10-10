//! Work out the simplest Countdown expression that hits a target or gets closest to it

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
const rank_min = 16;

/// Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
const Entry = extern struct {
    // Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
    head: u64,
    // Pack the larger operand in the low half and the smaller in the high half
    operands: u64,

    fn value(e: Entry) u32 {
        return @truncate(e.head);
    }
    fn op(e: Entry) u8 {
        return @truncate(e.head >> 32);
    }
    fn largerMask(e: Entry) u8 {
        return @truncate(e.head >> 40);
    }
    fn smallerMask(e: Entry) u8 {
        return @truncate(e.head >> 48);
    }
    fn larger(e: Entry) u32 {
        return @truncate(e.operands);
    }
    fn smaller(e: Entry) u32 {
        return @truncate(e.operands >> 32);
    }
};

/// Return the operator and masks of an entry shifted above its value
fn template(op: u8, larger_mask: usize, smaller_mask: usize) u64 {
    return @as(u64, op | larger_mask << 8 | smaller_mask << 16) << 32;
}

/// Return x divided by y rounded to the nearest integer using the reciprocal of y
inline fn quotient(x: u32, inv: f64) u32 {
    const q = @as(f64, @floatFromInt(x)) * inv;
    // Round with one instruction since @round adds a separate rounding step
    if (builtin.cpu.arch == .x86_64) {
        return @bitCast(asm ("cvtsd2si %[q], %[r]"
            : [r] "=r" (-> i32),
            : [q] "x" (q),
        ));
    }
    return @intFromFloat(@round(q));
}

/// Hold the working memory of one solve
const State = struct {
    gpa: Allocator,
    target: u32,
    full: usize,
    // Keep every subset's sorted values back to back in one arena
    arena: std.ArrayList(Entry) = .empty,
    off: [256]u32 = @splat(0),
    len: [256]u32 = @splat(0),
    // Hold the largest value each subset can make which bounds the bitset words it touches
    max: [256]u32 = @splat(0),
    // Hold one bit per value seen in the subset being built
    seen: []u64 = &.{},
    // Collect a subset's new values here before they are sorted into the arena
    tmp: std.ArrayList(Entry) = .empty,
    // Hold the count of values below each bitset word for ranking
    rank: []u32 = &.{},
    // Hold the right half's values with their reciprocals for the split being built
    right_values: std.ArrayList(u32) = .empty,
    right_inv: std.ArrayList(f64) = .empty,

    fn values(s: *const State, mask: usize) []const Entry {
        return s.arena.items[s.off[mask]..][0..s.len[mask]];
    }

    fn deinit(s: *State) void {
        s.arena.deinit(s.gpa);
        s.tmp.deinit(s.gpa);
        s.gpa.free(s.seen);
        s.gpa.free(s.rank);
        s.right_values.deinit(s.gpa);
        s.right_inv.deinit(s.gpa);
    }

    /// Make the bitset and its ranks cover every value up to largest
    fn reserveSeen(s: *State, largest: u32) !void {
        const words = largest / 64 + 1;
        if (words <= s.seen.len) return;
        // Replace rather than copy since building leaves the bitset clear
        s.gpa.free(s.seen);
        s.gpa.free(s.rank);
        s.seen = &.{};
        s.rank = &.{};
        s.seen = try s.gpa.alloc(u64, words);
        @memset(s.seen, 0);
        s.rank = try s.gpa.alloc(u32, words);
    }

    /// Make room for the values and reciprocals of the largest subset built so far
    fn reserveRights(s: *State) !void {
        var biggest: usize = 0;
        for (s.len[1 .. s.full + 1]) |n| biggest = @max(biggest, n);
        try s.right_values.resize(s.gpa, biggest);
        try s.right_inv.resize(s.gpa, biggest);
    }
};

/// Append values advancing past each only if the bitset shows it is new so duplicates cost no mispredicted branch
const Emit = struct {
    seen: [*]u64,
    out: [*]Entry,

    inline fn act(self: *Emit, v: u32, tmpl: u64, operands: u64) void {
        const word = self.seen[v >> 6];
        self.seen[v >> 6] = word | @as(u64, 1) << @truncate(v);
        self.out[0] = .{ .head = tmpl | v, .operands = operands };
        self.out += @as(usize, @truncate(~word >> @truncate(v) & 1));
    }
};

/// Keep the whole pool's value closest to the target preferring the lower value on equal distance
const Check = struct {
    target: u32,
    distance: u32 = std.math.maxInt(u32),
    best: Entry = .{ .head = std.math.maxInt(u32), .operands = 0 },

    inline fn act(self: *Check, v: u32, tmpl: u64, operands: u64) void {
        const d = distance(v, self.target);
        if (v != 0 and (d < self.distance or (d == self.distance and v < self.best.value()))) {
            self.distance = d;
            self.best = .{ .head = tmpl | v, .operands = operands };
        }
    }
};

/// Pass every legal value from x and y under Countdown rules to act where x is at least y and inv is 1/y
inline fn ops(context: anytype, x: u32, y: u32, inv: f64, t: *const [4]u64) void {
    const operands = x | @as(u64, y) << 32;
    context.act(x + y, t[0], operands);
    // Skip a zero result since every intermediate value must be a positive integer
    if (x != y) context.act(x - y, t[1], operands);
    // Skip multiplying and dividing by one as they never produce a new value
    if (y != 1) {
        context.act(x * y, t[2], operands);
        // Emit zero for an inexact division since bit 0 stays set so it is dropped
        const q = quotient(x, inv);
        context.act(if (q *% y == x) q else 0, t[3], operands);
    }
}

/// Pass every legal combination of each left value with each right value to act
inline fn pairs(s: *State, left: usize, right: usize, context: anytype) void {
    const tl = [4]u64{ template('+', left, right), template('-', left, right), template('*', left, right), template('/', left, right) };
    const tr = [4]u64{ template('+', right, left), template('-', right, left), template('*', right, left), template('/', right, left) };
    const rights = s.values(right);
    const rv = s.right_values.items[0..rights.len];
    const ri = s.right_inv.items[0..rights.len];
    // Invert each right value once per split rather than once per pair
    for (rights, rv, ri) |e, *v, *inv| {
        v.* = e.value();
        inv.* = 1.0 / @as(f64, @floatFromInt(v.*));
    }
    for (s.values(left)) |e| {
        const a = e.value();
        var j: usize = 0;
        // Pair with right values up to a first where a is the larger and ties go left
        while (j < rv.len and rv[j] <= a) : (j += 1) ops(context, a, rv[j], ri[j], &tl);
        // Pair with the remaining larger right values where a is the smaller
        const ia = 1.0 / @as(f64, @floatFromInt(a));
        while (j < rv.len) : (j += 1) ops(context, rv[j], a, ia, &tr);
    }
}

/// Return the index of value among sorted entries or null when it is absent
inline fn lookup(entries: []const Entry, value: u32) ?usize {
    // Skip the search when the value lies outside the subset's range
    if (entries.len == 0 or value < entries[0].value() or value > entries[entries.len - 1].value()) return null;
    // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
    var base: usize = 0;
    var n = entries.len;
    while (n > 1) {
        const half = n / 2;
        if (entries[base + half].value() <= value) {
            @branchHint(.unpredictable);
            base += half;
        }
        n -= half;
    }
    return if (entries[base].value() == value) base else null;
}

/// Pair a number with the operator that combines it with another to make the target
const Partner = struct { value: u32, op: u8 };

/// Return every number that combines with n under Countdown rules to make the target in operator order
inline fn partners(n: u32, target: u32, buf: *[6]Partner) []const Partner {
    var count: usize = 0;
    if (target > n) {
        buf[count] = .{ .value = target - n, .op = '+' };
        count += 1;
    }
    if (n > target) {
        buf[count] = .{ .value = n - target, .op = '-' };
        count += 1;
    }
    buf[count] = .{ .value = n + target, .op = '-' };
    count += 1;
    // Divide only when the quotient could be at least two since neither operand may be one
    if (n != 1 and 2 * n <= target and target % n == 0) {
        buf[count] = .{ .value = target / n, .op = '*' };
        count += 1;
    }
    if (n >= 2 * target and n % target == 0) {
        buf[count] = .{ .value = n / target, .op = '/' };
        count += 1;
    }
    // Skip a product too large for any subset to make
    if (n != 1 and @as(u64, n) * target <= std.math.maxInt(u32)) {
        buf[count] = .{ .value = n * target, .op = '/' };
        count += 1;
    }
    return buf[0..count];
}

/// Return how the target is first made from a subset without building all of its values
fn findExact(s: *const State, mask: usize) ?Entry {
    var buf: [6]Partner = undefined;
    var left = (mask - 1) & mask;
    while (left != 0) : (left = (left - 1) & mask) {
        const right = mask ^ left;
        // Visit splits in the same order as building so the same origin wins
        if (left >= right) continue;
        const lefts = s.values(left);
        const rights = s.values(right);
        // Keep the lowest pair as building would since partners come in operator order
        var best_a: u32 = std.math.maxInt(u32);
        var best_b: u32 = std.math.maxInt(u32);
        var best_op: u8 = 0;
        if (lefts.len <= rights.len) {
            // Take the first left value with any partner on the right since left values ascend
            for (lefts) |e| {
                for (partners(e.value(), s.target, &buf)) |p| {
                    if (p.value < best_b and lookup(rights, p.value) != null) {
                        best_a = e.value();
                        best_b = p.value;
                        best_op = p.op;
                    }
                }
                if (best_op != 0) break;
            }
        } else {
            for (rights) |e| {
                for (partners(e.value(), s.target, &buf)) |p| {
                    if (p.value < best_a and lookup(lefts, p.value) != null) {
                        best_a = p.value;
                        best_b = e.value();
                        best_op = p.op;
                    }
                }
            }
        }
        if (best_op != 0) {
            return if (best_a >= best_b)
                .{ .head = template(best_op, left, right) | s.target, .operands = best_a | @as(u64, best_b) << 32 }
            else
                .{ .head = template(best_op, right, left) | s.target, .operands = best_b | @as(u64, best_a) << 32 };
        }
    }
    return null;
}

/// Grow a list to at least need items by doubling so repeated small reservations stay rare
fn reserve(comptime T: type, list: *std.ArrayList(T), gpa: Allocator, need: usize) !void {
    if (need <= list.capacity) return;
    var cap = @max(list.capacity, 1024);
    while (cap < need) cap *= 2;
    try list.ensureTotalCapacityPrecise(gpa, cap);
}

/// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
fn build(s: *State, mask: usize) !void {
    const seen = s.seen;
    var count: usize = 0;
    // Mark zero as seen so inexact divisions never become entries
    seen[0] |= 1;
    var left = (mask - 1) & mask;
    while (left != 0) : (left = (left - 1) & mask) {
        const right = mask ^ left;
        // Visit each split once rather than once per ordering
        if (left >= right) continue;
        // Reserve room for every pair's results plus the one slot each store may write past the end
        const pair_count = 4 * @as(usize, s.len[left]) * s.len[right];
        // Count the values so far as items so growing the list keeps them
        s.tmp.items.len = count;
        try reserve(Entry, &s.tmp, s.gpa, count + @min(pair_count, s.max[mask]) + 1);
        var emit: Emit = .{ .seen = seen.ptr, .out = s.tmp.items.ptr + count };
        pairs(s, left, right, &emit);
        count = emit.out - s.tmp.items.ptr;
    }
    seen[0] &= ~@as(u64, 1);

    s.tmp.items.len = count;
    const candidates = s.tmp.items;
    const top = s.arena.items.len;
    try reserve(Entry, &s.arena, s.gpa, top + count);
    s.arena.items.len = top + count;
    const sorted = s.arena.items[top..];
    if (count < rank_min) {
        // Clear only the words this subset touched and insertion sort the few values
        for (candidates, 0..) |e, i| {
            seen[e.value() >> 6] = 0;
            var k = i;
            while (k > 0 and sorted[k - 1].value() > e.value()) : (k -= 1) sorted[k] = sorted[k - 1];
            sorted[k] = e;
        }
    } else {
        // Place each value at its rank in the bitset which needs no comparisons
        const words = s.max[mask] / 64 + 1;
        var below: u32 = 0;
        for (seen[0..words], s.rank[0..words]) |word, *r| {
            r.* = below;
            below += @popCount(word);
        }
        for (candidates) |e| {
            const v = e.value();
            const lower = seen[v >> 6] & ((@as(u64, 1) << @truncate(v)) - 1);
            sorted[s.rank[v >> 6] + @popCount(lower)] = e;
        }
        @memset(seen[0..words], 0);
    }
    s.off[mask] = @intCast(top);
    s.len[mask] = @intCast(count);
}

fn distance(value: u32, target: u32) u32 {
    return if (value > target) value - target else target - value;
}

/// Write the expression for an entry following its origins back to the pool with brackets when asked
fn render(s: *const State, e: Entry, w: *std.Io.Writer, bracket: bool) std.Io.Writer.Error!void {
    if (e.op() == 0) return w.print("{d}", .{e.value()});
    const larger = s.values(e.largerMask());
    const smaller = s.values(e.smallerMask());
    if (bracket) try w.writeByte('(');
    try render(s, larger[lookup(larger, e.larger()).?], w, true);
    try w.print(" {c} ", .{e.op()});
    try render(s, smaller[lookup(smaller, e.smaller()).?], w, true);
    if (bracket) try w.writeByte(')');
}

/// Hold the answer with its expression written into the caller's buffer
pub const Solution = struct { value: u32, expr: []const u8 };

/// Return the simplest expression that hits the target or gets closest to it with its value
pub fn solve(gpa: Allocator, target: u32, pool: []const u32, out: []u8) !Solution {
    var s: State = .{ .gpa = gpa, .target = target, .full = (@as(usize, 1) << @intCast(pool.len)) - 1 };
    defer s.deinit();

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    var largest: [10]u32 = @splat(0);
    for (1..s.full + 1) |mask| {
        if (mask & (mask - 1) == 0) {
            s.max[mask] = pool[@ctz(mask)];
        } else {
            var left = (mask - 1) & mask;
            while (left != 0) : (left = (left - 1) & mask) {
                const a: u64 = s.max[left];
                const b: u64 = s.max[mask ^ left];
                s.max[mask] = @intCast(@max(s.max[mask], a * b, a + b));
            }
        }
        // Track the largest value of each size so the bitset only grows when bigger subsets are built
        largest[@popCount(mask)] = @max(largest[@popCount(mask)], s.max[mask]);
    }

    // Store each pool number as a one-number subset
    var best: ?Entry = null;
    for (pool, 0..) |n, i| {
        try s.arena.append(gpa, .{ .head = n, .operands = 0 });
        s.off[@as(usize, 1) << @intCast(i)] = @intCast(i);
        s.len[@as(usize, 1) << @intCast(i)] = 1;
        if (best == null and n == target) best = s.arena.items[i];
    }

    // List subsets by size then mask so the loops below need no unpredictable size test
    var order: [256]u8 = undefined;
    var first: [10]usize = @splat(0);
    for (1..s.full + 1) |mask| first[@popCount(mask) + 1] += 1;
    for (1..pool.len + 2) |size| first[size] += first[size - 1];
    var fill = first;
    for (1..s.full + 1) |mask| {
        order[fill[@popCount(mask)]] = @intCast(mask);
        fill[@popCount(mask)] += 1;
    }

    // Work through subsets smallest first stopping at the first size that hits the target
    var size: usize = 2;
    while (size <= pool.len and best == null) : (size += 1) {
        // Keep the lowest matching subset of this size to break ties the same way every run
        for (order[first[size]..first[size + 1]]) |mask| {
            best = findExact(&s, mask);
            if (best != null) break;
        }
        // Skip building the whole pool's values since no larger subset is made from them
        if (best != null or size == pool.len) break;
        try s.reserveRights();
        try s.reserveSeen(largest[size]);
        for (order[first[size]..first[size + 1]]) |mask| try build(&s, mask);
    }

    if (best == null) {
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        var best_distance: u32 = std.math.maxInt(u32);
        var best_used: usize = 99;
        for (1..s.full) |mask| {
            const used = @popCount(mask);
            for (s.values(mask)) |e| {
                const d = distance(e.value(), target);
                if (d < best_distance or (d == best_distance and used < best_used)) {
                    best = e;
                    best_distance = d;
                    best_used = used;
                }
            }
        }
        // Check the whole pool's values as they are made since no larger subset is built from them
        if (pool.len > 1) {
            try s.reserveRights();
            var check: Check = .{ .target = target };
            var left = (s.full - 1) & s.full;
            while (left != 0) : (left = (left - 1) & s.full) {
                if (left < s.full ^ left) pairs(&s, left, s.full ^ left, &check);
            }
            // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            if (check.distance < best_distance) best = check.best;
        }
    }

    // Render without outer brackets which matches stripping them from the bracketed form
    var w: std.Io.Writer = .fixed(out);
    try render(&s, best.?, &w, false);
    return .{ .value = best.?.value(), .expr = w.buffered() };
}

test "finds simplest solution" {
    var buf: [128]u8 = undefined;
    const s = try solve(std.testing.allocator, 125, &.{ 1, 5, 7, 3, 75, 50 }, &buf);
    try std.testing.expectEqual(125, s.value);
    try std.testing.expectEqualStrings("75 + 50", s.expr);
    try std.testing.expectEqual(552, (try solve(std.testing.allocator, 552, &.{ 8, 4, 2, 5, 100, 25 }, &buf)).value);
}

test "reports closest when unsolvable" {
    var buf: [128]u8 = undefined;
    const s = try solve(std.testing.allocator, 974, &.{ 8, 8, 6, 8, 25, 100 }, &buf);
    try std.testing.expectEqual(1, distance(s.value, 974));
}
