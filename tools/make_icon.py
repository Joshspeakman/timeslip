"""The game's own Xbox dashboard picture -- the title image in default.xbe's
$$XTIMAGE section -- as a Windows icon, for the desktop and Start menu
shortcuts (tools/install_windows.ps1). Made from the player's own disc on
their own machine: nothing of the game is in this repository.

    py -3 tools/make_icon.py --game <folder with default.xbe> --out <file.ico> [--png <file.png>]

The image is an XPR0 resource holding one texture (DXT1 or DXT3/5,
128x128 on this disc); the icon carries it at 256, 128, 64, 48, 32 and 16
pixels. Needs Pillow.
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', required=True)
    ap.add_argument('--out', required=True, help='the .ico to write')
    ap.add_argument('--png', help='also the picture itself, at 256')
    a = ap.parse_args()
    img = title_image(a.game.rstrip('/\\') + '/default.xbe')
    big = img.resize((256, 256), Image.LANCZOS)
    # TS2's is a disc on a white square: outside the disc made clear, so the
    # icon is the disc on the desktop rather than a white tile.
    if big.getpixel((2, 2))[:3] >= (235, 235, 235) and big.getpixel((253, 253))[:3] >= (235, 235, 235):
        from PIL import ImageDraw, ImageChops
        m = Image.new('L', (1024, 1024), 0)
        ImageDraw.Draw(m).ellipse((6, 6, 1017, 1017), fill=255)
        m = m.resize((256, 256), Image.LANCZOS)
        big.putalpha(ImageChops.multiply(big.getchannel('A'), m))
    big.save(a.out, format='ICO', sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
    if a.png:
        big.save(a.png)
    print('make_icon: %dx%d title image -> %s' % (img.width, img.height, a.out))


if __name__ == '__main__':
    sys.exit(main())
