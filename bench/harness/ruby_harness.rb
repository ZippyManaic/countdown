# Time the solver in a Ruby file over a file of rounds and write each answer as value tab expression

require File.expand_path(ARGV[0])

rounds = File.readlines(ARGV[1]).map { |line| line.split.map(&:to_i) }
reps = (ARGV[3] || "1").to_i
# Solve every round three times untimed when a JIT is on so the timing shows compiled code
jit = (defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?) || (defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?)
3.times { rounds.each { |target, *pool| Solver.solve(target, pool) } } if jit
out = nil
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
reps.times do
  out = rounds.map { |target, *pool| Solver.solve(target, pool) }
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
warn format("%.4f ms/round", elapsed * 1000 / (rounds.length * reps))
File.write(ARGV[2], out.map { |value, expr| "#{value}\t#{expr}" }.join("\n"))
