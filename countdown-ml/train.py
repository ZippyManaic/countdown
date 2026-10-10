#!/usr/bin/env python3
"""
Train the model to write the reference solver's answer for each round
"""

import math
import sys
import time

import torch
from torch.nn import functional as F

from model import Model
from tokens import PAD, PROMPT_LEN


def main():
    data_path, out_path, epochs = sys.argv[1], sys.argv[2], int(sys.argv[3])
    width, depth = int(sys.argv[4]), int(sys.argv[5])
    device = torch.device("cuda")
    data = torch.load(data_path).long().to(device)
    torch.manual_seed(0)
    model = Model(width, depth, max(width // 64, 1)).to(device)
    print(f"{sum(p.numel() for p in model.parameters()):,} parameters", file=sys.stderr)
    batch = 1024
    steps = epochs * (data.shape[0] // batch)
    optimiser = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=0.01, betas=(0.9, 0.98))
    # Warm up then decay the learning rate along a cosine to zero
    schedule = torch.optim.lr_scheduler.LambdaLR(
        optimiser, lambda s: min(1, s / 500) * 0.5 * (1 + math.cos(math.pi * min(s, steps) / steps)))
    step_fn = torch.compile(model)
    start = time.perf_counter()
    step = 0
    for epoch in range(epochs):
        order = torch.randperm(data.shape[0], device=device)
        for first in range(0, data.shape[0] - batch + 1, batch):
            rows = data[order[first:first + batch]]
            inputs, targets = rows[:, :-1], rows[:, 1:].clone()
            # Score only the answer tokens since the prompt is given
            targets[:, :PROMPT_LEN - 1] = PAD
            with torch.autocast("cuda", dtype=torch.bfloat16):
                logits = step_fn(inputs)
            loss = F.cross_entropy(logits.float().flatten(0, 1), targets.flatten(), ignore_index=PAD)
            optimiser.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimiser.step()
            schedule.step()
            step += 1
            if step % 500 == 0:
                print(f"epoch {epoch} step {step}/{steps} loss {loss.item():.4f} "
                      f"{time.perf_counter() - start:.0f} s", file=sys.stderr)
    torch.save({"width": width, "depth": depth, "state": model.state_dict()}, out_path)


if __name__ == "__main__":
    main()
