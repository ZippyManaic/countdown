// Generate a Countdown numbers round and work out whether it can be solved
import { randomInt } from "node:crypto";
import { solve } from "./solver.mjs";

const LARGE_NUMBERS = [25, 50, 75, 100];

// Shuffle a list in place with Fisher-Yates
function shuffle(items) {
    for (let i = items.length - 1; i > 0; i--) {
        const j = randomInt(i + 1);
        [items[i], items[j]] = [items[j], items[i]];
    }
}

// Return a random target and a pool of six numbers with either one or two large numbers
export function generateRound() {
    const target = randomInt(100, 1000);
    const largeCount = randomInt(1, 3);
    // Hold two cards of each small number to match the game's deck
    const small = Array.from({ length: 20 }, (_, i) => (i % 10) + 1);
    shuffle(small);
    // Shuffle a copy since each large number appears only once in the game
    const large = [...LARGE_NUMBERS];
    shuffle(large);
    return [target, [...small.slice(0, 6 - largeCount), ...large.slice(0, largeCount)]];
}

if (import.meta.main ?? process.argv[1]?.endsWith("countdown.mjs")) {
    const [target, pool] = generateRound();
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
