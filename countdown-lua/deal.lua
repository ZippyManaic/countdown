-- Deal Countdown rounds in standard, cats and nasty-cats modes and read the mode from the command line

-- Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
local LARGE_NUMBERS = {
    standard = { 25, 50, 75, 100 },
    cats = { 25, 50, 75, 100 },
    nasty = { 12, 37, 62, 87 },
}

local USAGE = "usage: countdown [standard|cats|nasty] [LARGE]"

-- Shuffle a list in place with Fisher-Yates
local function shuffle(items)
    for i = #items, 2, -1 do
        local j = math.random(i)
        items[i], items[j] = items[j], items[i]
    end
end

-- Return a random target and six numbers with one or two large in standard mode and none to four otherwise
local function generate_round(mode, large_count)
    mode = mode or "standard"
    local target = math.random(100, 999)
    if large_count == nil then
        large_count = mode == "standard" and math.random(1, 2) or math.random(0, 4)
    end

    -- Hold two cards of each small number to match the game's deck
    local small = {}
    for i = 1, 20 do
        small[i] = (i - 1) % 10 + 1
    end
    shuffle(small)
    -- Shuffle a copy since each large number appears only once in the game
    local large = { (table.unpack or unpack)(LARGE_NUMBERS[mode]) }
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

-- Return the mode and fixed large count from the arguments, or nil when they are invalid
local function parse_args(args)
    if #args > 2 then
        return nil
    end
    local mode = args[1] or "standard"
    if not LARGE_NUMBERS[mode] then
        return nil
    end
    if #args < 2 then
        return mode, nil
    end
    local allowed = mode == "standard" and { ["1"] = 1, ["2"] = 2 }
        or { ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4 }
    local count = allowed[args[2]]
    if count == nil then
        return nil
    end
    return mode, count
end

return {
    LARGE_NUMBERS = LARGE_NUMBERS,
    USAGE = USAGE,
    generate_round = generate_round,
    parse_args = parse_args,
}
