# Check the solver against rounds with known answers

require_relative "solver"
require_relative "countdown"

failures = 0
expect = lambda do |ok, what|
  next if ok

  puts "FAIL: #{what}"
  failures += 1
end

value, expr = Solver.solve(125, [1, 5, 7, 3, 75, 50])
expect.call(value == 125 && expr == "75 + 50", "finds simplest solution")
expect.call(Solver.solve(552, [8, 4, 2, 5, 100, 25])[0] == 552, "solves 552")
expect.call((Solver.solve(974, [8, 8, 6, 8, 25, 100])[0] - 974).abs == 1, "reports closest when unsolvable")
value, expr = Solver.solve(431, [3, 2, 3, 4, 2, 25])
expect.call(value == 432 && expr == "((25 * 3) - 3) * (4 + 2)", "matches reference closest answer")
value, expr = Solver.solve(7, [7])
expect.call(value == 7 && expr == "7", "handles a single number")
value, expr = Solver.solve(9, [7])
expect.call(value == 7 && expr == "7", "reports a single number when it misses")
value, expr = Solver.solve(9, [2, 3])
expect.call(value == 6 && expr == "3 * 2", "handles smaller pools")
# Check one dealt round and return its large count
check_round = lambda do |mode, target, pool, counts|
  expect.call((100..999).cover?(target), "#{mode}: target in range")
  expect.call(pool.length == 6, "#{mode}: six numbers")
  large = pool.select { |n| n > 10 }
  expect.call(counts.include?(large.length), "#{mode}: large count allowed")
  expect.call((large - LARGE_NUMBERS[mode]).empty?, "#{mode}: large numbers from the mode's set")
  expect.call(large.uniq.length == large.length, "#{mode}: large numbers distinct")
  # Allow each small number at most twice since the deck holds two of each
  expect.call(pool.select { |n| n <= 10 }.tally.values.all? { |c| c <= 2 }, "#{mode}: small numbers at most twice")
  large.length
end

srand(1)
[["standard", [1, 2]], ["cats", [0, 1, 2, 3, 4]], ["nasty", [0, 1, 2, 3, 4]]].each do |mode, counts|
  seen = Array.new(2000) { check_round.call(mode, *generate_round(mode), counts) }.uniq.sort
  expect.call(seen == counts, "#{mode}: every large count occurs")
end
%w[cats nasty].each do |mode|
  (0..4).each do |k|
    expect.call(check_round.call(mode, *generate_round(mode, k), [k]) == k, "#{mode}: fixed count #{k}")
  end
end

expect.call(parse_args([]) == ["standard", nil], "parses no arguments")
expect.call(parse_args(%w[nasty 4]) == ["nasty", 4], "parses nasty 4")
expect.call(parse_args(%w[cats 0]) == ["cats", 0], "parses cats 0")
[%w[standard 3], %w[cats 5], %w[dogs], %w[cats 1 2], %w[cats x]].each do |bad|
  expect.call(parse_args(bad).nil?, "rejects #{bad.join(' ')}")
end

value, expr = Solver.solve(999, [10, 10, 25, 50, 75, 100])
expect.call(value == 999 && expr == "(((75 + 25) * 100) - 10) / 10", "solves cats round 999")
value, expr = Solver.solve(100, [1, 1, 2, 2, 3, 3])
expect.call(value == 81 && expr == "(((2 + 1) * (2 + 1)) * 3) * 3", "reports closest on cats round with no large")
value, expr = Solver.solve(999, [2, 3, 87, 62, 37, 12])
expect.call(value == 999 && expr == "37 * ((87 / 3) - 2)", "solves nasty round 999")
exit 1 if failures.positive?
puts "all tests passed"
