# TimeSplitters: Future Perfect (Timeslip collection)

The Timeslip collection's second game: TimeSplitters: Future Perfect (Xbox),
statically recompiled on the [Recompose](https://github.com/Joshspeakman/recompose)
toolkit, beside TimeSplitters 2 (the repository's root). It shares the toolkit
submodule, the tools and the launcher; everything that is about this game is
in this folder.

**Work in progress** (Nov 2026): being brought up on Windows and the Mac.

## Where it is (25 November 2026)

- **Plays.** The front end (1-4 players, profiles, storage, the main menu),
  story mode's first level -- 2401, Time To Split: its briefing, the whole
  in-engine intro cutscene and the level itself, the handgun in hand and the
  HUD up -- at 60 fps with no fault, on Windows (Vulkan) and the Mac (Metal).
  Its movies (XMV) play through FFmpeg on both.
- **System Link** hosts a match: Xbox Live / System Link > System Link >
  Start New Match, the lobby, team select, an Assault match in the VR arena.
- **Online co-op** (lockstep, as TimeSplitters 2's: `docs/multiplayer.md`):
  Story Co-op split screen, the whole game run on both machines and only the
  controllers sent. See "Online co-op" below.
- **Widescreen**, the game's own 16:9 mode (Widescreen in the launcher's
  Graphics or the Esc menu's Display): its camera, front end, cutscenes and
  HUD laid out for 16:9 by the game itself, on the console's widescreen flag.
  Its 3D vertex programs copy positions it transformed itself, which the
  renderer took for 2D and squeezed back to a 4:3 band; `src/main.c` has it
  squeeze none of Future Perfect's 2D (`fp/CMakeLists.txt`).
- **Installs** on Windows and the Mac, with its own icon from the disc and
  the launcher's Updates tile (see "Building").
- **Keyboard and mouse** laid out over the game's own Default control layout
  (Settings > Controls): W A S D, the mouse to look (turned over for the
  game's default Inverse Look), left button fire, right button aim, G
  grenade, R reload, V melee, F/E/Space activate, C/Ctrl crouch, the wheel
  and Q change weapon, the middle button or Z toggle the weapon's mode (zoom
  in while aiming), X change grenades (zoom out). All of it in
  `src/title_defaults.c`; any of it rebound in the launcher. With mouse look
  on, the profile's **Auto Lookahead** is set aside while the game's look
  step runs (`sub_0025D520`; the profile itself is untouched), as
  TimeSplitters 2 does it: it levelled the view as you walked, so a look up
  or down with the mouse was pulled back to the horizon within a second
  (tried in 2401, before and after).
- **The launcher's art** from your disc (`tools/make_disc_art.py --title
  fp`): the logo, the ship over the planet, the cockpit, the canyon, the same
  frames on Windows and the Mac (the run is timed by frame under lockstep).
- Not yet: native mouse look (the mouse moves the right stick, which the
  game's turn acceleration acts on; TimeSplitters 2 turns its camera
  directly, which also changes what online co-op sends. Where to start: the
  look step `sub_0025D520` turns the stick into the look state's angles,
  [0x007B0C7C] +0x100 and +0x104), the field of view, the number keys, each
  co-op player's whole screen. The game has its own crosshair options
  (Settings > Controls > Crosshair).
- **Clears of some colour channels** as the console does them
  (`xbox_D3D8SetClearChannels(1)` in `src/main.c`; recompose
  `d3d8_xbox.h`, `RECOMP_CLEAR_CHANNELS=0/1` to override): the Audio/Video
  Options panel clears only its rectangle's alpha (D3DCLEAR flags 0x80) and is
  translucent over the front end, where a clear of all four channels painted
  it black.
- Open: the **volume sliders** in Settings > Audio/Video Options (MUSIC
  VOLUME, SOUND VOLUME) are not drawn, on Windows and the Mac alike. No draw
  lands beside those labels (every draw of one options frame logged: the
  labels and the row highlight are there), nothing is skipped or fails, the
  push-buffer walk never resynchronises, and changing the volume shows
  nothing. `sub_000204F0` is the panel's frame, not the slider. The game
  issues no draw for the bar at all: one options frame's every draw on both
  host paths logged, 134 and no indexed ones, the labels and highlights
  among them; the 98-vertex fans through 0x000225CF are the backdrop's rings.
  So it is the menu code deciding not to draw it -- probably on a value it
  reads (the volume, or something it asks the sound system that the HLE
  answers otherwise); next, the options screen's slider routine.
- For Josh: TimeSplitters 2 clears some channels too, on its title and
  player-count screen, and with them honoured the blue swirl behind its logo
  comes out darker and more see-through in the middle. Which is right wants
  a look at the console or footage; if the darker one is, TimeSplitters 2
  turns the clears on as Future Perfect does.

A scripted path to the first level (fresh saves, a game copy without UDATA):

    RECOMP_INPUT_SEQ_PAD=1
    RECOMP_INPUT_SEQ=20000:a,26000:a,32000:a,38000:a,44000:a,50000:a,56000:a,62000:a

1 PLAYER, Create New Profile, Enter Name (A keeps "Player 1"), the Xbox Hard
Disk, Story, 2401 Time To Split, Normal, the briefing. To host System Link
instead: `20000:a,26000:a,32000:a,38000:a,43000:down,44000:down,45000:down,
47000:a,50000:down,51500:a,56000:a` (with `RECOMP_SYSLINK=host`), which
leaves the host in its lobby; A starts it.

## Online co-op

As TimeSplitters 2's (`docs/multiplayer.md`, "Online co-op"): both machines
run the whole game and send only the controllers, frame by frame (recompose
`docs/technical/lockstep.md`). In the launcher's System Link tab one player
chooses **Host online co-op** and the other **Join online co-op** with the
host's address; or `RECOMP_LOCKSTEP_NET=host` (UDP 27620) and
`RECOMP_LOCKSTEP_NET=join RECOMP_LOCKSTEP_PEER=<host>`. Then, as on one
console: **2 PLAYER**, each player makes or picks a profile (player 2 presses
START to join), **Story Co-op**. Both copies must be the same build. It is
the console's split screen on both machines: Future Perfect has no hook yet
for each player's whole screen.

What it took (`src/recomp_manual.c`, `config/us/overrides.inc`):

- One step per frame: the frame clock (USA `sub_001538C0`) waits for the
  vblank count to move and steps by the vblanks since the last frame, 1 to 3;
  under lockstep the count (`sub_00022030`) answers the frame tick instead.
- The loading screen's own thread is never started in a session
  (`sub_00156D80`): it draws while the game loads, spinning on the vblank
  count, which no load moves under lockstep, so the game froze at its first
  load. In co-op a loading screen holds still.
- The state checked is `.data`, less the vblank count and five GPU fence
  times the game keeps there. Direct3D's fence time follows the host's
  timing -- the boot's movies play before the first frame on the host's
  clock, and Direct3D fences as its push buffer fills, as fast as the host's
  GPU thread empties it -- so those words differ between machines, though the
  game only hands them back to Direct3D's waits.

`tests/lockstep/` holds the checks (its README): Story Co-op in 2401, and a
2-player Arcade Deathmatch in Vietnam against six bots with a pause. Measured
26 November 2026 (Windows, Vulkan): four copies replaying the Arcade one at
once and three the Story one, each the same as its recording at every frame;
online between two copies on one PC (1 ms, 3 frames of delay), host and
joiner each the same as the recording at every frame and as each other at
every 60-frame check, through frame 14,400, with the Arcade one (and with the
first Story recording, before the fifth fence word). On the Mac (M1 Pro,
arm64, Metal, re-lifted at the same commits) the first Story recording
replayed the same at every frame. Not yet: online between two machines (the
PC's firewall and the Mac's ask their owner first).

| | |
| --- | --- |
| Title ID | `45410066` ("TimeSplitters FP") |
| Release | USA, version 1, built 2005-02-28; `default.xbe` SHA-1 `daf0bcc57b6e93a7ebf5498074c8a9e7dc90381e` |
| XDK | 5849, plain D3D8, with XONLINE, XNET, XMV (its movies) and DOLBY |
| Entry point | `0x0038024D` |
| Code | `.text` 3.9 MB, twice TimeSplitters 2's |

## Building

Put your own disc's files in `fp/game/` (`default.xbe`, `pak/`, `xmv/`; never
committed), then:

    py -3 fp/scripts/build.py              # lift (first time), then build
    py -3 fp/scripts/build.py --relift     # after seeds, overrides or the toolkit change

On Windows with the zig toolchain, `tools\build_windows.ps1 -Title fp -Vulkan`.
The executable is `fp/build/Release/timeslip_fp(.exe)`, with
`timeslip_fp_launcher` beside it.

To install it as a program: `tools\install_windows.ps1 -Title fp` on Windows
(`%LOCALAPPDATA%\Programs\Timeslip Future Perfect`, Start menu and desktop
shortcuts named "TimeSplitters Future Perfect", an entry in Settings > Apps,
FFmpeg's three libraries beside the game for its movies, the launcher's art
made once from your disc by `tools/make_disc_art.py --title fp` and the icon
from it), or `mac/install.sh --title fp` on a Mac. The launcher's Updates tile
updates it from the collection's releases as it does TimeSplitters 2.

## Layout

```text
fp/CMakeLists.txt        the executable and the launcher, on top of ../recompose
fp/scripts/build.py      lift (first time or --relift), then configure and build
fp/src/main.c            the host entry point (TimeSplitters 2's, renamed)
fp/src/recomp_manual.c   the toolkit template's runtime glue; Future Perfect's hooks
fp/src/title_defaults.c  the keyboard, mouse and settings defaults
fp/config/us/            the USA release's addresses: seeds.json, xdk_symbols.json, overrides.inc
fp/game/                 the disc, supplied by you            (ignored)
fp/src/recomp/           the lifted code: game code            (ignored)
.pipeline/fp-us/         the pipeline's stage output           (ignored)
```

`config/us/seeds.json` starts from Recompose's runtime seeds for this title
(`recompose/config/seeds/45410066.json`) and `overrides.inc` carries the
toolkit project's one override (`titles/futureperfect`): the toolkit took the
game to its front end in September 2026 (recompose `CLAUDE.md`, "Update, 22 Sep
2026", and `docs/technical/shadow-mode.md`).
