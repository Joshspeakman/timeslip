"""Timeslip's own pictures: the icon, the logo, the box art and the social preview.

    py -3 tools/art/make_art.py [OUT]          (default: art/)

All of it is drawn here, from shapes and an open font (Exo 2, SIL Open Font
License, tools/art/fonts): no artwork, logo, character or mark of the game's,
its publishers' or any console's. The mark is an hourglass cut along a slant,
its lower half slipped along the cut, with light in the gap: time, slipping.

Writes:
    timeslip.ico          16-256 px, both executables' icon
    icon-1024.png, icon-256.png, icon-64.png
    emblem.png            the hourglass alone, transparent, 1024 px
    logo.png, logo-dark.png   the mark and the name; transparent, and on the dark
    boxart.png            1200x1800
    social-preview.png    1280x640, for the repository's settings
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, 'fonts', 'Exo2-Italic-wght.ttf')
FONT_UP = os.path.join(HERE, 'fonts', 'Exo2-wght.ttf')

ORANGE_HI = (255, 184, 82)
ORANGE_LO = (226, 98, 26)
CAP = (255, 236, 210)
RIFT = (140, 244, 255)
TEAL_HI = (24, 84, 96)
TEAL_LO = (5, 12, 15)
INK = (246, 242, 234)


def font(size, weight, italic=True):
    f = ImageFont.truetype(FONT if italic else FONT_UP, size)
    f.set_variation_by_axes([weight])
    return f


def vgrad(w, h, top, bottom):
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, float)[None, None, :]
    b = np.array(bottom, float)[None, None, :]
    return np.broadcast_to(a + (b - a) * t, (h, w, 3))


def to_img(arr, alpha=None):
    rgb = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB')
    if alpha is None:
        return rgb
    rgb.putalpha(alpha)
    return rgb


def emblem(n):
    """The hourglass, slipped, on transparency: n x n RGBA."""
    ss = 4
    s = n * ss
    P = lambda pts: [(x * s, y * s) for x, y in pts]

    body = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(body)
    d.polygon(P([(0.22, 0.17), (0.78, 0.17), (0.535, 0.47), (0.465, 0.47)]), fill=255)
    d.polygon(P([(0.465, 0.53), (0.535, 0.53), (0.78, 0.83), (0.22, 0.83)]), fill=255)
    d.rectangle(P([(0.465, 0.46), (0.535, 0.54)]), fill=255)
    caps = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(caps)
    r = int(0.03 * s)
    d.rounded_rectangle(P([(0.15, 0.10), (0.85, 0.165)]), radius=r, fill=255)
    d.rounded_rectangle(P([(0.15, 0.835), (0.85, 0.90)]), radius=r, fill=255)

    # The cut: a line through the middle, rising to the right.
    ang = math.radians(-22)
    dx, dy = math.cos(ang), math.sin(ang)
    yy, xx = np.mgrid[0:s, 0:s] / s
    side = (xx - 0.5) * dy - (yy - 0.5) * dx          # > 0 above the line
    above_cut = side > 0.012
    below_cut = side < -0.012
    # The upper half slips along the cut, up and to the right, and a touch
    # away from it, so the light shows between.
    slip = (0.11 * dx, 0.11 * dy - 0.012)
    below, above = above_cut, below_cut                # the half that moves, the half that stays

    def shifted(mask_img, keep, sx, sy):
        m = np.asarray(mask_img, float) / 255.0 * keep
        im = Image.fromarray((m * 255).astype(np.uint8), 'L')
        return im.transform(im.size, Image.AFFINE, (1, 0, -sx * s, 0, 1, -sy * s),
                            resample=Image.BILINEAR)

    top_body = shifted(body, above, 0, 0)
    low_body = shifted(body, below, *slip)
    top_caps = shifted(caps, above, 0, 0)
    low_caps = shifted(caps, below, *slip)

    out = np.zeros((s, s, 4), float)

    def lay(mask, colour_arr):
        a = np.asarray(mask, float)[..., None] / 255.0
        out[..., :3] = out[..., :3] * (1 - a) + colour_arr * a
        out[..., 3:] = out[..., 3:] * (1 - a) + 255 * a

    sand = vgrad(s, s, ORANGE_HI, ORANGE_LO)
    lay(top_body, sand)
    lay(low_body, sand)
    capc = np.broadcast_to(np.array(CAP, float), (s, s, 3))
    lay(top_caps, capc)
    lay(low_caps, capc)

    # The glass: a darker inner shape, so it reads as a vessel, not a slab.
    inner = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(inner)
    d.polygon(P([(0.30, 0.21), (0.70, 0.21), (0.515, 0.445), (0.485, 0.445)]), fill=255)
    d.polygon(P([(0.485, 0.555), (0.515, 0.555), (0.70, 0.79), (0.30, 0.79)]), fill=255)
    sand_level = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(sand_level)
    d.polygon(P([(0.38, 0.31), (0.62, 0.31), (0.515, 0.445), (0.485, 0.445)]), fill=255)
    d.polygon(P([(0.24, 0.83), (0.76, 0.83), (0.62, 0.68), (0.38, 0.68)]), fill=255)
    hollow = np.asarray(inner, float) / 255.0 * (1 - np.asarray(sand_level, float) / 255.0)
    hollow_img = Image.fromarray((hollow * 255).astype(np.uint8), 'L')
    glass = np.broadcast_to(np.array((46, 22, 10), float), (s, s, 3))
    for keep, sh in ((above, (0, 0)), (below, slip)):
        m = shifted(hollow_img, keep, *sh)
        a = np.asarray(m, float)[..., None] / 255.0 * 0.78
        out[..., :3] = out[..., :3] * (1 - a) + glass * a

    # The rift: light along the cut, across the glass.
    rift = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(rift)
    L = 0.42
    p0 = (0.5 - L * dx + slip[0] / 2, 0.5 - L * dy + slip[1] / 2)
    p1 = (0.5 + L * dx + slip[0] / 2, 0.5 + L * dy + slip[1] / 2)
    d.line(P([p0, p1]), fill=255, width=max(1, int(0.016 * s)))
    glow = rift.filter(ImageFilter.GaussianBlur(0.035 * s))
    core = rift.filter(ImageFilter.GaussianBlur(0.004 * s))
    for m, strength in ((glow, 1.6), (core, 1.0)):
        a = np.clip(np.asarray(m, float)[..., None] / 255.0 * strength, 0, 1)
        out[..., :3] = out[..., :3] * (1 - a) + np.array(RIFT, float) * a
        out[..., 3:] = np.maximum(out[..., 3:], 255 * a)

    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')
    return img.resize((n, n), Image.LANCZOS)


def tile(n):
    """The icon: the emblem on a rounded dark-teal tile."""
    ss = 4
    s = n * ss
    yy, xx = np.mgrid[0:s, 0:s] / s
    dist = np.sqrt((xx - 0.5) ** 2 + ((yy - 0.36) * 1.1) ** 2)
    t = np.clip(dist / 0.75, 0, 1)[..., None]
    bg = np.array(TEAL_HI, float) * (1 - t) + np.array(TEAL_LO, float) * t
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=int(0.22 * s), fill=255)
    rim = Image.new('L', (s, s), 0)
    ImageDraw.Draw(rim).rounded_rectangle((int(0.012 * s),) * 2 + (s - 1 - int(0.012 * s),) * 2,
                                          radius=int(0.21 * s), outline=255,
                                          width=max(1, int(0.006 * s)))
    a = np.asarray(rim, float)[..., None] / 255.0 * 0.35
    bg = bg * (1 - a) + np.array((90, 170, 184), float) * a
    base = to_img(bg, mask).resize((n, n), Image.LANCZOS)
    e = emblem(int(n * 0.80))
    base.alpha_composite(e, ((n - e.width) // 2, (n - e.height) // 2))
    return base


def wordmark(height, colour=INK):
    """'TIMESLIP', heavy italic, with the slip's light through it."""
    f = font(int(height * 1.25), 860)
    text = 'TIMESLIP'
    box = f.getbbox(text)
    w, h = box[2] - box[0] + int(height * 0.2), box[3] - box[1] + int(height * 0.2)
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).text((int(height * 0.1) - box[0], int(height * 0.1) - box[1]), text,
                           font=f, fill=255)
    # The slip: the top half moved a little left along a cut just above the middle.
    yy, xx = np.mgrid[0:h, 0:w]
    cut = h * 0.52 - (xx - w / 2) * 0.05
    arr = np.asarray(m, float)
    top = np.where(yy < cut - h * 0.03, arr, 0)
    low = np.where(yy > cut + h * 0.03, arr, 0)
    top_img = Image.fromarray(top.astype(np.uint8), 'L').transform(
        (w, h), Image.AFFINE, (1, 0, height * 0.06, 0, 1, 0), resample=Image.BILINEAR)
    mask = Image.fromarray(np.maximum(np.asarray(top_img, float), low).astype(np.uint8), 'L')
    out = Image.new('RGBA', (w, h), colour + (0,))
    out.putalpha(mask)
    # Light in the gap.
    line = Image.new('L', (w, h), 0)
    ImageDraw.Draw(line).line([(0, h * 0.52 + w / 2 * 0.05), (w, h * 0.52 - w / 2 * 0.05)],
                              fill=255, width=max(1, int(h * 0.018)))
    glow = line.filter(ImageFilter.GaussianBlur(h * 0.05))
    lit = Image.new('RGBA', (w, h), RIFT + (0,))
    a = np.clip(np.asarray(glow, float) * 1.5 + np.asarray(line, float) * 0.6, 0, 255)
    lit.putalpha(Image.fromarray(a.astype(np.uint8), 'L'))
    out = Image.alpha_composite(lit, out)
    return out


def field(w, h, cx=0.5, cy=0.4, seed=7):
    """A time vortex: teal light from a point, rings, and faint streaks."""
    yy, xx = np.mgrid[0:h, 0:w]
    nx, ny = (xx - cx * w) / max(w, h), (yy - cy * h) / max(w, h)
    r = np.sqrt(nx ** 2 + ny ** 2)
    t = np.clip(r / 0.85, 0, 1)[..., None]
    bg = np.array((16, 58, 70), float) * (1 - t) ** 1.6 + np.array(TEAL_LO, float) * (1 - (1 - t) ** 1.6)
    rings = (0.5 + 0.5 * np.cos(r * 2 * math.pi * 7.5)) ** 18 * np.clip(1 - r / 1.1, 0, 1)
    bg += rings[..., None] * np.array((40, 120, 132), float) * 0.35
    ang = np.arctan2(ny, nx)
    rng = np.random.default_rng(seed)
    streak = np.zeros_like(r)
    for a0 in rng.uniform(-math.pi, math.pi, 46):
        da = np.angle(np.exp(1j * (ang - a0)))
        streak += np.exp(-(da / 0.006) ** 2) * np.clip((r - 0.12) / 0.5, 0, 1)
    bg += np.clip(streak, 0, 1)[..., None] * np.array((243, 154, 44), float) * 0.10
    return np.clip(bg, 0, 255)


def text_line(img, text, y, size, weight, colour, italic=True, spacing=0.0):
    f = font(size, weight, italic)
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), text, font=f)
    x = (img.width - (box[2] - box[0])) // 2 - box[0]
    d.text((x, y), text, font=f, fill=colour)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'art')
    os.makedirs(out, exist_ok=True)

    big = tile(1024)
    big.save(os.path.join(out, 'icon-1024.png'))
    big.resize((256, 256), Image.LANCZOS).save(os.path.join(out, 'icon-256.png'))
    big.resize((64, 64), Image.LANCZOS).save(os.path.join(out, 'icon-64.png'))
    # Each size drawn at its own size, so 16 and 24 stay crisp rather than mush.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [tile(n) for n in sizes]
    frames[-1].save(os.path.join(out, 'timeslip.ico'), sizes=[(n, n) for n in sizes],
                    append_images=frames[:-1])
    emblem(1024).save(os.path.join(out, 'emblem.png'))

    # Logo: the mark, then the name.
    em = emblem(520)
    wm = wordmark(300)
    gap = 40
    logo = Image.new('RGBA', (em.width + gap + wm.width, max(em.height, wm.height)), (0, 0, 0, 0))
    logo.alpha_composite(em, (0, (logo.height - em.height) // 2))
    logo.alpha_composite(wm, (em.width + gap, (logo.height - wm.height) // 2))
    logo.save(os.path.join(out, 'logo.png'))
    dark = to_img(field(logo.width + 160, logo.height + 120, 0.3, 0.5))
    dark.paste(logo, (80, 60), logo)
    dark.save(os.path.join(out, 'logo-dark.png'))

    # Box art, 2:3.
    W, H = 1200, 1800
    box = to_img(field(W, H, 0.5, 0.37)).convert('RGBA')
    em = emblem(700)
    halo = Image.new('L', box.size, 0)
    ImageDraw.Draw(halo).ellipse((W / 2 - 330, H * 0.37 - 330, W / 2 + 330, H * 0.37 + 330), fill=90)
    halo = halo.filter(ImageFilter.GaussianBlur(120))
    lightc = Image.new('RGBA', box.size, (40, 140, 160, 0))
    lightc.putalpha(halo)
    box = Image.alpha_composite(box, lightc)
    box.alpha_composite(em, ((W - em.width) // 2, int(H * 0.37 - em.height / 2)))
    wm = wordmark(190)
    box.alpha_composite(wm, ((W - wm.width) // 2, int(H * 0.64)))
    text_line(box, 'TimeSplitters 2, recompiled to run natively', int(H * 0.775), 44, 500,
              (200, 222, 228))
    text_line(box, 'PC   ·   Mac   ·   Linux', int(H * 0.885), 40, 700, ORANGE_HI,
              italic=False)
    text_line(box, 'Bring your own copy of the game', int(H * 0.925), 30, 400, (140, 168, 176))
    box.convert('RGB').save(os.path.join(out, 'boxart.png'))

    # Social preview, 2:1.
    W, H = 1280, 640
    sp = to_img(field(W, H, 0.26, 0.5)).convert('RGBA')
    em = emblem(420)
    sp.alpha_composite(em, (60, (H - em.height) // 2))
    x0 = 500
    wm = wordmark(150)
    if wm.width > W - x0 - 50:                      # as large as fits
        wm = wordmark(int(150 * (W - x0 - 50) / wm.width))
    sp.alpha_composite(wm, (x0, 190))
    d = ImageDraw.Draw(sp)
    d.text((x0 + 30, 190 + wm.height + 20), 'TimeSplitters 2, recompiled to run natively',
           font=font(34, 500), fill=(200, 222, 228))
    d.text((x0 + 30, 190 + wm.height + 72), 'PC  ·  Mac  ·  Linux',
           font=font(30, 700, False), fill=ORANGE_HI)
    sp.convert('RGB').save(os.path.join(out, 'social-preview.png'))
    print('wrote', os.path.abspath(out))


if __name__ == '__main__':
    main()
