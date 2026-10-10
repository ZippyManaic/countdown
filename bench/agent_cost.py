#!/usr/bin/env python3
# Estimate the Claude tokens and time spent on each solution from this project's Claude Code transcripts
#
# Usage: bench/agent_cost.py [transcript-dir]
#
# Charge each main-session response to the solutions its tool calls touch and split it evenly between them
# Charge each subagent response to the solutions named in the subagent's description
# Report everything else as general work such as the paper, the notes and discussion
import bisect
import collections
from datetime import datetime
import glob
import json
import os
import re
import sys

# Map each project directory suffix to the bench/run.sh name it belongs to
DIRS = {
    "rs": "rust", "rs-par": "rust-par", "c-par": "c-par", "go-par": "go-par", "java-par": "java-par",
    "julia-par": "julia-par", "erlang-par": "erlang-par", "elixir-par": "elixir-par",
}
for name in ("table ml cuda torch asm c cpp zig go fortran pascal cobol lua forth js ada java csharp swift "
             "wasm fsharp kotlin ruby lisp haskell ocaml freebasic basic julia erlang elixir ispc").split():
    DIRS[name] = name
# Map each language-specific harness file to its solution, leaving the shared C harness unattributed
HARNESSES = {
    "python_harness": "python", "torch_harness": "torch", "rust_harness": "rust", "cuda_harness": "cuda",
    "zig_harness": "zig", "go_harness": "go", "go_par_harness": "go-par", "pascal_harness": "pascal",
    "cobol_harness": "cobol", "lua_harness": "lua", "forth_harness": "forth", "js_harness": "js",
    "swift_harness": "swift", "harness/csharp": "csharp", "JavaHarness": "java", "ada_harness": "ada",
    "wasm_harness": "wasm", "harness/fsharp": "fsharp", "KotlinHarness": "kotlin", "ruby_harness": "ruby",
    "lisp_harness": "lisp", "haskell_harness": "haskell", "ocaml_harness": "ocaml",
    "freebasic_harness": "freebasic", "basic_harness": "basic", "julia_harness": "julia",
    "julia_par_harness": "julia-par", "erlang_harness": "erlang", "erlang_par_harness": "erlang-par",
    "JavaParHarness": "java-par", "elixir_harness": "elixir", "elixir_par_harness": "elixir-par",
}
# Fold run.sh variants into the solution whose code they run
ALIASES = {"luajit": "lua", "gforth": "forth", "rubyjit": "ruby", "rust-par1": "rust-par"}
RUN_NAMES = set(DIRS.values()) | set(ALIASES) | {"python"}
# Name the solutions each subagent was asked to write when its own tool calls do not say
AGENT_TOPICS = {
    "FreeBASIC and classic BASIC": ["freebasic", "basic"], "Haskell and OCaml": ["haskell", "ocaml"],
    "F# and Kotlin": ["fsharp", "kotlin"], "Ruby and Common Lisp": ["ruby", "lisp"],
    "WebAssembly version": ["wasm"], "Julia implementation": ["julia"], "Erlang implementation": ["erlang"],
    "Elixir implementation": ["elixir"], "Parallel C solver": ["c-par"], "Parallel Go solver": ["go-par"],
    "Parallel Rust solver": ["rust-par"], "Parallel Java solver": ["java-par"],
    "Parallel Julia solver": ["julia-par"], "Parallel Erlang solver": ["erlang-par"],
    "Parallel Elixir solver": ["elixir-par"], "Erlang single-core to Elixir design": ["erlang"],
    "Erlang parallel to Elixir-par design": ["erlang-par"], "ISPC implementation": ["ispc"], "Fix elixir-par 32-thread hang": ["elixir-par"],
}
DIR_RE = re.compile(r"countdown-(rs-par|c-par|go-par|java-par|julia-par|erlang-par|elixir-par|[a-z]+)\b")
PY_RE = re.compile(r"((?:[\w.~-]+/)*)countdown\.py\b")
RUN_RE = re.compile(r"(?:run|scale)\.sh((?:\s+(?:-n\s+\d+|--whole|[a-z0-9-]+))+)")
# Cap the time charged to one response so idle gaps between user messages are not counted
MAX_GAP = 15 * 60


def solutions(tool_inputs):
    found = set()
    for text in tool_inputs:
        found |= {DIRS[m] for m in DIR_RE.findall(text) if m in DIRS}
        for prefix in PY_RE.findall(text):
            if not re.search(r"countdown-[\w-]+/$", prefix):
                found.add("python")
        found |= {lang for key, lang in HARNESSES.items() if key in text}
        for args in RUN_RE.findall(text):
            found |= {ALIASES.get(a, a) for a in args.split() if a in RUN_NAMES}
    return found


def parse_time(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()


def read(path, topics, seen):
    entries, records = [], []
    for line in open(path):
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    # Group the content blocks of each response, which the transcript stores one per line with growing usage
    responses = collections.OrderedDict()
    # Mark where each response starts and where the user typed, to bound the time charged to a response
    starts, prompts = [], []
    for e in entries:
        m = e.get("message")
        if not isinstance(m, dict) or not e.get("timestamp"):
            continue
        t = parse_time(e["timestamp"])
        if m.get("role") == "user" and isinstance(m.get("content"), str):
            prompts.append(t)
        if m.get("role") != "assistant" or "usage" not in m:
            continue
        if m["id"] not in responses:
            responses[m["id"]] = {"time": t, "inputs": [], "visible": 0, "hidden": 0}
            starts.append(t)
        r = responses[m["id"]]
        r["usage"] = m["usage"]
        for block in m.get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                r["inputs"].append(json.dumps(block.get("input")))
                r["visible"] += len(r["inputs"][-1])
            elif block.get("type") == "text":
                r["visible"] += len(block.get("text", ""))
            elif block.get("type") == "thinking":
                r["hidden"] += len(block.get("thinking", "")) + len(block.get("signature", ""))
    starts.sort()
    prompts.sort()
    for rid, r in responses.items():
        if rid in seen:
            continue
        seen.add(rid)
        # Charge subagents only to their own solutions since they also read other projects to port them
        touched = solutions(r["inputs"])
        langs = (touched & set(topics) or set(topics)) if topics else touched or {"(general)"}
        u = r["usage"]
        # Charge the time until the next response or user message, which covers generating and running tools
        t = r["time"]
        ends = [t + MAX_GAP]
        i = bisect.bisect_right(starts, t)
        if i < len(starts):
            ends.append(starts[i])
        j = bisect.bisect_right(prompts, t)
        if j < len(prompts):
            ends.append(prompts[j])
        records.append({
            "langs": langs, "agent": bool(topics), "output": u.get("output_tokens", 0),
            "input": u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
            + u.get("cache_read_input_tokens", 0),
            "visible": r["visible"], "hidden": r["hidden"], "seconds": min(ends) - t,
        })
    return records


def calibrate(records):
    # Fit output tokens to visible and hidden characters by least squares without an intercept
    sxx = sum(r["visible"] ** 2 for r in records)
    syy = sum(r["hidden"] ** 2 for r in records)
    sxy = sum(r["visible"] * r["hidden"] for r in records)
    sx = sum(r["visible"] * r["output"] for r in records)
    sy = sum(r["hidden"] * r["output"] for r in records)
    det = sxx * syy - sxy * sxy
    return (sx * syy - sy * sxy) / det, (sy * sxx - sx * sxy) / det


def main():
    cwd = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default = os.path.expanduser("~/.claude/projects/" + cwd.replace("/", "-"))
    root = sys.argv[1] if len(sys.argv) > 1 else default
    seen = set()
    # Read subagents first so a forked context replayed in the parent is not counted twice
    sub = []
    for meta in sorted(glob.glob(os.path.join(root, "*", "subagents", "*.meta.json"))):
        topics = AGENT_TOPICS.get(json.load(open(meta)).get("description"), [])
        sub += read(meta.replace(".meta.json", ".jsonl"), topics, seen)
    main_records = []
    for path in sorted(glob.glob(os.path.join(root, "*.jsonl"))):
        main_records += read(path, [], seen)
    # Estimate subagent output from content size since their transcripts record usage before streaming ends
    a, b = calibrate(main_records)
    for r in sub:
        r["output"] = max(r["output"], a * r["visible"] + b * r["hidden"])

    totals = collections.defaultdict(collections.Counter)
    for r in main_records + sub:
        share = 1 / len(r["langs"])
        for lang in r["langs"]:
            row = totals[lang]
            row["calls"] += share
            for k in ("output", "input", "seconds"):
                row[k] += r[k] * share
            row["agent"] |= r["agent"]

    print(f"Subagent output estimated as {a:.3f} tokens per visible and {b:.3f} per hidden character")
    print()
    print("| Solution | API calls | Output tokens | Input tokens (mostly cached) | Hours | Subagent |")
    print("|---|---|---|---|---|---|")
    grand = collections.Counter()
    for lang, row in sorted(totals.items(), key=lambda kv: -kv[1]["output"]):
        print(f"| {lang} | {row['calls']:.0f} | {row['output']:,.0f} | {row['input'] / 1e6:.1f}M "
              f"| {row['seconds'] / 3600:.2f} | {'yes' if row['agent'] else ''} |")
        for k in ("calls", "output", "input", "seconds"):
            grand[k] += row[k]
    print(f"| **Total** | {grand['calls']:.0f} | {grand['output']:,.0f} | {grand['input'] / 1e6:.1f}M "
          f"| {grand['seconds'] / 3600:.2f} | |")


if __name__ == "__main__":
    main()
