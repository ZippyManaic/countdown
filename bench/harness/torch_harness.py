"""
Time the PyTorch solver over a file of rounds solved as one batch and write each answer as value tab expression
"""

import importlib.util
import sys
import time

import torch

spec = importlib.util.spec_from_file_location("solver", sys.argv[1])
solver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(solver)
rounds = [(target, pool) for target, *pool in (list(map(int, line.split())) for line in open(sys.argv[2]))]
reps = int(sys.argv[4]) if len(sys.argv) > 4 else 1
device = solver.default_device()
# Warm up untimed so device start-up and kernel loading are excluded like the JIT languages
for _ in range(2):
    solver.solve_many(rounds, device)
start = time.perf_counter()
for _ in range(reps):
    out = solver.solve_many(rounds, device)
if device.type == "cuda":
    torch.cuda.synchronize()
print(f"{(time.perf_counter() - start) * 1000 / (len(rounds) * reps):.4f} ms/round", file=sys.stderr)
open(sys.argv[3], "w").write("\n".join(f"{value}\t{expr}" for value, expr in out))
