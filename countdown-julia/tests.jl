# Check the solver against known answers and the dealer against the game's rules
using Random
using Test

include(joinpath(@__DIR__, "solver.jl"))
using .Solver

include(joinpath(@__DIR__, "dealer.jl"))

@testset "solver" begin
    @test solve(125, [1, 5, 7, 3, 75, 50]) == (125, "75 + 50")
    @test solve(552, [8, 4, 2, 5, 100, 25])[1] == 552
    @test abs(solve(974, [8, 8, 6, 8, 25, 100])[1] - 974) == 1
    @test solve(431, [3, 2, 3, 4, 2, 25]) == (432, "((25 * 3) - 3) * (4 + 2)")
    @test solve(423, [6, 2, 2, 1, 1, 25]) == (423, "(25 * ((6 * (2 + 1)) - 1)) - 2")
    @test solve(10, [3, 4]) == (12, "4 * 3")
    @test solve(7, [7]) == (7, "7")
    @test solve(5, [9]) == (9, "9")
end

@testset "dealer" begin
    rng = Random.Xoshiro(1)
    for _ in 1:1000
        target, pool = generate_round(rng)
        @test 100 <= target <= 999
        @test length(pool) == 6
        @test count(>(10), pool) in (1, 2)
        @test all(count(==(k), pool) <= 2 for k in 1:10)
    end
end
