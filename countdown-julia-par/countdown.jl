# Generate a Countdown numbers round and work out whether it can be solved with several threads sharing the work
include(joinpath(@__DIR__, "solver.jl"))
include(joinpath(@__DIR__, "dealer.jl"))
using .ParSolver

function main(args)
    parsed = parse_args(args)
    if parsed === nothing
        println(stderr, USAGE)
        return 2
    end
    target, pool = generate_round(Random.default_rng(), parsed...)
    println("Target: ", target)
    println("Pool:   ", join(pool, " "))
    value, expr = solve(target, pool)
    if value == target
        println("Solved: ", expr, " = ", value)
        return 0
    end
    println("No exact solution, closest is ", expr, " = ", value, " (", abs(value - target), " away)")
    return 1
end

exit(main(ARGS))
