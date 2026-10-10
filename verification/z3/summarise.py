"""Summarise the result files of every check into results/summary.json and print it"""

import glob
import json
import os
import statistics

from common import OUT, write_json


def no_solution(job):
    """Return agreement and timing figures for one no-solution job"""
    rows = []
    for path in sorted(glob.glob(os.path.join(OUT, f"no_solution_{job}_*.jsonl"))):
        with open(path) as f:
            rows += [json.loads(line) for line in f]
    if not rows:
        return None
    out = {"instances": len(rows)}
    for kind in ("sat", "unsat", "unknown"):
        ts = [r["time"] for r in rows if r["result"] == kind]
        if ts:
            out[kind] = {"count": len(ts), "mean": statistics.mean(ts), "median": statistics.median(ts),
                         "max": max(ts), "total": sum(ts)}
    out["disagree_with_table"] = sum(1 for r in rows if r["result"] in ("sat", "unsat")
                                     and (r["result"] == "sat") != r["expected_solvable"])
    out["table_vs_python"] = sum(1 for r in rows if r["expected_solvable"] != r["python_solvable"])
    out["bad_witnesses"] = sum(1 for r in rows if r["result"] == "sat" and not r.get("witness_ok"))
    return out


def main():
    summary = {job: no_solution(job) for job in ("worst", "t967", "cats4")}
    for name in ("prop_prime", "cats_max", "prop_max_bound", "lemma_reciprocal_validate",
                 "lemma_reciprocal_mutation", "lemma_reciprocal_int32", "lemma_reciprocal_fp"):
        path = os.path.join(OUT, name + ".json")
        if not os.path.exists(path):
            continue
        with open(path) as f:
            data = json.load(f)
        if name == "lemma_reciprocal_int32":
            data = data["summary"]
        elif name == "prop_prime":
            data = {k: v for k, v in data.items() if k != "generic"}
        elif name == "prop_max_bound":
            trees = data["trees"]
            data = {"lemmas": data["lemmas"], "tree_checks": {}}
            for row in trees:
                key = f"{row['claim']} {row['regime']}"
                d = data["tree_checks"].setdefault(key, {"cases": 0, "unsat": 0, "open": 0, "time": 0.0, "max_time": 0.0})
                d["cases"] += 1
                closed = row["result"] == "unsat" or row.get("split_results", {}).get("unsat") == 4 ** (len(row["S"]) - 1)
                d["unsat"] += closed
                d["open"] += not closed
                d["time"] += row["time"] + row.get("split_time", 0.0)
                d["max_time"] = max(d["max_time"], row["time"])
        summary[name] = data
    write_json("summary.json", summary)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
