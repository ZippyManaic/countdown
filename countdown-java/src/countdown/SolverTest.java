// Check the solver against rounds with known answers
package countdown;

import java.util.Random;

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

    public static void main(String[] args) {
        Solver.Result result = Solver.solve(125, new int[] {1, 5, 7, 3, 75, 50});
        expect(result.value() == 125 && result.expr().equals("75 + 50"), "finds simplest solution");
        expect(Solver.solve(552, new int[] {8, 4, 2, 5, 100, 25}).value() == 552, "solves 552");
        expect(Math.abs(Solver.solve(974, new int[] {8, 8, 6, 8, 25, 100}).value() - 974) == 1,
                "reports closest when unsolvable");
        Random random = new Random();
        for (int i = 0; i < 1000; i++) {
            int[] target = new int[1];
            int[] pool = Countdown.generateRound(random, target);
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
