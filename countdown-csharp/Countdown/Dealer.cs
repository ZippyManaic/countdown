// Deal Countdown numbers rounds and read the game mode from the command line
namespace Countdown;

public static class Dealer
{
    // Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
    public static readonly Dictionary<string, int[]> LargeNumbers = new()
    {
        ["standard"] = [25, 50, 75, 100],
        ["cats"] = [25, 50, 75, 100],
        ["nasty"] = [12, 37, 62, 87],
    };

    public const string Usage = "usage: countdown [standard|cats|nasty] [LARGE]";

    // Return a random target and six numbers with one or two large in standard mode and none to four otherwise
    public static (int Target, int[] Pool) GenerateRound(Random random, string mode = "standard", int? fixedLarge = null)
    {
        var target = random.Next(100, 1000);
        var largeCount = fixedLarge ?? (mode == "standard" ? random.Next(1, 3) : random.Next(0, 5));
        // Hold two cards of each small number to match the game's deck
        var small = Enumerable.Range(0, 20).Select(i => i % 10 + 1).ToArray();
        random.Shuffle(small);
        // Shuffle a copy since each large number appears only once in the game
        var large = (int[])LargeNumbers[mode].Clone();
        random.Shuffle(large);
        return (target, [.. small[..(6 - largeCount)], .. large[..largeCount]]);
    }

    // Return the mode and fixed large count from the command line, or null when the arguments are invalid
    public static (string Mode, int? Large)? ParseArgs(string[] args)
    {
        if (args.Length > 2) return null;
        var mode = args.Length > 0 ? args[0] : "standard";
        if (!LargeNumbers.ContainsKey(mode)) return null;
        if (args.Length < 2) return (mode, null);
        string[] allowed = mode == "standard" ? ["1", "2"] : ["0", "1", "2", "3", "4"];
        return allowed.Contains(args[1]) ? (mode, int.Parse(args[1])) : null;
    }
}
