"""
Define a small decoder-only transformer that reads a round and writes an answer in postfix one token at a time
"""

import torch
from torch import nn
from torch.nn import functional as F

from tokens import ANSWER_LEN, PROMPT_LEN, VOCAB


class Block(nn.Module):
    def __init__(self, width, heads):
        super().__init__()
        self.heads = heads
        self.norm1 = nn.LayerNorm(width)
        self.qkv = nn.Linear(width, 3 * width)
        self.proj = nn.Linear(width, width)
        self.norm2 = nn.LayerNorm(width)
        self.mlp = nn.Sequential(nn.Linear(width, 4 * width), nn.GELU(), nn.Linear(4 * width, width))

    def forward(self, x, cache=None):
        b, t, w = x.shape
        q, k, v = self.qkv(self.norm1(x)).view(b, t, 3, self.heads, w // self.heads).permute(2, 0, 3, 1, 4)
        if cache is None:
            y = F.scaled_dot_product_attention(q, k, v, is_causal=t > 1)
        else:
            # Write into a buffer sized for the whole sequence so decoding feeds only the newest token
            if "k" not in cache:
                shape = (b, self.heads, PROMPT_LEN + ANSWER_LEN, w // self.heads)
                cache["k"], cache["v"] = k.new_empty(shape), v.new_empty(shape)
                cache["at"] = 0
            at = cache["at"]
            cache["k"][:, :, at:at + t], cache["v"][:, :, at:at + t] = k, v
            cache["at"] = at + t
            k, v = cache["k"][:, :, :at + t], cache["v"][:, :, :at + t]
            # Attend with plain matrix products since flash kernels are slow for one query over a short context
            scores = (q @ k.transpose(-1, -2)) * (q.shape[-1] ** -0.5)
            if t > 1:
                scores = scores.masked_fill(torch.ones(t, t, dtype=torch.bool, device=x.device).triu(1), -torch.inf)
            y = scores.softmax(-1) @ v
        x = x + self.proj(y.transpose(1, 2).reshape(b, t, w))
        return x + self.mlp(self.norm2(x))


class Model(nn.Module):
    def __init__(self, width=256, depth=6, heads=8):
        super().__init__()
        self.embed = nn.Embedding(VOCAB, width)
        self.position = nn.Embedding(PROMPT_LEN + ANSWER_LEN, width)
        self.blocks = nn.ModuleList(Block(width, heads) for _ in range(depth))
        self.norm = nn.LayerNorm(width)
        self.head = nn.Linear(width, VOCAB)

    def forward(self, tokens, start=0, caches=None):
        """
        Return next-token logits for every position given tokens beginning at position start
        """
        x = self.embed(tokens) + self.position(torch.arange(start, start + tokens.shape[1], device=tokens.device))
        for i, block in enumerate(self.blocks):
            x = block(x, None if caches is None else caches[i])
        return self.head(self.norm(x))
