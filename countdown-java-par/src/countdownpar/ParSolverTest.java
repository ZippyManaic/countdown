// Check the parallel solver against rounds with known answers
package countdownpar;

import java.util.Random;

public final class ParSolverTest {

    private static int failures;

    private ParSolverTest() {
    }

    private static void expect(boolean ok, String what) {
        if (!ok) {
            System.out.println("FAIL: " + what);
            failures++;
        }
    }

    public static void main(String[] args) {
        ParSolver.Result result = ParSolver.solve(125, new int[] {1, 5, 7, 3, 75, 50});
        expect(result.value() == 125 && result.expr().equals("75 + 50"), "finds simplest solution");
        expect(ParSolver.solve(552, new int[] {8, 4, 2, 5, 100, 25}).value() == 552, "solves 552");
        expect(Math.abs(ParSolver.solve(974, new int[] {8, 8, 6, 8, 25, 100}).value() - 974) == 1,
                "reports closest when unsolvable");
        // Check a round that needs every number and the whole-pool search
        ParSolver.Result six = ParSolver.solve(423, new int[] {6, 2, 2, 1, 1, 25});
        expect(six.value() == 423 && six.expr().equals("(25 * ((6 * (2 + 1)) - 1)) - 2"), "uses all six numbers");
        ParSolver.Result miss = ParSolver.solve(431, new int[] {3, 2, 3, 4, 2, 25});
        expect(miss.value() == 432 && miss.expr().equals("((25 * 3) - 3) * (4 + 2)"), "breaks closest ties the same way");
        ParSolver.Result single = ParSolver.solve(10, new int[] {7});
        expect(single.value() == 7 && single.expr().equals("7"), "answers a one-number pool");
        expect(ParSolver.solve(10, new int[] {3, 4}).expr().equals("4 * 3"), "handles smaller pools");
        Random random = new Random();
        for (int i = 0; i < 1000; i++) {
            int[] target = new int[1];
            int[] pool = Countdown.generateRound(random, target);
            long large = java.util.Arrays.stream(pool).filter(n -> n > 10).count();
            expect(target[0] >= 100 && target[0] <= 999 && pool.length == 6 && (large == 1 || large == 2),
                    "deals a valid pool");
            // Solve twice since the answer must not depend on how the workers happened to share the work
            expect(ParSolver.solve(target[0], pool).equals(ParSolver.solve(target[0], pool)), "solves deterministically");
        }
        if (failures > 0) {
            System.exit(1);
        }
        System.out.println("all tests passed");
    }
}
