// Check the solver against rounds with known answers
import { test } from "node:test";
import assert from "node:assert/strict";
import { solve } from "./solver.mjs";
import { generateRound } from "./countdown.mjs";

test("finds simplest solution", () => {
    assert.deepEqual(solve(125, [1, 5, 7, 3, 75, 50]), [125, "75 + 50"]);
    assert.equal(solve(552, [8, 4, 2, 5, 100, 25])[0], 552);
});

test("reports closest when unsolvable", () => {
    assert.equal(Math.abs(solve(974, [8, 8, 6, 8, 25, 100])[0] - 974), 1);
});

test("deals a valid pool", () => {
    for (let i = 0; i < 1000; i++) {
        const [target, pool] = generateRound();
        assert.ok(target >= 100 && target <= 999);
        assert.equal(pool.length, 6);
        const large = pool.filter((n) => n > 10).length;
        assert.ok(large === 1 || large === 2);
        for (let n = 1; n <= 10; n++) assert.ok(pool.filter((p) => p === n).length <= 2);
    }
});
