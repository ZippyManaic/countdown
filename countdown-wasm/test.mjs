// Check the dealer in every mode and the solver against rounds with known answers
import { test } from "node:test";
import assert from "node:assert/strict";
import { solve } from "./solver.mjs";
import { generateRound, parseArgs, LARGE_NUMBERS } from "./countdown.mjs";

test("finds simplest solution", () => {
    assert.deepEqual(solve(125, [1, 5, 7, 3, 75, 50]), [125, "75 + 50"]);
    assert.equal(solve(552, [8, 4, 2, 5, 100, 25])[0], 552);
});

test("reports closest when unsolvable", () => {
    assert.equal(Math.abs(solve(974, [8, 8, 6, 8, 25, 100])[0] - 974), 1);
});

// Check one dealt round against the rules of its mode and return its large count
function checkRound(mode, target, pool, counts) {
    assert.ok(target >= 100 && target <= 999);
    assert.equal(pool.length, 6);
    const large = pool.filter((n) => n > 10);
    assert.equal(new Set(large).size, large.length);
    assert.ok(large.every((n) => LARGE_NUMBERS[mode].includes(n)));
    for (let n = 1; n <= 10; n++) assert.ok(pool.filter((p) => p === n).length <= 2);
    assert.ok(counts.includes(large.length));
    return large.length;
}

test("deals valid pools in every mode", () => {
    for (const [mode, counts] of [["standard", [1, 2]], ["cats", [0, 1, 2, 3, 4]], ["nasty", [0, 1, 2, 3, 4]]]) {
        const seen = new Set();
        for (let i = 0; i < 2000; i++) seen.add(checkRound(mode, ...generateRound(mode), counts));
        assert.deepEqual([...seen].sort((a, b) => a - b), counts, mode);
    }
});

test("deals a fixed large count", () => {
    for (const mode of ["cats", "nasty"]) {
        for (let k = 0; k <= 4; k++) assert.equal(checkRound(mode, ...generateRound(mode, k), [k]), k);
    }
});

test("parses arguments", () => {
    assert.deepEqual(parseArgs([]), ["standard", null]);
    assert.deepEqual(parseArgs(["nasty", "4"]), ["nasty", 4]);
    assert.deepEqual(parseArgs(["cats", "0"]), ["cats", 0]);
    for (const bad of [["standard", "3"], ["cats", "5"], ["dogs"], ["cats", "1", "2"], ["cats", "x"]]) {
        assert.equal(parseArgs(bad), null, bad.join(" "));
    }
});

test("solves cats rounds", () => {
    assert.deepEqual(solve(999, [10, 10, 25, 50, 75, 100]), [999, "(((75 + 25) * 100) - 10) / 10"]);
    assert.deepEqual(solve(100, [1, 1, 2, 2, 3, 3]), [81, "(((2 + 1) * (2 + 1)) * 3) * 3"]);
    assert.deepEqual(solve(999, [2, 3, 87, 62, 37, 12]), [999, "37 * ((87 / 3) - 2)"]);
});

test("handles smaller pools", () => {
    assert.deepEqual(solve(7, [7]), [7, "7"]);
    assert.deepEqual(solve(12, [3, 4]), [12, "4 * 3"]);
});
