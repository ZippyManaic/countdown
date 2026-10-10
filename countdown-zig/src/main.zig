//! Generate a Countdown numbers round and work out whether it can be solved

const std = @import("std");
const solver = @import("solver.zig");

/// Name the ways of dealing a round, with nasty-cats using the large cards of the 2010 specials
const Mode = enum {
    standard,
    cats,
    nasty,

    /// Return the four large cards the mode deals from
    fn largeNumbers(mode: Mode) [4]u32 {
        return if (mode == .nasty) .{ 12, 37, 62, 87 } else .{ 25, 50, 75, 100 };
    }
};

/// Hold the mode and a fixed large count, or null to choose the count at random
const Args = struct { mode: Mode, large_count: ?usize };

const usage = "usage: countdown [standard|cats|nasty] [LARGE]\n";

/// Hold a random target and a pool of six numbers
const Round = struct { target: u32, pool: [6]u32 };

/// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
fn generateRound(rng: std.Random, mode: Mode, fixed_count: ?usize) Round {
    const target = rng.intRangeAtMost(u32, 100, 999);
    const large_count = fixed_count orelse if (mode == .standard) rng.intRangeAtMost(usize, 1, 2) else rng.intRangeAtMost(usize, 0, 4);

    // Hold two cards of each small number to match the game's deck
    var small: [20]u32 = undefined;
    for (&small, 0..) |*n, i| n.* = @intCast(i % 10 + 1);
    rng.shuffle(u32, &small);
    // Shuffle a copy since each large number appears only once in the game
    var large = mode.largeNumbers();
    rng.shuffle(u32, &large);

    var round: Round = .{ .target = target, .pool = undefined };
    @memcpy(round.pool[0 .. 6 - large_count], small[0 .. 6 - large_count]);
    @memcpy(round.pool[6 - large_count ..], large[0..large_count]);
    return round;
}

/// Return the mode and fixed large count from the arguments after the program name, or null when they are invalid
fn parseArgs(args: []const [:0]const u8) ?Args {
    if (args.len > 2) return null;
    if (args.len == 0) return .{ .mode = .standard, .large_count = null };
    const mode = std.meta.stringToEnum(Mode, args[0]) orelse return null;
    if (args.len == 1) return .{ .mode = mode, .large_count = null };
    // Accept only a single digit so that signs, spaces and trailing text are rejected
    if (args[1].len != 1 or !std.ascii.isDigit(args[1][0])) return null;
    const n: usize = args[1][0] - '0';
    const ok = if (mode == .standard) n == 1 or n == 2 else n <= 4;
    return if (ok) .{ .mode = mode, .large_count = n } else null;
}

pub fn main(init: std.process.Init) !u8 {
    const all_args = try init.minimal.args.toSlice(init.arena.allocator());
    const parsed = parseArgs(all_args[1..]) orelse {
        var stderr_writer: std.Io.File.Writer = .init(.stderr(), init.io, &.{});
        try stderr_writer.interface.writeAll(usage);
        return 2;
    };

    var seed: u64 = undefined;
    init.io.random(std.mem.asBytes(&seed));
    var prng: std.Random.DefaultPrng = .init(seed);
    const round = generateRound(prng.random(), parsed.mode, parsed.large_count);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    try stdout.print("Target: {d}\nPool:  ", .{round.target});
    for (round.pool) |n| try stdout.print(" {d}", .{n});
    try stdout.writeByte('\n');

    var expr_buffer: [128]u8 = undefined;
    const s = try solver.solve(std.heap.c_allocator, round.target, &round.pool, &expr_buffer);
    if (s.value == round.target) {
        try stdout.print("Solved: {s} = {d}\n", .{ s.expr, s.value });
        return 0;
    }
    const away = if (s.value > round.target) s.value - round.target else round.target - s.value;
    try stdout.print("No exact solution, closest is {s} = {d} ({d} away)\n", .{ s.expr, s.value, away });
    return 1;
}

test {
    _ = solver;
}

/// Return the large count of a dealt round after checking it follows the rules of its mode
fn checkRound(mode: Mode, round: Round) !usize {
    try std.testing.expect(round.target >= 100 and round.target <= 999);
    const cards = mode.largeNumbers();
    var large_seen: [4]bool = @splat(false);
    var counts: [11]u8 = @splat(0);
    var large: usize = 0;
    for (round.pool) |n| {
        if (n <= 10) {
            // Reject a small number after a large one since the pool lists small cards first
            try std.testing.expect(n >= 1 and large == 0);
            counts[n] += 1;
            try std.testing.expect(counts[n] <= 2);
            continue;
        }
        const k = std.mem.indexOfScalar(u32, &cards, n) orelse return error.NotLargeCard;
        try std.testing.expect(!large_seen[k]);
        large_seen[k] = true;
        large += 1;
    }
    return large;
}

test "deals valid pools in every mode" {
    var prng: std.Random.DefaultPrng = .init(std.testing.random_seed);
    for ([_]Mode{ .standard, .cats, .nasty }) |mode| {
        var seen: [5]bool = @splat(false);
        for (0..2000) |_| seen[try checkRound(mode, generateRound(prng.random(), mode, null))] = true;
        const want: [5]bool = if (mode == .standard) .{ false, true, true, false, false } else @splat(true);
        try std.testing.expectEqual(want, seen);
    }
}

test "deals a fixed large count" {
    var prng: std.Random.DefaultPrng = .init(std.testing.random_seed);
    for ([_]Mode{ .cats, .nasty }) |mode| {
        for (0..5) |k| try std.testing.expectEqual(k, try checkRound(mode, generateRound(prng.random(), mode, k)));
    }
}

test "parses arguments" {
    try std.testing.expectEqual(Args{ .mode = .standard, .large_count = null }, parseArgs(&.{}).?);
    try std.testing.expectEqual(Args{ .mode = .nasty, .large_count = 4 }, parseArgs(&.{ "nasty", "4" }).?);
    try std.testing.expectEqual(Args{ .mode = .cats, .large_count = 0 }, parseArgs(&.{ "cats", "0" }).?);
    try std.testing.expect(parseArgs(&.{ "standard", "3" }) == null);
    try std.testing.expect(parseArgs(&.{ "cats", "5" }) == null);
    try std.testing.expect(parseArgs(&.{"dogs"}) == null);
    try std.testing.expect(parseArgs(&.{ "cats", "1", "2" }) == null);
    try std.testing.expect(parseArgs(&.{ "cats", "x" }) == null);
}

test "solves cats rounds" {
    var buf: [128]u8 = undefined;
    const cases = [_]struct { target: u32, pool: [6]u32, value: u32, expr: []const u8 }{
        .{ .target = 999, .pool = .{ 10, 10, 25, 50, 75, 100 }, .value = 999, .expr = "(((75 + 25) * 100) - 10) / 10" },
        .{ .target = 100, .pool = .{ 1, 1, 2, 2, 3, 3 }, .value = 81, .expr = "(((2 + 1) * (2 + 1)) * 3) * 3" },
        .{ .target = 999, .pool = .{ 2, 3, 87, 62, 37, 12 }, .value = 999, .expr = "37 * ((87 / 3) - 2)" },
    };
    for (cases) |c| {
        const s = try solver.solve(std.testing.allocator, c.target, &c.pool, &buf);
        try std.testing.expectEqual(c.value, s.value);
        try std.testing.expectEqualStrings(c.expr, s.expr);
    }
}
