-- Work out the simplest Countdown expression that hits a target or gets closest to it
-- Run unchanged on Lua 5.4 and LuaJIT by avoiding the bitwise and floor division operators LuaJIT cannot parse

local floor, sort, abs = math.floor, table.sort, math.abs

-- Presize hash tables on LuaJIT and fall back to plain tables on Lua 5.4 which has no table.new
local ok, table_new = pcall(require, "table.new")
if not ok then
    table_new = function() return {} end
end

-- Encode operators so an origin packs into one number as larger * 256 + larger mask * 4 + operator
local ADD, SUB, MUL, DIV = 0, 1, 2, 3
local OP_TEXT = { [0] = "+", "-", "*", "/" }

local RADIX = 2048
local INSERTION_MAX = 48

-- Sort count numbers from first upwards in place by insertion which suits short runs
local function insertion_sort(list, first, last)
    for i = first + 1, last do
        local v = list[i]
        local k = i - 1
        while k >= first and list[k] > v do
            list[k + 1] = list[k]
            k = k - 1
        end
        list[k + 1] = v
    end
end

-- Sort count positive integers in place a digit of base RADIX at a time using scratch tables for buckets and output
local function radix_sort(list, count, buckets, scratch)
    if count <= INSERTION_MAX then
        insertion_sort(list, 1, count)
        return
    end
    local largest = 0
    for i = 1, count do
        if list[i] > largest then
            largest = list[i]
        end
    end
    -- Multiply by the exact reciprocal of each power of two since it is cheaper than dividing
    local from, to, place, inv = list, scratch, 1, 1
    while place <= largest do
        for d = 0, RADIX - 1 do
            buckets[d] = 0
        end
        for i = 1, count do
            local d = floor(from[i] * inv) % RADIX
            buckets[d] = buckets[d] + 1
        end
        local sum = 1
        for d = 0, RADIX - 1 do
            local c = buckets[d]
            buckets[d] = sum
            sum = sum + c
        end
        for i = 1, count do
            local v = from[i]
            local d = floor(v * inv) % RADIX
            to[buckets[d]] = v
            buckets[d] = buckets[d] + 1
        end
        from, to = to, from
        place = place * RADIX
        inv = inv / RADIX
    end
    -- Copy back when an odd number of passes left the result in the scratch table
    if from ~= list then
        for i = 1, count do
            list[i] = from[i]
        end
    end
end

-- Sort with radix on LuaJIT which compiles it and with table.sort on Lua 5.4 where the C sort beats interpreted code
local sort_values
if jit then
    sort_values = radix_sort
else
    sort_values = function(list)
        sort(list)
    end
end

-- Return whether bit i (from zero) of n is set using arithmetic that both runtimes share
local function has_bit(n, i)
    return floor(n / 2 ^ i) % 2 == 1
end

-- Return each subset's size, its splits flattened as left then right in visiting order and the subsets by size
local function subsets(n)
    local full = floor(2 ^ n - 1)
    local sizes, splits, by_size = {}, {}, {}
    for size = 1, n do
        by_size[size] = {}
    end
    for mask = 1, full do
        local size = 0
        for i = 0, n - 1 do
            if has_bit(mask, i) then
                size = size + 1
            end
        end
        sizes[mask] = size
        local list = by_size[size]
        list[#list + 1] = mask
        -- List every submask from mask - 1 down to 1 since this is the order (left - 1) & mask visits them
        local flat = {}
        for left = mask - 1, 1, -1 do
            local inside = true
            for i = 0, n - 1 do
                if has_bit(left, i) and not has_bit(mask, i) then
                    inside = false
                    break
                end
            end
            -- Visit each split once rather than once per ordering
            if inside and left < mask - left then
                flat[#flat + 1] = left
                flat[#flat + 1] = mask - left
            end
        end
        splits[mask] = flat
    end
    return full, sizes, splits, by_size
end

-- Return how the target is first made from a subset as a packed origin without building all of its values
local function find_exact(values, origins, splits, mask, target)
    local split = splits[mask]
    for s = 1, #split, 2 do
        local left, right = split[s], split[s + 1]
        local lefts, rights = values[left], values[right]
        -- Loop over the smaller half and look up the larger for the lowest pair building would yield
        local left_loop = #lefts <= #rights
        local loop, search = lefts, origins[right]
        if not left_loop then
            loop, search = rights, origins[left]
        end
        -- Keep the lowest partner then operator since partners are tried in operator order and ties keep the first
        local best_n, best_m, best_op
        for i = 1, #loop do
            local n = loop[i]
            -- Try each number that combines with n to make the target in operator order
            local m
            if target > n then
                m = target - n
                if search[m] ~= nil and (not best_m or m < best_m) then
                    best_n, best_m, best_op = n, m, ADD
                end
            end
            if n > target then
                m = n - target
                if search[m] ~= nil and (not best_m or m < best_m) then
                    best_n, best_m, best_op = n, m, SUB
                end
            end
            m = n + target
            if search[m] ~= nil and (not best_m or m < best_m) then
                best_n, best_m, best_op = n, m, SUB
            end
            -- Divide only when the quotient could be at least two since neither operand may be one
            if n ~= 1 and 2 * n <= target and target % n == 0 then
                m = floor(target / n)
                if search[m] ~= nil and (not best_m or m < best_m) then
                    best_n, best_m, best_op = n, m, MUL
                end
            end
            if n >= 2 * target and n % target == 0 then
                m = floor(n / target)
                if search[m] ~= nil and (not best_m or m < best_m) then
                    best_n, best_m, best_op = n, m, DIV
                end
            end
            if n ~= 1 then
                m = n * target
                if search[m] ~= nil and (not best_m or m < best_m) then
                    best_n, best_m, best_op = n, m, DIV
                end
            end
            -- Take the first left value with any partner since left values ascend and the lowest partner wins
            if best_m and left_loop then
                break
            end
        end
        if best_m then
            local a, b = best_n, best_m
            if not left_loop then
                a, b = best_m, best_n
            end
            if a >= b then
                return a * 256 + left * 4 + best_op
            end
            return b * 256 + right * 4 + best_op
        end
    end
    return nil
end

-- Return the smaller operand of a value made from a larger operand with an operator
local function smaller_of(value, larger, op)
    if op == ADD then
        return value - larger
    elseif op == SUB then
        return larger - value
    elseif op == MUL then
        return floor(value / larger)
    end
    return floor(larger / value)
end

-- Rebuild the expression for a value made from subset mask by following packed origins back to the pool
local function render(origins, mask, value, origin, bracket)
    if origin == 0 then
        return tostring(value)
    end
    local op = origin % 4
    local larger_mask = floor(origin / 4) % 64
    local larger = floor(origin / 256)
    local smaller_mask = mask - larger_mask
    local smaller = smaller_of(value, larger, op)
    local text = render(origins, larger_mask, larger, origins[larger_mask][larger], true) .. " " .. OP_TEXT[op] ..
        " " .. render(origins, smaller_mask, smaller, origins[smaller_mask][smaller], true)
    if bracket then
        return "(" .. text .. ")"
    end
    return text
end

local cache = {}

-- Return the simplest expression that hits the target or gets closest to it with its value
local function solve(target, pool)
    local n = #pool
    if not cache[n] then
        cache[n] = { subsets(n) }
    end
    local full, sizes, splits, by_size = cache[n][1], cache[n][2], cache[n][3], cache[n][4]
    -- Map each subset of the pool (as a bitmask) to its values sorted ascending and to each value's packed origin
    local values, origins = {}, {}
    for mask = 1, full do
        values[mask], origins[mask] = {}, {}
    end
    local exact_mask, exact_origin
    local buckets, scratch = table_new(RADIX, 0), {}

    -- Store each pool number as a one-number subset with origin zero
    local mask = 1
    for i = 1, n do
        local v = pool[i]
        values[mask], origins[mask] = { v }, { [v] = 0 }
        if v == target and not exact_mask then
            exact_mask, exact_origin = mask, 0
        end
        mask = mask * 2
    end

    -- Work through subsets smallest first stopping at the first size that hits the target
    for size = 2, n do
        if exact_mask then
            break
        end
        local masks = by_size[size]
        -- Keep the lowest matching subset of this size to break ties the same way every run
        for k = 1, #masks do
            local origin = find_exact(values, origins, splits, masks[k], target)
            if origin then
                exact_mask, exact_origin = masks[k], origin
                break
            end
        end
        -- Skip building the whole pool's values since no larger subset is made from them
        if exact_mask or size == n then
            break
        end
        for k = 1, #masks do
            local m = masks[k]
            -- Keep only the first way found to make each value so duplicates never reach the sort
            local split = splits[m]
            -- Presize for twice the pairs since LuaJIT's hash collides heavily when nearly full
            local pairs_count = 0
            for s = 1, #split, 2 do
                pairs_count = pairs_count + #values[split[s]] * #values[split[s + 1]]
            end
            local list, count, seen = table_new(floor(pairs_count * 2), 0), 0, table_new(0, floor(pairs_count * 2))
            for s = 1, #split, 2 do
                local left, right = split[s], split[s + 1]
                local lefts, rights = values[left], values[right]
                local nr = #rights
                local left_code, right_code = left * 4, right * 4
                for i = 1, #lefts do
                    local a = lefts[i]
                    local j = 1
                    -- Pair with right values up to a first where a is the larger and ties go left
                    while j <= nr do
                        local b = rights[j]
                        if b > a then
                            break
                        end
                        local base = a * 256 + left_code
                        local v = a + b
                        if seen[v] == nil then
                            seen[v] = base + ADD
                            count = count + 1
                            list[count] = v
                        end
                        -- Skip a zero result since every intermediate value must be a positive integer
                        if a ~= b then
                            v = a - b
                            if seen[v] == nil then
                                seen[v] = base + SUB
                                count = count + 1
                                list[count] = v
                            end
                        end
                        -- Skip multiplying and dividing by one as they never produce a new value
                        if b ~= 1 then
                            v = a * b
                            if seen[v] == nil then
                                seen[v] = base + MUL
                                count = count + 1
                                list[count] = v
                            end
                            if a % b == 0 then
                                v = floor(a / b)
                                if seen[v] == nil then
                                    seen[v] = base + DIV
                                    count = count + 1
                                    list[count] = v
                                end
                            end
                        end
                        j = j + 1
                    end
                    -- Pair with the remaining larger right values where a is the smaller
                    while j <= nr do
                        local b = rights[j]
                        local base = b * 256 + right_code
                        local v = b + a
                        if seen[v] == nil then
                            seen[v] = base + ADD
                            count = count + 1
                            list[count] = v
                        end
                        v = b - a
                        if seen[v] == nil then
                            seen[v] = base + SUB
                            count = count + 1
                            list[count] = v
                        end
                        if a ~= 1 then
                            v = b * a
                            if seen[v] == nil then
                                seen[v] = base + MUL
                                count = count + 1
                                list[count] = v
                            end
                            if b % a == 0 then
                                v = floor(b / a)
                                if seen[v] == nil then
                                    seen[v] = base + DIV
                                    count = count + 1
                                    list[count] = v
                                end
                            end
                        end
                        j = j + 1
                    end
                end
            end
            sort_values(list, count, buckets, scratch)
            values[m], origins[m] = list, seen
        end
    end

    local value_mask, value, origin = exact_mask, target, exact_origin
    if not value_mask then
        -- Rank by distance from the target then by how many numbers are used so the simplest answer wins
        local best_distance, best_used
        -- Include a one-number pool here since the whole-pool pass below needs at least two numbers
        for m = 1, n > 1 and full - 1 or full do
            local used = sizes[m]
            local list = values[m]
            for i = 1, #list do
                local d = abs(list[i] - target)
                if not best_distance or d < best_distance or (d == best_distance and used < best_used) then
                    value_mask, value, best_distance, best_used = m, list[i], d, used
                end
            end
        end
        origin = origins[value_mask][value]

        -- Check the whole pool's values as they are made since no larger subset is built from them
        if n > 1 then
            local whole, whole_origin, whole_distance
            local split = splits[full]
            for s = 1, #split, 2 do
                local left, right = split[s], split[s + 1]
                local lefts, rights = values[left], values[right]
                for i = 1, #lefts do
                    local a = lefts[i]
                    for j = 1, #rights do
                        local b = rights[j]
                        local x, y, base = a, b, a * 256 + left * 4
                        if b > a then
                            x, y, base = b, a, b * 256 + right * 4
                        end
                        -- Try each result in operator order preferring the lower value on equal distance
                        for op = ADD, DIV do
                            local v
                            if op == ADD then
                                v = x + y
                            elseif op == SUB then
                                v = x > y and x - y or nil
                            elseif op == MUL then
                                v = y ~= 1 and x * y or nil
                            else
                                v = y ~= 1 and x % y == 0 and floor(x / y) or nil
                            end
                            if v then
                                local d = abs(v - target)
                                if not whole_distance or d < whole_distance or (d == whole_distance and v < whole) then
                                    whole, whole_origin, whole_distance = v, base + op, d
                                end
                            end
                        end
                    end
                end
            end
            -- Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            if whole_distance and whole_distance < best_distance then
                value_mask, value, origin = full, whole, whole_origin
            end
        end
    end

    -- Render without outer brackets which matches stripping them from the bracketed form
    return value, render(origins, value_mask, value, origin, false)
end

return { solve = solve }
