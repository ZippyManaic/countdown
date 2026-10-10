# Deal a Countdown numbers round under the game's rules
using Random

const LARGE_NUMBERS = [25, 50, 75, 100]

# Return a random target and a pool of six numbers with either one or two large numbers
function generate_round(rng = Random.default_rng())
    target = rand(rng, 100:999)
    large_count = rand(rng, 1:2)
    # Hold two cards of each small number to match the game's deck
    small = shuffle!(rng, [1:10; 1:10])
    # Shuffle a copy since each large number appears only once in the game
    large = shuffle!(rng, copy(LARGE_NUMBERS))
    return target, [small[1:6-large_count]; large[1:large_count]]
end
