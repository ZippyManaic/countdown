// Check the dealer in every mode and the solver against rounds with known answers

#include <algorithm>
#include <cstdint>
#include <initializer_list>
#include <print>
#include <random>
#include <set>
#include <string_view>
#include <vector>

#include "round.hpp"
#include "solver.hpp"

namespace {

int failures = 0;

void expect(bool ok, const char *what)
{
    if (!ok) {
        std::println(stderr, "FAIL: {}", what);
        failures++;
    }
}

// Return the large count of a dealt round, or nothing when it breaks the rules
std::optional<std::size_t> check_round(countdown::Mode mode, std::uint32_t target, const std::vector<std::uint32_t> &pool)
{
    if (target < 100 || target > 999 || pool.size() != 6)
        return {};
    const auto &cards = countdown::large_numbers(mode);
    std::array<int, 11> small_seen{};
    std::set<std::uint32_t> large;
    for (auto n : pool) {
        if (n >= 1 && n <= 10) {
            // Reject a small number after a large one since the pool lists small cards first
            if (!large.empty() || ++small_seen[n] > 2)
                return {};
        } else if (std::ranges::find(cards, n) == cards.end() || !large.insert(n).second) {
            return {};
        }
    }
    return large.size();
}

void check_modes()
{
    using countdown::Mode;
    std::mt19937_64 rng{std::random_device{}()};
    const std::set<std::size_t> standard_counts{1, 2}, cats_counts{0, 1, 2, 3, 4};
    for (auto [mode, name] : {std::pair{Mode::standard, "standard"}, {Mode::cats, "cats"}, {Mode::nasty, "nasty"}}) {
        const auto &allowed = mode == Mode::standard ? standard_counts : cats_counts;
        std::set<std::size_t> seen;
        bool ok = true;
        for (int r = 0; r < 2000; r++) {
            auto [target, pool] = countdown::generate_round(rng, mode);
            auto count = check_round(mode, target, pool);
            ok = ok && count.has_value();
            if (count)
                seen.insert(*count);
        }
        expect(ok && seen == allowed, name);
        if (mode == Mode::standard)
            continue;
        for (std::size_t k = 0; k <= 4; k++) {
            auto [target, pool] = countdown::generate_round(rng, mode, k);
            expect(check_round(mode, target, pool) == k, "deals the fixed large count");
        }
    }
}

// Return the parse of the given arguments
std::optional<countdown::Args> parse(std::initializer_list<std::string_view> args)
{
    return countdown::parse_args(std::vector<std::string_view>(args));
}

void check_args()
{
    using countdown::Args, countdown::Mode;
    expect(parse({}) == Args{Mode::standard, {}}, "parses no arguments");
    expect(parse({"nasty", "4"}) == Args{Mode::nasty, 4}, "parses nasty 4");
    expect(parse({"cats", "0"}) == Args{Mode::cats, 0}, "parses cats 0");
    expect(!parse({"standard", "3"}), "rejects standard 3");
    expect(!parse({"cats", "5"}), "rejects cats 5");
    expect(!parse({"dogs"}), "rejects an unknown mode");
    expect(!parse({"cats", "1", "2"}), "rejects three arguments");
    expect(!parse({"cats", "x"}), "rejects a non-numeric count");
}

} // namespace

int main()
{
    auto [value, expr] = countdown::solve(125, std::vector<std::uint32_t>{1, 5, 7, 3, 75, 50});
    expect(value == 125 && expr == "75 + 50", "finds simplest solution");
    expect(countdown::solve(552, std::vector<std::uint32_t>{8, 4, 2, 5, 100, 25}).first == 552, "solves 552");
    auto closest = countdown::solve(974, std::vector<std::uint32_t>{8, 8, 6, 8, 25, 100}).first;
    expect(closest == 973 || closest == 975, "reports closest when unsolvable");
    auto lone = countdown::solve(100, std::vector<std::uint32_t>{7});
    expect(lone.first == 7 && lone.second == "7", "reports a lone number as closest");
    auto cats = countdown::solve(999, std::vector<std::uint32_t>{10, 10, 25, 50, 75, 100});
    expect(cats.first == 999 && cats.second == "(((75 + 25) * 100) - 10) / 10", "solves 999 with four large");
    auto none = countdown::solve(100, std::vector<std::uint32_t>{1, 1, 2, 2, 3, 3});
    expect(none.first == 81 && none.second == "(((2 + 1) * (2 + 1)) * 3) * 3", "reports closest with no large");
    auto nasty = countdown::solve(999, std::vector<std::uint32_t>{2, 3, 87, 62, 37, 12});
    expect(nasty.first == 999 && nasty.second == "37 * ((87 / 3) - 2)", "solves 999 with nasty large numbers");
    check_modes();
    check_args();
    if (!failures)
        std::println("all tests passed");
    return failures != 0;
}
