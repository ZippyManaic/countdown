// Time the solver over a file of rounds and write each answer as value tab expression
using System.Diagnostics;
using Countdown;

var rounds = File.ReadAllLines(args[0])
    .Where(line => line.Length > 0)
    .Select(line => line.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(int.Parse).ToArray())
    .ToArray();
var reps = args.Length > 2 ? int.Parse(args[2]) : 1;
// Warm up with untimed passes so the timing measures fully compiled code rather than the JIT compiling it
for (var pass = 0; pass < 3; pass++)
    foreach (var r in rounds) Solver.Solve(r[0], r[1..]);
var output = new (int Value, string Expr)[rounds.Length];
var watch = Stopwatch.StartNew();
for (var rep = 0; rep < reps; rep++)
    for (var i = 0; i < rounds.Length; i++) output[i] = Solver.Solve(rounds[i][0], rounds[i][1..]);
watch.Stop();
Console.Error.WriteLine($"{watch.Elapsed.TotalMilliseconds / (rounds.Length * reps):F4} ms/round");
File.WriteAllText(args[1], string.Join('\n', output.Select(o => $"{o.Value}\t{o.Expr}")));
