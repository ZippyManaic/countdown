"""
Time the solver in a Python module over a file of rounds and write each answer as value tab expression
"""

import importlib.util
import sys
import time

spec = importlib.util.spec_from_file_location("solver", sys.argv[1])
solver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(solver)
rounds = [list(map(int, line.split())) for line in open(sys.argv[2])]
reps = int(sys.argv[4]) if len(sys.argv) > 4 else 1
start = time.perf_counter()
for _ in range(reps):
    out = [solver.solve(target, pool) for target, *pool in rounds]
print(f"{(time.perf_counter() - start) * 1000 / (len(rounds) * reps):.4g} ms/round", file=sys.stderr)
open(sys.argv[3], "w").write("\n".join(f"{value}\t{expr}" for value, expr in out))
