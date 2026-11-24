"""Corridor sweep analysis.

usage: analyze.py <run dir> [--jpg]

Reads p_t<tick>-<k>[i].bmp dumps (i = an in-between frame) and the driver's sweep.csv.
Writes <run>/metrics.csv and <run>/flags.csv:
  sky_new   sky pixels (160x90) where the slow reference turn, at any yaw the frame can
            have, never showed sky: see-through cracks
  luma      mean luma; blink = luma well under both neighbours in the shown order
--jpg converts every BMP to a JPG beside it and deletes the BMP (after reading).
"""
import sys, os, re, glob, csv, math
import numpy as np
from PIL import Image
from concurrent.futures import ProcessPoolExecutor

run = sys.argv[1]
to_jpg = "--jpg" in sys.argv
YAW_OFF = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--off=")), "0"))
W, H = 160, 90
NAME = re.compile(r"p_t(\d+)(?:-(\d+))?(i?)\.(bmp|jpg)$")


def sky_mask(a):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (b > r + 25) & (b > g + 8) & (b > 80)


def load(path):
    im = Image.open(path).convert("RGB")
    if to_jpg and path.endswith(".bmp"):
        im.save(path[:-4] + ".jpg", quality=90)
        os.remove(path)
    small = np.asarray(im.resize((W, H), Image.BILINEAR))
    full = np.asarray(im)
    luma = float((0.2126 * full[..., 0] + 0.7152 * full[..., 1] + 0.0722 * full[..., 2]).mean())
    # the HUD corners hold blue-ish icons: leave the top 14% of the corners out
    m = sky_mask(small)
    return os.path.basename(path), m, luma


def main():
    paths = sorted(glob.glob(os.path.join(run, "p_t*.bmp")) + glob.glob(os.path.join(run, "p_t*.jpg")))
    with ProcessPoolExecutor(8) as ex:
        res = list(ex.map(load, paths, chunksize=8))
    log = {int(r["tick"]): r for r in csv.DictReader(open(os.path.join(run, "sweep.csv")))}
    frames = []
    for name, m, luma in res:
        k = NAME.search(name)
        if not k:
            continue
        tick, idx, inb = int(k.group(1)), int(k.group(2) or 0), k.group(3) == "i"
        frames.append(dict(name=name, tick=tick, idx=idx, inb=inb, mask=m, luma=luma))
    frames.sort(key=lambda f: (f["tick"], f["idx"]))

    def yaw_shown(t):
        # the yaw drawn at tick t: logged at t+1, before that tick's turn
        r = log.get(t + YAW_OFF) or log.get(t)
        return float(r["yaw"]) if r else None

    # in-between frames are drawn between tick t-1's picture and t's
    for f in frames:
        a, b = yaw_shown(f["tick"] - 1 if f["inb"] else f["tick"]), yaw_shown(f["tick"])
        f["yaw_a"], f["yaw_b"] = a, b
        r = log.get(f["tick"])
        f["held"] = int(r["held"]) if r else -1

    ref = [f for f in frames if 4440 <= f["tick"] <= 4799 and f["yaw_b"] is not None]
    ref_yaws = np.array([f["yaw_b"] for f in ref])
    ref_masks = np.stack([f["mask"] for f in ref]) if ref else None

    def expected(ya, yb):
        if ya is None or yb is None:
            return None
        d = ((yb - ya + 180) % 360) - 180
        lo = ya + min(0, d) - 3
        hi = ya + max(0, d) + 3
        sel = np.zeros(len(ref_yaws), bool)
        for off in (-360, 0, 360):
            sel |= (ref_yaws + off >= lo) & (ref_yaws + off <= hi)
        if not sel.any():
            return None
        e = ref_masks[sel].any(axis=0)
        # dilate by one pixel
        e2 = e.copy()
        e2[1:] |= e[:-1]; e2[:-1] |= e[1:]; e2[:, 1:] |= e[:, :-1]; e2[:, :-1] |= e[:, 1:]
        return e2

    hud = np.zeros((H, W), bool)
    hud[:14, :24] = True; hud[:16, W - 26:] = True        # rank, radar
    for f in frames:
        e = expected(f["yaw_a"], f["yaw_b"])
        if e is None:
            f["sky_new"] = -1
            continue
        new = f["mask"] & ~e & ~hud
        f["sky_new"] = int(new.sum())
    # blinks: luma against the frames shown either side
    for i, f in enumerate(frames):
        nb = [frames[j]["luma"] for j in (i - 2, i - 1, i + 1, i + 2)
              if 0 <= j < len(frames) and abs(frames[j]["tick"] - f["tick"]) <= 2]
        f["luma_ratio"] = f["luma"] / (np.median(nb) + 1e-6) if nb else 1.0
    with open(os.path.join(run, "metrics.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["name", "tick", "inbetween", "held", "yaw_a", "yaw_b", "sky_new", "luma", "luma_ratio"])
        for f in frames:
            w.writerow([f["name"], f["tick"], int(f["inb"]), f["held"], f["yaw_a"], f["yaw_b"],
                        f["sky_new"], round(f["luma"], 1), round(f["luma_ratio"], 3)])
    flagged = [f for f in frames if f["sky_new"] >= 12 or f["luma_ratio"] < 0.7]
    with open(os.path.join(run, "flags.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["name", "tick", "inbetween", "held", "sky_new", "luma_ratio"])
        for f in flagged:
            w.writerow([f["name"], f["tick"], int(f["inb"]), f["held"], f["sky_new"], round(f["luma_ratio"], 3)])
    # summary by phase
    phases = [("A ref turn 1/f", 4440, 4799), ("B swing 5/f", 4860, 4979), ("B swing 15/f", 4980, 5099),
              ("B swing 30/f", 5100, 5219), ("B swing 60/f", 5220, 5339), ("C pistols", 5400, 5699),
              ("C fire rifle", 5700, 6099), ("C weapon 13/fire rifle", 6100, 6399), ("C shotgun", 6400, 6699),
              ("C plasma autorifle", 6700, 6999), ("D strafe", 7000, 7300)]
    for name, a, b in phases:
        fs = [f for f in frames if a <= f["tick"] <= b]
        if not fs:
            continue
        ib = [f for f in fs if f["inb"]]; mn = [f for f in fs if not f["inb"]]
        crack = lambda l: sum(1 for f in l if f["sky_new"] >= 12)
        blink = lambda l: sum(1 for f in l if f["luma_ratio"] < 0.7)
        print(f"{name:16s} frames {len(fs):4d}  game frames: {crack(mn):3d} see-through, {blink(mn):3d} dark"
              f"  |  in-between: {crack(ib):3d}/{len(ib)} see-through, {blink(ib):3d} dark")


if __name__ == "__main__":
    main()
