// Generate a Countdown numbers round and work out whether it can be solved
package countdown;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public final class Countdown {

    // Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
    static final Map<String, List<Integer>> LARGE_NUMBERS = Map.of("standard", List.of(25, 50, 75, 100),
            "cats", List.of(25, 50, 75, 100), "nasty", List.of(12, 37, 62, 87));
    static final String USAGE = "usage: countdown [standard|cats|nasty] [LARGE]";

    // Hold the mode and the fixed large count, which is -1 when the count is chosen at random
    record Options(String mode, int largeCount) {
    }

    private Countdown() {
    }

    // Return a random target and six numbers with one or two large in standard mode and none to four otherwise
    static int[] generateRound(Random random, String mode, int largeCount, int[] target) {
        target[0] = 100 + random.nextInt(900);
        if (largeCount < 0) {
            largeCount = mode.equals("standard") ? 1 + random.nextInt(2) : random.nextInt(5);
        }
        // Hold two cards of each small number to match the game's deck
        List<Integer> small = new ArrayList<>();
        for (int i = 0; i < 20; i++) {
            small.add(i % 10 + 1);
        }
        Collections.shuffle(small, random);
        // Shuffle a copy since each large number appears only once in the game
        List<Integer> large = new ArrayList<>(LARGE_NUMBERS.get(mode));
        Collections.shuffle(large, random);
        return IntStream.concat(small.subList(0, 6 - largeCount).stream().mapToInt(Integer::intValue),
                large.subList(0, largeCount).stream().mapToInt(Integer::intValue)).toArray();
    }

    // Return the mode and fixed large count from the command line, or null when the arguments are invalid
    static Options parseArgs(String[] args) {
        if (args.length > 2) {
            return null;
        }
        String mode = args.length > 0 ? args[0] : "standard";
        if (!LARGE_NUMBERS.containsKey(mode)) {
            return null;
        }
        if (args.length < 2) {
            return new Options(mode, -1);
        }
        List<String> allowed = mode.equals("standard") ? List.of("1", "2") : List.of("0", "1", "2", "3", "4");
        return allowed.contains(args[1]) ? new Options(mode, Integer.parseInt(args[1])) : null;
    }

    public static void main(String[] args) {
        Options options = parseArgs(args);
        if (options == null) {
            System.err.println(USAGE);
            System.exit(2);
        }
        int[] target = new int[1];
        int[] pool = generateRound(new Random(), options.mode(), options.largeCount(), target);
        System.out.println("Target: " + target[0]);
        System.out.println("Pool:   " + IntStream.of(pool).mapToObj(Integer::toString).collect(Collectors.joining(" ")));
        Solver.Result result = Solver.solve(target[0], pool);
        if (result.value() == target[0]) {
            System.out.println("Solved: " + result.expr() + " = " + result.value());
            return;
        }
        System.out.println("No exact solution, closest is " + result.expr() + " = " + result.value() + " ("
                + Math.abs(result.value() - target[0]) + " away)");
        System.exit(1);
    }
}
