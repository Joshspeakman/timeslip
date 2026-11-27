"""The launcher's pictures of each game and its desktop icon, from the LaunchBox Games
Database (gamesdb.launchbox-app.com): the games' key art, their clear logos, and a square
of the key art for the icon. Nothing of them is in this repository -- only where they are.

    py -3 tools/fetch_art.py [--title ts2|fp|all] [--out DIR] [--force]

Into the launcher's art folder (the one tools/make_disc_art.py fills; default
%LOCALAPPDATA%\\xboxrecomp\\art\\<title id>, or $XDG_DATA_HOME/xboxrecomp/art/<id>, or
~/Library/Application Support/xboxrecomp/art/<id> on a Mac):

    key_*.jpg/png   the key art the launcher shows behind its menu (LaunchBox's
                    "Fanart - Background": the games' promotional art)
    logo_hd.png     the game's clear logo, larger than the disc's own
    icon.png        1024 by 1024, a square of one of the key art pictures: the
                    desktop icon (tools/make_icon.py) and the Mac's app icon

TimeSplitters 2: Cortez and Hart (the cover's art, and on red), and a group of its
characters in a neon-lit alley.
Future Perfect: Cortez coming out of the time portal, and Cortez in the corridor.
A file already there is kept unless --force. The downloads are checked to be pictures
and written whole or not at all. Standard library only; icon.png needs Pillow.
"""
import argparse
import os
import sys
import urllib.request

LB = 'https://images.launchbox-app.com/'
ART = {
    'ts2': dict(
        title_id='4553000A',
        files=[('key_cover.jpg', LB + '1e237a25-e045-413f-8136-168c78a49a86.jpg'),   # 2560x1440
               ('key_pair.jpg', LB + '085b06a9-30d8-4596-81cc-302dbf8414f0.jpg'),    # 2560x1440
               ('key_alley.jpg', LB + '195217a6-2585-448d-be9c-f2299a6a79cd.jpg'),  # 1920x1080
               ('logo_hd.png', LB + 'b1507610-5ed9-419b-9586-a89ca1cd65d6.png')],    # 2289x820
        icon=('key_pair.jpg', (700, 80, 1900, 1280))),       # Hart and Cortez
    'fp': dict(
        title_id='45410066',
        files=[('key_portal.png', LB + '6d409b69-3661-4681-aec0-a79f2a3b84d4.png'),  # 1920x1080
               ('key_corridor.jpg', LB + 'ab570622-9e5b-4912-a2f6-3fef2c51ea09.jpg'),  # 1920x1080
               ('logo_hd.png', LB + '80a9ddec-9a26-4514-82a5-537a59f33d93.png')],    # 1235x468
        icon=('key_portal.png', (1230, 0, 1830, 600))),      # Cortez in the portal's light
}
AGENT = 'Mozilla/5.0 (compatible; game launcher art)'


def art_dir(title_id):
    if os.name == 'nt':
        return os.path.join(os.environ['LOCALAPPDATA'], 'xboxrecomp', 'art', title_id)
    if sys.platform == 'darwin':
        return os.path.expanduser('~/Library/Application Support/xboxrecomp/art/' + title_id)
    base = os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share')
    return os.path.join(base, 'xboxrecomp', 'art', title_id)


def fetch(url, path):
    """The file at url into path, whole, when it is a JPEG or a PNG. 1 when it is there."""
    req = urllib.request.Request(url, headers={'User-Agent': AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read(32 * 1024 * 1024)
    if not (data[:3] == b'\xff\xd8\xff' or data[:8] == b'\x89PNG\r\n\x1a\n'):
        raise ValueError('not a picture')
    part = path + '.part'
    with open(part, 'wb') as f:
        f.write(data)
    os.replace(part, path)
    return len(data)


def make_icon_square(out, name, box):
    try:
        from PIL import Image
    except ImportError:
        print('fetch_art: icon.png needs Pillow', file=sys.stderr)
        return
    src = os.path.join(out, name)
    if not os.path.isfile(src):
        return
    img = Image.open(src).convert('RGB').crop(box).resize((1024, 1024), Image.LANCZOS)
    img.save(os.path.join(out, 'icon.png'))
    print('   icon.png from', name)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--title', default='all', choices=['all'] + sorted(ART))
    ap.add_argument('--out', default=None, help='the art folder (one title only)')
    ap.add_argument('--force', action='store_true', help='fetch again what is there')
    a = ap.parse_args()
    titles = sorted(ART) if a.title == 'all' else [a.title]
    if a.out and len(titles) > 1:
        sys.exit('fetch_art: --out needs --title')
    failed = 0
    for t in titles:
        spec = ART[t]
        out = a.out or art_dir(spec['title_id'])
        os.makedirs(out, exist_ok=True)
        print('==', t, '->', out)
        for name, url in spec['files']:
            path = os.path.join(out, name)
            if os.path.isfile(path) and not a.force:
                print('  ', name, '(there)')
                continue
            try:
                print('  ', name, '%d KB' % (fetch(url, path) // 1024))
            except Exception as e:                  # offline, moved: the launcher does without
                print('fetch_art: %s: %s' % (name, e), file=sys.stderr)
                failed += 1
        if a.force or not os.path.isfile(os.path.join(out, 'icon.png')):
            make_icon_square(out, *spec['icon'])
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
