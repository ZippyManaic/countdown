-- Time the solver over a file of rounds and write each answer as value tab expression
local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path
local solver = require("solver")
local rounds = {}
for line in io.lines(arg[2]) do
    local r = {}
    for n in line:gmatch("%d+") do
        r[#r + 1] = tonumber(n)
    end
    rounds[#rounds + 1] = r
end
local reps = tonumber(arg[4] or "1")
local out = {}
local start = os.clock()
for _ = 1, reps do
    for i, r in ipairs(rounds) do
        local value, expr = solver.solve(r[1], { r[2], r[3], r[4], r[5], r[6], r[7] })
        out[i] = value .. "\t" .. expr
    end
end
io.stderr:write(("%.4f ms/round\n"):format((os.clock() - start) * 1000 / (#rounds * reps)))
local f = io.open(arg[3], "w")
f:write(table.concat(out, "\n"))
f:close()
