# The corridor sweep

A test that plays the game and looks at every frame for breaks in the level
and flashes: an Arcade match on Mexican Mission, the player in the mission's
cloister, turned the way a mouse turns it, firing each of the match's
weapons. Made 24 November 2026 for Josh's report of the sky showing through
the walls on fast mouse turns, and what it found is in
[docs/pc-native.md](../../docs/pc-native.md), "The corridor sweep".

| File | What it is |
| --- | --- |
| `corridor.seq` | The controller script (`RECOMP_INPUT_SEQ`): the menus to Arcade Custom, Deathmatch, Mexican Mission, Recommended, then the trigger and the strafes, all by frame (`t<tick>:`). By the clock, as the menus first were, each press landed on whatever frame the loading allowed, and two Mac runs started the match in two other places than the PC's; by frame, every machine starts in the cloister at (-19.245, 0.009, 0.037), facing 90, at tick 4418 |
| `corridor.sweep` | The test's own script (`RECOMP_TS2_SWEEP`, `src/recomp_manual.c`): weapons given, health kept, the player kept in place, a slow full turn, swings at 5, 15, 30 and 60 degrees a frame, then each weapon fired standing still and swinging |
| `corridor.ticks` | The frames dumped (`RECOMP_PRESENT_DUMP_TICKS`, three presents from each: frame interpolation's in-between frames are named `...i.bmp`) |
| `analyze.py` | Sky where the slow turn never shows it (breaks through the walls), and frames much darker than their neighbours, by part of the run |
| `odd.py` | In-between frames unlike both game frames around them while the player stands still |
| `run_corridor.ps1` | All of it on Windows |
| `run_corridor.sh` | All of it on macOS and Linux (the recipe below, with the checks: a game copy without saves, an empty output folder) |

Under lockstep (`RECOMP_LOCKSTEP=1`) the run is the same game on every
machine and renderer, so a run's recording (`RECOMP_LOCKSTEP_TRACE`) can be
replayed with any setting that only changes the picture -- frame
interpolation, the renderer, post-processing -- and the frames compared one
for one. The player starts in the cloister because the script reaches the
match the same way every time; the match's five weapons are 6 (two pistols),
20 (a fire rifle), 13 (the game switches away from it), 32 (shotgun) and 22
(Plasma Autorifle).

## Running it

Windows: `tests\sweep\run_corridor.ps1 -Out <folder> -Game <the game folder>
-Settings <a copy of your settings file, fullscreen = 0>`.

macOS and Linux: `tests/sweep/run_corridor.sh --out <empty folder> --game <a game
copy with no UDATA> --settings <a settings copy> --python <one with numpy and Pillow>`,
with any `RECOMP_*` settings (renderer, frame interpolation) in the environment;
`--replay <out>/corridor.trace` replays an earlier run. The game writes a profile into
the copy's `UDATA`, so empty it before the next run. Or by hand: a game folder with an
empty `UDATA`, then

```bash
RECOMP_GAME_DIR=<game> RECOMP_SAVE_DIR=<empty folder> RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 \
RECOMP_WINDOW_SIZE=1600x900 RECOMP_DISPLAY_CONFIG=<settings copy> \
RECOMP_LOCKSTEP=1 RECOMP_LOCKSTEP_END=7320 RECOMP_LOCKSTEP_TRACE=<out>/corridor.trace \
RECOMP_INPUT_SEQ="$(cat tests/sweep/corridor.seq)" \
RECOMP_TS2_SWEEP=<out>/corridor.sweep \
RECOMP_PRESENT_DUMP=<out>/p_ RECOMP_PRESENT_DUMP_TICKS="$(cat tests/sweep/corridor.ticks)" \
RECOMP_PRESENT_DUMP_FRAMES=3 RECOMP_PRESENT_DUMP_MAX=6000 \
./timeslip 2> <out>/run.log
python3 tests/sweep/analyze.py <out> --jpg
python3 tests/sweep/odd.py <out>
```

(on a Retina Mac `RECOMP_WINDOW_SIZE=800x450`: the size is in points, and 3200x1800 dumps are
slow enough that in-between frames miss their moment), where `<out>/corridor.sweep` is
`corridor.sweep` with a last line
`log <out>/sweep.csv` (every frame's position, turn, weapon and ammo, which
the analysis reads). Frames are about 6 MB each as BMP; `--jpg` converts them.

## Reading it

`analyze.py` prints, for each part of the run, how many game frames and how
many in-between frames show sky the slow turn never showed from that
direction. Game frames should always be near 0 (the few it counts are the
courtyard's open roof); in-between frames are the ones frame interpolation
draws. The strafing part cannot be judged this way (the player moves), and
the Plasma Autorifle's blue beam reads as sky.

How many in-between frames a part has varies a little from run to run (they
are dumped by the clock); the game frames do not. Measured on Windows
(D3D11, 5x, 16:9, FOV 80, frame interpolation 3), in-between frames with
sky through the walls, as `analyze.py` prints them:

| Part | Before the fix (88e1999) | Turn limit 70 (16a6700) | After: limit 20 |
| --- | --- | --- | --- |
| Swinging 5 degrees a frame | 34 of 72 | 11 of 62 | 8 of 59 |
| 15 | 50 of 71 | 1 of 59 | 1 of 62 |
| 30 | 0 of 14 | 20 of 62 | 0 of 12 |
| 60 | 0 of 25 | 11 of 54 | 0 of 22 |
| Pistols, firing and swinging | 60 of 148 | 4 of 150 | 3 of 150 |
| Fire rifle | 49 of 410 | 0 of 383 | 0 of 381 |
| Shotgun | 55 of 147 | 1 of 145 | 1 of 146 |

At 5 degrees most of what is counted is the courtyard's open sky (the game
frames of that part count it too, 8 here); the real ones are a sliver at the
screen's edge on the frame a swing turns back. At 30 and 60 the game's own
frames are shown for the turn itself (a flick past 20 degrees a frame is not
interpolated); the in-between frames left are where the swing turns back.

Second round (24 November 2026, menus by frame): the sweep's one spot hid
most of the breaks -- they were common while walking and away from it (see
docs/pc-native.md). With the doorway scissors off in play, the camera's
motion voted without the gun, and a turn limit of 12 degrees a frame, Windows
(D3D11, 5x, 16:9, interpolation 3), recorded fresh at each field of view:

| Part | FOV 0 (60) | FOV 80 | FOV 100 |
| --- | --- | --- | --- |
| Swinging 5 degrees a frame | 4 of 63 | 2 of 71 | 6 of 78 |
| 15 | 0 of 14 | 0 of 7 | 0 of 2 |
| 30 | 0 of 34 | 0 of 10 | 0 of 0 |
| 60 | 0 of 40 | 0 of 29 | 7 of 41 |
| Pistols | 2 of 141 | 1 of 149 | 1 of 150 |
| Fire rifle | 0 of 371 | 0 of 463 | 10 of 481 |
| Shotgun | 0 of 147 | 1 of 147 | 4 of 147 |

At FOV 100 the sky test also flags game frames (16 in the 15-degree part, 5
in the fire rifle's), so part of that column is the test, not the picture.
For breaks while moving, a test that compares each in-between frame with the
game frames either side is the better judge (Fable's `novel.py`, the Mac's
walking run); the runner here clears any `RECOMP_LOCKSTEP_REPLAY` and the
like an earlier run in the same shell left set.

## The corridor walk

Made 28 November 2026 for Josh's report of corridors that blinked darker for
a moment while walking back and forth through them. The same menus to the
same match as the sweep, then twelve legs of 3 seconds forward and 3 back
through Mexican Mission's cloister and corridors, turning right after every
second leg; the bots fight around the player.

| File | What it is |
| --- | --- |
| `walk.seq` | The controller script (`RECOMP_INPUT_SEQ`): `corridor.seq`'s menus, then the walk, by frame, to tick 9060 |
| `walk.sweep` | The test's own script (`RECOMP_TS2_SWEEP`): health kept from the match's start |
| `blinks.py` | A part of the picture (a 12 by 9 grid) much brighter or darker in one frame than in both frames either side while those two agree, in in-between and game frames |

Record it with frame interpolation on, then replay the recording with every
frame of a stretch dumped:

```bash
RECOMP_GAME_DIR=<game> RECOMP_SAVE_DIR=<empty folder> RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 \
RECOMP_WINDOW_SIZE=1280x720 RECOMP_DISPLAY_CONFIG=<settings copy, frame_interp = 3> \
RECOMP_LOCKSTEP=1 RECOMP_LOCKSTEP_END=9200 RECOMP_LOCKSTEP_TRACE=<out>/walk.trace \
RECOMP_INPUT_SEQ="$(cat tests/sweep/walk.seq)" RECOMP_TS2_SWEEP=tests/sweep/walk.sweep \
./timeslip
RECOMP_GAME_DIR=... (the same) RECOMP_LOCKSTEP_END=9100 RECOMP_LOCKSTEP_REPLAY=<out>/walk.trace \
RECOMP_TS2_SWEEP=tests/sweep/walk.sweep RECOMP_PRESENT_DUMP=<out>/w_ \
RECOMP_PRESENT_DUMP_TICKS=8300-9060 RECOMP_PRESENT_DUMP_FRAMES=3 RECOMP_PRESENT_DUMP_MAX=6000 \
./timeslip
python3 tests/sweep/blinks.py <out> w_ 10
```

`RECOMP_INTERP_ACCOUNT=4420-9200` on a replay prints, for each frame, what
the frame before drew that the in-between frames fill in and how much of it
the newer frame draws too; "its mesh drawn here unpaired" above 0 is the
fault below. The game's own fire and the Plasma Autorifle's beam change from
frame to frame, so `blinks.py` flags them too: look at what it flags.

What it found (recompose `docs/technical/frame-interpolation.md`, "Matching,
tier 4"): the game moves a room's pieces from one vertex program to another
as the player walks between rooms; interpolation paired them with nothing,
and the in-between frames drew the room twice, alpha blended, so darker and
sharper for one frame. Windows, D3D11, interpolation 3, the same recordings
replayed before and after the fix:

| Run | Before | After |
| --- | --- | --- |
| 4:3, FOV 0, ticks 8300-9060: in-between frames that blinked (`blinks.py`, 18) | 3, the corridor at 8563, 8725 and 8922 | 0 |
| 4:3, FOV 0, ticks 5290-5920 (`blinks.py`, 10), largest change | 44.8 | 13.2, the game's fire |
| 16:9, FOV 80, ticks 4420-9200: pieces drawn twice (`RECOMP_INTERP_ACCOUNT`) | 311 in 38 frames | 0 |

The corridor sweep at 16:9, FOV 80 gave the same counts before and after.
