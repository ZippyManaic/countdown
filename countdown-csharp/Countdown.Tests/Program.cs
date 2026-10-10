// Check the dealer in every mode and the solver against rounds with known answers
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
Expect(Solver.Solve(100, [7]) == (7, "7"), "reports a lone number as closest");
// Check one dealt round against its mode and return how many large numbers it holds
int CheckRound(string mode, int target, int[] pool, int[] counts)
{
    var large = pool.Where(n => n > 10).ToArray();
    Expect(target is >= 100 and <= 999 && pool.Length == 6, $"{mode} deals a target and six numbers");
    Expect(large.Distinct().Count() == large.Length && large.All(Dealer.LargeNumbers[mode].Contains),
        $"{mode} deals distinct large numbers from its set");
    Expect(Enumerable.Range(1, 10).All(n => pool.Count(p => p == n) <= 2), $"{mode} deals each small number at most twice");
    Expect(counts.Contains(large.Length), $"{mode} deals an allowed large count");
    return large.Length;
}

foreach (var (mode, counts) in new[] { ("standard", new[] { 1, 2 }), ("cats", [0, 1, 2, 3, 4]), ("nasty", [0, 1, 2, 3, 4]) })
{
    var seen = new HashSet<int>();
    for (var i = 0; i < 2000; i++)
    {
        var (target, pool) = Dealer.GenerateRound(Random.Shared, mode);
        seen.Add(CheckRound(mode, target, pool, counts));
    }
    Expect(seen.SetEquals(counts), $"{mode} deals every allowed large count");
}
foreach (var mode in new[] { "cats", "nasty" })
{
    for (var k = 0; k <= 4; k++)
    {
        var (target, pool) = Dealer.GenerateRound(Random.Shared, mode, k);
        Expect(CheckRound(mode, target, pool, [k]) == k, $"{mode} deals a fixed large count");
    }
}
Expect(Dealer.ParseArgs([]) == ("standard", null), "accepts no arguments");
Expect(Dealer.ParseArgs(["nasty", "4"]) == ("nasty", 4), "accepts nasty 4");
Expect(Dealer.ParseArgs(["cats", "0"]) == ("cats", 0), "accepts cats 0");
foreach (var bad in new string[][] { ["standard", "3"], ["cats", "5"], ["easy"], ["cats", "1", "2"], ["cats", "x"] })
{
    Expect(Dealer.ParseArgs(bad) is null, $"rejects {string.Join(' ', bad)}");
}
Expect(Solver.Solve(999, [10, 10, 25, 50, 75, 100]) == (999, "(((75 + 25) * 100) - 10) / 10"), "solves a four-large round");
Expect(Solver.Solve(100, [1, 1, 2, 2, 3, 3]) == (81, "(((2 + 1) * (2 + 1)) * 3) * 3"), "solves a no-large round");
Expect(Solver.Solve(999, [2, 3, 87, 62, 37, 12]) == (999, "37 * ((87 / 3) - 2)"), "solves a nasty round");
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
