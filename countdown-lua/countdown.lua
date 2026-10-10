-- Generate a Countdown numbers round and work out whether it can be solved

local here = arg[0]:match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local solver = require("solver")
local deal = require("deal")

local mode, large_count = deal.parse_args({ ... })
if mode == nil then
    io.stderr:write(deal.USAGE .. "\n")
    os.exit(2)
end

-- Seed explicitly since LuaJIT starts from a fixed seed
math.randomseed(os.time() + math.floor(os.clock() * 1e6))
local target, pool = deal.generate_round(mode, large_count)
print("Target: " .. target)
print("Pool:   " .. table.concat(pool, " "))

local value, expr = solver.solve(target, pool)
if value == target then
    print("Solved: " .. expr .. " = " .. value)
    os.exit(0)
end
print(("No exact solution, closest is %s = %d (%d away)"):format(expr, value, math.abs(value - target)))
os.exit(1)
