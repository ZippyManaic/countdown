// Deal Countdown numbers rounds
namespace Countdown;

public static class Dealer
{
    private static readonly int[] LargeNumbers = [25, 50, 75, 100];

    // Return a random target and a pool of six numbers with either one or two large numbers
    public static (int Target, int[] Pool) GenerateRound(Random random)
    {
        var target = random.Next(100, 1000);
        var largeCount = random.Next(1, 3);
        // Hold two cards of each small number to match the game's deck
        var small = Enumerable.Range(0, 20).Select(i => i % 10 + 1).ToArray();
        random.Shuffle(small);
        // Shuffle a copy since each large number appears only once in the game
        var large = (int[])LargeNumbers.Clone();
        random.Shuffle(large);
        return (target, [.. small[..(6 - largeCount)], .. large[..largeCount]]);
    }
}
