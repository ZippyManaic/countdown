// Check the solver against rounds with known answers
using Countdown;

var failures = 0;
void Expect(bool ok, string what)
{
    if (ok) return;
    Console.WriteLine($"FAIL: {what}");
    failures++;
}

Expect(Solver.Solve(125, [1, 5, 7, 3, 75, 50]) == (125, "75 + 50"), "finds simplest solution");
Expect(Solver.Solve(552, [8, 4, 2, 5, 100, 25]).Value == 552, "solves 552");
Expect(Math.Abs(Solver.Solve(974, [8, 8, 6, 8, 25, 100]).Value - 974) == 1, "reports closest when unsolvable");
for (var i = 0; i < 1000; i++)
{
    var (target, pool) = Dealer.GenerateRound(Random.Shared);
    var large = pool.Count(n => n > 10);
    Expect(target is >= 100 and <= 999 && pool.Length == 6 && large is 1 or 2
        && Enumerable.Range(1, 10).All(n => pool.Count(p => p == n) <= 2), "deals a valid pool");
}
if (failures > 0) return 1;
Console.WriteLine("all tests passed");
return 0;
