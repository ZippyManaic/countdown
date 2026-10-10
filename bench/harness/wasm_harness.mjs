// Time a C solver compiled to WebAssembly over a file of rounds and write each answer as value tab expression
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const TEXT = 128;
const [wasmPath, roundsPath, outPath, repsText = "1"] = process.argv.slice(2);
const { load, readText } = await import(new URL("solver.mjs", pathToFileURL(wasmPath)).href);
const wasm = load(wasmPath);
const rounds = readFileSync(roundsPath, "utf8").trim().split("\n").map((line) => line.trim().split(/\s+/).map(Number));
const reps = Number(repsText);
const n = rounds.length;

// Place every pool and answer buffer in linear memory up front so the timed loop only calls the solver
const poolsAt = wasm.malloc(4 * 6 * n), textsAt = wasm.malloc(TEXT * n);
const pools = new Uint32Array(wasm.memory.buffer, poolsAt, 6 * n);
rounds.forEach(([, ...pool], i) => pools.set(pool, 6 * i));
const targets = Int32Array.from(rounds, ([target]) => target);
const values = new Uint32Array(n);
const pass = () => {
    for (let i = 0; i < n; i++) values[i] = wasm.solve(targets[i], poolsAt + 24 * i, 6, textsAt + TEXT * i);
};

// Warm up with untimed passes so the timing measures V8's optimised tier rather than its baseline compiler
for (let k = 0; k < 3; k++) pass();
const start = process.hrtime.bigint();
for (let r = 0; r < reps; r++) pass();
const ms = Number(process.hrtime.bigint() - start) / 1e6;
console.error(`${(ms / (n * reps)).toFixed(4)} ms/round`);
writeFileSync(outPath, Array.from(values, (value, i) => `${value}\t${readText(wasm, textsAt + TEXT * i)}`).join("\n"));
