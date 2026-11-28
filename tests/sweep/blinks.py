"""Blinks: a part of the picture that is much brighter or darker in one frame than in both
frames either side, while those two agree. Frames in presentation order (tick, then index).
    py -3 blinks.py <folder> <prefix> [threshold]"""
import glob, os, re, sys
import numpy as np
from PIL import Image

folder, prefix = sys.argv[1], sys.argv[2]
thr = float(sys.argv[3]) if len(sys.argv) > 3 else 18.0
pat = re.compile(re.escape(prefix) + r't(\d+)-(\d+)(i?)\.bmp$')
frames = []
for f in glob.glob(os.path.join(folder, prefix + 't*.bmp')):
    m = pat.search(os.path.basename(f))
    if m:
        frames.append((int(m.group(1)), int(m.group(2)), m.group(3) == 'i', f))
frames.sort()
GX, GY = 12, 9
lum = []
for _, _, _, f in frames:
    a = np.asarray(Image.open(f).convert('L'), dtype=np.float32)
    h, w = a.shape
    a = a[: h // GY * GY, : w // GX * GX]
    lum.append(a.reshape(GY, h // GY, GX, w // GX).mean(axis=(1, 3)))
lum = np.array(lum)
hits = []
for i in range(1, len(frames) - 1):
    prev, cur, nxt = lum[i - 1], lum[i], lum[i + 1]
    agree = np.abs(prev - nxt)
    dev = np.minimum(np.abs(cur - prev), np.abs(cur - nxt)) * np.sign(cur - prev)
    same_dir = np.sign(cur - prev) == np.sign(cur - nxt)
    spike = (np.abs(dev) > thr) & same_dir & (agree < thr / 2)
    if spike.any():
        cells = np.argwhere(spike)
        worst = np.abs(dev)[spike].max()
        hits.append((frames[i], len(cells), float(worst), float(np.sign(dev[spike][0]))))
inb = [h for h in hits if h[0][2]]
game = [h for h in hits if not h[0][2]]
print(f'{len(frames)} frames: {sum(1 for f in frames if f[2])} in-between, {sum(1 for f in frames if not f[2])} game')
print(f'blinks: {len(inb)} in in-between frames, {len(game)} in game frames (threshold {thr})')
for (t, k, ib, f), n, worst, sign in sorted(hits, key=lambda h: -h[2])[:25]:
    print(f'  t{t}-{k}{"i" if ib else " "} cells {n:3d} worst {worst:5.1f} {"brighter" if sign > 0 else "darker"}  {os.path.basename(f)}')
