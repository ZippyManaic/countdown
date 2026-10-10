// Generate a Countdown numbers round and work out whether it can be solved
package countdown;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public final class Countdown {

    private static final List<Integer> LARGE_NUMBERS = List.of(25, 50, 75, 100);

    private Countdown() {
    }

    // Return a random target and a pool of six numbers with either one or two large numbers
    static int[] generateRound(Random random, int[] target) {
        target[0] = 100 + random.nextInt(900);
        int largeCount = 1 + random.nextInt(2);
        // Hold two cards of each small number to match the game's deck
        List<Integer> small = new ArrayList<>();
        for (int i = 0; i < 20; i++) {
            small.add(i % 10 + 1);
        }
        Collections.shuffle(small, random);
        // Shuffle a copy since each large number appears only once in the game
        List<Integer> large = new ArrayList<>(LARGE_NUMBERS);
        Collections.shuffle(large, random);
        return IntStream.concat(small.subList(0, 6 - largeCount).stream().mapToInt(Integer::intValue),
                large.subList(0, largeCount).stream().mapToInt(Integer::intValue)).toArray();
    }

    public static void main(String[] args) {
        int[] target = new int[1];
        int[] pool = generateRound(new Random(), target);
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
