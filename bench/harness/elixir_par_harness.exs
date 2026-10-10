# Time the parallel Elixir solver over a file of rounds and write each answer as value tab expression

[solver, rounds_path, out_path | rest] = System.argv()
Code.require_file(solver)
reps = String.to_integer(List.first(rest) || "1")

rounds =
  rounds_path
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.map(fn line -> line |> String.split() |> Enum.map(&String.to_integer/1) end)

solve_all = fn -> Enum.map(rounds, fn [target | pool] -> CountdownPar.Solver.solve(target, pool) end) end
# Solve every round three times untimed so the timing shows code the JIT has already loaded and warmed
for _ <- 1..3, do: solve_all.()
start = System.monotonic_time(:nanosecond)
out = Enum.reduce(1..reps, nil, fn _, _ -> solve_all.() end)
elapsed = System.monotonic_time(:nanosecond) - start
IO.puts(:stderr, :io_lib.format("~.4f ms/round", [elapsed / 1.0e6 / (length(rounds) * reps)]))
File.write!(out_path, Enum.map_join(out, "\n", fn {value, expr} -> "#{value}\t#{expr}" end))
