"""The launcher's art, made from the player's own copy of the game -- mac/make_art.sh for
Windows and Linux, with the same path through the game and the same frames, so every
machine's launcher shows the same pictures.

    py -3 tools/make_disc_art.py [--title ts2|fp] [--game DIR] [--out DIR] [--build DIR]

TimeSplitters 2 (the default):
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

--title fp, TimeSplitters: Future Perfect (fp/scripts/build.py first): down the story path
to 2401's canyon under lockstep, timed by frame so every machine picks the same frames,
about five minutes; logo.png is the front end's own logo texture (DXT3,
1024x512, clear around the letters) and glow.png a soft halo made from its outline;
backdrop.jpg the ship over the planet, card_metal.jpg the cockpit, card_vulkan.jpg the
canyon. The art folder's default is .../art/45410066.
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
TS2_SEQ = ('12000:start,16000:start,20000:start,24000:start,28000:a,34000:a,40000:a,46000:a,'
       '52000:a,58000:a,64000:a,70000:a,76000:a,82000:a,88000:a,94000:a,'
       '120000:lstick_up:3000,125000:rstick_right:1200,134000:lstick_up:4000')
# Each game: its title id, executable and build folder, the scripted path through it,
# which swaps are captured, how long it runs, and which frames make which picture (the
# brightest frame between two swaps).
TITLES = {
    'ts2': dict(
        title_id='4553000A', exe='timeslip', build=os.path.join(HERE, 'build', 'Release'),
        game=os.path.join(HERE, 'game'), seq=TS2_SEQ, pad=False, lockstep_end=0, seconds=170,
        capture=('600', '300', '28'), logo='ts2',
        pictures=[('backdrop', 3900, 5700),       # the dam: the level's opening shot, snow-bright
                  ('card_metal', 3500, 3700),     # the hub, its portal open
                  ('card_vulkan', 6900, 8400)]),  # outside, at the base
    'fp': dict(
        title_id='45410066', exe='timeslip_fp', build=os.path.join(HERE, 'fp', 'build', 'Release'),
        game=os.path.join(HERE, 'fp', 'game'), pad=False, seconds=330,
        # Under lockstep, timed by frame, so every machine reaches each scene at the same
        # swap (a load presents nothing then; free-running, the PC's loading screen
        # presents at 60 while it loads and the Mac's did not, ~1,650 swaps apart by the
        # canyon). 1 PLAYER, a new profile, its name, the hard disk, Story, 2401, Normal,
        # the briefing; the run ends itself at tick 13,000, in the canyon.
        seq='t1231:a:200,t1591:a:200,t1951:a:200,t2311:a:200,t2671:a:200,t3031:a:200,'
            't3391:a:200,t3750:a:200',
        lockstep_end=13000,
        capture=('600', '300', '42'), logo='fp',   # 600: the title logo screen, the logo's texture
        pictures=[('backdrop', 7650, 7950),       # the ship over the planet
                  ('card_metal', 7050, 7350),     # the cockpit
                  ('card_vulkan', 11550, 13000)]),  # the canyon, 2401's first ground
}


def art_dir(title_id):
    if os.name == 'nt':
        return os.path.join(os.environ['LOCALAPPDATA'], 'xboxrecomp', 'art', title_id)
    base = os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share')
    return os.path.join(base, 'xboxrecomp', 'art', title_id)


def fp_logo(capdir, outdir):
    """Future Perfect's front end logo: a 1024x512 DXT3 texture, clear around its letters (the
    other one that size is its shadow, mostly opaque). There is no glow layer on the disc, so
    glow.png is the logo's own outline, spread and softened. Needs Pillow; 1 when not found."""
    try:
        from PIL import Image, ImageFilter
        sys.path.insert(0, os.path.join(HERE, 'tools'))
        import make_icon
    except Exception:
        print('make_disc_art: the logo needs Pillow', file=sys.stderr)
        return 1
    for cap in sorted(glob.glob(os.path.join(capdir, '*.d3dcap'))):
        for tid, fmt, w, h, lv, data in captex.textures(cap):
            if fmt != 0x0E or (w, h) != (1024, 512) or len(data) < w * h:
                continue
            img = make_icon.decode(fmt, w, h, data)
            a = img.getchannel('A')
            clear = sum(a.histogram()[:13]) / (w * h)
            if not 0.55 < clear < 0.85:
                continue
            box = a.point(lambda v: 255 if v > 8 else 0).getbbox()
            x0, y0 = max(box[0] - 24, 0), max(box[1] - 24, 0)
            x1, y1 = min(box[2] + 24, w), min(box[3] + 24, h)
            logo = img.crop((x0, y0, x1, y1))
            halo = logo.getchannel('A').filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(10))
            glow = Image.new('RGBA', logo.size, (120, 170, 255, 0))
            glow.putalpha(halo.point(lambda v: v * 3 // 5))
            logo.save(os.path.join(outdir, 'logo.png'))
            glow.save(os.path.join(outdir, 'glow.png'))
            print('logo from', os.path.basename(cap), 'box', (x0, y0, x1, y1))
            return 0
    print('no logo texture in', capdir, file=sys.stderr)
    return 1


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
    ap.add_argument('--title', default='ts2', choices=sorted(TITLES), help='which game (default ts2)')
    ap.add_argument('--game', default=None, help="the game's folder (default.xbe)")
    ap.add_argument('--out', default=None, help="where the pictures go (the launcher's art folder)")
    ap.add_argument('--build', default=None, help='the built game')
    a = ap.parse_args()
    t = TITLES[a.title]
    a.game = a.game or t['game']
    a.build = a.build or t['build']
    out = a.out or art_dir(t['title_id'])
    game_exe = os.path.join(a.build, t['exe'] + EXE)
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
                   RECOMP_MUTE='1', RECOMP_WINDOW_BACKGROUND='1', RECOMP_INPUT_SEQ=t['seq'],
                   RECOMP_D3D8_CAPTURE=os.path.join(work, 'caps', 'a.d3dcap'),
                   RECOMP_D3D8_CAPTURE_SWAP=t['capture'][0], RECOMP_D3D8_CAPTURE_EVERY=t['capture'][1],
                   RECOMP_D3D8_CAPTURE_MAX=t['capture'][2])
        for k in ('RECOMP_LOCKSTEP_REPLAY', 'RECOMP_LOCKSTEP', 'RECOMP_LOCKSTEP_TRACE', 'RECOMP_LOCKSTEP_END',
                  'RECOMP_INPUT_FAKE', 'RECOMP_MOUSE_FAKE', 'RECOMP_INPUT_SEQ_PAD', 'RECOMP_INPUT_SEQ_P2'):
            env.pop(k, None)
        if t['pad']:
            env['RECOMP_INPUT_SEQ_PAD'] = '1'
        if t['lockstep_end']:
            env['RECOMP_LOCKSTEP'] = '1'
            env['RECOMP_LOCKSTEP_END'] = str(t['lockstep_end'])
        print('== playing down the scripted path (about %d minutes)' % round(t['seconds'] / 60), flush=True)
        log = open(os.path.join(work, 'game.log'), 'wb')
        proc = subprocess.Popen([game_exe], cwd=a.build, env=env, stdout=log, stderr=log)
        for _ in range(t['seconds']):
            if proc.poll() is not None:
                break
            time.sleep(1)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        log.close()
        caps = sorted(glob.glob(os.path.join(work, 'caps', '*.d3dcap')))
        if len(caps) < 20:
            # the work folder goes below (it holds the game), so the log is copied out first
            kept = os.path.join(tempfile.gettempdir(), 'make_disc_art-game.log')
            shutil.copy2(os.path.join(work, 'game.log'), kept)
            sys.exit(f'make_disc_art: only {len(caps)} frames were captured (the game log: {kept})')

        print('== the logo', flush=True)
        find_logo = fp_logo if t['logo'] == 'fp' else captex.logo
        if find_logo(os.path.join(work, 'caps'), os.path.join(work, 'art')):
            print('make_disc_art: no logo found; the launcher writes the name instead', file=sys.stderr)

        print('== choosing the pictures', flush=True)
        renv = dict(os.environ, RECOMP_D3D8_BACKEND='d3d11' if os.name == 'nt'
                    else 'metal' if sys.platform == 'darwin' else 'vulkan')
        for c in caps:
            base = os.path.splitext(os.path.basename(c))[0]
            subprocess.run([replay, c, '--out', os.path.join(work, 'frames', base + '_'), '--quiet'],
                           env=renv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for name, lo, hi in t['pictures']:
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
