# Check the solver against rounds with known answers

require_relative "solver"

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
exit 1 if failures.positive?
puts "all tests passed"
