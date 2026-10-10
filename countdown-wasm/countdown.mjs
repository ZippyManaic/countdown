// Generate a Countdown numbers round and work out whether it can be solved with the WebAssembly solver
import { randomInt } from "node:crypto";
import { solve } from "./solver.mjs";

// Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
export const LARGE_NUMBERS = { standard: [25, 50, 75, 100], cats: [25, 50, 75, 100], nasty: [12, 37, 62, 87] };
export const USAGE = "usage: countdown [standard|cats|nasty] [LARGE]";

// Shuffle a list in place with Fisher-Yates
function shuffle(items) {
    for (let i = items.length - 1; i > 0; i--) {
        const j = randomInt(i + 1);
        [items[i], items[j]] = [items[j], items[i]];
    }
}

// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
export function generateRound(mode = "standard", largeCount = null) {
    const target = randomInt(100, 1000);
    largeCount ??= mode === "standard" ? randomInt(1, 3) : randomInt(0, 5);
    // Hold two cards of each small number to match the game's deck
    const small = Array.from({ length: 20 }, (_, i) => (i % 10) + 1);
    shuffle(small);
    // Shuffle a copy since each large number appears only once in the game
    const large = [...LARGE_NUMBERS[mode]];
    shuffle(large);
    return [target, [...small.slice(0, 6 - largeCount), ...large.slice(0, largeCount)]];
}

// Return the mode and fixed large count from the command line, or null when the arguments are invalid
export function parseArgs(args) {
    if (args.length > 2) return null;
    const mode = args[0] ?? "standard";
    if (!Object.hasOwn(LARGE_NUMBERS, mode)) return null;
    if (args.length < 2) return [mode, null];
    const allowed = mode === "standard" ? ["1", "2"] : ["0", "1", "2", "3", "4"];
    return allowed.includes(args[1]) ? [mode, Number(args[1])] : null;
}

if (import.meta.main ?? process.argv[1]?.endsWith("countdown.mjs")) {
    const parsed = parseArgs(process.argv.slice(2));
    if (parsed === null) {
        console.error(USAGE);
        process.exit(2);
    }
    const [target, pool] = generateRound(...parsed);
    console.log(`Target: ${target}`);
    console.log(`Pool:   ${pool.join(" ")}`);
    const [value, expr] = solve(target, pool);
    if (value === target) {
        console.log(`Solved: ${expr} = ${value}`);
    } else {
        console.log(`No exact solution, closest is ${expr} = ${value} (${Math.abs(value - target)} away)`);
        process.exitCode = 1;
    }
}
