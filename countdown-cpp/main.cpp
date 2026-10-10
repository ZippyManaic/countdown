// Generate a Countdown numbers round and work out whether it can be solved

#include <print>
#include <random>
#include <string_view>
#include <vector>

#include "round.hpp"
#include "solver.hpp"

int main(int argc, char **argv)
{
    std::vector<std::string_view> args(argv + 1, argv + argc);
    auto parsed = countdown::parse_args(args);
    if (!parsed) {
        std::println(stderr, "{}", countdown::usage);
        return 2;
    }
    std::mt19937_64 rng{std::random_device{}()};
    auto [target, pool] = countdown::generate_round(rng, parsed->mode, parsed->large_count);
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
