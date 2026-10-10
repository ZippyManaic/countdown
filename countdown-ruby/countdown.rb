# Generate a Countdown numbers round and work out whether it can be solved

require_relative "solver"

# Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
LARGE_NUMBERS = {
  "standard" => [25, 50, 75, 100].freeze,
  "cats" => [25, 50, 75, 100].freeze,
  "nasty" => [12, 37, 62, 87].freeze
}.freeze
USAGE = "usage: countdown.rb [standard|cats|nasty] [LARGE]"

# Return a random target and six numbers with one or two large in standard mode and none to four otherwise
def generate_round(mode = "standard", large_count = nil)
  target = rand(100..999)
  large_count ||= mode == "standard" ? rand(1..2) : rand(0..4)
  # Hold two cards of each small number to match the game's deck
  small = ((1..10).to_a * 2).shuffle
  # Shuffle a copy since each large number appears only once in the game
  large = LARGE_NUMBERS[mode].shuffle
  [target, small.first(6 - large_count) + large.first(large_count)]
end

# Return the mode and fixed large count from the arguments, or nil when they are invalid
def parse_args(args)
  return nil if args.length > 2

  mode = args.fetch(0, "standard")
  return nil unless LARGE_NUMBERS.key?(mode)
  return [mode, nil] if args.length < 2

  allowed = mode == "standard" ? %w[1 2] : %w[0 1 2 3 4]
  allowed.include?(args[1]) ? [mode, args[1].to_i] : nil
end

if __FILE__ == $PROGRAM_NAME
  parsed = parse_args(ARGV)
  if parsed.nil?
    warn USAGE
    exit 2
  end
  target, pool = generate_round(*parsed)
  puts "Target: #{target}"
  puts "Pool:   #{pool.join(' ')}"

  value, expr = Solver.solve(target, pool)
  if value == target
    puts "Solved: #{expr} = #{value}"
    exit 0
  end
  puts "No exact solution, closest is #{expr} = #{value} (#{(value - target).abs} away)"
  exit 1
end
