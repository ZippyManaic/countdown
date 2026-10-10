# Check the solver against rounds with known answers and the dealer in every mode

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

  test "solves cats and nasty-cats rounds" do
    assert Solver.solve(999, [10, 10, 25, 50, 75, 100]) == {999, "(((75 + 25) * 100) - 10) / 10"}
    assert Solver.solve(100, [1, 1, 2, 2, 3, 3]) == {81, "(((2 + 1) * (2 + 1)) * 3) * 3"}
    assert Solver.solve(999, [2, 3, 87, 62, 37, 12]) == {999, "37 * ((87 / 3) - 2)"}
  end

  # Return the large count of a dealt round after checking it keeps the rules of its mode
  defp check_round(mode, counts, {target, pool}) do
    assert target in 100..999
    assert length(pool) == 6
    large = Enum.filter(pool, &(&1 > 10))
    assert length(large) in counts
    assert Enum.all?(large, &(&1 in Countdown.large_numbers(mode)))
    assert Enum.uniq(large) == large
    # Allow each small number at most twice since the deck holds two of each
    for n <- 1..10, do: assert(Enum.count(pool, &(&1 == n)) <= 2)
    length(large)
  end

  test "deals every mode" do
    :rand.seed(:exsss, 1)

    for mode <- [:standard, :cats, :nasty] do
      counts = Countdown.allowed_counts(mode)
      seen = for _ <- 1..2000, do: check_round(mode, counts, Countdown.generate_round(mode))
      assert Enum.sort(Enum.uniq(seen)) == counts
    end
  end

  test "deals a fixed large count" do
    for mode <- [:cats, :nasty], k <- 0..4 do
      assert check_round(mode, [k], Countdown.generate_round(mode, k)) == k
    end
  end

  test "parses arguments" do
    assert Countdown.parse_args([]) == {:standard, nil}
    assert Countdown.parse_args(["nasty", "4"]) == {:nasty, 4}
    assert Countdown.parse_args(["cats", "0"]) == {:cats, 0}

    for bad <- [["standard", "3"], ["cats", "5"], ["dogs"], ["cats", "1", "2"], ["cats", "x"]] do
      assert Countdown.parse_args(bad) == nil
    end
  end
end
