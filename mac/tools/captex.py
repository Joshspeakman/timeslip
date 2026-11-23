"""Textures and frames out of .d3dcap captures, for the launcher's art (mac/make_art.sh).

    captex.py list <cap...>                   every texture: id, Xbox format, size
    captex.py logo <capdir> <outdir>          the title's logo and its glow, trimmed alike
    captex.py pick <bmpdir> <from> <to>       the brightest replayed frame whose swap is in [from, to]

A capture is game content: it is read here and never kept (make_art.sh deletes them).
The texture bytes are the host's copy of the Xbox texture, so the 32-bit and 16-bit
formats are still in the Xbox's swizzled (Morton) order; DXT blocks are not swizzled.
Read-only, standard library only.
"""
import glob, os, re, struct, sys, zlib

TEXTURE = 11


def chunks(path):
    d = open(path, 'rb').read()
    off = struct.unpack_from('<I', d, 12)[0]           # D3D8CapHeader.header_bytes
    while off + 8 <= len(d):
        t, n = struct.unpack_from('<II', d, off)
        yield t, d[off + 8:off + 8 + n]
        off += 8 + n + ((4 - (n & 3)) & 3)              # CAP_ALIGN 4


def textures(path):
    for t, p in chunks(path):
        if t == TEXTURE and len(p) >= 24:
            tid, fmt, w, h, levels, usage = struct.unpack_from('<6I', p, 0)
            lv = [struct.unpack_from('<3I', p, 24 + 12 * i) for i in range(levels)]
            start = 24 + 12 * levels
            yield tid, fmt, w, h, lv, p[start:start + (lv[0][2] if lv else 0)]


def morton(w, h):
    def idx(x, y):
        i = bit = xb = yb = 0
        sx, sy = w, h
        while sx > 1 or sy > 1:
            if sx > 1:
                i |= ((x >> xb) & 1) << bit; bit += 1; xb += 1; sx >>= 1
            if sy > 1:
                i |= ((y >> yb) & 1) << bit; bit += 1; yb += 1; sy >>= 1
        return i
    return idx


def argb32(w, h, data):
    """A swizzled A8R8G8B8 texture as RGBA rows."""
    idx, out = morton(w, h), bytearray(w * h * 4)
    for y in range(h):
        for x in range(w):
            o = idx(x, y) * 4
            b, g, r, a = data[o:o + 4]
            out[(y * w + x) * 4:(y * w + x) * 4 + 4] = bytes((r, g, b, a))
    return out


def write_png(path, w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    def ck(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + ck(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
                ck(b'IDAT', zlib.compress(raw, 9)) + ck(b'IEND', b''))


def alpha_share(rgba):
    a = rgba[3::4]
    n = len(a)
    return sum(1 for v in a if v < 13) / n, sum(1 for v in a if v > 242) / n


def logo(capdir, outdir):
    """The title screen draws its logo (opaque letters, clear around them) over a glow
    layer (the same shape, soft, nothing fully opaque), both 512x256 A8R8G8B8."""
    for cap in sorted(glob.glob(os.path.join(capdir, '*.d3dcap'))):
        found = {}
        for tid, fmt, w, h, lv, data in textures(cap):
            if fmt != 0x06 or (w, h) != (512, 256) or len(data) < w * h * 4:
                continue
            px = argb32(w, h, data)
            clear, solid = alpha_share(px)
            if 0.7 < clear < 0.95 and solid > 0.05:
                found['logo'] = px
            elif 0.5 < clear < 0.9 and solid < 0.01:
                found['glow'] = px
        if 'logo' in found:
            w, h = 512, 256
            # one box for both, so they stay registered
            xs, ys = [], []
            for name in found:
                a = found[name][3::4]
                for i, v in enumerate(a):
                    if v > 8:
                        xs.append(i % w); ys.append(i // w)
            x0, x1, y0, y1 = max(min(xs) - 4, 0), min(max(xs) + 5, w), max(min(ys) - 4, 0), min(max(ys) + 5, h)
            for name, px in found.items():
                cw, chh = x1 - x0, y1 - y0
                crop = bytearray(cw * chh * 4)
                for y in range(chh):
                    crop[y * cw * 4:(y + 1) * cw * 4] = px[((y0 + y) * w + x0) * 4:((y0 + y) * w + x1) * 4]
                write_png(os.path.join(outdir, name + '.png'), cw, chh, crop)
            print('logo from', os.path.basename(cap), 'box', (x0, y0, x1, y1), 'layers', sorted(found))
            return 0
    print('no logo texture in', capdir, file=sys.stderr)
    return 1


def bmp_mean(path):
    d = open(path, 'rb').read()
    off = struct.unpack_from('<I', d, 10)[0]
    w, h = struct.unpack_from('<ii', d, 18)
    bpp = struct.unpack_from('<H', d, 28)[0] // 8
    h = abs(h); row = (w * bpp + 3) & ~3
    s = n = 0
    for y in range(0, h, 8):
        r = d[off + y * row:off + y * row + w * bpp]
        for x in range(0, len(r) - 2, bpp * 8):
            s += r[x] + r[x + 1] + r[x + 2]; n += 3
    return s / n if n else 0


def pick(bmpdir, lo, hi):
    best = None
    for f in glob.glob(os.path.join(bmpdir, '*.bmp')):
        m = re.search(r'_(\d+)_000', os.path.basename(f))
        if not m or not lo <= int(m.group(1)) <= hi:
            continue
        v = bmp_mean(f)
        if not best or v > best[0]:
            best = (v, f)
    if not best:
        return 1
    print(best[1])
    return 0


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'list':
        for cap in sys.argv[2:]:
            for tid, fmt, w, h, lv, data in textures(cap):
                print(f"{os.path.basename(cap)} id={tid} fmt=0x{fmt:02X} {w}x{h} levels={len(lv)}")
    elif cmd == 'logo':
        sys.exit(logo(sys.argv[2], sys.argv[3]))
    elif cmd == 'pick':
        sys.exit(pick(sys.argv[2], int(sys.argv[3]), int(sys.argv[4])))
    else:
        sys.exit(__doc__)
