# Time a parallel Julia solver over a file of rounds and write each answer as value tab expression
include(abspath(ARGS[1]))
using .ParSolver

function main(args)
    rounds = [parse.(Int, split(line)) for line in eachline(args[2]) if !isempty(strip(line))]
    reps = length(args) > 3 ? parse(Int, args[4]) : 1
    answers = Vector{Tuple{Int,String}}(undef, length(rounds))
    run() = for (i, r) in enumerate(rounds)
        answers[i] = solve(r[1], view(r, 2:length(r)))
    end
    # Warm up with untimed passes so the timing measures compiled code rather than the JIT compiling it
    for _ in 1:3
        run()
    end
    start = time_ns()
    for _ in 1:reps
        run()
    end
    elapsed = (time_ns() - start) / 1e6
    println(stderr, string(round(elapsed / (length(rounds) * reps); digits = 4)) * " ms/round")
    open(args[3], "w") do f
        print(f, join(("$v\t$e" for (v, e) in answers), "\n"))
    end
end

main(ARGS)
