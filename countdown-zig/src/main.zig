//! Generate a Countdown numbers round and work out whether it can be solved

const std = @import("std");
const solver = @import("solver.zig");

const large_numbers = [_]u32{ 25, 50, 75, 100 };

/// Hold a random target and a pool of six numbers
const Round = struct { target: u32, pool: [6]u32 };

/// Return a random target and a pool of six numbers with either one or two large numbers
fn generateRound(rng: std.Random) Round {
    const target = rng.intRangeAtMost(u32, 100, 999);
    const large_count = rng.intRangeAtMost(usize, 1, 2);

    // Hold two cards of each small number to match the game's deck
    var small: [20]u32 = undefined;
    for (&small, 0..) |*n, i| n.* = @intCast(i % 10 + 1);
    rng.shuffle(u32, &small);
    // Shuffle a copy since each large number appears only once in the game
    var large = large_numbers;
    rng.shuffle(u32, &large);

    var round: Round = .{ .target = target, .pool = undefined };
    @memcpy(round.pool[0 .. 6 - large_count], small[0 .. 6 - large_count]);
    @memcpy(round.pool[6 - large_count ..], large[0..large_count]);
    return round;
}

pub fn main(init: std.process.Init) !u8 {
    var seed: u64 = undefined;
    init.io.random(std.mem.asBytes(&seed));
    var prng: std.Random.DefaultPrng = .init(seed);
    const round = generateRound(prng.random());

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

test "deals a valid pool" {
    var prng: std.Random.DefaultPrng = .init(std.testing.random_seed);
    for (0..1000) |_| {
        const round = generateRound(prng.random());
        try std.testing.expect(round.target >= 100 and round.target <= 999);
        var large: usize = 0;
        var counts: [11]u8 = @splat(0);
        for (round.pool) |n| {
            if (n > 10) large += 1 else counts[n] += 1;
        }
        try std.testing.expect(large == 1 or large == 2);
        for (counts) |c| try std.testing.expect(c <= 2);
    }
}
