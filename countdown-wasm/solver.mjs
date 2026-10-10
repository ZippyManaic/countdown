// Run the C solver compiled to WebAssembly and convert between JavaScript values and its linear memory
import { readFileSync, writeSync } from "node:fs";

const TEXT = 128;

// Give the module the few WASI calls the C library links in for reporting allocation failure
function wasiImports(memory) {
    return {
        wasi_snapshot_preview1: {
            fd_write(fd, iovs, count, written) {
                const view = new DataView(memory().buffer);
                let total = 0;
                for (let i = 0; i < count; i++) {
                    const base = view.getUint32(iovs + 8 * i, true), length = view.getUint32(iovs + 8 * i + 4, true);
                    writeSync(fd === 1 ? 1 : 2, new Uint8Array(memory().buffer, base, length));
                    total += length;
                }
                view.setUint32(written, total, true);
                return 0;
            },
            fd_close: () => 0,
            // Report seeking as unsupported since the solver only ever writes to standard error
            fd_seek: () => 70,
            proc_exit(code) {
                throw new Error(`solver exited with code ${code}`);
            },
        },
    };
}

// Instantiate a solver module synchronously and return its exports
export function load(path = new URL("./solver.wasm", import.meta.url)) {
    let exports;
    const module = new WebAssembly.Module(readFileSync(path));
    exports = new WebAssembly.Instance(module, wasiImports(() => exports.memory)).exports;
    exports._initialize?.();
    return exports;
}

let wasm;
const decoder = new TextDecoder();

// Return the text the solver wrote at a pointer up to its terminating zero
export function readText(exports, pointer) {
    const bytes = new Uint8Array(exports.memory.buffer, pointer, TEXT);
    return decoder.decode(bytes.subarray(0, bytes.indexOf(0)));
}

// Return the simplest expression that hits the target or gets closest to it, with its value
export function solve(target, pool) {
    // Load the module on first use so importing this file for load alone needs no solver.wasm beside it
    wasm ??= load();
    const poolAt = wasm.malloc(4 * pool.length), textAt = wasm.malloc(TEXT);
    new Uint32Array(wasm.memory.buffer, poolAt, pool.length).set(pool);
    const value = wasm.solve(target, poolAt, pool.length, textAt);
    const expr = readText(wasm, textAt);
    wasm.free(poolAt);
    wasm.free(textAt);
    return [value, expr];
}
