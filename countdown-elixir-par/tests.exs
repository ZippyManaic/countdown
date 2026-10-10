# Check the parallel solver against rounds with known answers

ExUnit.start()

defmodule CountdownPar.SolverTest do
  use ExUnit.Case, async: false

  alias CountdownPar.Solver

  test "finds the simplest solution" do
    assert Solver.solve(125, [1, 5, 7, 3, 75, 50]) == {125, "75 + 50"}
    assert elem(Solver.solve(552, [8, 4, 2, 5, 100, 25]), 0) == 552
  end

  test "reports the closest value when unsolvable" do
    {value, _} = Solver.solve(974, [8, 8, 6, 8, 25, 100])
    assert abs(value - 974) == 1
  end

  test "matches the reference closest answer" do
    assert Solver.solve(431, [3, 2, 3, 4, 2, 25]) == {432, "((25 * 3) - 3) * (4 + 2)"}
  end

  test "handles a single number" do
    assert Solver.solve(7, [7]) == {7, "7"}
    assert Solver.solve(9, [7]) == {7, "7"}
  end

  test "handles smaller pools" do
    assert Solver.solve(9, [2, 3]) == {6, "3 * 2"}
    assert Solver.solve(10, [3, 4]) == {12, "4 * 3"}
  end

  test "matches every reference answer" do
    data = Path.join([__DIR__, "..", "bench", "data"])
    rounds = File.read!(Path.join(data, "rounds1k.txt")) |> String.split("\n", trim: true)
    answers = File.read!(Path.join(data, "ref1k.tsv")) |> String.split("\n", trim: true)

    for {line, answer} <- Enum.zip(rounds, answers) do
      [target | pool] = line |> String.split() |> Enum.map(&String.to_integer/1)
      {value, expr} = Solver.solve(target, pool)
      assert "#{value}\t#{expr}" == answer
    end
  end

  test "deals a valid pool" do
    for _ <- 1..1000 do
      {target, pool} = CountdownPar.generate_round()
      assert target in 100..999
      assert length(pool) == 6
      large = Enum.count(pool, &(&1 > 10))
      assert large in 1..2
      for n <- 1..10, do: assert(Enum.count(pool, &(&1 == n)) <= 2)
    end
  end
end
