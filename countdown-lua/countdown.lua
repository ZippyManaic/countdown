-- Generate a Countdown numbers round and work out whether it can be solved

local here = arg[0]:match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local solver = require("solver")

local LARGE_NUMBERS = { 25, 50, 75, 100 }

-- Shuffle a list in place with Fisher-Yates
local function shuffle(items)
    for i = #items, 2, -1 do
        local j = math.random(i)
        items[i], items[j] = items[j], items[i]
    end
end

-- Return a random target and a pool of six numbers with either one or two large numbers
local function generate_round()
    local target = math.random(100, 999)
    local large_count = math.random(1, 2)

    -- Hold two cards of each small number to match the game's deck
    local small = {}
    for i = 1, 20 do
        small[i] = (i - 1) % 10 + 1
    end
    shuffle(small)
    -- Shuffle a copy since each large number appears only once in the game
    local large = { (table.unpack or unpack)(LARGE_NUMBERS) }
    shuffle(large)

    local pool = {}
    for i = 1, 6 - large_count do
        pool[#pool + 1] = small[i]
    end
    for i = 1, large_count do
        pool[#pool + 1] = large[i]
    end
    return target, pool
end

-- Seed explicitly since LuaJIT starts from a fixed seed
math.randomseed(os.time() + math.floor(os.clock() * 1e6))
local target, pool = generate_round()
print("Target: " .. target)
print("Pool:   " .. table.concat(pool, " "))

local value, expr = solver.solve(target, pool)
if value == target then
    print("Solved: " .. expr .. " = " .. value)
    os.exit(0)
end
print(("No exact solution, closest is %s = %d (%d away)"):format(expr, value, math.abs(value - target)))
os.exit(1)
