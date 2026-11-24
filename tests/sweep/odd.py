"""In-between frames that differ from both neighbouring game frames much more than
the two differ from each other, in stretches where the player stands still (the first
130 ticks of each weapon window): what the sky test misses (tan gaps, a jolt).
usage: odd.py <run dir>"""
import sys, os, re, glob
import numpy as np
from PIL import Image

run = sys.argv[1]
NAME = re.compile(r"p_t(\d+)(?:-(\d+))?(i?)\.(bmp|jpg)$")
still = [(5400, 5530), (5700, 5830), (6100, 6230), (6400, 6530), (6700, 6830)]
labels = ["pistols", "fire rifle", "weapon 13/fire rifle", "shotgun", "plasma autorifle"]
files = sorted(glob.glob(os.path.join(run, "p_t*.jpg")) + glob.glob(os.path.join(run, "p_t*.bmp")))
frames = []
for p in files:
    m = NAME.search(os.path.basename(p))
    if m:
        frames.append((int(m.group(1)), int(m.group(2) or 0), m.group(3) == "i", p))
frames.sort()
cache = {}
def img(p):
    if p not in cache:
        cache[p] = np.asarray(Image.open(p).convert("L").resize((320, 180)), np.int16)
    return cache[p]
for (a, b), lab in zip(still, labels):
    seq = [f for f in frames if a <= f[0] <= b]
    flagged, total = [], 0
    for k, f in enumerate(seq):
        if not f[2]:
            continue
        prev = next((g for g in reversed(seq[:k]) if not g[2]), None)
        nxt = next((g for g in seq[k + 1:] if not g[2]), None)
        if not prev or not nxt:
            continue
        total += 1
        x, p0, p1 = img(f[3]), img(prev[3]), img(nxt[3])
        both = (np.abs(x - p0) > 40) & (np.abs(x - p1) > 40)
        base = (np.abs(p0 - p1) > 40)
        n = int(both.sum()) - int(base.sum())
        if n > 40:
            flagged.append((n, os.path.basename(f[3])))
    flagged.sort(reverse=True)
    print(f"{lab:18s} in-betweens {total:3d}, odd {len(flagged):3d}  {flagged[:4]}")
