// Time the solver over a file of rounds and write each answer as value tab expression
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public final class JavaHarness {

    private JavaHarness() {
    }

    public static void main(String[] args) throws Exception {
        List<int[]> rounds = Files.readAllLines(Path.of(args[0])).stream()
                .filter(line -> !line.isBlank())
                .map(line -> java.util.Arrays.stream(line.trim().split("\\s+")).mapToInt(Integer::parseInt).toArray())
                .toList();
        int reps = args.length > 2 ? Integer.parseInt(args[2]) : 1;
        // Warm up with untimed passes so the timing measures fully compiled code rather than the JIT compiling it
        for (int pass = 0; pass < 3; pass++) {
            for (int[] r : rounds) {
                countdown.Solver.solve(r[0], java.util.Arrays.copyOfRange(r, 1, 7));
            }
        }
        countdown.Solver.Result[] out = new countdown.Solver.Result[rounds.size()];
        long start = System.nanoTime();
        for (int rep = 0; rep < reps; rep++) {
            for (int i = 0; i < rounds.size(); i++) {
                int[] r = rounds.get(i);
                out[i] = countdown.Solver.solve(r[0], java.util.Arrays.copyOfRange(r, 1, 7));
            }
        }
        double ms = (System.nanoTime() - start) / 1e6 / (rounds.size() * (double) reps);
        System.err.printf("%.4f ms/round%n", ms);
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < out.length; i++) {
            if (i > 0) {
                text.append('\n');
            }
            text.append(out[i].value()).append('\t').append(out[i].expr());
        }
        Files.writeString(Path.of(args[1]), text);
    }
}
