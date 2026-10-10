// Generate a Countdown numbers round and work out whether it can be solved
using Countdown;

if (Dealer.ParseArgs(args) is not var (mode, fixedLarge))
{
    Console.Error.WriteLine(Dealer.Usage);
    return 2;
}
var (target, pool) = Dealer.GenerateRound(Random.Shared, mode, fixedLarge);
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
