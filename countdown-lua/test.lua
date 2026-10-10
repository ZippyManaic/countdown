-- Check the solver against rounds with known answers

local here = arg[0]:match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local solver = require("solver")

local failures = 0

local function expect(ok, what)
    if not ok then
        print("FAIL: " .. what)
        failures = failures + 1
    end
end

local value, expr = solver.solve(125, { 1, 5, 7, 3, 75, 50 })
expect(value == 125 and expr == "75 + 50", "finds simplest solution")
expect(solver.solve(552, { 8, 4, 2, 5, 100, 25 }) == 552, "solves 552")
value = solver.solve(974, { 8, 8, 6, 8, 25, 100 })
expect(math.abs(value - 974) == 1, "reports closest when unsolvable")

local deal = require("deal")

-- Check one dealt round and return its large count
local function check_round(mode, target, pool, counts, what)
    expect(target >= 100 and target <= 999, what .. ": target in range")
    expect(#pool == 6, what .. ": six numbers")
    local seen, large = {}, 0
    local allowed = {}
    for _, n in ipairs(deal.LARGE_NUMBERS[mode]) do
        allowed[n] = true
    end
    for _, n in ipairs(pool) do
        seen[n] = (seen[n] or 0) + 1
        if n > 10 then
            large = large + 1
            expect(allowed[n], what .. ": large number from the mode's set")
            expect(seen[n] == 1, what .. ": large numbers distinct")
        else
            -- Allow each small number at most twice since the deck holds two of each
            expect(seen[n] <= 2, what .. ": small number at most twice")
        end
    end
    expect(counts[large], what .. ": large count allowed")
    return large
end

math.randomseed(1)
for _, case in ipairs({
    { "standard", { [1] = true, [2] = true } },
    { "cats", { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true } },
    { "nasty", { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true } },
}) do
    local mode, counts = case[1], case[2]
    local seen = {}
    for _ = 1, 2000 do
        local target, pool = deal.generate_round(mode)
        seen[check_round(mode, target, pool, counts, mode)] = true
    end
    for k in pairs(counts) do
        expect(seen[k], mode .. ": every large count occurs")
    end
end

for _, mode in ipairs({ "cats", "nasty" }) do
    for k = 0, 4 do
        local target, pool = deal.generate_round(mode, k)
        expect(check_round(mode, target, pool, { [k] = true }, mode .. " fixed") == k, mode .. ": fixed count " .. k)
    end
end

local m, c = deal.parse_args({})
expect(m == "standard" and c == nil, "parses no arguments")
m, c = deal.parse_args({ "nasty", "4" })
expect(m == "nasty" and c == 4, "parses nasty 4")
m, c = deal.parse_args({ "cats", "0" })
expect(m == "cats" and c == 0, "parses cats 0")
for _, bad in ipairs({ { "standard", "3" }, { "cats", "5" }, { "dogs" }, { "cats", "1", "2" }, { "cats", "x" } }) do
    expect(deal.parse_args(bad) == nil, "rejects " .. table.concat(bad, " "))
end

value, expr = solver.solve(999, { 10, 10, 25, 50, 75, 100 })
expect(value == 999 and expr == "(((75 + 25) * 100) - 10) / 10", "solves cats round 999")
value, expr = solver.solve(100, { 1, 1, 2, 2, 3, 3 })
expect(value == 81 and expr == "(((2 + 1) * (2 + 1)) * 3) * 3", "reports closest on cats round with no large")
value, expr = solver.solve(999, { 2, 3, 87, 62, 37, 12 })
expect(value == 999 and expr == "37 * ((87 / 3) - 2)", "solves nasty round 999")
if failures > 0 then
    os.exit(1)
end
print("all tests passed")
