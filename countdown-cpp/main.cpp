// Generate a Countdown numbers round and work out whether it can be solved

#include <algorithm>
#include <array>
#include <cstdint>
#include <print>
#include <random>
#include <vector>

#include "solver.hpp"

namespace {

constexpr std::array<std::uint32_t, 4> large_numbers{25, 50, 75, 100};

// Return a random target and a pool of six numbers with either one or two large numbers
std::pair<std::uint32_t, std::vector<std::uint32_t>> generate_round(std::mt19937_64 &rng)
{
    auto target = std::uniform_int_distribution<std::uint32_t>{100, 999}(rng);
    auto large_count = std::uniform_int_distribution<std::size_t>{1, 2}(rng);

    // Hold two cards of each small number to match the game's deck
    std::vector<std::uint32_t> small;
    for (std::uint32_t n = 1; n <= 20; n++)
        small.push_back((n - 1) % 10 + 1);
    std::ranges::shuffle(small, rng);
    // Shuffle a copy since each large number appears only once in the game
    auto large = large_numbers;
    std::ranges::shuffle(large, rng);

    std::vector pool(small.begin(), small.begin() + static_cast<std::ptrdiff_t>(6 - large_count));
    pool.insert(pool.end(), large.begin(), large.begin() + static_cast<std::ptrdiff_t>(large_count));
    return {target, pool};
}

} // namespace

int main()
{
    std::mt19937_64 rng{std::random_device{}()};
    auto [target, pool] = generate_round(rng);
    std::print("Target: {}\nPool:  ", target);
    for (auto n : pool)
        std::print(" {}", n);
    std::println("");

    auto [value, expr] = countdown::solve(target, pool);
    if (value == target) {
        std::println("Solved: {} = {}", expr, value);
        return 0;
    }
    std::println("No exact solution, closest is {} = {} ({} away)", expr, value,
                 value > target ? value - target : target - value);
    return 1;
}
