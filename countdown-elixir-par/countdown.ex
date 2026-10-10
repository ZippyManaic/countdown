defmodule CountdownPar do
  @moduledoc """
  Generate a Countdown numbers round and work out whether it can be solved sharing the work across schedulers
  """

  @usage "usage: countdown [standard|cats|nasty] [LARGE]"
  @modes %{"standard" => :standard, "cats" => :cats, "nasty" => :nasty}

  @doc """
  Return the large cards of a mode, with nasty-cats using the cards of the 2010 specials
  """
  def large_numbers(:nasty), do: [12, 37, 62, 87]
  def large_numbers(_mode), do: [25, 50, 75, 100]

  @doc """
  Return the large counts a mode allows
  """
  def allowed_counts(:standard), do: [1, 2]
  def allowed_counts(_mode), do: [0, 1, 2, 3, 4]

  @doc """
  Return a random target and six numbers with one or two large in standard mode and none to four otherwise
  """
  def generate_round(mode \\ :standard, large_count \\ nil) do
    target = Enum.random(100..999)
    large_count = large_count || Enum.random(allowed_counts(mode))
    # Hold two cards of each small number to match the game's deck
    small = Enum.shuffle(Enum.concat(1..10, 1..10))
    # Shuffle a copy since each large number appears only once in the game
    large = Enum.shuffle(large_numbers(mode))
    {target, Enum.take(small, 6 - large_count) ++ Enum.take(large, large_count)}
  end

  @doc """
  Return the mode and fixed large count from the command line, or nil when the arguments are invalid
  """
  def parse_args(args) do
    with {mode_name, count} when length(args) <= 2 <-
           {Enum.at(args, 0, "standard"), Enum.at(args, 1)},
         mode when mode != nil <- @modes[mode_name] do
      cond do
        count == nil -> {mode, nil}
        k = Enum.find(allowed_counts(mode), &("#{&1}" == count)) -> {mode, k}
        true -> nil
      end
    else
      _ -> nil
    end
  end

  @doc """
  Deal and solve one round from the arguments the launcher passes after -extra then exit with status zero only when the target is hit
  """
  def main do
    case parse_args(Enum.map(:init.get_plain_arguments(), &List.to_string/1)) do
      nil ->
        IO.puts(:stderr, @usage)
        System.halt(2)

      {mode, large_count} ->
        play(mode, large_count)
    end
  end

  defp play(mode, large_count) do
    {target, pool} = generate_round(mode, large_count)
    IO.puts("Target: #{target}")
    IO.puts("Pool:   #{Enum.join(pool, " ")}")

    case CountdownPar.Solver.solve(target, pool) do
      {^target, expr} ->
        IO.puts("Solved: #{expr} = #{target}")
        System.halt(0)

      {value, expr} ->
        IO.puts("No exact solution, closest is #{expr} = #{value} (#{abs(value - target)} away)")
        System.halt(1)
    end
  end
end
