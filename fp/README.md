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
- **Widescreen** not yet: with the Xbox's widescreen flag the front end and
  cutscenes lay themselves out wider, but the 3D view comes out as a 4:3 band
  in the middle; the title defaults to 4:3 until that is understood.
- Not yet: the keyboard and mouse checked against the game's own controls,
  native mouse look, the field of view, the crosshair, each co-op player's
  whole screen, the launcher's art and the installer.

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
- The state checked is `.data`, less the vblank count and four GPU fence
  times the game keeps there: the boot's movies play before the first frame
  on the host's clock, so about one boot in two makes a frame more or less of
  fences, and those words differ forever after, though the game only hands
  them back to Direct3D's waits.

`tests/lockstep/coop-2401-us.trace` is the check: 2 PLAYER, both profiles,
Story Co-op, 2401 on Normal, then both players walking, turning, strafing and
firing, 13,770 frames. Measured 25 November 2026 (Windows, Vulkan): three
copies replaying it at once the same as it at every frame (one of them had
booted with the fences 4 apart); online between two copies on one PC (1 ms,
3 frames of delay), host and joiner each the same as the recording at every
frame and as each other at every 60-frame check, through frame 14,400. Not
yet: between two machines, and on the Mac.

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
