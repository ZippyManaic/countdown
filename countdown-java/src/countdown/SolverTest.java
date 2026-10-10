// Check the dealer in every mode and the solver against rounds with known answers
package countdown;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;

public final class SolverTest {

    private static int failures;

    private SolverTest() {
    }

    private static void expect(boolean ok, String what) {
        if (!ok) {
            System.out.println("FAIL: " + what);
            failures++;
        }
    }

    // Check one dealt round against its mode and return how many large numbers it holds
    private static int checkRound(String mode, int target, int[] pool, Set<Integer> counts) {
        List<Integer> largeSet = Countdown.LARGE_NUMBERS.get(mode);
        int[] large = Arrays.stream(pool).filter(n -> n > 10).toArray();
        int[] small = Arrays.stream(pool).filter(n -> n <= 10).toArray();
        expect(target >= 100 && target <= 999 && pool.length == 6, mode + " deals a target and six numbers");
        expect(Arrays.stream(large).distinct().count() == large.length
                && Arrays.stream(large).allMatch(largeSet::contains), mode + " deals distinct large numbers from its set");
        expect(Arrays.stream(small).allMatch(n -> n >= 1
                && Arrays.stream(small).filter(m -> m == n).count() <= 2), mode + " deals each small number at most twice");
        expect(counts.contains(large.length), mode + " deals an allowed large count");
        return large.length;
    }

    private static void testDealer(Random random) {
        Set<Integer> standard = Set.of(1, 2);
        Set<Integer> any = Set.of(0, 1, 2, 3, 4);
        for (String mode : List.of("standard", "cats", "nasty")) {
            Set<Integer> counts = mode.equals("standard") ? standard : any;
            Set<Integer> seen = new HashSet<>();
            for (int i = 0; i < 2000; i++) {
                int[] target = new int[1];
                int[] pool = Countdown.generateRound(random, mode, -1, target);
                seen.add(checkRound(mode, target[0], pool, counts));
            }
            expect(seen.equals(counts), mode + " deals every allowed large count");
        }
        for (String mode : List.of("cats", "nasty")) {
            for (int k = 0; k <= 4; k++) {
                int[] target = new int[1];
                int[] pool = Countdown.generateRound(random, mode, k, target);
                expect(checkRound(mode, target[0], pool, Set.of(k)) == k, mode + " deals a fixed large count");
            }
        }
        expect(Countdown.parseArgs(new String[] {}).equals(new Countdown.Options("standard", -1)), "accepts no arguments");
        expect(Countdown.parseArgs(new String[] {"nasty", "4"}).equals(new Countdown.Options("nasty", 4)), "accepts nasty 4");
        expect(Countdown.parseArgs(new String[] {"cats", "0"}).equals(new Countdown.Options("cats", 0)), "accepts cats 0");
        for (String[] bad : List.of(new String[] {"standard", "3"}, new String[] {"cats", "5"}, new String[] {"easy"},
                new String[] {"cats", "1", "2"}, new String[] {"cats", "x"})) {
            expect(Countdown.parseArgs(bad) == null, "rejects " + String.join(" ", bad));
        }
    }

    private static void testCatsRounds() {
        Solver.Result r = Solver.solve(999, new int[] {10, 10, 25, 50, 75, 100});
        expect(r.value() == 999 && r.expr().equals("(((75 + 25) * 100) - 10) / 10"), "solves a four-large round");
        r = Solver.solve(100, new int[] {1, 1, 2, 2, 3, 3});
        expect(r.value() == 81 && r.expr().equals("(((2 + 1) * (2 + 1)) * 3) * 3"), "solves a no-large round");
        r = Solver.solve(999, new int[] {2, 3, 87, 62, 37, 12});
        expect(r.value() == 999 && r.expr().equals("37 * ((87 / 3) - 2)"), "solves a nasty round");
    }

    public static void main(String[] args) {
        testDealer(new Random());
        testCatsRounds();
        Solver.Result result = Solver.solve(125, new int[] {1, 5, 7, 3, 75, 50});
        expect(result.value() == 125 && result.expr().equals("75 + 50"), "finds simplest solution");
        expect(Solver.solve(552, new int[] {8, 4, 2, 5, 100, 25}).value() == 552, "solves 552");
        expect(Math.abs(Solver.solve(974, new int[] {8, 8, 6, 8, 25, 100}).value() - 974) == 1,
                "reports closest when unsolvable");
        Solver.Result lone = Solver.solve(100, new int[] {7});
        expect(lone.value() == 7 && lone.expr().equals("7"), "reports a lone number as closest");
        lone = Solver.solve(7, new int[] {7});
        expect(lone.value() == 7 && lone.expr().equals("7"), "solves with a lone number");
        Solver.Result pair = Solver.solve(100, new int[] {3, 4});
        expect(pair.value() == 12 && pair.expr().equals("4 * 3"), "reports closest with two numbers");
        Random random = new Random();
        for (int i = 0; i < 1000; i++) {
            int[] target = new int[1];
            int[] pool = Countdown.generateRound(random, "standard", -1, target);
            long large = java.util.Arrays.stream(pool).filter(n -> n > 10).count();
            expect(target[0] >= 100 && target[0] <= 999 && pool.length == 6 && (large == 1 || large == 2),
                    "deals a valid pool");
        }
        if (failures > 0) {
            System.exit(1);
        }
        System.out.println("all tests passed");
    }
}
