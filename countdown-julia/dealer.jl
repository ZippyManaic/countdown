# Deal a Countdown numbers round under the game's rules and read the game mode from the command line
using Random

# Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
const LARGE_NUMBERS = Dict("standard" => [25, 50, 75, 100], "cats" => [25, 50, 75, 100], "nasty" => [12, 37, 62, 87])
const USAGE = "usage: countdown [standard|cats|nasty] [LARGE]"

# Return a random target and six numbers with one or two large in standard mode and none to four otherwise
function generate_round(rng = Random.default_rng(), mode = "standard", large_count = nothing)
    target = rand(rng, 100:999)
    if large_count === nothing
        large_count = mode == "standard" ? rand(rng, 1:2) : rand(rng, 0:4)
    end
    # Hold two cards of each small number to match the game's deck
    small = shuffle!(rng, [1:10; 1:10])
    # Shuffle a copy since each large number appears only once in the game
    large = shuffle!(rng, copy(LARGE_NUMBERS[mode]))
    return target, [small[1:6-large_count]; large[1:large_count]]
end

# Return the mode and fixed large count from the command line, or nothing when the arguments are invalid
function parse_args(args)
    length(args) > 2 && return nothing
    mode = isempty(args) ? "standard" : args[1]
    haskey(LARGE_NUMBERS, mode) || return nothing
    length(args) < 2 && return mode, nothing
    allowed = mode == "standard" ? ("1", "2") : ("0", "1", "2", "3", "4")
    return args[2] in allowed ? (mode, parse(Int, args[2])) : nothing
end
