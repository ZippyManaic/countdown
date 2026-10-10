# Generate a Countdown numbers round and work out whether it can be solved
include(joinpath(@__DIR__, "solver.jl"))
include(joinpath(@__DIR__, "dealer.jl"))
using .Solver

function main()
    target, pool = generate_round()
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

exit(main())
