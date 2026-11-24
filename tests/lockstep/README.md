# Lockstep recordings

Online co-op runs the whole game on every machine and sends only the
controllers, so every build on every system has to compute the same game
from the same pads (recompose `src/kernel/recomp_lockstep.h`). These files
are the check: controller input for each frame, with a hash of the game's
state every 60 frames, recorded on one machine. A replay on any other build
must reach the same hash at every checkpoint.

| File | Release | What it plays | Frames |
| --- | --- | --- | --- |
| `coop-siberia-us.trace` | USA | A fresh game: 2 Players, both create a profile, Story Co-op, Siberia, both players walking, turning and firing | 8,000 |
| `arcade-mexican-mission-us.trace` | USA | A fresh game: 1 Player, a profile, Arcade Custom, Normal, Deathmatch on Mexican Mission with the recommended bots and weapons, walking along the walls, turning, strafing and firing until the bots win (about frame 7,600), then the results screens | 13,500 |

A gate replay must run without `RECOMP_TS2_VIEW_PORT`: offline it turns on
each player's own screen, which lays the game out differently (the co-op one
differs from frame 4,680 with it).

Both are recorded at the default settings and replay the same only at them:
widescreen (and each player's own screen, `RECOMP_TS2_VIEW_PORT`) change the
game's memory, so a replay with them on differs from the recording early on
-- which is fine for comparing pictures between two replays, which agree with
each other.

Replay one from a copy of the game folder with no `UDATA` (the recording
starts from a fresh profile) and an empty save folder, muted:

```bash
RECOMP_GAME_DIR=<game copy without UDATA> RECOMP_SAVE_DIR=<empty folder> \
RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 \
RECOMP_LOCKSTEP_REPLAY=tests/lockstep/coop-siberia-us.trace RECOMP_LOCKSTEP_END=8000 \
./timeslip 2> replay.log
grep LOCKSTEP replay.log | tail -2
```

The last line says `every tick was the same as the recording`, or names the
first tick that differs. To find out why, write a trace of the replay
(`RECOMP_LOCKSTEP_TRACE=<file>`, which hashes each 4 KB page every frame) on
both machines and compare them, then dump memory at the first differing
tick (`RECOMP_LOCKSTEP_DUMP=<tick>`):

```bash
py -3 -m tools.lockstep trace a.trace b.trace --base 0x002A01E0   # from recompose/
py -3 -m tools.lockstep dump a.trace.t<tick>.bin b.trace.t<tick>.bin
```

Checked (23 November 2026): Windows 11 (zig/clang, Direct3D 11 and Vulkan)
and Linux (WSL Ubuntu, clang, Vulkan on llvmpipe) replay it the same at every
frame.

The co-op one was recorded with the menu script in `docs/multiplayer.md`
("Online co-op"); the Arcade one (24 November 2026, Windows, Direct3D 11)
with `RECOMP_LOCKSTEP=1` and `RECOMP_INPUT_SEQ` set to
`12000:start,16000:start,20000:start,24000:start,28000:a,34000:down,38000:a,42000:down,47000:a,52000:a,57000:a,62000:a,67000:a,72000:a`
(a profile, Arcade, Arcade Custom, Normal, Deathmatch, Mexican Mission, GO,
the first character), then from 80 s every 6 s for 140 s:
`<t>:lstick_up:3500,<t+800>:rt:1800,<t+3600>:rstick_left:450,<t+4200>:lstick_left:1200`
(every third turn to the right, every second strafe to the right). Both were
reduced with `py -3 -m tools.lockstep compact`. Rendering does not touch the
game's state: the co-op one replays the same at 5x with offscreen targets
scaled (24 November 2026).
