// Check the solver against rounds with known answers

#include <cstdint>
#include <print>
#include <vector>

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

} // namespace

int main()
{
    auto [value, expr] = countdown::solve(125, std::vector<std::uint32_t>{1, 5, 7, 3, 75, 50});
    expect(value == 125 && expr == "75 + 50", "finds simplest solution");
    expect(countdown::solve(552, std::vector<std::uint32_t>{8, 4, 2, 5, 100, 25}).first == 552, "solves 552");
    auto closest = countdown::solve(974, std::vector<std::uint32_t>{8, 8, 6, 8, 25, 100}).first;
    expect(closest == 973 || closest == 975, "reports closest when unsolvable");
    if (!failures)
        std::println("all tests passed");
    return failures != 0;
}
