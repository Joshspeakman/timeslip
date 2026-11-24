"""The launcher's art, made from the player's own copy of the game -- mac/make_art.sh for
Windows and Linux, with the same path through the game and the same frames, so every
machine's launcher shows the same pictures.

    py -3 tools/make_disc_art.py [--game DIR] [--out DIR] [--build DIR]

Runs the built game once, unseen and muted, down the scripted path to Siberia, capturing
frames as it goes (recompose's d3d8 capture); then
    logo.png, glow.png   the title screen's own logo textures (mac/tools/captex.py)
    backdrop.jpg         the Oblask Dam establishing shot, replayed at 4x
    card_metal.jpg       the time portal hub, 4x       (the first renderer card)
    card_vulkan.jpg      Siberia's base, 4x            (the second)
into the launcher's art folder (default: %LOCALAPPDATA%\\xboxrecomp\\art\\4553000A, or
$XDG_DATA_HOME/xboxrecomp/art/4553000A). Takes about three minutes. The captures and the
copy of the game it ran from are deleted afterwards (both are game content); nothing of
the player's -- settings, saves -- is read or written.
"""
import argparse
import glob
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, 'mac', 'tools'))
import captex  # noqa: E402

EXE = '.exe' if os.name == 'nt' else ''
SEQ = ('12000:start,16000:start,20000:start,24000:start,28000:a,34000:a,40000:a,46000:a,'
       '52000:a,58000:a,64000:a,70000:a,76000:a,82000:a,88000:a,94000:a,'
       '120000:lstick_up:3000,125000:rstick_right:1200,134000:lstick_up:4000')
PICTURES = [('backdrop', 3900, 5700),     # the dam: the level's opening shot, snow-bright
            ('card_metal', 3500, 3700),   # the hub, its portal open
            ('card_vulkan', 6900, 8400)]  # outside, at the base


def art_dir():
    if os.name == 'nt':
        return os.path.join(os.environ['LOCALAPPDATA'], 'xboxrecomp', 'art', '4553000A')
    base = os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share')
    return os.path.join(base, 'xboxrecomp', 'art', '4553000A')


def link_tree(src, dst):
    """The game's files, linked rather than copied where the disk allows (the game only
    reads them; its saves folders are left out)."""
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d.upper() not in ('UDATA', 'TDATA')]
        rel = os.path.relpath(root, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            a, b = os.path.join(root, f), os.path.join(dst, rel, f)
            try:
                os.link(a, b)
            except OSError:
                shutil.copy2(a, b)


def bmp_to_rgb(path):
    d = open(path, 'rb').read()
    off = struct.unpack_from('<I', d, 10)[0]
    w, h = struct.unpack_from('<ii', d, 18)
    bpp = struct.unpack_from('<H', d, 28)[0] // 8
    top_down, h = h < 0, abs(h)
    row = (w * bpp + 3) & ~3
    out = bytearray(w * h * 3)
    for y in range(h):
        src = d[off + (y if top_down else h - 1 - y) * row:][:w * bpp]
        line = bytearray(w * 3)
        line[0::3] = src[2::bpp]
        line[1::3] = src[1::bpp]
        line[2::3] = src[0::bpp]
        out[y * w * 3:(y + 1) * w * 3] = line
    return w, h, bytes(out)


def save_picture(bmp, out_base):
    """JPEG through Pillow when it is there; else PNG, which needs nothing."""
    try:
        from PIL import Image
        Image.open(bmp).convert('RGB').save(out_base + '.jpg', quality=88)
        return out_base + '.jpg'
    except Exception:
        w, h, rgb = bmp_to_rgb(bmp)
        raw = b''.join(b'\x00' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

        def chunk(t, b):
            return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
        with open(out_base + '.png', 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
                    chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
        return out_base + '.png'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--game', default=os.path.join(HERE, 'game'), help="the game's folder (default.xbe)")
    ap.add_argument('--out', default=None, help="where the pictures go (the launcher's art folder)")
    ap.add_argument('--build', default=os.path.join(HERE, 'build', 'Release'), help='the built game')
    a = ap.parse_args()
    out = a.out or art_dir()
    game_exe = os.path.join(a.build, 'timeslip' + EXE)
    replay = os.path.join(a.build, 'xboxrecomp', 'src', 'replay', 'd3d8_replay' + EXE)
    if not os.path.isfile(os.path.join(a.game, 'default.xbe')):
        sys.exit(f'make_disc_art: no game at {a.game}')
    for f in (game_exe, replay):
        if not os.path.isfile(f):
            sys.exit(f'make_disc_art: {f} is not built (scripts/build.py)')

    # Beside the game, so its files are hard links (no link crosses drives, and the
    # system's temp folder is often on another one); the system's if that can't be written.
    try:
        work = tempfile.mkdtemp(prefix='.ts2art-', dir=os.path.dirname(os.path.abspath(a.game)))
    except OSError:
        work = tempfile.mkdtemp(prefix='ts2art-')
    proc = None
    try:
        game = os.path.join(work, 'game')
        link_tree(a.game, game)
        for d in ('caps', 'saves', 'frames', 'art', 'user'):
            os.makedirs(os.path.join(work, d))
        conf = os.path.join(work, 'user', 'art.conf')          # nothing of the player's settings
        open(conf, 'w').write('resolution_scale = 1\nwidescreen = 0\nfullscreen = 0\nframe_interp = 1\n')
        env = dict(os.environ, RECOMP_GAME_DIR=game, RECOMP_SAVE_DIR=os.path.join(work, 'saves'),
                   RECOMP_USER_DIR=os.path.join(work, 'user'), RECOMP_DISPLAY_CONFIG=conf,
                   RECOMP_MUTE='1', RECOMP_WINDOW_BACKGROUND='1', RECOMP_INPUT_SEQ=SEQ,
                   RECOMP_D3D8_CAPTURE=os.path.join(work, 'caps', 'a.d3dcap'),
                   RECOMP_D3D8_CAPTURE_SWAP='600', RECOMP_D3D8_CAPTURE_EVERY='300',
                   RECOMP_D3D8_CAPTURE_MAX='28')
        env.pop('RECOMP_LOCKSTEP_REPLAY', None)
        print('== playing to Siberia (about 3 minutes)', flush=True)
        log = open(os.path.join(work, 'game.log'), 'wb')
        proc = subprocess.Popen([game_exe], cwd=a.build, env=env, stdout=log, stderr=log)
        for _ in range(170):
            if proc.poll() is not None:
                break
            time.sleep(1)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        log.close()
        caps = sorted(glob.glob(os.path.join(work, 'caps', '*.d3dcap')))
        if len(caps) < 20:
            sys.exit(f'make_disc_art: only {len(caps)} frames were captured (the game log: '
                     f'{os.path.join(work, "game.log")} -- kept)')

        print('== the logo', flush=True)
        if captex.logo(os.path.join(work, 'caps'), os.path.join(work, 'art')):
            print('make_disc_art: no logo found; the launcher writes the name instead', file=sys.stderr)

        print('== choosing the pictures', flush=True)
        renv = dict(os.environ, RECOMP_D3D8_BACKEND='d3d11' if os.name == 'nt' else 'vulkan')
        for c in caps:
            base = os.path.splitext(os.path.basename(c))[0]
            subprocess.run([replay, c, '--out', os.path.join(work, 'frames', base + '_'), '--quiet'],
                           env=renv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for name, lo, hi in PICTURES:
            best, frame = None, None
            for f in glob.glob(os.path.join(work, 'frames', '*.bmp')):
                m = re.search(r'_(\d+)_000', os.path.basename(f))
                if m and lo <= int(m.group(1)) <= hi:
                    v = captex.bmp_mean(f)
                    if best is None or v > best:
                        best, frame = v, f
            if not frame:
                print(f'make_disc_art: no frame between swaps {lo} and {hi} for {name}', file=sys.stderr)
                continue
            cap = os.path.join(work, 'caps', re.sub(r'_000\.bmp$', '', os.path.basename(frame)) + '.d3dcap')
            subprocess.run([replay, cap, '--out', os.path.join(work, 'hi_' + name + '_'), '--quiet'],
                           env=dict(renv, RECOMP_RES_SCALE='4'),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            hi_bmp = os.path.join(work, 'hi_' + name + '_000.bmp')
            if os.path.isfile(hi_bmp):
                print(f'   {name}: {os.path.basename(cap)} -> {save_picture(hi_bmp, os.path.join(work, "art", name))}')

        os.makedirs(out, exist_ok=True)
        for f in os.listdir(os.path.join(work, 'art')):
            shutil.copy2(os.path.join(work, 'art', f), os.path.join(out, f))
        print('== art in', out)
        for f in sorted(os.listdir(out)):
            print('  ', f)
    finally:
        if proc and proc.poll() is None:
            proc.kill()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
