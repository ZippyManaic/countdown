// Time the solver in a JavaScript module over a file of rounds and write each answer as value tab expression
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const [solverPath, roundsPath, outPath, repsText = "1"] = process.argv.slice(2);
const { solve } = await import(pathToFileURL(solverPath).href);
const rounds = readFileSync(roundsPath, "utf8").trim().split("\n").map((line) => line.trim().split(/\s+/).map(Number));
const reps = Number(repsText);
// Warm up with untimed passes so the timing measures fully compiled code rather than the JIT compiling it
for (let pass = 0; pass < 3; pass++) for (const [target, ...pool] of rounds) solve(target, pool);
const out = new Array(rounds.length);
const start = process.hrtime.bigint();
for (let r = 0; r < reps; r++) {
    for (let i = 0; i < rounds.length; i++) out[i] = solve(rounds[i][0], rounds[i].slice(1));
}
const ms = Number(process.hrtime.bigint() - start) / 1e6;
console.error(`${(ms / (rounds.length * reps)).toFixed(4)} ms/round`);
writeFileSync(outPath, out.map(([value, expr]) => `${value}\t${expr}`).join("\n"));
