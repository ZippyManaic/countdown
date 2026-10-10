#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <utility>

namespace countdown {

// Return the simplest expression that hits the target or gets closest to it with its value
std::pair<std::uint32_t, std::string> solve(std::uint32_t target, std::span<const std::uint32_t> pool);

}
