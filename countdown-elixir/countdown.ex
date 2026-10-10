defmodule Countdown do
  @moduledoc """
  Generate a Countdown numbers round and work out whether it can be solved
  """

  @large_numbers [25, 50, 75, 100]

  @doc """
  Return a random target and a pool of six numbers with either one or two large numbers
  """
  def generate_round do
    target = Enum.random(100..999)
    large_count = Enum.random(1..2)
    # Hold two cards of each small number to match the game's deck
    small = Enum.shuffle(Enum.concat(1..10, 1..10))
    # Shuffle a copy since each large number appears only once in the game
    large = Enum.shuffle(@large_numbers)
    {target, Enum.take(small, 6 - large_count) ++ Enum.take(large, large_count)}
  end

  @doc """
  Deal and solve one round then exit with status zero only when the target is hit
  """
  def main do
    {target, pool} = generate_round()
    IO.puts("Target: #{target}")
    IO.puts("Pool:   #{Enum.join(pool, " ")}")

    case Countdown.Solver.solve(target, pool) do
      {^target, expr} ->
        IO.puts("Solved: #{expr} = #{target}")
        System.halt(0)

      {value, expr} ->
        IO.puts("No exact solution, closest is #{expr} = #{value} (#{abs(value - target)} away)")
        System.halt(1)
    end
  end
end
