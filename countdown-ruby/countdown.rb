# Generate a Countdown numbers round and work out whether it can be solved

require_relative "solver"

LARGE_NUMBERS = [25, 50, 75, 100].freeze

# Return a random target and a pool of six numbers with either one or two large numbers
def generate_round
  target = rand(100..999)
  large_count = rand(1..2)
  # Hold two cards of each small number to match the game's deck
  small = ((1..10).to_a * 2).shuffle
  # Shuffle a copy since each large number appears only once in the game
  large = LARGE_NUMBERS.shuffle
  [target, small.first(6 - large_count) + large.first(large_count)]
end

target, pool = generate_round
puts "Target: #{target}"
puts "Pool:   #{pool.join(' ')}"

value, expr = Solver.solve(target, pool)
if value == target
  puts "Solved: #{expr} = #{value}"
  exit 0
end
puts "No exact solution, closest is #{expr} = #{value} (#{(value - target).abs} away)"
exit 1
