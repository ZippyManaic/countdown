// Deal Countdown rounds in the standard, cats and nasty-cats modes and read the mode from the command line

#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <random>
#include <span>
#include <string_view>
#include <utility>
#include <vector>

namespace countdown {

enum class Mode { standard, cats, nasty };

struct Args {
    Mode mode;
    // Leave the large count empty to choose it at random
    std::optional<std::size_t> large_count;

    bool operator==(const Args &) const = default;
};

inline constexpr std::string_view usage = "usage: countdown [standard|cats|nasty] [LARGE]";

// Return the four large cards a mode deals from
const std::array<std::uint32_t, 4> &large_numbers(Mode mode);

// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
std::pair<std::uint32_t, std::vector<std::uint32_t>> generate_round(std::mt19937_64 &rng, Mode mode = Mode::standard,
                                                                    std::optional<std::size_t> large_count = {});

// Return the mode and fixed large count from the arguments after the program name, or nothing when they are invalid
std::optional<Args> parse_args(std::span<const std::string_view> args);

} // namespace countdown
