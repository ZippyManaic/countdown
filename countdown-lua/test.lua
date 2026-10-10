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
if failures > 0 then
    os.exit(1)
end
print("all tests passed")
