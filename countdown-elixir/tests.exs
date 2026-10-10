# Check the solver against rounds with known answers

ExUnit.start()

defmodule Countdown.SolverTest do
  use ExUnit.Case, async: true

  alias Countdown.Solver

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

  test "deals a valid pool" do
    for _ <- 1..1000 do
      {target, pool} = Countdown.generate_round()
      assert target in 100..999
      assert length(pool) == 6
      large = Enum.count(pool, &(&1 > 10))
      assert large in 1..2
      for n <- 1..10, do: assert(Enum.count(pool, &(&1 == n)) <= 2)
    end
  end
end
