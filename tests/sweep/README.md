# The corridor sweep

A test that plays the game and looks at every frame for breaks in the level
and flashes: an Arcade match on Mexican Mission, the player in the mission's
cloister, turned the way a mouse turns it, firing each of the match's
weapons. Made 24 November 2026 for Josh's report of the sky showing through
the walls on fast mouse turns, and what it found is in
[docs/pc-native.md](../../docs/pc-native.md), "The corridor sweep".

| File | What it is |
| --- | --- |
| `corridor.seq` | The controller script (`RECOMP_INPUT_SEQ`): the menus by the clock to Arcade Custom, Deathmatch, Mexican Mission, Recommended; then, by frame (`t<tick>:`), the trigger and the strafes |
| `corridor.sweep` | The test's own script (`RECOMP_TS2_SWEEP`, `src/recomp_manual.c`): weapons given, health kept, the player kept in place, a slow full turn, swings at 5, 15, 30 and 60 degrees a frame, then each weapon fired standing still and swinging |
| `corridor.ticks` | The frames dumped (`RECOMP_PRESENT_DUMP_TICKS`, three presents from each: frame interpolation's in-between frames are named `...i.bmp`) |
| `analyze.py` | Sky where the slow turn never shows it (breaks through the walls), and frames much darker than their neighbours, by part of the run |
| `odd.py` | In-between frames unlike both game frames around them while the player stands still |
| `run_corridor.ps1` | All of it on Windows |

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

macOS and Linux, by hand: a game folder with an empty `UDATA`, then

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

where `<out>/corridor.sweep` is `corridor.sweep` with a last line
`log <out>/sweep.csv` (every frame's position, turn, weapon and ammo, which
the analysis reads). Frames are about 6 MB each as BMP; `--jpg` converts them.

## Reading it

`analyze.py` prints, for each part of the run, how many game frames and how
many in-between frames show sky the slow turn never showed from that
direction. Game frames should always be near 0 (the few it counts are the
courtyard's open roof); in-between frames are the ones frame interpolation
draws. The strafing part cannot be judged this way (the player moves), and
the Plasma Autorifle's blue beam reads as sky.

Measured on Windows (D3D11, 5x, 16:9, FOV 80, frame interpolation 3), in
in-between frames with sky through the walls:

| Part | Before the fix (88e1999) | After (16a6700) |
| --- | --- | --- |
| Swinging 5 degrees a frame | 34 of 72 | 1 to 3 real, at the screen's edge as a swing starts |
| 15 | 50 of 71 | 2 of 54 |
| Pistols, firing and swinging | 60 of 148 | 4 of 150 |
| Fire rifle | 49 of 410 | 0 of 386 |
| Shotgun | 55 of 147 | 2 of 145 |
