"""The game's icon, for the desktop and Start menu shortcuts
(tools/install_windows.ps1) and the Mac's app (--png --size 1024). Made from
the player's own disc on their own machine: nothing of the game is in this
repository.

    py -3 tools/make_icon.py --game <folder with default.xbe> [--art <dir>]
                             [--out <file.ico>] [--png <file.png> [--size 1024]]

With --art holding icon.png (tools/fetch_art.py: a square of the game's
key art, 1024 pixels -- Hart and Cortez for TimeSplitters 2, Cortez in the
time portal's light for Future Perfect): that, at every size, sharpened a
little at the small ones. Else, with --art from the disc alone
(tools/make_disc_art.py), the title screen's logo in a rounded square; and
without --art the Xbox dashboard picture, the title image in default.xbe's
$$XTIMAGE (128x128, soft made bigger). Needs Pillow.
"""
import argparse
import struct
import sys

from PIL import Image


def section(xbe, want):
    base = struct.unpack_from('<I', xbe, 0x104)[0]
    count = struct.unpack_from('<I', xbe, 0x11C)[0]
    headers = struct.unpack_from('<I', xbe, 0x120)[0] - base
    for i in range(count):
        o = headers + i * 0x38
        _flags, _va, _vsize, raw, rawsize, nameaddr = struct.unpack_from('<IIIIII', xbe, o)
        n = nameaddr - base
        name = xbe[n:xbe.index(b'\0', n)].decode('latin1')
        if name == want:
            return xbe[raw:raw + rawsize]
    return None


def rgb565(c):
    return ((c >> 11 & 31) * 255 // 31, (c >> 5 & 63) * 255 // 63, (c & 31) * 255 // 31)


def dxt_colours(block, opaque_only):
    c0, c1, bits = struct.unpack_from('<HHI', block)
    p0, p1 = rgb565(c0), rgb565(c1)
    if c0 > c1 or opaque_only:
        p2 = tuple((2 * a + b) // 3 for a, b in zip(p0, p1))
        p3 = tuple((a + 2 * b) // 3 for a, b in zip(p0, p1))
        pal = [p0 + (255,), p1 + (255,), p2 + (255,), p3 + (255,)]
    else:
        p2 = tuple((a + b) // 2 for a, b in zip(p0, p1))
        pal = [p0 + (255,), p1 + (255,), p2 + (255,), (0, 0, 0, 0)]
    return [pal[(bits >> (2 * i)) & 3] for i in range(16)]


def decode(fmt, w, h, data):
    img = Image.new('RGBA', (w, h))
    px = img.load()
    step = 8 if fmt == 0x0C else 16
    off = 0
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            block = data[off:off + step]
            off += step
            if fmt == 0x0C:
                texels = dxt_colours(block, False)
            elif fmt == 0x0E:                    # DXT3: 4-bit alpha, then colour
                a = struct.unpack_from('<Q', block)[0]
                texels = [c[:3] + (((a >> (4 * i)) & 15) * 17,)
                          for i, c in enumerate(dxt_colours(block[8:], True))]
            else:                                # DXT5: interpolated alpha
                a0, a1 = block[0], block[1]
                bits = int.from_bytes(block[2:8], 'little')
                if a0 > a1:
                    al = [a0, a1] + [((6 - i) * a0 + (i + 1) * a1) // 7 for i in range(6)]
                else:
                    al = [a0, a1] + [((4 - i) * a0 + (i + 1) * a1) // 5 for i in range(4)] + [0, 255]
                texels = [c[:3] + (al[(bits >> (3 * i)) & 7],)
                          for i, c in enumerate(dxt_colours(block[8:], True))]
            for i, t in enumerate(texels):
                x, y = bx + i % 4, by + i // 4
                if x < w and y < h:
                    px[x, y] = t
    return img


def title_image(xbe_path):
    xbe = open(xbe_path, 'rb').read()
    xpr = section(xbe, '$$XTIMAGE')
    if not xpr or xpr[:4] != b'XPR0':
        raise SystemExit('make_icon: no title image in ' + xbe_path)
    _total, header = struct.unpack_from('<II', xpr, 4)
    _common, data_off, _lock, fmt_word, _size = struct.unpack_from('<IIIII', xpr, 12)
    fmt = (fmt_word >> 8) & 0xFF
    w = 1 << ((fmt_word >> 20) & 15)
    h = 1 << ((fmt_word >> 24) & 15)
    if fmt not in (0x0C, 0x0E, 0x0F):
        raise SystemExit('make_icon: title image format 0x%02X not handled' % fmt)
    return decode(fmt, w, h, xpr[header + data_off:])


def rounded(img, radius):
    from PIL import ImageDraw
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.size[0] - 1, img.size[1] - 1), radius, fill=255)
    out = img.copy()
    out.putalpha(m)
    return out


def blue_ground(size):
    """The front end's deep blue, lighter towards the middle, as a rounded square."""
    from PIL import ImageDraw
    g = Image.new('RGBA', (size, size), (12, 19, 40, 255))
    d = ImageDraw.Draw(g)
    for r in range(size // 2, 0, -max(1, size // 256)):
        t = 1.0 - r / (size / 2)
        d.ellipse((size // 2 - r, size // 2 - r, size // 2 + r, size // 2 + r),
                  fill=(12 + int(32 * t), 19 + int(42 * t), 40 + int(74 * t), 255))
    return g


def logo_icon(art, size):
    """The title screen's own logo (tools/make_disc_art.py: logo.png and glow.png,
    from the player's disc), sharp, across the front end's blue."""
    logo = Image.open(art + '/logo.png').convert('RGBA')
    glow = Image.open(art + '/glow.png').convert('RGBA')
    box = logo.getbbox()
    lg = logo.crop(box)
    # Nearly edge to edge: the logo is about 4:1, so at 90% it filled only a
    # quarter of the height and read thin at the Dock's 128 (the Mac session,
    # 25 Nov 2026).
    w = int(size * 0.97)
    h = int(lg.height * w / lg.width)
    k = w / lg.width
    ground = blue_ground(size)
    gw, gh = int(glow.width * k), int(glow.height * k)
    top = int(size * 0.50) - h // 2
    ground.alpha_composite(glow.resize((gw, gh), Image.LANCZOS),
                           ((size - gw) // 2, top - int(box[1] * k)))
    ground.alpha_composite(lg.resize((w, h), Image.LANCZOS), ((size - w) // 2, top))
    return rounded(ground, int(size * 0.16))


def emblem(img, size):
    """The title image at `size`: TS2's is a disc on a white square, so outside
    the disc is made clear and the icon is the disc on the desktop."""
    big = img.resize((size, size), Image.LANCZOS)
    if big.getpixel((1, 1))[:3] >= (235, 235, 235) and big.getpixel((size - 2, size - 2))[:3] >= (235, 235, 235):
        from PIL import ImageDraw, ImageChops
        m = Image.new('L', (1024, 1024), 0)
        ImageDraw.Draw(m).ellipse((6, 6, 1017, 1017), fill=255)
        m = m.resize((size, size), Image.LANCZOS)
        big.putalpha(ImageChops.multiply(big.getchannel('A'), m))
    return big


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', required=True)
    ap.add_argument('--out', help='the .ico to write')
    ap.add_argument('--png', help='also the picture itself')
    ap.add_argument('--size', type=int, default=256, help='the picture\'s size (--png); 1024 for a Mac')
    ap.add_argument('--art', help='the launcher\'s art from this disc (tools/make_disc_art.py); '
                                  'its logo makes a sharper icon than the 128-pixel title image')
    a = ap.parse_args()
    import os
    if a.art and os.path.exists(os.path.join(a.art, 'icon.png')):
        from PIL import ImageFilter
        src = Image.open(os.path.join(a.art, 'icon.png')).convert('RGBA')
        sizes = (256, 128, 64, 48, 32, 24, 16)
        imgs = []
        for sz in sizes:
            im = src.resize((sz, sz), Image.LANCZOS)
            if sz <= 48:                         # a little crisper, so a face still reads
                im = im.filter(ImageFilter.UnsharpMask(radius=0.8, percent=60, threshold=1))
            imgs.append(im)
        if a.out:
            imgs[0].save(a.out, format='ICO', sizes=[(z, z) for z in sizes], append_images=imgs[1:])
        if a.png:
            src.resize((a.size, a.size), Image.LANCZOS).save(a.png)
        print('make_icon: the key art from %s -> %s' % (a.art, a.out or a.png))
        return 0
    if a.art and os.path.exists(a.art + '/logo.png') and os.path.exists(a.art + '/glow.png'):
        big = logo_icon(a.art, max(a.size, 256))
        if a.out:
            # The logo is sharp from 64 up; below that a word cannot be read, and
            # the title image -- 128 pixels, soft only when made bigger -- is
            # sharp made smaller, and reads as the game at a glance.
            icon = big.resize((256, 256), Image.LANCZOS)
            mid = [big.resize((s, s), Image.LANCZOS) for s in (128, 64)]
            try:
                disc = title_image(a.game.rstrip('/\\') + '/default.xbe')
                small = [emblem(disc, s) for s in (48, 32, 24, 16)]
            except SystemExit:
                small = [big.resize((s, s), Image.LANCZOS) for s in (48, 32, 24, 16)]
            icon.save(a.out, format='ICO', sizes=[(256, 256), (128, 128), (64, 64), (48, 48),
                                                   (32, 32), (24, 24), (16, 16)],
                      append_images=mid + small)
        if a.png:
            big.resize((a.size, a.size), Image.LANCZOS).save(a.png)
        print('make_icon: the title logo from %s -> %s' % (a.art, a.out or a.png))
        return 0
    if not a.out:
        raise SystemExit('make_icon: --out is needed without --art')
    img = title_image(a.game.rstrip('/\\') + '/default.xbe')
    big = emblem(img, 256)
    big.save(a.out, format='ICO', sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
    if a.png:
        big.save(a.png)
    print('make_icon: %dx%d title image -> %s' % (img.width, img.height, a.out))


if __name__ == '__main__':
    sys.exit(main())
