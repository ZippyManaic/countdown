const std = @import("std");
const solver = @import("solver.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const io = init.io;
    const data = try std.Io.Dir.cwd().readFileAlloc(io, args[1], gpa, .unlimited);
    var rounds: std.ArrayList([7]u32) = .empty;
    var lines = std.mem.tokenizeScalar(u8, data, '\n');
    while (lines.next()) |line| {
        var r: [7]u32 = undefined;
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        for (&r) |*n| n.* = try std.fmt.parseInt(u32, it.next().?, 10);
        try rounds.append(gpa, r);
    }
    const values = try gpa.alloc(u32, rounds.items.len);
    const exprs = try gpa.alloc([128]u8, rounds.items.len);
    const lens = try gpa.alloc(usize, rounds.items.len);
    const reps: usize = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 1;
    const alloc = if (@import("builtin").link_libc) std.heap.c_allocator else gpa;
    const start = std.Io.Clock.awake.now(io);
    for (0..reps) |_| for (rounds.items, 0..) |r, i| {
        const s = try solver.solve(alloc, r[0], r[1..], &exprs[i]);
        values[i] = s.value;
        // Move the expression to the start of its buffer since solve may strip a leading bracket
        std.mem.copyForwards(u8, &exprs[i], s.expr);
        lens[i] = s.expr.len;
    };
    const elapsed = start.untilNow(io, .awake);
    std.debug.print("{d:.4} ms/round\n", .{@as(f64, @floatFromInt(elapsed.toNanoseconds())) / 1e6 / @as(f64, @floatFromInt(rounds.items.len * reps))});
    var buf: [4096]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, args[2], .{});
    var fw = file.writer(io, &buf);
    for (values, 0..) |v, i| {
        if (i != 0) try fw.interface.writeByte('\n');
        try fw.interface.print("{d}\t{s}", .{ v, exprs[i][0..lens[i]] });
    }
    try fw.interface.flush();
}
