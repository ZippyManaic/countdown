# Check the parallel solver against known answers and the dealer and argument parsing against the game's rules
using Random
using Test

include(joinpath(@__DIR__, "solver.jl"))
using .ParSolver

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
    @test solve(100, [7]) == (7, "7")
    @test solve(100, [3, 4]) == (12, "4 * 3")
    # Solve the same round twice since the pool must carry nothing from one solve to the next
    @test solve(431, [3, 2, 3, 4, 2, 25]) == solve(431, [3, 2, 3, 4, 2, 25])
end

@testset "dealer" begin
    rng = Random.Xoshiro(1)
    for _ in 1:1000
        target, pool = generate_round(rng, "standard")
        @test 100 <= target <= 999
        @test length(pool) == 6
        @test count(>(10), pool) in (1, 2)
        @test all(count(==(k), pool) <= 2 for k in 1:10)
    end
end

# Check one dealt round against its mode and return how many large numbers it holds
function check_round(mode, target, pool, counts)
    large = filter(>(10), pool)
    @test 100 <= target <= 999
    @test length(pool) == 6
    @test allunique(large) && all(in(LARGE_NUMBERS[mode]), large)
    @test all(count(==(k), pool) <= 2 for k in 1:10)
    @test length(large) in counts
    return length(large)
end

@testset "modes" begin
    rng = Random.Xoshiro(2)
    for (mode, counts) in (("standard", Set([1, 2])), ("cats", Set(0:4)), ("nasty", Set(0:4)))
        seen = Set(check_round(mode, generate_round(rng, mode)..., counts) for _ in 1:2000)
        @test seen == counts
    end
    for mode in ("cats", "nasty"), k in 0:4
        @test check_round(mode, generate_round(rng, mode, k)..., Set([k])) == k
    end
end

@testset "arguments" begin
    @test parse_args(String[]) == ("standard", nothing)
    @test parse_args(["nasty", "4"]) == ("nasty", 4)
    @test parse_args(["cats", "0"]) == ("cats", 0)
    for bad in (["standard", "3"], ["cats", "5"], ["easy"], ["cats", "1", "2"], ["cats", "x"])
        @test parse_args(bad) === nothing
    end
end

@testset "cats rounds" begin
    @test solve(999, [10, 10, 25, 50, 75, 100]) == (999, "(((75 + 25) * 100) - 10) / 10")
    @test solve(100, [1, 1, 2, 2, 3, 3]) == (81, "(((2 + 1) * (2 + 1)) * 3) * 3")
    @test solve(999, [2, 3, 87, 62, 37, 12]) == (999, "37 * ((87 / 3) - 2)")
end
