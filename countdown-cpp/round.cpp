// Deal Countdown rounds in the standard, cats and nasty-cats modes and read the mode from the command line

#include "round.hpp"

#include <algorithm>

namespace countdown {

namespace {

// Give nasty-cats the large cards of the 2010 specials
constexpr std::array<std::uint32_t, 4> standard_large{25, 50, 75, 100};
constexpr std::array<std::uint32_t, 4> nasty_large{12, 37, 62, 87};

} // namespace

const std::array<std::uint32_t, 4> &large_numbers(Mode mode)
{
    return mode == Mode::nasty ? nasty_large : standard_large;
}

std::pair<std::uint32_t, std::vector<std::uint32_t>> generate_round(std::mt19937_64 &rng, Mode mode,
                                                                    std::optional<std::size_t> large_count)
{
    auto target = std::uniform_int_distribution<std::uint32_t>{100, 999}(rng);
    auto count = large_count ? *large_count
                 : mode == Mode::standard ? std::uniform_int_distribution<std::size_t>{1, 2}(rng)
                                          : std::uniform_int_distribution<std::size_t>{0, 4}(rng);

    // Hold two cards of each small number to match the game's deck
    std::vector<std::uint32_t> small;
    for (std::uint32_t n = 1; n <= 20; n++)
        small.push_back((n - 1) % 10 + 1);
    std::ranges::shuffle(small, rng);
    // Shuffle a copy since each large number appears only once in the game
    auto large = large_numbers(mode);
    std::ranges::shuffle(large, rng);

    std::vector pool(small.begin(), small.begin() + static_cast<std::ptrdiff_t>(6 - count));
    pool.insert(pool.end(), large.begin(), large.begin() + static_cast<std::ptrdiff_t>(count));
    return {target, pool};
}

std::optional<Args> parse_args(std::span<const std::string_view> args)
{
    if (args.size() > 2)
        return {};
    Args parsed{Mode::standard, {}};
    if (args.empty())
        return parsed;
    if (args[0] == "cats")
        parsed.mode = Mode::cats;
    else if (args[0] == "nasty")
        parsed.mode = Mode::nasty;
    else if (args[0] != "standard")
        return {};
    if (args.size() == 1)
        return parsed;
    // Accept only a single digit so that signs, spaces and trailing text are rejected
    auto count = args[1];
    if (count.size() != 1 || count[0] < '0' || count[0] > '9')
        return {};
    std::size_t n = static_cast<std::size_t>(count[0] - '0');
    if (parsed.mode == Mode::standard ? n < 1 || n > 2 : n > 4)
        return {};
    parsed.large_count = n;
    return parsed;
}

} // namespace countdown
