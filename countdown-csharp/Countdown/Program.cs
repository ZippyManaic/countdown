// Generate a Countdown numbers round and work out whether it can be solved
using Countdown;

var (target, pool) = Dealer.GenerateRound(Random.Shared);
Console.WriteLine($"Target: {target}");
Console.WriteLine($"Pool:   {string.Join(' ', pool)}");
var (value, expr) = Solver.Solve(target, pool);
if (value == target)
{
    Console.WriteLine($"Solved: {expr} = {value}");
    return 0;
}
Console.WriteLine($"No exact solution, closest is {expr} = {value} ({Math.Abs(value - target)} away)");
return 1;
